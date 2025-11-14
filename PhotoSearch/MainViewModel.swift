//
//  MainViewModel.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import SwiftUI
import Combine
import CoreML

@MainActor
final class MainViewModel: ObservableObject {

    struct SampleItem: Identifiable {
        let id: String
        let title: String
        let imageName: String
        var embedding: [Float]?
    }

    @Published var query: String = ""
    @Published var results: [SampleItem] = []
    @Published var isIndexing: Bool = false
    @Published var statusMessage: String?

    private var items: [SampleItem] = [
        .init(id: "apple",  title: "Apple",  imageName: "apple",  embedding: nil),
        .init(id: "banana", title: "Banana", imageName: "banana", embedding: nil),
        .init(id: "otter",  title: "Otter",  imageName: "otter",  embedding: nil),
    ]

    private let engine: MobileCLIPEngineProtocol

    init(engine: MobileCLIPEngineProtocol) {
        self.engine = engine
    }

    // View에서 onAppear에서 호출
    func setupIfNeeded() {
        guard !isIndexing, results.isEmpty else { return }
        Task {
            await buildInitialIndex()
        }
    }

    private func buildInitialIndex() async {
        isIndexing = true
        statusMessage = "Loading model..."
        await engine.load()

        statusMessage = "Indexing sample images..."
        var newItems: [SampleItem] = []

        for var item in items {
            guard let uiImage = UIImage(named: item.imageName) else {
                print("⚠️ Failed to load image: \(item.imageName)")
                newItems.append(item)
                continue
            }
            do {
                let embedding = try await engine.embedImage(uiImage: uiImage)
                item.embedding = embedding
            } catch {
                print("⚠️ Embedding failed for \(item.imageName): \(error)")
            }
            newItems.append(item)
        }

        items = newItems
        results = newItems        // 초기에는 그냥 전체 노출
        statusMessage = "Ready"
        isIndexing = false
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 쿼리 비어 있으면 전체 보여주기
            results = items
            return
        }

        Task {
            await performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        do {
            let queryEmbedding = try await engine.embedText(query)

            // 임베딩 없는 아이템은 제외
            let validItems = items.compactMap { item -> (SampleItem, Float)? in
                guard let v = item.embedding else { return nil }
                let score = EmbeddingUtils.cosineSimilarity(queryEmbedding, v)
                return (item, score)
            }

            let sorted = validItems
                .sorted { $0.1 > $1.1 } // score 내림차순
                .map { $0.0 }

            await MainActor.run {
                self.results = sorted
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }
}
