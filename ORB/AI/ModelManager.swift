//
//  ModelManager.swift
//  ORB
//
//  Owns the two real on-device models and their lifecycle:
//    • Moonshine (base) — streaming speech-to-text, ONNX Runtime
//    • Gemma 4 E4B (4-bit) — vision + intent, MLX
//
//  Both models are downloaded with our own pausable URLSession downloader
//  (see ModelDownloader) so progress is real, downloads resume, and each model
//  can be paused independently. Everything lands in one user-visible folder
//  (relocatable in Settings). Gemma is loaded from that local folder — no
//  network is touched at load time.
//

import Foundation
import Combine
import AppKit
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
        case paused(Double)           // 0...1, resumable
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
        var isDownloading: Bool { if case .downloading = self { return true }; return false }
        var isPaused: Bool { if case .paused = self { return true }; return false }
        var fraction: Double {
            switch self {
            case .ready: return 1
            case .downloading(let f), .paused(let f): return f
            default: return 0
            }
        }
    }

    @Published private(set) var moonshine: Phase = .notDownloaded
    @Published private(set) var gemma: Phase = .notDownloaded

    /// Bytes downloaded / total, for human-readable labels.
    @Published private(set) var moonshineBytes: (Int64, Int64) = (0, 0)
    @Published private(set) var gemmaBytes: (Int64, Int64) = (0, 0)

    // MARK: - Repos & file layout

    static let moonshineRepo = "onnx-community/moonshine-base-ONNX"
    static let gemmaRepo     = "mlx-community/gemma-4-e4b-it-4bit"

    /// Files the Moonshine engine needs (HF path -> local filename).
    static let moonshineFiles: [(remote: String, local: String)] = [
        ("onnx/encoder_model.onnx",            "encoder_model.onnx"),
        ("onnx/decoder_model.onnx",            "decoder_model.onnx"),
        ("onnx/decoder_with_past_model.onnx",  "decoder_with_past_model.onnx"),
        ("tokenizer.json",                     "tokenizer.json"),
        ("config.json",                        "config.json"),
        ("generation_config.json",             "generation_config.json"),
    ]

    private static let folderKey = "orb.models.folder"
    private static let gemmaCompleteKey = "orb.gemma.complete"

    /// The default models root inside Application Support.
    var defaultModelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORB/Models", isDirectory: true)
    }

    /// The single root that holds *every* model ORB downloads. Relocatable by the
    /// user (Settings → Model Storage); falls back to `defaultModelsRoot`.
    var modelsRoot: URL {
        if let p = UserDefaults.standard.string(forKey: Self.folderKey), !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return defaultModelsRoot
    }
    var isUsingDefaultFolder: Bool {
        (UserDefaults.standard.string(forKey: Self.folderKey) ?? "").isEmpty
    }

    var moonshineDir: URL { modelsRoot.appendingPathComponent("moonshine", isDirectory: true) }
    var gemmaDir: URL { modelsRoot.appendingPathComponent("gemma", isDirectory: true) }

    /// The loaded Gemma container, shared with the engine once downloaded.
    private(set) var gemmaContainer: ModelContainer?

    private var moonshineTask: Task<Void, Never>?
    private var gemmaTask: Task<Void, Never>?
    private var moonshineDownloader: ModelDownloader?
    private var gemmaDownloader: ModelDownloader?

    var bothReady: Bool { moonshine.isReady && gemma.isReady }

    // MARK: - Lifecycle

    init() { refresh() }

    /// Reconcile published state with what is already on disk, without clobbering
    /// an in-flight or paused download.
    func refresh() {
        moonshine = reconcile(moonshine, present: moonshineFilesPresent)
        gemma = reconcile(gemma, present: gemmaFilesPresent)
    }

    private func reconcile(_ phase: Phase, present: Bool) -> Phase {
        if present { return .ready }
        switch phase {
        case .downloading, .paused, .failed: return phase
        default: return .notDownloaded
        }
    }

    private var moonshineFilesPresent: Bool {
        Self.moonshineFiles.allSatisfy { f in
            let url = moonshineDir.appendingPathComponent(f.local)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            return size > 0
        }
    }

    /// Gemma counts as present only once a full download completed (flag) and the
    /// config still sits in the current folder — so a partial/paused set or a
    /// folder the user emptied is correctly treated as not-installed.
    private var gemmaFilesPresent: Bool {
        guard UserDefaults.standard.bool(forKey: Self.gemmaCompleteKey) else { return false }
        return FileManager.default.fileExists(atPath: gemmaDir.appendingPathComponent("config.json").path)
    }

    // MARK: - Download / pause / resume

    func downloadMoonshine() {
        guard !moonshine.isReady, !moonshine.isDownloading else { return }
        moonshine = .downloading(moonshine.fraction)
        moonshineTask = Task { [weak self] in await self?.runMoonshine() }
    }

    func pauseMoonshine() { moonshineDownloader?.pause() }

    func resumeMoonshine() {
        guard moonshine.isPaused else { downloadMoonshine(); return }
        moonshine = .downloading(moonshine.fraction)
        moonshineTask = Task { [weak self] in await self?.runMoonshine() }
    }

    func downloadGemma() {
        guard !gemma.isReady, !gemma.isDownloading else { return }
        gemma = .downloading(gemma.fraction)
        gemmaTask = Task { [weak self] in await self?.runGemma() }
    }

    func pauseGemma() { gemmaDownloader?.pause() }

    func resumeGemma() {
        guard gemma.isPaused else { downloadGemma(); return }
        gemma = .downloading(gemma.fraction)
        gemmaTask = Task { [weak self] in await self?.runGemma() }
    }

    private func runMoonshine() async {
        do {
            let dl = try await moonshineDownloaderInstance()
            try await dl.run()
            moonshine = .ready
            moonshineBytes = (dl.grandTotal, dl.grandTotal)
            moonshineDownloader = nil
        } catch is ModelDownloader.DownloadPaused {
            moonshine = .paused(moonshine.fraction)
        } catch {
            moonshine = .failed(friendly(error))
        }
    }

    private func runGemma() async {
        do {
            let dl = try await gemmaDownloaderInstance()
            try await dl.run()
            UserDefaults.standard.set(true, forKey: Self.gemmaCompleteKey)
            gemma = .ready
            gemmaBytes = (dl.grandTotal, dl.grandTotal)
            gemmaDownloader = nil
        } catch is ModelDownloader.DownloadPaused {
            gemma = .paused(gemma.fraction)
        } catch {
            gemma = .failed(friendly(error))
        }
    }

    /// Reuse the existing downloader (to keep resume data) or build a fresh one.
    private func moonshineDownloaderInstance() async throws -> ModelDownloader {
        if let dl = moonshineDownloader { return dl }
        try FileManager.default.createDirectory(at: moonshineDir, withIntermediateDirectories: true)
        let sizes = try await fetchSizes(repo: Self.moonshineRepo)
        let specs = Self.moonshineFiles.map { f in
            ModelDownloader.FileSpec(
                remote: hfURL(Self.moonshineRepo, f.remote),
                dest: moonshineDir.appendingPathComponent(f.local),
                size: sizes[f.remote] ?? 0)
        }
        let dl = ModelDownloader(files: specs)
        dl.onProgress = { [weak self] done, total in
            guard let self else { return }
            self.moonshineBytes = (done, total)
            if self.moonshine.isDownloading {
                self.moonshine = .downloading(total > 0 ? Double(done) / Double(total) : 0)
            }
        }
        moonshineDownloader = dl
        return dl
    }

    private func gemmaDownloaderInstance() async throws -> ModelDownloader {
        if let dl = gemmaDownloader { return dl }
        try FileManager.default.createDirectory(at: gemmaDir, withIntermediateDirectories: true)
        let tree = try await fetchTree(repo: Self.gemmaRepo)
        let excluded: Set<String> = [".gitattributes", "README.md", "LICENSE"]
        let specs = tree
            .filter { !excluded.contains($0.path) && !$0.path.hasSuffix(".md") }
            .map { e in
                ModelDownloader.FileSpec(
                    remote: hfURL(Self.gemmaRepo, e.path),
                    dest: gemmaDir.appendingPathComponent(e.path),
                    size: e.size)
            }
        guard !specs.isEmpty else { throw ORBError.modelNotDownloaded("Gemma 4 E4B") }
        let dl = ModelDownloader(files: specs)
        dl.onProgress = { [weak self] done, total in
            guard let self else { return }
            self.gemmaBytes = (done, total)
            if self.gemma.isDownloading {
                self.gemma = .downloading(total > 0 ? Double(done) / Double(total) : 0)
            }
        }
        gemmaDownloader = dl
        return dl
    }

    // MARK: - Loading (no network)

    /// Load the Gemma container from the local folder. Does **not** download —
    /// throws if the model isn't installed yet.
    func loadGemmaContainer() async throws -> ModelContainer {
        if let c = gemmaContainer { return c }
        guard gemmaFilesPresent else { throw ORBError.modelNotDownloaded("Gemma 4 E4B") }
        let container = try await VLMModelFactory.shared.loadContainer(
            from: gemmaDir, using: #huggingFaceTokenizerLoader())
        gemmaContainer = container
        gemma = .ready
        return container
    }

    // MARK: - Hugging Face metadata

    private func hfURL(_ repo: String, _ path: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(path)")!
    }

    /// List the files in a repo with their sizes via the HF tree API.
    private func fetchTree(repo: String) async throws -> [(path: String, size: Int64)] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=true")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard (item["type"] as? String) == "file", let path = item["path"] as? String else { return nil }
            let size = (item["size"] as? NSNumber)?.int64Value ?? 0
            return (path, size)
        }
    }

    private func fetchSizes(repo: String) async throws -> [String: Int64] {
        Dictionary(try await fetchTree(repo: repo).map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
    }

    private func friendly(_ error: Error) -> String {
        if (error as? URLError)?.code == .notConnectedToInternet { return "No internet connection." }
        return error.localizedDescription
    }

    // MARK: - Folder access & management

    /// Total size on disk of everything ORB has downloaded, human readable.
    var totalSizeLabel: String {
        let bytes = Self.directorySize(modelsRoot)
        guard bytes > 0 else { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Open the single models folder in Finder.
    func revealModelsFolder() {
        try? FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([modelsRoot])
    }

    /// Point the models root at a new folder (pass `nil` to reset to default).
    /// Cancels any in-flight downloads and re-checks what's present in the new spot.
    func setModelsFolder(_ url: URL?) {
        moonshineTask?.cancel(); gemmaTask?.cancel()
        moonshineDownloader?.invalidate(); gemmaDownloader?.invalidate()
        moonshineDownloader = nil; gemmaDownloader = nil
        gemmaContainer = nil
        if let url { UserDefaults.standard.set(url.path, forKey: Self.folderKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.folderKey) }
        moonshine = .notDownloaded; gemma = .notDownloaded
        moonshineBytes = (0, 0); gemmaBytes = (0, 0)
        refresh()
    }

    /// Delete every downloaded model and reset state (frees the whole folder).
    func deleteAllModels() {
        moonshineTask?.cancel(); gemmaTask?.cancel()
        moonshineDownloader?.invalidate(); gemmaDownloader?.invalidate()
        moonshineDownloader = nil; gemmaDownloader = nil
        gemmaContainer = nil
        try? FileManager.default.removeItem(at: moonshineDir)
        try? FileManager.default.removeItem(at: gemmaDir)
        UserDefaults.standard.set(false, forKey: Self.gemmaCompleteKey)
        moonshine = .notDownloaded
        gemma = .notDownloaded
        moonshineBytes = (0, 0)
        gemmaBytes = (0, 0)
    }

    /// Recursively sum the byte size of a directory tree.
    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in e {
            let v = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
