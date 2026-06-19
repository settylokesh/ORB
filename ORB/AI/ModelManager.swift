//
//  ModelManager.swift
//  ORB
//
//  Owns the two real on-device models and their lifecycle:
//    • Moonshine (base) — streaming speech-to-text, ONNX Runtime
//    • Gemma 4 E4B (4-bit) — vision + intent, MLX
//
//  Downloads are real Hugging Face fetches with live byte-progress, stored on
//  disk and reused offline. Nothing here is simulated.
//

import Foundation
import Combine
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

@MainActor
final class ModelManager: ObservableObject {

    enum Phase: Equatable {
        case notDownloaded
        case downloading(Double)      // 0...1
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
        var fraction: Double {
            switch self {
            case .ready: return 1
            case .downloading(let f): return f
            default: return 0
            }
        }
    }

    @Published private(set) var moonshine: Phase = .notDownloaded
    @Published private(set) var gemma: Phase = .notDownloaded

    /// Bytes downloaded / total, for human-readable labels.
    @Published private(set) var moonshineBytes: (Int64, Int64) = (0, 0)
    @Published private(set) var gemmaBytes: (Int64, Int64) = (0, 0)

    // MARK: - Storage layout

    // Moonshine "base" — the standard small English streaming model, exported as
    // a clean (non-merged) optimum encoder/decoder pair with named KV tensors.
    static let moonshineRepo = "onnx-community/moonshine-base-ONNX"
    static let gemmaConfiguration = VLMRegistry.gemma4_E4B_it_4bit   // mlx-community/gemma-4-e4b-it-4bit

    /// Files the Moonshine engine needs (HF path -> local filename).
    static let moonshineFiles: [(remote: String, local: String)] = [
        ("onnx/encoder_model.onnx",            "encoder_model.onnx"),
        ("onnx/decoder_model.onnx",            "decoder_model.onnx"),
        ("onnx/decoder_with_past_model.onnx",  "decoder_with_past_model.onnx"),
        ("tokenizer.json",                     "tokenizer.json"),
        ("config.json",                        "config.json"),
        ("generation_config.json",             "generation_config.json"),
    ]

    var modelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORB/Models", isDirectory: true)
    }
    var moonshineDir: URL { modelsRoot.appendingPathComponent("moonshine", isDirectory: true) }

    /// The loaded Gemma container, shared with the engine once downloaded.
    private(set) var gemmaContainer: ModelContainer?

    var bothReady: Bool { moonshine.isReady && gemma.isReady }

    // MARK: - Lifecycle

    init() { refresh() }

    /// Reconcile published state with what is already on disk.
    func refresh() {
        if moonshineFilesPresent { moonshine = .ready }
        if gemmaCachePresent { gemma = .ready }
    }

    private var moonshineFilesPresent: Bool {
        Self.moonshineFiles.allSatisfy { f in
            let url = moonshineDir.appendingPathComponent(f.local)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            return size > 0
        }
    }

    /// Gemma is considered present if MLX has previously cached its weights.
    private var gemmaCachePresent: Bool {
        UserDefaults.standard.bool(forKey: "orb.gemma.downloaded")
    }

    // MARK: - Moonshine download (URLSession, real byte progress)

    func downloadMoonshine() async {
        guard !moonshine.isReady else { return }
        moonshine = .downloading(0)
        do {
            try FileManager.default.createDirectory(at: moonshineDir, withIntermediateDirectories: true)

            // Probe total size for an accurate aggregate progress bar.
            var totals: [Int64] = []
            for f in Self.moonshineFiles {
                totals.append(try await contentLength(for: remoteURL(f.remote)))
            }
            let grandTotal = max(1, totals.reduce(0, +))
            moonshineBytes = (0, grandTotal)

            var completed: Int64 = 0
            for (i, f) in Self.moonshineFiles.enumerated() {
                let dest = moonshineDir.appendingPathComponent(f.local)
                if let size = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                    completed += totals[i]
                    continue
                }
                try await download(remoteURL(f.remote), to: dest, fileBytes: totals[i]) { [weak self] bytesThisFile in
                    guard let self else { return }
                    let done = completed + bytesThisFile
                    self.moonshineBytes = (done, grandTotal)
                    self.moonshine = .downloading(Double(done) / Double(grandTotal))
                }
                completed += totals[i]
            }
            moonshine = .ready
            moonshineBytes = (grandTotal, grandTotal)
        } catch {
            moonshine = .failed(error.localizedDescription)
        }
    }

    private func remoteURL(_ path: String) -> URL {
        URL(string: "https://huggingface.co/\(Self.moonshineRepo)/resolve/main/\(path)")!
    }

    private func contentLength(for url: URL) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.expectedContentLength ?? resp.expectedContentLength
    }

    /// Streamed download with periodic progress, written atomically to `dest`.
    private func download(_ url: URL, to dest: URL, fileBytes: Int64,
                          progress: @escaping (Int64) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = max(fileBytes, (response as? HTTPURLResponse)?.expectedContentLength ?? fileBytes)
        let tmp = dest.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }

        var buffer = Data(capacity: 1 << 20)
        var received: Int64 = 0
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 20) {
                handle.write(buffer); received += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.1 { progress(min(received, total)); lastReport = Date() }
            }
        }
        if !buffer.isEmpty { handle.write(buffer); received += Int64(buffer.count) }
        try? handle.close()
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: tmp, to: dest)
        progress(total)
    }

    // MARK: - Gemma download (MLX, real progress via Hugging Face Hub)

    func downloadGemma() async {
        guard !gemma.isReady || gemmaContainer == nil else { return }
        gemma = .downloading(0)
        do {
            let container = try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: Self.gemmaConfiguration
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.gemmaBytes = (Int64(progress.completedUnitCount), Int64(max(1, progress.totalUnitCount)))
                    self.gemma = .downloading(progress.fractionCompleted)
                }
            }
            gemmaContainer = container
            UserDefaults.standard.set(true, forKey: "orb.gemma.downloaded")
            gemma = .ready
        } catch {
            gemma = .failed(error.localizedDescription)
        }
    }

    /// Loads (from cache, fast) and returns the Gemma container, downloading if needed.
    func loadGemmaContainer() async throws -> ModelContainer {
        if let c = gemmaContainer { return c }
        let container = try await VLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: Self.gemmaConfiguration
        ) { [weak self] progress in
            Task { @MainActor in self?.gemma = .downloading(progress.fractionCompleted) }
        }
        gemmaContainer = container
        UserDefaults.standard.set(true, forKey: "orb.gemma.downloaded")
        gemma = .ready
        return container
    }
}
