//
//  HFModel.swift
//  TinyBrain
//
//  Created by Clemens Hemmerling on 10/04/25.
//

struct HFModel: Codable, Identifiable {
    let id: String
    let lastModified: String?
    let pipeline_tag: String?
    let likes: Int?
    let downloads: Int?
    let tags: [String]?

    var downloadableFilename: String?
    var description: String?
    var sizeInBytes: Int?

    var sizeFormatted: String {
        guard let size = sizeInBytes else { return "Unknown size" }
        if size > 1_048_576 {
            return String(format: "%.2f MB", Double(size) / 1_048_576)
        } else {
            return String(format: "%.0f KB", Double(size) / 1024)
        }
    }
}
