import SwiftUI

struct ModelListView: View {
    @State private var models: [HFModel] = []
    @State private var isLoading = true
    @State private var downloadStatus: String?

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.6), Color.purple.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView("Loading models...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    } else {
                        ForEach(models) { model in
                            NavigationLink(destination: ModelDetailView(model: model)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.id)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)

                                    if let tag = model.pipeline_tag {
                                        Text("Pipeline: \(tag.capitalized)")
                                            .font(.caption2)
                                            .foregroundColor(.cyan)
                                    }

                                    if let likes = model.likes {
                                        Text("❤️ \(likes) likes")
                                            .font(.caption2)
                                            .foregroundColor(.pink)
                                    }

                                    if let sizeText = model.sizeFormatted as String? {
                                        Text("📦 \(sizeText)")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }

                                    if let desc = model.description {
                                        Text(desc)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: Color.cyan.opacity(0.3), radius: 5, x: 0, y: 3)
                            }
                        }
                    }

                    if let status = downloadStatus {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Available Models")
        .onAppear(perform: fetchModels)
    }

    func fetchModels() {
        isLoading = true
        ModelFetcherService.shared.fetchModels { result in
            DispatchQueue.main.async {
                self.models = result
                self.isLoading = false
            }
        }
    }
}
