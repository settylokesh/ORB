//
//  ModelManager.swift
//  ORB
//
//  Owns the on-device models and their lifecycle:
//    • Moonshine (base) — streaming speech-to-text, ONNX Runtime
//    • Gemma 4 (4-bit) — vision + intent, MLX. Two interchangeable variants are
//      offered: E4B (larger, most capable) and E2B (the lighter mobile/edge
//      variant Google ships in the AI Edge Gallery). Both are downloadable; the
//      one the user selects drives automation.
//
//  Every model is downloaded with our own pausable URLSession downloader (see
//  ModelDownloader) so progress is real, downloads resume, and each model can be
//  paused independently. Everything lands in one user-visible folder (relocatable
//  in Settings). Gemma is loaded from that local folder — no network at load time.
//

import Foundation
import Combine
import AppKit
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Which on-device runtime a Gemma variant runs on.
enum GemmaRuntime: Equatable {
    case mlx        // Apple MLX, loaded by MLXGemmaEngine (VLMModelFactory)
    case litert     // Google LiteRT-LM (.litertlm), loaded by LiteRTGemmaEngine
}

/// The two interchangeable Gemma 4 automation models the user can pick between.
///   • E4B — Apple MLX 4-bit VLM (the model ORB has always shipped).
///   • E2B — the Gemma 4 E2B `.litertlm` Google ships in the AI Edge Gallery for
///           mobile/edge, run via the LiteRT-LM runtime (~2.54 GB).
/// E4B keeps the original on-disk folder/flag so existing installs aren't
/// re-downloaded.
enum GemmaVariant: String, CaseIterable, Identifiable, Codable {
    case e4b
    case e2b

    var id: String { rawValue }

    var runtime: GemmaRuntime {
        switch self {
        case .e4b: return .mlx
        case .e2b: return .litert
        }
    }

    /// Hugging Face repo the weights come from.
    var repo: String {
        switch self {
        case .e4b: return "mlx-community/gemma-4-e4b-it-4bit"
        case .e2b: return "litert-community/gemma-4-E2B-it-litert-lm"
        }
    }

    /// When set, download only these exact files instead of the whole repo tree.
    /// The `.litertlm` bundle is self-contained (weights + tokenizer + chat
    /// template), so a single file is all LiteRT-LM needs.
    var downloadFiles: [String]? {
        switch self {
        case .e4b: return nil                                   // whole repo tree
        case .e2b: return ["gemma-4-E2B-it.litertlm"]
        }
    }

    /// The model file the runtime loads, relative to the variant's folder.
    /// MLX loads a directory, so it has none; LiteRT loads this single file.
    var modelFileName: String? {
        switch self {
        case .e4b: return nil
        case .e2b: return "gemma-4-E2B-it.litertlm"
        }
    }

    /// A file whose presence (with the completion flag) means "installed".
    var presenceSentinel: String {
        switch self {
        case .e4b: return "config.json"
        case .e2b: return "gemma-4-E2B-it.litertlm"
        }
    }

    var displayName: String {
        switch self {
        case .e4b: return "Gemma 4 E4B"
        case .e2b: return "Gemma 4 E2B"
        }
    }

    /// Name with a runtime/format hint, as shown in lists.
    var menuLabel: String {
        switch self {
        case .e4b: return "Gemma 4 E4B · 4-bit"
        case .e2b: return "Gemma 4 E2B · LiteRT"
        }
    }

    var subtitle: String {
        switch self {
        case .e4b: return "VISION + INTENT · MLX"
        case .e2b: return "VISION + INTENT · LiteRT-LM"
        }
    }

    /// One-line note distinguishing the variants in pickers.
    var blurb: String {
        switch self {
        case .e4b: return "Larger · most capable · Apple MLX"
        case .e2b: return "Lighter · Google AI Edge Gallery model"
        }
    }

    /// Approximate on-disk download size, for the pre-download label.
    var approxSizeLabel: String {
        switch self {
        case .e4b: return "~5.2 GB"
        case .e2b: return "~2.5 GB"
        }
    }

    /// Folder under the models root. E4B keeps the legacy "gemma" folder so an
    /// existing download isn't orphaned by this change.
    var folderName: String {
        switch self {
        case .e4b: return "gemma"
        case .e2b: return "gemma-e2b-litert"
        }
    }

