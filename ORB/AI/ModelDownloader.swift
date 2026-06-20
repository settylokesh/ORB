//
//  ModelDownloader.swift
//  ORB
//
//  Downloads a list of files sequentially with real aggregate byte progress and
//  supports pause / resume. Built on URLSessionDownloadTask so multi-gigabyte
//  files stream efficiently (no per-byte iteration — the old streaming path was
//  why a multi-GB model could appear "stuck") and resume across pauses using the
//  system's resume data.
//

import Foundation

final class ModelDownloader: NSObject, @unchecked Sendable {

    struct FileSpec: Sendable {
        let remote: URL
        let dest: URL
        let size: Int64
    }

    enum DownloadPaused: Error { case paused }

    let files: [FileSpec]
    let grandTotal: Int64

    private let session: URLSession
    private let lock = NSLock()

    private var baseBytes: Int64 = 0          // bytes from fully-completed files, this run
    private var currentTask: URLSessionDownloadTask?
    private var pausedResumeData: Data?
    private var isPaused = false
    private var progressObservation: NSKeyValueObservation?

    /// Reports (downloadedBytes, totalBytes) on the main queue while running.
    var onProgress: ((Int64, Int64) -> Void)?

    init(files: [FileSpec]) {
        self.files = files
        self.grandTotal = max(1, files.reduce(0) { $0 + $1.size })
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60 * 8   // allow very large downloads
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    private func sync<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    /// Run (or continue) the download. Throws `DownloadPaused.paused` when paused,
    /// or a network error on failure. Returns normally when everything is on disk.
    func run() async throws {
        sync { isPaused = false; baseBytes = 0 }
        for f in files {
            if Self.isComplete(f) {
                let done = sync { baseBytes += f.size; return baseBytes }
                report(done)
                continue
            }
            try await downloadOne(f)
            let done = sync { baseBytes += f.size; return baseBytes }
            report(done)
        }
    }

    /// Pause the in-flight file (completed files stay on disk; the current file
    /// resumes from where it left off via the system's resume data).
    func pause() {
        sync { isPaused = true }
        currentTask?.cancel(byProducingResumeData: { [weak self] data in
            guard let self, let data else { return }
            self.sync { if self.pausedResumeData == nil { self.pausedResumeData = data } }
        })
    }

    // MARK: - One file

    private func downloadOne(_ f: FileSpec) async throws {
        try FileManager.default.createDirectory(
            at: f.dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let stableTemp: URL = try await withCheckedThrowingContinuation { cont in
            let handler: @Sendable (URL?, URLResponse?, Error?) -> Void = { [weak self] url, _, error in
                guard let self else { cont.resume(throwing: CancellationError()); return }
                self.progressObservation?.invalidate()
                if let url {
                    // The temp file is removed once this handler returns, so move it now.
                    let stable = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    do { try FileManager.default.moveItem(at: url, to: stable); cont.resume(returning: stable) }
                    catch { cont.resume(throwing: error) }
                } else {
                    let paused = self.sync { self.isPaused }
                    if paused {
                        if let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                            self.sync { if self.pausedResumeData == nil { self.pausedResumeData = data } }
                        }
                        cont.resume(throwing: DownloadPaused.paused)
                    } else {
                        cont.resume(throwing: error ?? URLError(.unknown))
                    }
                }
            }

            let resume = sync { () -> Data? in let d = pausedResumeData; pausedResumeData = nil; return d }
            let task = resume.map { session.downloadTask(withResumeData: $0, completionHandler: handler) }
                ?? session.downloadTask(with: f.remote, completionHandler: handler)
            let base = sync { currentTask = task; return baseBytes }
            progressObservation = task.progress.observe(\.completedUnitCount) { [weak self] prog, _ in
                guard let self else { return }
                self.report(min(base + prog.completedUnitCount, self.grandTotal))
            }
            task.resume()
        }

        try? FileManager.default.removeItem(at: f.dest)
        try FileManager.default.moveItem(at: stableTemp, to: f.dest)
    }

    private func report(_ done: Int64) {
        let total = grandTotal
        DispatchQueue.main.async { [weak self] in self?.onProgress?(done, total) }
    }

    static func isComplete(_ f: FileSpec) -> Bool {
        guard let size = try? f.dest.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return f.size > 0 ? Int64(size) >= f.size : size > 0
    }
}
