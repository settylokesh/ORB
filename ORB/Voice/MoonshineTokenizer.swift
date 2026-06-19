//
//  MoonshineTokenizer.swift
//  ORB
//
//  Minimal, self-contained decoder for Moonshine's `tokenizer.json` (a
//  SentencePiece-style BPE). Implements the model's decoder pipeline:
//    Replace ▁ → space · ByteFallback (<0xHH>) · Fuse · Strip leading space
//

import Foundation

struct MoonshineTokenizer {

    private let idToToken: [Int: String]
    private let specialIds: Set<Int>

    init(tokenizerJSON url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ORBError.modelNotDownloaded("Moonshine tokenizer")
        }

        var map: [Int: String] = [:]
        var specials: Set<Int> = []

        if let model = root["model"] as? [String: Any],
           let vocab = model["vocab"] as? [String: Any] {
            for (token, idValue) in vocab {
                if let id = (idValue as? NSNumber)?.intValue { map[id] = token }
            }
        }
        if let added = root["added_tokens"] as? [[String: Any]] {
            for entry in added {
                guard let id = (entry["id"] as? NSNumber)?.intValue,
                      let content = entry["content"] as? String else { continue }
                map[id] = content
                if (entry["special"] as? NSNumber)?.boolValue == true { specials.insert(id) }
            }
        }
        // Core specials are always suppressed in output.
        specials.formUnion([0, 1, 2])

        self.idToToken = map
        self.specialIds = specials
    }

    /// Decode token ids to text, skipping special tokens.
    func decode(_ ids: [Int]) -> String {
        var out = ""
        var byteBuffer: [UInt8] = []

        func flushBytes() {
            guard !byteBuffer.isEmpty else { return }
            out += String(decoding: byteBuffer, as: UTF8.self)
            byteBuffer.removeAll(keepingCapacity: true)
        }

        for id in ids {
            if specialIds.contains(id) { continue }
            guard let token = idToToken[id] else { continue }

            // ByteFallback tokens: "<0xHH>"
            if token.count == 6, token.hasPrefix("<0x"), token.hasSuffix(">"),
               let byte = UInt8(token.dropFirst(3).dropLast(), radix: 16) {
                byteBuffer.append(byte)
                continue
            }
            // Suppress any other angle-bracket control tokens, e.g. "<<ST_3>>".
            if token.hasPrefix("<") && token.hasSuffix(">") && token.contains("ST_") { continue }

            flushBytes()
            out += token.replacingOccurrences(of: "\u{2581}", with: " ")
        }
        flushBytes()

        if out.hasPrefix(" ") { out.removeFirst() }
        return out
    }
}