    /// UserDefaults flag marking a *completed* download for this variant.
    fileprivate var completeKey: String {
        switch self {
        case .e4b: return "orb.gemma.complete"
        case .e2b: return "orb.gemma-e2b-litert.complete"
        }
    }
}

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

    /// Per-variant Gemma download phase and byte progress.
    @Published private(set) var gemmaPhases: [GemmaVariant: Phase] = [:]
    @Published private(set) var gemmaByteMaps: [GemmaVariant: (Int64, Int64)] = [:]

    /// Which Gemma variant drives automation. Changing it drops any resident
    /// container so the next load maps the newly-selected weights.
    @Published var selectedGemma: GemmaVariant = .e4b {
        didSet {
            guard selectedGemma != oldValue else { return }
            UserDefaults.standard.set(selectedGemma.rawValue, forKey: Self.selectedKey)
            gemmaContainer = nil
            loadedGemma = nil
        }
    }

    /// Bytes downloaded / total for Moonshine, for human-readable labels.
    @Published private(set) var moonshineBytes: (Int64, Int64) = (0, 0)

    // MARK: - Repos & file layout

    static let moonshineRepo = "onnx-community/moonshine-base-ONNX"

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
    private static let selectedKey = "orb.gemma.selected"

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
    func gemmaDir(_ v: GemmaVariant) -> URL { modelsRoot.appendingPathComponent(v.folderName, isDirectory: true) }
    /// Folder of the model that currently drives automation.
    var gemmaDir: URL { gemmaDir(selectedGemma) }

    /// The loaded Gemma container, shared with the engine once downloaded, plus
    /// the variant it was loaded from (so a selection change re-maps the weights).
    private(set) var gemmaContainer: ModelContainer?
    private var loadedGemma: GemmaVariant?

    private var moonshineTask: Task<Void, Never>?
    private var gemmaTasks: [GemmaVariant: Task<Void, Never>] = [:]
    private var moonshineDownloader: ModelDownloader?
    private var gemmaDownloaders: [GemmaVariant: ModelDownloader] = [:]

    /// Phase/bytes of the active automation model (the selected variant).
    var gemma: Phase { phase(for: selectedGemma) }
    var gemmaBytes: (Int64, Int64) { bytes(for: selectedGemma) }

    func phase(for v: GemmaVariant) -> Phase { gemmaPhases[v] ?? .notDownloaded }
    func bytes(for v: GemmaVariant) -> (Int64, Int64) { gemmaByteMaps[v] ?? (0, 0) }

    var bothReady: Bool { moonshine.isReady && gemma.isReady }
    /// At least one Gemma variant is installed (any can drive automation).
    var anyGemmaReady: Bool { GemmaVariant.allCases.contains { phase(for: $0).isReady } }

    // MARK: - Lifecycle

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey),
           let v = GemmaVariant(rawValue: raw) {
            selectedGemma = v
        }
        refresh()
    }

    /// Reconcile published state with what is already on disk, without clobbering
    /// an in-flight or paused download.
    func refresh() {
        moonshine = reconcile(moonshine, present: moonshineFilesPresent, dir: moonshineDir)
        if moonshine.isPaused, let st = loadResumeState(dir: moonshineDir) { moonshineBytes = st }
        for v in GemmaVariant.allCases {
            let phase = reconcile(phase(for: v), present: gemmaFilesPresent(v), dir: gemmaDir(v))
            gemmaPhases[v] = phase
            if phase.isPaused, let st = loadResumeState(dir: gemmaDir(v)) { gemmaByteMaps[v] = st }
        }
    }

    private func reconcile(_ phase: Phase, present: Bool, dir: URL) -> Phase {
        if present { clearResumeState(dir: dir); return .ready }
        switch phase {
        case .downloading, .paused, .failed: return phase
        default:
            // Fresh launch: a download interrupted by quitting (or a failure) left a
            // saved partial on disk — surface it as resumable rather than as a brand
            // new "not downloaded", so the user continues instead of starting over.
            if let st = loadResumeState(dir: dir) {
                return .paused(st.1 > 0 ? Double(st.0) / Double(st.1) : 0)
            }
            return .notDownloaded
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
    /// variant's sentinel file still sits in the current folder — so a partial /
    /// paused set or a folder the user emptied is correctly treated as not-installed.
    private func gemmaFilesPresent(_ v: GemmaVariant) -> Bool {
        guard UserDefaults.standard.bool(forKey: v.completeKey) else { return false }
        return FileManager.default.fileExists(atPath: gemmaDir(v).appendingPathComponent(v.presenceSentinel).path)
    }

    /// On-disk URL of a LiteRT variant's `.litertlm` file (nil for MLX variants).
    /// Used by `LiteRTGemmaEngine` to point the runtime at the model.
    func gemmaModelFileURL(_ v: GemmaVariant) -> URL? {
        guard let file = v.modelFileName else { return nil }
        return gemmaDir(v).appendingPathComponent(file)
    }

    // MARK: - Download / pause / resume

    func downloadMoonshine() {
        guard !moonshine.isReady, !moonshine.isDownloading else { return }
        moonshine = .downloading(moonshine.fraction)
        moonshineTask = Task { [weak self] in await self?.runMoonshine() }
    }

    func pauseMoonshine() {
        moonshineDownloader?.pause()
        saveResumeState(dir: moonshineDir, bytes: moonshineBytes)
    }

    func resumeMoonshine() {
        guard moonshine.isPaused else { downloadMoonshine(); return }
        moonshine = .downloading(moonshine.fraction)
        moonshineTask = Task { [weak self] in await self?.runMoonshine() }
    }

    // Convenience overloads operating on the active automation model.
    func downloadGemma() { downloadGemma(selectedGemma) }
    func pauseGemma()    { pauseGemma(selectedGemma) }
    func resumeGemma()   { resumeGemma(selectedGemma) }

    func downloadGemma(_ v: GemmaVariant) {
        let p = phase(for: v)
        guard !p.isReady, !p.isDownloading else { return }
        gemmaPhases[v] = .downloading(p.fraction)
        gemmaTasks[v] = Task { [weak self] in await self?.runGemma(v) }
    }

    func pauseGemma(_ v: GemmaVariant) {
        gemmaDownloaders[v]?.pause()
        saveResumeState(dir: gemmaDir(v), bytes: bytes(for: v))
    }

    func resumeGemma(_ v: GemmaVariant) {
        guard phase(for: v).isPaused else { downloadGemma(v); return }
        gemmaPhases[v] = .downloading(phase(for: v).fraction)
        gemmaTasks[v] = Task { [weak self] in await self?.runGemma(v) }
    }

    /// True while any model is actively transferring (used to decide whether the
    /// app needs to capture resume state before quitting).
    var hasActiveDownload: Bool {
        moonshine.isDownloading || GemmaVariant.allCases.contains { phase(for: $0).isDownloading }
    }

    /// Capture and persist resume state for any in-flight downloads so the next
    /// launch continues instead of restarting at byte 0. Call from the app's
    /// `applicationShouldTerminate`. Safe to call when nothing is downloading.
    func prepareForTermination() async {
        if let dl = moonshineDownloader {
            await dl.suspendForTermination()
            saveResumeState(dir: moonshineDir, bytes: moonshineBytes)
        }
        for v in GemmaVariant.allCases {
            if let dl = gemmaDownloaders[v] {
                await dl.suspendForTermination()
                saveResumeState(dir: gemmaDir(v), bytes: bytes(for: v))
            }
        }
    }

    private func runMoonshine() async {
        do {
            let dl = try await moonshineDownloaderInstance()
            try await dl.run()
            // Ignore a late completion if a folder change / delete superseded us.
            guard moonshineDownloader === dl else { return }
            clearResumeState(dir: moonshineDir)
            moonshine = .ready
            moonshineBytes = (dl.grandTotal, dl.grandTotal)
            moonshineDownloader = nil
        } catch is ModelDownloader.DownloadPaused {
            if moonshine.isDownloading { moonshine = .paused(moonshine.fraction) }
        } catch {
            if moonshine.isDownloading { moonshine = .failed(friendly(error)) }
        }
    }

    private func runGemma(_ v: GemmaVariant) async {
        do {
            let dl = try await gemmaDownloaderInstance(v)
            try await dl.run()
            guard gemmaDownloaders[v] === dl else { return }
            UserDefaults.standard.set(true, forKey: v.completeKey)
            clearResumeState(dir: gemmaDir(v))
            gemmaPhases[v] = .ready
            gemmaByteMaps[v] = (dl.grandTotal, dl.grandTotal)
            gemmaDownloaders[v] = nil
            // If nothing was usable for automation before, adopt the model the user
            // just finished downloading so commands work without a manual switch.
            if !phase(for: selectedGemma).isReady { selectedGemma = v }
        } catch is ModelDownloader.DownloadPaused {
            if phase(for: v).isDownloading { gemmaPhases[v] = .paused(phase(for: v).fraction) }
        } catch {
            if phase(for: v).isDownloading { gemmaPhases[v] = .failed(friendly(error)) }
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

    private func gemmaDownloaderInstance(_ v: GemmaVariant) async throws -> ModelDownloader {
        if let dl = gemmaDownloaders[v] { return dl }
        let dir = gemmaDir(v)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tree = try await fetchTree(repo: v.repo)
        let sizes = Dictionary(tree.map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        let paths: [String]
        if let only = v.downloadFiles {
            // Single-file (LiteRT) download: just the named file(s).
            paths = only
        } else {
            // Whole repo tree, minus docs/metadata (MLX directory model).
            let excluded: Set<String> = [".gitattributes", "README.md", "LICENSE"]
            paths = tree.map(\.path).filter { !excluded.contains($0) && !$0.hasSuffix(".md") }
        }
        let specs = paths.map { path in
            ModelDownloader.FileSpec(
                remote: hfURL(v.repo, path),
                dest: dir.appendingPathComponent(path),
                size: sizes[path] ?? 0)
        }
        guard !specs.isEmpty else { throw ORBError.modelNotDownloaded(v.displayName) }
        let dl = ModelDownloader(files: specs)
        dl.onProgress = { [weak self] done, total in
            guard let self else { return }
            self.gemmaByteMaps[v] = (done, total)
            if self.phase(for: v).isDownloading {
                self.gemmaPhases[v] = .downloading(total > 0 ? Double(done) / Double(total) : 0)
            }
        }
        gemmaDownloaders[v] = dl
        return dl
    }

    // MARK: - Loading (no network)

    /// Load the *selected* MLX Gemma container from its local folder. Does **not**
    /// download — throws if that variant isn't installed yet. Re-maps when the
    /// selection changed since the last load. Only valid for MLX variants; LiteRT
    /// models are loaded by `LiteRTGemmaEngine` straight from their `.litertlm`.
    func loadGemmaContainer() async throws -> ModelContainer {
        let v = selectedGemma
        guard v.runtime == .mlx else { throw ORBError.modelNotDownloaded(v.displayName) }
        if let c = gemmaContainer, loadedGemma == v { return c }
        gemmaContainer = nil
        loadedGemma = nil
        guard gemmaFilesPresent(v) else { throw ORBError.modelNotDownloaded(v.displayName) }
        let container = try await VLMModelFactory.shared.loadContainer(
            from: gemmaDir(v), using: #huggingFaceTokenizerLoader())
        gemmaContainer = container
        loadedGemma = v
        gemmaPhases[v] = .ready
        return container
    }

    /// Drop the resident Gemma container to reclaim its memory. The model stays
    /// downloaded, so its phase remains `.ready`; the next `loadGemmaContainer`
    /// re-maps it from disk. Used by the engine's idle auto-unload.
    func releaseGemmaContainer() {
        gemmaContainer = nil
        loadedGemma = nil
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

    // MARK: - Resume state (downloaded/total) — drives the launch "PAUSED %" label

    private static let stateFile = ".orb-download-state.json"
    private func stateURL(_ dir: URL) -> URL { dir.appendingPathComponent(Self.stateFile) }

    /// Persist a model's byte progress so the next launch can show the right % and
    /// offer to resume. A complete or empty download clears the state instead.
    private func saveResumeState(dir: URL, bytes: (Int64, Int64)) {
        guard bytes.1 > 0, bytes.0 > 0, bytes.0 < bytes.1 else { clearResumeState(dir: dir); return }
        guard let data = try? JSONEncoder().encode(["downloaded": bytes.0, "total": bytes.1]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: stateURL(dir), options: .atomic)
    }

    private func loadResumeState(dir: URL) -> (Int64, Int64)? {
        guard let data = try? Data(contentsOf: stateURL(dir)),
              let dict = try? JSONDecoder().decode([String: Int64].self, from: data),
              let downloaded = dict["downloaded"], let total = dict["total"], total > 0
        else { return nil }
        return (downloaded, total)
    }

    private func clearResumeState(dir: URL) { try? FileManager.default.removeItem(at: stateURL(dir)) }

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
        moonshineTask?.cancel()
        gemmaTasks.values.forEach { $0.cancel() }; gemmaTasks.removeAll()
        moonshineDownloader?.invalidate()
        gemmaDownloaders.values.forEach { $0.invalidate() }; gemmaDownloaders.removeAll()
        moonshineDownloader = nil
        gemmaContainer = nil; loadedGemma = nil
        if let url { UserDefaults.standard.set(url.path, forKey: Self.folderKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.folderKey) }
        moonshine = .notDownloaded
        gemmaPhases.removeAll(); gemmaByteMaps.removeAll()
        moonshineBytes = (0, 0)
        refresh()
    }

    /// Delete every downloaded model and reset state (frees the whole folder).
    func deleteAllModels() {
        moonshineTask?.cancel()
        gemmaTasks.values.forEach { $0.cancel() }; gemmaTasks.removeAll()
        moonshineDownloader?.invalidate()
        gemmaDownloaders.values.forEach { $0.invalidate() }; gemmaDownloaders.removeAll()
        moonshineDownloader = nil
        gemmaContainer = nil; loadedGemma = nil
        try? FileManager.default.removeItem(at: moonshineDir)
        for v in GemmaVariant.allCases {
            try? FileManager.default.removeItem(at: gemmaDir(v))
            UserDefaults.standard.set(false, forKey: v.completeKey)
        }
        moonshine = .notDownloaded
        gemmaPhases.removeAll()
        gemmaByteMaps.removeAll()
        moonshineBytes = (0, 0)
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
