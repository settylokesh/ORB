//
//  ModelDownloader.swift
//  ORB
//
//  Downloads a list of files sequentially with real aggregate byte progress and
//  supports pause / resume. Built on URLSessionDownloadTask via the *delegate*
//  API (URLSessionDownloadDelegate) because that is the only path that streams
//  incremental progress on macOS — the completion-handler convenience variant's
//  `task.progress.completedUnitCount` does not update until the transfer ends,
//  which made multi-GB models look frozen at 0% (and so "never install"). With
//  `didWriteData` the UI moves in real time, and resume across pauses uses the
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

    /// Reports (downloadedBytes, totalBytes) on the main queue while running.
    var onProgress: ((Int64, Int64) -> Void)?

    private let lock = NSLock()
    private var session: URLSession!

    private var baseBytes: Int64 = 0          // bytes from fully-completed files, this run
    private var isPaused = false
    private var pausedResumeData: Data?
    private var lastReported: Int64 = -1

    // Per-file delegate plumbing (only one file is ever in flight).
    private var currentTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?

    init(files: [FileSpec]) {
        self.files = files
        self.grandTotal = max(1, files.reduce(0) { $0 + $1.size })
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60 * 8   // allow very large downloads
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    private func sync<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    /// Run (or continue) the download. Throws `DownloadPaused.paused` when paused,
    /// or a network error on failure. Returns normally when everything is on disk.
    func run() async throws {
        sync { isPaused = false; baseBytes = 0; lastReported = -1 }
        for f in files {
            if Self.isComplete(f) {
                let done = sync { baseBytes += f.size; return baseBytes }
                report(done, force: true)
                continue
            }
            try await downloadOne(f)
            let done = sync { baseBytes += f.size; return baseBytes }
            report(done, force: true)
        }
        // Everything is on disk — tear the session down so the delegate retain
        // cycle (session ↔︎ self) doesn't keep this instance alive forever.
        session.finishTasksAndInvalidate()
    }

    /// Pause the in-flight file (completed files stay on disk; the current file
    /// resumes from where it left off via the system's resume data).
    func pause() {
        let task = sync { () -> URLSessionDownloadTask? in isPaused = true; return currentTask }
        task?.cancel(byProducingResumeData: { [weak self] data in
            guard let self, let data else { return }
            self.sync { if self.pausedResumeData == nil { self.pausedResumeData = data } }
        })
    }

    /// Stop everything and release the session. Call when discarding a downloader
    /// that will not be resumed (e.g. the user changed the models folder).
    func invalidate() {
        let task = sync { () -> URLSessionDownloadTask? in isPaused = true; return currentTask }
        task?.cancel()
        session.invalidateAndCancel()
    }

    // MARK: - One file

    private func downloadOne(_ f: FileSpec) async throws {
        try FileManager.default.createDirectory(
            at: f.dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        let stableTemp: URL = try await withCheckedThrowingContinuation { cont in
            sync {
                self.continuation = cont
                let resume = self.pausedResumeData
                self.pausedResumeData = nil
                let task = resume.map { self.session.downloadTask(withResumeData: $0) }
                    ?? self.session.downloadTask(with: f.remote)
                self.currentTask = task
                task.resume()
            }
        }

        try? FileManager.default.removeItem(at: f.dest)
        try FileManager.default.moveItem(at: stableTemp, to: f.dest)
    }

    /// Resume the awaiting continuation exactly once.
    private func finish(_ result: Result<URL, Error>) {
        let cont = sync { () -> CheckedContinuation<URL, Error>? in
            let c = continuation
            continuation = nil
            currentTask = nil
            return c
        }
        guard let cont else { return }
        switch result {
        case .success(let url): cont.resume(returning: url)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    private func report(_ done: Int64, force: Bool = false) {
        let total = grandTotal
        // Throttle by byte delta so a multi-GB file doesn't flood the main queue
        // with thousands of identical UI updates; always send the final value.
        let shouldSend = sync { () -> Bool in
            if force || lastReported < 0 || done >= total
                || done - lastReported >= max(total / 400, 1_048_576) {
                lastReported = done
                return true
            }
            return false
        }
        guard shouldSend else { return }
        DispatchQueue.main.async { [weak self] in self?.onProgress?(done, total) }
    }

    static func isComplete(_ f: FileSpec) -> Bool {
        guard let size = try? f.dest.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return f.size > 0 ? Int64(size) >= f.size : size > 0
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {

    /// Live progress — fires repeatedly as bytes stream in.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let base = sync { baseBytes }
        report(min(base + totalBytesWritten, grandTotal))
    }

    /// Success: the temp file at `location` is removed the moment this returns,
    /// so move it to a stable spot now and hand it back to `downloadOne`.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let stable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try? FileManager.default.removeItem(at: stable)
            try FileManager.default.moveItem(at: location, to: stable)
            finish(.success(stable))
        } catch {
            finish(.failure(error))
        }
    }

    /// Completion / failure. Success already resolved in `didFinishDownloadingTo`,
    /// so here we only handle errors (including a pause that produced resume data).
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let paused = sync { isPaused }
        if paused {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                sync { if pausedResumeData == nil { pausedResumeData = data } }
            }
            finish(.failure(DownloadPaused.paused))
        } else {
            finish(.failure(error))
        }
    }
}
