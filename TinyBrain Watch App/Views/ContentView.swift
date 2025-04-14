//
//  ContentView.swift
//  TinyBrain
//
//  Created by Clemens Hemmerling on 10/04/25.
//


import SwiftUI

struct ContentView: View {
    @State private var showModelList = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("TinyBrain")
                    .font(.title3)
                    .bold()

                Button("Load Model") {
                    showModelList = true
                }
                .buttonStyle(.borderedProminent)
                .navigationDestination(isPresented: $showModelList) {
                    ModelListView()
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
