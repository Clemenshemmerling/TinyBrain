import Foundation

class ModelFetcherService {
    static let shared = ModelFetcherService()

    func fetchModels(completion: @escaping ([HFModel]) -> Void) {
        print("🔄 Fetching models from Hugging Face...")

        guard let url = URL(string: "https://huggingface.co/api/models?filter=coreml") else {
            print("❌ Invalid URL.")
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                print("❌ No data received from Hugging Face.")
                completion([])
                return
            }

            do {
                let results = try JSONDecoder().decode([HFModel].self, from: data)
                print("📦 Retrieved \(results.count) models")

                let group = DispatchGroup()
                var filteredModels: [HFModel] = []

                for var model in results {
                    group.enter()
                    self.getModelFileAssets(for: model.id) { assets in
                        if let assets = assets {
                            let modelFile = assets.modelFile
                            print("✅ \(model.id) has model file: \(modelFile.filename)")
                            model.downloadableFilename = modelFile.filename
                            model.sizeInBytes = modelFile.size
                            model.description = modelFile.description

                            // Attach tokenizer files if found
                            model.tokenizerFilenames = assets.tokenizerFiles.map { $0.filename }

                            filteredModels.append(model)
                        } else {
                            print("❌ \(model.id) does not have a compatible model file")
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    print("✅ Valid models: \(filteredModels.count)")
                    completion(filteredModels)
                }

            } catch {
                print("❌ Decoding error: \(error.localizedDescription)")
                completion([])
            }

        }.resume()
    }

    private func getModelFileAssets(for modelId: String, completion: @escaping (ModelAssets?) -> Void) {
        guard let url = URL(string: "https://huggingface.co/api/models/\(modelId)") else {
            print("❌ Invalid URL for model: \(modelId)")
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let siblings = json["siblings"] as? [[String: Any]] else {
                print("❌ Could not retrieve file info for model: \(modelId)")
                completion(nil)
                return
            }

            // Buscar archivo del modelo
            let modelFile = siblings.compactMap { file -> FileAsset? in
                guard let filename = file["rfilename"] as? String else { return nil }
                if filename.hasSuffix(".mlmodelc") || filename.hasSuffix(".mlpackage") || filename.hasSuffix(".zip") {
                    return FileAsset(filename: filename,
                                     size: file["size"] as? Int,
                                     description: (json["cardData"] as? [String: Any])?["description"] as? String)
                }
                return nil
            }.first

            // Buscar archivos de tokenizer
            let tokenizerFiles = siblings.compactMap { file -> FileAsset? in
                guard let filename = file["rfilename"] as? String else { return nil }
                if filename == "vocab.json" || filename == "tokenizer.json" || filename == "merges.txt" {
                    return FileAsset(filename: filename,
                                     size: file["size"] as? Int,
                                     description: nil)
                }
                return nil
            }

            if let modelFile = modelFile {
                completion(ModelAssets(modelFile: modelFile, tokenizerFiles: tokenizerFiles))
            } else {
                completion(nil)
            }
        }.resume()
    }
}

struct FileAsset {
    let filename: String
    let size: Int?
    let description: String?
}

struct ModelAssets {
    let modelFile: FileAsset
    let tokenizerFiles: [FileAsset]
}
