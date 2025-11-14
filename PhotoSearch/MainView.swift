//
//  MainView.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/13/25.
//

import SwiftUI

struct MainView: View {
    
    @StateObject private var viewModel: MainViewModel

    init() {
        // MainActor 컨텍스트에서 엔진 생성
        let engine = MobileCLIPEngine(encoder: S2Model())
        _viewModel = StateObject(wrappedValue: MainViewModel(engine: engine))
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Search (e.g. \"a red fruit\")", text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.search() }

                    Button("Search") {
                        viewModel.search()
                    }
                    .disabled(viewModel.isIndexing)
                }
                .padding()

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                List(viewModel.results) { item in
                    HStack {
                        Image(item.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(item.title)
                    }
                }
            }
            .navigationTitle("PhotoSearch Demo")
            .onAppear {
                viewModel.setupIfNeeded()
            }
        }
    }
}

#Preview {
    MainView()
}
