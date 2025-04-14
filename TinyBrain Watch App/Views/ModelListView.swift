//
//  ModelListView.swift
//  TinyBrain
//
//  Created by Clemens Hemmerling on 10/04/25.
//

import SwiftUI

struct ModelListView: View {
    @State private var models: [HFModel] = []
    @State private var isLoading = true
    @State private var downloadStatus: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    ProgressView("Loading models...")
                } else {
                    ForEach(models) { model in
                        NavigationLink(destination: ModelDetailView(model: model)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.id)
                                    .font(.headline)

                                if let tag = model.pipeline_tag {
                                    Text("Pipeline: \(tag.capitalized)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                if let likes = model.likes {
                                    Text("❤️ \(likes) likes")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                if let sizeText = model.sizeFormatted as String? {
                                    Text("📦 \(sizeText)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                if let desc = model.description {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
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
