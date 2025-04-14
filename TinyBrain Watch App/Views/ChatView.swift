import SwiftUI

struct ChatView: View {
    @State private var inputText: String = ""
    @State private var messages: [(text: String, speed: Double?)] = []
    @State private var isProcessing = false

    let model: HFModel

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.indices, id: \.self) { index in
                            let message = messages[index]
                            VStack(alignment: index % 2 == 0 ? .leading : .trailing, spacing: 4) {
                                Text(message.text)
                                    .font(.system(size: 12))
                                    .padding(8)
                                    .background(index % 2 == 0 ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                    .frame(maxWidth: .infinity, alignment: index % 2 == 0 ? .leading : .trailing)

                                if let speed = message.speed {
                                    Text(String(format: "\u{26A1} %.2f tokens/s", speed))
                                        .font(.footnote)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                TextField("Enter your message...", text: $inputText)
                    .disabled(isProcessing)
                    .font(.system(size: 12))
                    .frame(height: 26)
                    .padding(4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(5)

                Button(action: sendMessage) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .imageScale(.small)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .frame(width: 22, height: 22)
            }
            .padding()
        }
        .navigationTitle(model.id)
    }

    func sendMessage() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messages.append((text: "You: \(prompt)", speed: nil))
        inputText = ""
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let (text, speed) = ModelRunnerService.shared.predict(from: prompt)

            DispatchQueue.main.async {
                messages.append((text: text, speed: speed > 0 ? speed : nil))
                isProcessing = false
            }
        }
    }
}
