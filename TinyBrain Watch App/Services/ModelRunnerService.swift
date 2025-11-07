import Foundation
import CoreML

final class ModelRunnerService {
    static let shared = ModelRunnerService()
    private var model: MLModel?
    private var tokenizer: RealTokenizer?
    private var seqLen: Int = 16
    private var respectsMask: Bool?
    private var temperature: Float = 0.8
    private var topK: Int = 50
    private var topP: Float = 0.9
    private var freqPenalty: Float = 0.3
    private var presencePenalty: Float = 0.1

    func setSampling(temperature: Float? = nil, topK: Int? = nil, topP: Float? = nil, freqPenalty: Float? = nil, presencePenalty: Float? = nil) {
        if let v = temperature { self.temperature = max(0.01, v) }
        if let v = topK { self.topK = max(1, v) }
        if let v = topP { self.topP = min(0.999, max(0.0, v)) }
        if let v = freqPenalty { self.freqPenalty = max(0, v) }
        if let v = presencePenalty { self.presencePenalty = max(0, v) }
    }

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
        if let c = m.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint, c.shape.count >= 2 {
            seqLen = c.shape.last?.intValue ?? 16
        }
        let bundle = Bundle.main
        var candidates: [String] = []
        candidates.append(url.appendingPathComponent("tokenizer").path)
        candidates.append(url.path)
        if let p = bundle.path(forResource: "tokenizer", ofType: nil) { candidates.append(p) }
        if let rp = bundle.resourcePath { candidates.append(rp) }
        if let rp = bundle.resourcePath { candidates.append((rp as NSString).appendingPathComponent("Models")) }
        for base in candidates {
            if let tok = RealTokenizer(basePath: base) { tokenizer = tok; break }
        }
        return tokenizer != nil
    }

    func predict(from input: String) -> (text: String, speed: Double) {
        guard let model = model else { return ("", 0) }
        guard let tokenizer = tokenizer else { return ("", 0) }
        var ids = tokenizer.encode(input)
        if ids.isEmpty { return ("", 0) }
        let L = seqLen
        let maxNew = 64
        let t0 = CFAbsoluteTimeGetCurrent()
        var counts: [Int:Int] = [:]

        for _ in 0..<maxNew {
            let cur = Array(ids.suffix(L))
            let padCount = max(0, L - cur.count)
            let useLeftPad: Bool = {
                if let r = respectsMask { return !r }
                guard let a = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32),
                      let m = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32) else { return true }
                for i in 0..<L { a[[0,i] as [NSNumber]] = NSNumber(value: 0) }
                for i in 0..<L { m[[0,i] as [NSNumber]] = NSNumber(value: 0) }
                let out0 = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": a,"attention_mask": m]))
                for i in 0..<L { m[[0,i] as [NSNumber]] = NSNumber(value: 1) }
                let out1 = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": a,"attention_mask": m]))
                let diff: Bool = {
                    guard let o0 = out0, let o1 = out1 else { return false }
                    guard let l0 = ModelRunnerService.logitsArray(from: o0), let l1 = ModelRunnerService.logitsArray(from: o1) else { return false }
                    let s0 = l0.shape.map{$0.intValue}; let s1 = l1.shape.map{$0.intValue}
                    if s0 != s1 { return true }
                    let n = min(1024, totalCount(of: l0))
                    let p0 = UnsafeRawPointer(l0.dataPointer)
                    let p1 = UnsafeRawPointer(l1.dataPointer)
                    return memcmp(p0, p1, n) != 0
                }()
                respectsMask = diff
                return !(diff)
            }()

            let padded = useLeftPad ? Array(repeating: tokenizer.pad, count: padCount) + cur : cur + Array(repeating: tokenizer.pad, count: padCount)
            let mask = useLeftPad ? Array(repeating: 0, count: padCount) + Array(repeating: 1, count: cur.count) : Array(repeating: 1, count: cur.count) + Array(repeating: 0, count: padCount)
            guard let idsArr = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32),
                  let maskArr = try? MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .int32) else { break }
            for (i, t) in padded.enumerated() { idsArr[[0, i] as [NSNumber]] = NSNumber(value: t) }
            for (i, m) in mask.enumerated() { maskArr[[0, i] as [NSNumber]] = NSNumber(value: m) }
            guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": idsArr, "attention_mask": maskArr])),
                  let logits = ModelRunnerService.logitsArray(from: out) else { break }

            let shape = logits.shape.map{$0.intValue}
            if shape.count != 3 { break }
            let V = shape[2]
            let strides = logits.strides.map{$0.intValue}
            let step = useLeftPad ? (L-1) : max(0, min(shape[1]-1, cur.count-1))
            let base = 0*strides[0] + step*strides[1]

            var scores = [Float](repeating: -Float.greatestFiniteMagnitude, count: V)
            switch logits.dataType {
            case .float16:
                let p = UnsafeMutablePointer<Float16>(OpaquePointer(logits.dataPointer))
                for v in 0..<V { scores[v] = Float(p[base + v*strides[2]]) }
            case .float32:
                let p = UnsafeMutablePointer<Float32>(OpaquePointer(logits.dataPointer))
                for v in 0..<V { scores[v] = p[base + v*strides[2]] }
            case .double:
                let p = UnsafeMutablePointer<Double>(OpaquePointer(logits.dataPointer))
                for v in 0..<V { scores[v] = Float(p[base + v*strides[2]]) }
            default:
                break
            }

            if freqPenalty > 0 || presencePenalty > 0 {
                for (tok, c) in counts {
                    let fp = freqPenalty * Float(c)
                    let pp = presencePenalty * (c > 0 ? 1 : 0).toFloat
                    if tok < V { scores[tok] -= (fp + pp) }
                }
            }

            let nextId = sampleToken(from: scores, temperature: temperature, topK: topK, topP: topP)
            ids.append(nextId)
            counts[nextId, default: 0] += 1
            if nextId == tokenizer.eos { break }
        }

        let dt = max(CFAbsoluteTimeGetCurrent() - t0, 1e-6)
        let outIds = Array(ids.suffix(maxNew))
        let raw = tokenizer.decode(outIds)
        let text = cleanDecoded(raw)
        let tps = Double(outIds.count) / dt
        return (text, tps)
    }

    private func cleanDecoded(_ s: String) -> String {
        let a = s.replacingOccurrences(of: "�", with: "")
            .replacingOccurrences(of: "\n\n", with: "\n")
            .replacingOccurrences(of: "  ", with: " ")
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func logitsArray(from out: MLFeatureProvider) -> MLMultiArray? {
        for name in out.featureNames {
            if let a = out.featureValue(for: name)?.multiArrayValue {
                let shp = a.shape.map{$0.intValue}
                if shp.count == 3 && shp[2] >= 1000 { return a }
            }
        }
        return nil
    }

    private func sampleToken(from logits: [Float], temperature: Float, topK: Int, topP: Float) -> Int {
        var scores = logits
        let invT = 1.0 / max(0.01, temperature)
        for i in 0..<scores.count { scores[i] *= Float(invT) }

        var idxs = Array(0..<scores.count)
        idxs.sort { scores[$0] > scores[$1] }

        var cut = min(topK, scores.count)
        if topP < 0.999 {
            var s: Float = 0
            let maxScore = scores[idxs[0]]
            var probs = [Float](repeating: 0, count: idxs.count)
            for (i,t) in idxs.enumerated() { probs[i] = exp(scores[t] - maxScore) }
            let z = probs.reduce(0,+)
            for i in 0..<probs.count { probs[i] /= max(z, 1e-9) }
            for i in 0..<probs.count { s += probs[i]; if s >= topP { cut = min(cut, i+1); break } }
        }

        let selected = Array(idxs.prefix(cut))
        let maxSel = selected.map { scores[$0] }.max() ?? 0
        var probsSel = selected.map { exp(scores[$0] - maxSel) }
        let z = probsSel.reduce(0,+)
        if z <= 0 { return selected.first ?? 0 }
        for i in 0..<probsSel.count { probsSel[i] /= z }
        let r = Float.random(in: 0..<1)
        var acc: Float = 0
        for (i,tok) in selected.enumerated() {
            acc += probsSel[i]
            if r <= acc { return tok }
        }
        return selected.last ?? 0
    }

    private func totalCount(of a: MLMultiArray) -> Int {
        a.shape.map{ $0.intValue }.reduce(1, *)
    }

    func getModelMetadata() -> [String] {
        guard let model = model else { return [] }
        var lines: [String] = []
        lines.append("Model loaded")
        lines.append("Inputs:")
        for (n, d) in model.modelDescription.inputDescriptionsByName { lines.append("- \(n): \(String(describing: d.type))") }
        lines.append("Outputs:")
        for (n, d) in model.modelDescription.outputDescriptionsByName { lines.append("- \(n): \(String(describing: d.type))") }
        return lines
    }
}

private extension Int {
    var toFloat: Float { Float(self) }
}
