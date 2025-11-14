//
//  PhotoGridCell.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import SwiftUI
import UIKit

struct PhotoGridCell: View {
    let assetId: String
    let score: Float?
    @ObservedObject var viewModel: MainViewModel

    @State private var image: UIImage?
    @State private var isLoading: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.width)
                }
                if let score {
                    let percentage = max(0, min(score, 1)) * 100
                    Text(String(format: "%.0f%%", percentage))
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .clipped()
            .cornerRadius(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            await load()
        }
    }

    private func load() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        let base: CGFloat = 200
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: base * scale, height: base * scale)
        let thumb = await viewModel.loadThumbnail(for: assetId, targetSize: targetSize)
        await MainActor.run {
            self.image = thumb
            self.isLoading = false
        }
    }
}
