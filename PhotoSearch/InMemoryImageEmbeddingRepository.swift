//
//  InMemoryImageEmbeddingRepository.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import Foundation

struct PhotoEmbedding {
    let localIdentifier: String      // PHAsset.localIdentifier
    let modelName: String            // "MobileCLIP-S2"
    var embedding: [Float]
    let updatedAt: Date
}

protocol ImageEmbeddingRepository {
    func save(_ embedding: PhotoEmbedding) async
    func fetchAll(modelName: String) async -> [PhotoEmbedding]
    func exists(localIdentifier: String, modelName: String) async -> Bool
}

final class InMemoryImageEmbeddingRepository: ImageEmbeddingRepository {
    private var storage: [PhotoEmbedding] = []

    func save(_ embedding: PhotoEmbedding) async {
        storage.removeAll {
            $0.localIdentifier == embedding.localIdentifier &&
            $0.modelName == embedding.modelName
        }
        storage.append(embedding)
    }

    func fetchAll(modelName: String) async -> [PhotoEmbedding] {
        storage.filter { $0.modelName == modelName }
    }

    func exists(localIdentifier: String, modelName: String) async -> Bool {
        storage.contains {
            $0.localIdentifier == localIdentifier && $0.modelName == modelName
        }
    }
}


