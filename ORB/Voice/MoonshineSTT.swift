//
//  MoonshineSTT.swift
//  ORB
//
//  Real streaming speech-to-text with Moonshine (base) on ONNX Runtime.
//
//  Pipeline:  raw 16 kHz audio → encoder_model → last_hidden_state
//             → decoder_model (1st token) → decoder_with_past_model (loop)
//             → greedy tokens → MoonshineTokenizer → text
//
//  KV-cache is threaded by name: every `present.*` output is fed back as the
//  matching `past_key_values.*` input, so the layer count and tensor shapes are
//  discovered from the model itself — nothing is hardcoded.
//

import Foundation
import AVFoundation
import OnnxRuntimeBindings

@MainActor
final class MoonshineSTT: STTEngine {

    let displayName = "Moonshine Base"
    private(set) var isReady = false
    private(set) var ramMB = 0
    private(set) var lastLatencyMS = 0

    private let models: ModelManager
    private var runner: MoonshineRunner?

    // Streaming state
    private var samples: [Float] = []
    private var onPartial: ((String) -> Void)?
    private var partialTimer: Timer?
    private var decoding = false

    /// 16 kHz; only re-decode partials once we have enough new audio.
    private let sampleRate: Double = 16_000

    init(models: ModelManager) { self.models = models }

    func load() async throws {
        guard runner == nil else { isReady = true; return }
        guard models.moonshine.isReady else { throw ORBError.modelNotDownloaded("Moonshine") }
        let dir = models.moonshineDir
        let before = ProcessRAM.residentMB()
        let r = try await Task.detached(priority: .userInitiated) {
            try MoonshineRunner(directory: dir)
        }.value
        runner = r
        ramMB = max(0, ProcessRAM.residentMB() - before)
        isReady = true
    }

    func unload() {
        partialTimer?.invalidate(); partialTimer = nil
        runner = nil
        isReady = false
        samples.removeAll()
    }

    func beginStreaming(onPartial: @escaping (String) -> Void) {
        self.onPartial = onPartial
        samples.removeAll(keepingCapacity: true)
        partialTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.emitPartial() }
        }
    }

    func feed(_ chunk: AVAudioPCMBuffer) {
        guard let data = chunk.floatChannelData?[0] else { return }
        let n = Int(chunk.frameLength)
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n))
    }

    private func emitPartial() async {
        guard !decoding, let runner, samples.count > Int(sampleRate * 0.4) else { return }
        decoding = true
        let snapshot = samples
        let text = await Task.detached(priority: .utility) { (try? runner.transcribe(snapshot)) ?? "" }.value
        decoding = false
        if !text.isEmpty { onPartial?(text) }
    }

    func finishStreaming() async -> String {
        partialTimer?.invalidate(); partialTimer = nil
        guard let runner, !samples.isEmpty else { return "" }
        let snapshot = samples
        let start = Date()
        let text = await Task.detached(priority: .userInitiated) { (try? runner.transcribe(snapshot)) ?? "" }.value
        lastLatencyMS = Int(Date().timeIntervalSince(start) * 1000)
        return text
    }
}

// MARK: - ONNX Runtime worker (runs off the main actor)

/// Owns the three ORT sessions + tokenizer and performs greedy decoding.
/// Not `@MainActor`: all heavy work happens on background tasks.
final class MoonshineRunner: @unchecked Sendable {

    private let env: ORTEnv
    private let encoder: ORTSession
    private let decoder: ORTSession           // first step, no past
    private let decoderWithPast: ORTSession   // subsequent steps
    private let tokenizer: MoonshineTokenizer

    private let encoderInputName: String
    private let encoderOutputName: String
    private let decoderInputNames: [String]
    private let decoderOutputNames: [String]
    private let pastInputNames: [String]
    private let pastOutputNames: [String]

    private let decoderStartTokenId: Int
    private let eosTokenId: Int
    private let maxNewTokens: Int

    init(directory: URL) throws {
        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let opts = try ORTSessionOptions()
        try opts.setGraphOptimizationLevel(.all)

        func makeSession(_ file: String) throws -> ORTSession {
            try ORTSession(env: env,
                           modelPath: directory.appendingPathComponent(file).path,
                           sessionOptions: opts)
        }
        let enc = try makeSession("encoder_model.onnx")
        let dec = try makeSession("decoder_model.onnx")
        let decP = try makeSession("decoder_with_past_model.onnx")

        self.env = env
        self.encoder = enc
        self.decoder = dec
        self.decoderWithPast = decP

        self.encoderInputName  = (try? enc.inputNames())?.first ?? "input_values"
        self.encoderOutputName = (try? enc.outputNames())?.first ?? "last_hidden_state"
        self.decoderInputNames = (try? dec.inputNames()) ?? ["input_ids", "encoder_hidden_states"]
        self.decoderOutputNames = (try? dec.outputNames()) ?? ["logits"]
        self.pastInputNames = (try? decP.inputNames()) ?? ["input_ids", "encoder_hidden_states"]
        self.pastOutputNames = (try? decP.outputNames()) ?? ["logits"]

        self.tokenizer = try MoonshineTokenizer(tokenizerJSON: directory.appendingPathComponent("tokenizer.json"))

        // Special tokens from generation/model config (with sane Moonshine defaults).
        let gen = MoonshineRunner.loadJSON(directory.appendingPathComponent("generation_config.json"))
        let cfg = MoonshineRunner.loadJSON(directory.appendingPathComponent("config.json"))
        decoderStartTokenId = (gen?["decoder_start_token_id"] as? Int) ?? (cfg?["decoder_start_token_id"] as? Int) ?? 1
        eosTokenId = (gen?["eos_token_id"] as? Int) ?? (cfg?["eos_token_id"] as? Int) ?? 2
        maxNewTokens = (cfg?["max_position_embeddings"] as? Int) ?? 200
    }

