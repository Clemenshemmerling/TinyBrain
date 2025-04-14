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
                    self.getMLModelFileInfo(for: model.id) { fileInfo in
                        if let fileInfo {
                            print("✅ \(model.id) has compatible file: \(fileInfo.filename) - \(fileInfo.size ?? 0) bytes")
                            model.downloadableFilename = fileInfo.filename
                            model.sizeInBytes = fileInfo.size
                            model.description = fileInfo.description
                            filteredModels.append(model)
                        } else {
                            print("❌ \(model.id) does not have a .mlmodelc, .mlpackage, or .mlmodelc.zip file")
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

    private func getMLModelFileInfo(for modelId: String, completion: @escaping (((filename: String, size: Int?, description: String?))?) -> Void) {
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

            if let file = siblings.first(where: { file in
                if let filename = file["rfilename"] as? String {
                    return filename.hasSuffix(".mlpackage") || filename.hasSuffix(".mlmodelc") || filename.hasSuffix(".zip")
                }
                return false
            }),
            let filename = file["rfilename"] as? String {

                let size = file["size"] as? Int
                let description = (json["cardData"] as? [String: Any])?["description"] as? String

                completion((filename, size, description))
            } else {
                completion(nil)
            }
        }.resume()
    }
}
