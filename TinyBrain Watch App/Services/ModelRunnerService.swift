import Foundation
import CoreML

final class ModelRunnerService {
    static let shared = ModelRunnerService()
    private var model: MLModel?
    private var tokenizer: RealTokenizer?

    func loadModel(from url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }

        let modelURL: URL?
        if isDir.boolValue {
            modelURL = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "mlmodelc" }
        } else {
            modelURL = url
        }
        guard let mURL = modelURL, let m = try? MLModel(contentsOf: mURL) else { return false }
        model = m

        let bundle = Bundle.main
        var cand: [String] = []
        cand.append(url.appendingPathComponent("tokenizer").path)
        cand.append(url.path)
        if let p = bundle.path(forResource: "tokenizer", ofType: nil) { cand.append(p) }
        if let rp = bundle.resourcePath { cand.append(rp) }
        if let rp = bundle.resourcePath { cand.append((rp as NSString).appendingPathComponent("Models")) }

        for base in cand {
            if let tok = RealTokenizer(basePath: base) { tokenizer = tok; break }
        }
        return tokenizer != nil
    }

    func predict(from input: String) -> (text: String, speed: Double) {
        guard let model = model else { return ("⚠️ No model loaded.", 0) }
        guard let tokenizer = tokenizer else { return ("❌ Tokenizer not initialized.", 0) }

        var ids = tokenizer.encode(input)
        if ids.isEmpty { return ("❌ Input too short or unknown tokens.", 0) }

        let maxLen = 32
        let maxNew = 32
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<maxNew {
            let cur = Array(ids.suffix(maxLen))
            let padCount = max(0, maxLen - cur.count)
            let padded = (padCount > 0 ? Array(repeating: tokenizer.pad, count: padCount) : []) + cur
            let attn = Array(repeating: 1, count: cur.count) + Array(repeating: 0, count: padCount)

            guard
                let idsArr = try? MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32),
                let maskArr = try? MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
            else { break }

            for (i, t) in padded.enumerated() { idsArr[[0, i] as [NSNumber]] = NSNumber(value: t) }
            for (i, m) in attn.enumerated() { maskArr[[0, i] as [NSNumber]] = NSNumber(value: m) }

            guard
                let feats = try? MLDictionaryFeatureProvider(dictionary: ["input_ids": idsArr, "attention_mask": maskArr]),
                let out = try? model.prediction(from: feats),
                let logits = out.featureNames.compactMap({ out.featureValue(for: $0)?.multiArrayValue }).first
            else { break }

            let shape = logits.shape.map { $0.intValue }
            if shape.count != 3 { break }
            let T = shape[1], V = shape[2]
            let used = min(cur.count, T)
            let step = max(used - 1, 0)

            var nextId = 0
            switch logits.dataType {
            case .float16:
                let p = UnsafeMutablePointer<Float16>(OpaquePointer(logits.dataPointer))
                var best = Float16(-Float.greatestFiniteMagnitude)
                let base = step * V
                for v in 0..<V { let val = p[base + v]; if val > best { best = val; nextId = v } }
            case .float32:
                let p = UnsafeMutablePointer<Float32>(OpaquePointer(logits.dataPointer))
                var best: Float32 = -Float.greatestFiniteMagnitude
                let base = step * V
                for v in 0..<V { let val = p[base + v]; if val > best { best = val; nextId = v } }
            case .double:
                let p = UnsafeMutablePointer<Double>(OpaquePointer(logits.dataPointer))
                var best: Double = -Double.greatestFiniteMagnitude
                let base = step * V
                for v in 0..<V { let val = p[base + v]; if val > best { best = val; nextId = v } }
            default:
                break
            }

            ids.append(nextId)
            if nextId == tokenizer.eos { break }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let gen = ids.suffix(maxNew)
        let text = tokenizer.decode(Array(gen))
        let tps = Double(gen.count) / max(elapsed, 1e-6)
        return (text, tps)
    }

    func getModelMetadata() -> [String] {
        guard let model = model else { return ["⚠️ No model loaded."] }
        var lines: [String] = []
        lines.append("✅ Model loaded successfully")
        lines.append("🟢 Inputs:")
        for (n, d) in model.modelDescription.inputDescriptionsByName { lines.append("- \(n): \(String(describing: d.type))") }
        lines.append("🔵 Outputs:")
        for (n, d) in model.modelDescription.outputDescriptionsByName { lines.append("- \(n): \(String(describing: d.type))") }
        return lines
    }
}
