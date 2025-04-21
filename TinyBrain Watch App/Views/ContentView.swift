import SwiftUI

struct ContentView: View {
    @State private var showModelList = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.7), Color.purple.opacity(0.7)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image("LogoBrain")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.4)]), startPoint: .top, endPoint: .bottom))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.2)
                        )
                        .shadow(color: .cyan.opacity(0.5), radius: 6, x: 0, y: 3)

                    Text("TinyBrain")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showModelList = true
                        }
                    }) {
                        Text("Load Model")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(gradient: Gradient(colors: [.red, .orange]), startPoint: .leading, endPoint: .trailing))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 5, x: 0, y: 3)
                    }
                    .navigationDestination(isPresented: $showModelList) {
                        ModelListView()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
            }
        }
    }
}
