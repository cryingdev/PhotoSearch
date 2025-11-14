//
//  PhotoLibraryRepository.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import Foundation
import Photos
import UIKit

// MARK: - Domain Model
struct PhotoAssetInfo: Identifiable {
    let id: String           // PHAsset.localIdentifier
    let creationDate: Date?  // 최신순 정렬용
}

// MARK: - Protocol
protocol PhotoLibraryRepository {
    func fetchAllAssets() async -> [PhotoAssetInfo]
    func requestImage(for id: String, targetSize: CGSize) async -> UIImage?
}

// MARK: - Default Implementation
final class DefaultPhotoLibraryRepository: PhotoLibraryRepository {

    private let manager = PHImageManager.default()

    func fetchAllAssets() async -> [PhotoAssetInfo] {
        // 사진 전체 불러오기
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)   // 최신순
        ]

        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var list: [PhotoAssetInfo] = []

        result.enumerateObjects { asset, _, _ in
            list.append(
                PhotoAssetInfo(
                    id: asset.localIdentifier,
                    creationDate: asset.creationDate
                )
            )
        }
        return list
    }

    func requestImage(for id: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [id],
            options: nil
        ).firstObject else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast

            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
