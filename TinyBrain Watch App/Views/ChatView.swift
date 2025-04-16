import SwiftUI

struct ChatView: View {
    @State private var inputText: String = ""
    @State private var messages: [(text: String, speed: Double?)] = []
    @State private var isProcessing = false

    let model: HFModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages.indices, id: \.self) { index in
                            let message = messages[index]
                            VStack(alignment: index % 2 == 0 ? .leading : .trailing, spacing: 4) {
                                Text(message.text)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(10)
                                    .background(index % 2 == 0 ? Color.green.opacity(0.2) : Color.purple.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .cornerRadius(8)
                                    .shadow(color: Color.cyan.opacity(0.3), radius: 2, x: 1, y: 1)
                                    .frame(maxWidth: .infinity, alignment: index % 2 == 0 ? .leading : .trailing)

                                if let speed = message.speed {
                                    Text(String(format: "⚡ %.2f tokens/s", speed))
                                        .font(.footnote.monospacedDigit())
                                        .foregroundColor(.cyan)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            HStack(spacing: 6) {
                TextField(">>>", text: $inputText)
                    .disabled(isProcessing)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                    )

                Button(action: sendMessage) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.cyan)
                            .imageScale(.small)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .frame(width: 28, height: 28)
            }
            .padding(.all, 10)
            .background(Color.black.opacity(0.4))
        }
        .background(LinearGradient(gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.2)]), startPoint: .top, endPoint: .bottom))
        .navigationTitle(Text(model.id).font(.system(size: 12, design: .monospaced)))
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