    private static func loadJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Inference

    func transcribe(_ audio: [Float]) throws -> String {
        guard audio.count > 240 else { return "" }   // < 15 ms is noise

        // 1. Encoder: raw audio [1, N] → last_hidden_state.
        let audioTensor = try Self.floatTensor(audio, shape: [1, NSNumber(value: audio.count)])
        let encOut = try encoder.run(withInputs: [encoderInputName: audioTensor],
                                     outputNames: Set([encoderOutputName]),
                                     runOptions: nil)
        guard let hidden = encOut[encoderOutputName] else { return "" }

        // 2. First decode step (no past).
        var ids: [Int] = []
        var inputs: [String: ORTValue] = [
            "input_ids": try Self.int64Tensor([Int64(decoderStartTokenId)], shape: [1, 1]),
            "encoder_hidden_states": hidden,
        ]
        var out = try decoder.run(withInputs: filter(inputs, to: decoderInputNames),
                                  outputNames: Set(decoderOutputNames),
                                  runOptions: nil)
        var token = try argmaxLastToken(out["logits"])
        var past = pastFromPresent(out)

        // 3. Greedy loop with KV cache.
        var steps = 0
        while token != eosTokenId && steps < maxNewTokens {
            ids.append(token)
            steps += 1
            inputs = [
                "input_ids": try Self.int64Tensor([Int64(token)], shape: [1, 1]),
                "encoder_hidden_states": hidden,
            ]
            for (k, v) in past { inputs[k] = v }
            out = try decoderWithPast.run(withInputs: filter(inputs, to: pastInputNames),
                                          outputNames: Set(pastOutputNames),
                                          runOptions: nil)
            token = try argmaxLastToken(out["logits"])
            // Update only the caches the model re-emits; encoder caches persist.
            for (name, value) in pastFromPresent(out) { past[name] = value }
        }

        return tokenizer.decode(ids)
    }

    /// Keep only the inputs the session actually declares.
    private func filter(_ provided: [String: ORTValue], to names: [String]) -> [String: ORTValue] {
        var result: [String: ORTValue] = [:]
        for n in names where provided[n] != nil { result[n] = provided[n] }
        return result
    }

    /// Map every `present.*` output to its `past_key_values.*` input name.
    private func pastFromPresent(_ outputs: [String: ORTValue]) -> [String: ORTValue] {
        var past: [String: ORTValue] = [:]
        for (name, value) in outputs where name.hasPrefix("present.") {
            past["past_key_values." + name.dropFirst("present.".count)] = value
        }
        return past
    }

    private func argmaxLastToken(_ logits: ORTValue?) throws -> Int {
        guard let logits else { throw ORBError.actionFailed("decoder produced no logits") }
        let info = try logits.tensorTypeAndShapeInfo()
        let shape = try info.shape.map { $0.intValue }            // [1, seq, vocab]
        let vocab = shape.last ?? 0
        guard vocab > 0 else { return eosTokenId }
        let seq = shape.count >= 2 ? shape[shape.count - 2] : 1
        let data = try logits.tensorData() as Data
        return data.withUnsafeBytes { raw -> Int in
            let ptr = raw.bindMemory(to: Float.self)
            let base = (seq - 1) * vocab
            var best = 0
            var bestVal = -Float.greatestFiniteMagnitude
            for v in 0..<vocab {
                let value = ptr[base + v]
                if value > bestVal { bestVal = value; best = v }
            }
            return best
        }
    }

    // MARK: Tensor builders

    static func floatTensor(_ values: [Float], shape: [NSNumber]) throws -> ORTValue {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Float>.size)
        return try ORTValue(tensorData: data, elementType: .float, shape: shape)
    }

    static func int64Tensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Int64>.size)
        return try ORTValue(tensorData: data, elementType: .int64, shape: shape)
    }
}

/// Tiny resident-memory probe shared by the engines.
enum ProcessRAM {
    static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / (1024 * 1024))
    }
}
