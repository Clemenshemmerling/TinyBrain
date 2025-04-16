//
//  ModelDetailView.swift
//  TinyBrain
//
//  Created by Clemens Hemmerling on 11/04/25.
//

import SwiftUI

struct ModelDetailView: View {
    let model: HFModel
    @State private var isDownloading = false
    @State private var downloadSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(model.id)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let tag = model.pipeline_tag {
                Text("Pipeline: \(tag.capitalized)")
                    .font(.caption)
            }

            if let filename = model.downloadableFilename {
                Text("File: \(filename)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            if isDownloading {
                ProgressView("Downloading...")
            } else if downloadSuccess {
                NavigationLink(destination: ChatView(model: model)) {
                    Text("Go to Chat")
                        .bold()
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Download Model") {
                    downloadModel()
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .navigationTitle("Model Info")
    }

    func downloadModel() {
        guard let filename = model.downloadableFilename else {
            errorMessage = "Missing filename"
            return
        }

        isDownloading = true
        _ = filename.replacingOccurrences(of: "/", with: "_")

        ModelDownloadService.shared.downloadModel(named: model.id, filename: filename) { url in
            DispatchQueue.main.async {
                self.isDownloading = false
                if let localURL = url {
                    let loadSuccess = ModelRunnerService.shared.loadModel(from: localURL)
                    if loadSuccess {
                        self.downloadSuccess = true
                    } else {
                        self.errorMessage = "Model could not be loaded into CoreML."
                    }
                } else {
                    self.errorMessage = "Failed to download."
                }
            }
        }
    }
}
