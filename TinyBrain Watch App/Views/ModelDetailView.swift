import SwiftUI

struct ModelDetailView: View {
    let model: HFModel
    @State private var isDownloading = false
    @State private var downloadSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.6), Color.purple.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(model.id)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let tag = model.pipeline_tag {
                    Text("Pipeline: \(tag.capitalized)")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }

                if let filename = model.downloadableFilename {
                    Text("File: \(filename)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                if isDownloading {
                    ProgressView("Downloading...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                } else if downloadSuccess {
                    NavigationLink(destination: ChatView(model: model)) {
                        Text("Go to Chat")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(gradient: Gradient(colors: [.green, .blue]), startPoint: .leading, endPoint: .trailing))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: .blue.opacity(0.5), radius: 5, x: 0, y: 3)
                    }
                } else {
                    Button(action: downloadModel) {
                        Text("Download Model")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(gradient: Gradient(colors: [.orange, .red]), startPoint: .leading, endPoint: .trailing))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 5, x: 0, y: 3)
                    }
                }

                if let error = errorMessage {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
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
