//
//  ModelDownloadService.swift
//  TinyBrain
//
//  Created by Clemens Hemmerling on 10/04/25.
//

import Foundation
import ZipArchive

class ModelDownloadService {
    static let shared = ModelDownloadService()

    func downloadModel(named modelId: String, filename: String, completion: @escaping (URL?) -> Void) {
        let urlString = "https://huggingface.co/\(modelId)/resolve/main/\(filename)"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid model URL")
            completion(nil)
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                print("❌ Download failed or invalid file")
                completion(nil)
                return
            }

            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                print("✅ Saved model ZIP to \(destinationURL.path)")

                let unzipDir = destinationURL.deletingPathExtension().deletingPathExtension()
                try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

                let success = SSZipArchive.unzipFile(atPath: destinationURL.path, toDestination: unzipDir.path)

                if success {
                    print("✅ Unzipped to \(unzipDir.path)")
                    completion(unzipDir)
                } else {
                    print("❌ Failed to unzip model")
                    completion(nil)
                }
            } catch {
                print("❌ Error handling file: \(error)")
                completion(nil)
            }
        }

        task.resume()
    }
}
