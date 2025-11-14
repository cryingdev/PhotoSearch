//
//  MainViewModel.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import SwiftUI
import Combine
import CoreML
import Translation

struct SearchResult {
    let localIdentifier: String
    let score: Float
}

@MainActor
final class MainViewModel: ObservableObject {

    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var isIndexing: Bool = false
    @Published var statusMessage: String?
    @Published var authState: PhotoAuthorizationState = .notDetermined

    // ✅ 포토 라이브러리에서 가져온 자산 목록 (최신순)
    @Published var photoAssets: [PhotoAssetInfo] = []
    
    //번역
    @Published var translationConfiguration: TranslationSession.Configuration?
    var translatedText: ((String) async throws -> String)?

    /// 검색어와 검색 결과에 따라 그리드에 표시할 자산 목록
    var filteredAssets: [PhotoAssetInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // 검색어가 없거나, 아직 결과가 없으면 전체 자산을 그대로 반환
        guard !trimmed.isEmpty, !results.isEmpty else {
            return photoAssets
        }

        // 빠른 조회를 위해 id -> asset 맵 구성
        let assetById = Dictionary(uniqueKeysWithValues: photoAssets.map { ($0.id, $0) })

        // results(유사도 순 정렬)를 기준으로 자산을 필터링 및 정렬
        return results.compactMap { assetById[$0.localIdentifier] }
    }

    private let engine: MobileCLIPEngineProtocol
    private let embeddingRepo: ImageEmbeddingRepository
    private let authRepo: PhotoAuthorizationRepository
    private let photoRepo: PhotoLibraryRepository
    private let modelName = "MobileCLIP-S2"

    init(
        engine: MobileCLIPEngineProtocol,
        embeddingRepo: ImageEmbeddingRepository,
        authRepo: PhotoAuthorizationRepository,
        photoRepo: PhotoLibraryRepository
    ) {
        self.engine = engine
        self.embeddingRepo = embeddingRepo
        self.authRepo = authRepo
        self.photoRepo = photoRepo
    }
    
    func setupIfNeeded() {
        Task {
            // 1) 권한 요청
            let state = await authRepo.requestAuthorizationIfNeeded()
            authState = state
            
            switch state {
            case .authorized:
                // 2) 권한 OK → 인덱싱 진행
                await loadPhotoAssets()     // ✅ 포토 라이브러리 자산 로드
                await buildInitialIndex()   // 엔진 로드
            case .denied:
                statusMessage = "사진 접근 권한이 필요합니다. 설정에서 허용해 주세요."
            case .notDetermined:
                statusMessage = "사진 권한 상태를 확인 중입니다."
            }
        }
    }
    
    private func loadPhotoAssets() async {
        let assets = await photoRepo.fetchAllAssets()
        // PhotoLibraryRepository에서 이미 최신순으로 정렬했으므로 그대로 사용
        self.photoAssets = assets
    }
    
    // MARK: - Thumbnail helper
    func loadThumbnail(for id: String, targetSize: CGSize) async -> UIImage? {
        await photoRepo.requestImage(for: id, targetSize: targetSize)
    }

    // MARK: - 엔진 로드(추후 UseCase로 분리할 예정)
    private func buildInitialIndex() async {
        isIndexing = true
        statusMessage = "Loading model..."
        await engine.load()

        statusMessage = "Indexing photos..."
        await indexAssetsIfNeeded()      // ✅ 여기서 실제 인덱싱
        
        statusMessage = "Ready"
        isIndexing = false

        await loadAllAsResults()
    }

    private func loadAllAsResults() async {
        let stored = await embeddingRepo.fetchAll(modelName: modelName)

        // 점수는 0으로 두고, 일단 전체 보여주기
        let mapped = stored.map { item in
            SearchResult(localIdentifier: item.localIdentifier, score: 0)
        }

        results = mapped
    }

    private func indexAssetsIfNeeded() async {
        // 1) 이미 저장된 임베딩 목록
        let existing = await embeddingRepo.fetchAll(modelName: modelName)
        let existingIds = Set(existing.map { $0.localIdentifier })

        // 2) 포토 라이브러리 자산 전체 순회
        for asset in photoAssets {
            if existingIds.contains(asset.id) {
                continue  // 이미 인덱싱된 사진은 스킵
            }

            // 적당한 해상도로 이미지 요청
            let base: CGFloat = 256
            let scale = UIScreen.main.scale
            let targetSize = CGSize(width: base * scale, height: base * scale)

            guard let uiImage = await loadThumbnail(for: asset.id, targetSize: targetSize) else {
                continue
            }

            do {
                // 3) MobileCLIP으로 이미지 임베딩 계산
                let vector = try await engine.embedImage(uiImage: uiImage)

                // 4) Repository에 저장
                let embedding = PhotoEmbedding(
                    localIdentifier: asset.id,
                    modelName: modelName,
                    embedding: vector,
                    updatedAt: Date()
                )
                await embeddingRepo.save(embedding)
            } catch {
                print("Indexing failed for \(asset.id): \(error)")
            }
        }
    }
    
    // MARK: - 검색
    func search() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else {
            Task { await loadAllAsResults() }
            return
        }

        Task {
            // 1) 번역기가 주입되어 있으면 먼저 번역 시도 (예: 한국어 → 영어)
            let textForSearch: String
            if let translator = translatedText {
                do {
                    let translated = try await translator(raw)
                    // 빈 문자열이나 whitespace만 나오는 경우를 방지
                    let trimmedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                    textForSearch = trimmedTranslated.isEmpty ? raw : trimmedTranslated
                } catch {
                    // 번역 실패 시 상태 메세지만 남기고 원문으로 검색
                    statusMessage = "Translation failed: \(error.localizedDescription). Searching with original text."
                    textForSearch = raw
                }
            } else {
                // 번역기가 설정되지 않은 경우에는 그대로 원문으로 검색
                textForSearch = raw
            }

            // 2) MobileCLIP 검색 수행
            await performSearch(query: textForSearch)
        }
    }

    private func performSearch(query: String) async {
        do {
            let queryVector = try await engine.embedText(query)
            let stored = await embeddingRepo.fetchAll(modelName: modelName)

            let scored: [SearchResult] = stored.map { item in
                let score = EmbeddingUtils.cosineSimilarity(queryVector, item.embedding)
                return SearchResult(localIdentifier: item.localIdentifier, score: score)
            }

            let sorted = scored.sorted { $0.score > $1.score }
            results = sorted
        } catch {
            statusMessage = "Search failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Debug helpers

    /// Return the similarity score for a given asset id, if available.
    func score(for assetId: String) -> Float? {
        results.first(where: { $0.localIdentifier == assetId })?.score
    }
    
    //MARK: - Translation
    func configureTranslation() {
        translationConfiguration?.invalidate()
        translationConfiguration = TranslationSession.Configuration(
            source: Locale(identifier: "ko-KR").language,
            target: Locale(identifier: "en-US").language,
        )
    }

}
