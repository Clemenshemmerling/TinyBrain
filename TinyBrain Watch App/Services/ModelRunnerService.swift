import Foundation
import CoreML

class RealTokenizer {
    let vocab: [String: Int]
    let reverseVocab: [Int: String]

    init?(from path: String) {
        print("📄 Trying to load tokenizer from path: \(path)")
        guard let data = FileManager.default.contents(atPath: path),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data) else {
            print("❌ Failed to load or decode vocab from: \(path)")
            return nil
        }
        self.vocab = raw
        self.reverseVocab = Dictionary(uniqueKeysWithValues: raw.map { ($1, $0) })
        print("✅ Tokenizer initialized with \(vocab.count) entries.")
    }

    func tokenize(_ text: String) -> [Int] {
        var tokens: [Int] = []
        for char in text {
            let str = String(char)
            if let id = vocab[str] {
                tokens.append(id)
            } else {
                tokens.append(vocab["<unk>"] ?? 0)
            }
        }
        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        return tokens.map { reverseVocab[$0] ?? "<?>" }.joined()
    }
}

class ModelRunnerService {
    static let shared = ModelRunnerService()
    private var model: MLModel?
    private var tokenizer: RealTokenizer?

    func loadModel(from url: URL) -> Bool {
        let path = url.path
        print("📦 Attempting to load model from folder: \(path)")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

        guard exists else {
            print("❌ Path does not exist: \(path)")
            return false
        }

        if isDirectory.boolValue {
            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            } catch {
                print("❌ Failed to list contents: \(error)")
                return false
            }

            if let modelURL = contents.first(where: { $0.pathExtension == "mlmodelc" }) {
                do {
                    model = try MLModel(contentsOf: modelURL)
                    print("✅ Model loaded successfully from \(modelURL.path)")
                } catch {
                    print("❌ Failed to load model: \(error.localizedDescription)")
                    return false
                }
            } else {
                print("❌ No .mlmodelc found in directory: \(path)")
                return false
            }

            let tokenizerPath = url.appendingPathComponent("tokenizer/vocab.json").path
            if FileManager.default.fileExists(atPath: tokenizerPath) {
                tokenizer = RealTokenizer(from: tokenizerPath)
                print("✅ Tokenizer loaded from \(tokenizerPath)")
            } else {
                tokenizer = nil
                print("⚠️ No tokenizer found for this model at path: \(tokenizerPath)")
            }

            return true
        } else {
            do {
                model = try MLModel(contentsOf: url)
                print("✅ Model loaded successfully from \(path)")
                return true
            } catch {
                print("❌ Failed to load model: \(error.localizedDescription)")
                return false
            }
        }
    }

    func predict(from input: String) -> (text: String, speed: Double) {
        guard let model = model else {
            print("⚠️ No model loaded.")
            return ("⚠️ No model loaded.", 0)
        }

        guard let tokenizer = tokenizer else {
            print("❌ Tokenizer not initialized. Please ensure tokenizer/vocab.json exists and is valid.")
            return ("❌ Tokenizer not initialized.", 0)
        }

        do {
            let inputIds = tokenizer.tokenize(input)

            guard !inputIds.isEmpty else {
                print("❌ Empty inputIds — tokenizer returned no tokens.")
                return ("❌ Input too short or unknown tokens.", 0)
            }

            let maxSequenceLength = 16
            let clampedIds = Array(inputIds.prefix(maxSequenceLength))
            let padded = clampedIds + Array(repeating: 0, count: maxSequenceLength - clampedIds.count)

            let mlArray = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            for (i, token) in padded.enumerated() {
                mlArray[[0, i] as [NSNumber]] = NSNumber(value: token)
            }

            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            for i in 0..<maxSequenceLength {
                attentionMask[[0, i] as [NSNumber]] = NSNumber(value: i < clampedIds.count ? 1 : 0)
            }

            print("📤 Sending shape: input_ids = \(mlArray.shape), attention_mask = \(attentionMask.shape)")

            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": mlArray,
                "attention_mask": attentionMask
            ])

            let startTime = CFAbsoluteTimeGetCurrent()
            let prediction = try model.prediction(from: inputFeatures)
            let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime

            for key in prediction.featureNames {
                if let array = prediction.featureValue(for: key)?.multiArrayValue {
                    let shape = array.shape.map { $0.intValue }
                    guard shape.count == 3 else {
                        print("❌ Unexpected output shape: \(shape)")
                        continue
                    }

                    let T = shape[1]
                    let V = shape[2]

                    let ptr = UnsafeMutablePointer<Float16>(OpaquePointer(array.dataPointer))
                    var predictedTokenIndices: [Int] = []

                    for t in 0..<T {
                        var maxVal: Float16 = Float16(-Float.greatestFiniteMagnitude)
                        var maxIdx = 0

                        for v in 0..<V {
                            let idx = t * V + v
                            let val = ptr[idx]
                            if val > maxVal {
                                maxVal = val
                                maxIdx = v
                            }
                        }

                        predictedTokenIndices.append(maxIdx)
                    }

                    let decoded = tokenizer.decode(predictedTokenIndices)
                    let tokensPerSecond = Double(predictedTokenIndices.count) / elapsedTime

                    return (decoded, tokensPerSecond)
                }
            }

            return ("⚠️ No output from model.", 0)
        } catch {
            print("❌ Prediction failed: \(error.localizedDescription)")
            return ("❌ Prediction failed: \(error.localizedDescription)", 0)
        }
    }

    func getModelMetadata() -> [String] {
        guard let model = model else {
            return ["⚠️ No model loaded."]
        }

        var lines: [String] = []
        lines.append("✅ Model loaded successfully")

        lines.append("🟢 Inputs:")
        for (name, desc) in model.modelDescription.inputDescriptionsByName {
            let type = String(describing: desc.type)
            lines.append("- \(name): \(type)")
        }

        lines.append("🔵 Outputs:")
        for (name, desc) in model.modelDescription.outputDescriptionsByName {
            let type = String(describing: desc.type)
            lines.append("- \(name): \(type)")
        }

        return lines
    }
}
