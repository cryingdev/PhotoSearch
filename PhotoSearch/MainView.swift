//
//  MainView.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/13/25.
//

import SwiftUI
import Translation

struct MainView: View {
    
    @StateObject private var viewModel: MainViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var scrollToTopFlag: Bool = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ] //3열
    
    init() {
        let engine = MobileCLIPEngine(encoder: S2Model())
        let embeddingRepo = InMemoryImageEmbeddingRepository()
        let authRepo = DefaultPhotoAuthorizationRepository()
        let photoRepo = DefaultPhotoLibraryRepository()
        
        _viewModel = StateObject(
            wrappedValue: MainViewModel(
                engine: engine,
                embeddingRepo: embeddingRepo,
                authRepo: authRepo,
                photoRepo: photoRepo
            )
        )
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    searchBar
                    
                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                    
                    ScrollViewReader { proxy in          // ✅ 내부
                        ScrollView{
                            Color.clear                      // ✅ 위쪽 앵커 뷰
                                .frame(height: 0)
                                .id("GRID_TOP")
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(viewModel.filteredAssets) { asset in
                                    PhotoGridCell(
                                        assetId: asset.id,
                                        score: viewModel.score(for: asset.id),
                                        viewModel: viewModel
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSearchFocused = false
                        }
                        .onChange(of: scrollToTopFlag) { _, _ in   // ✅ 플래그 변경 시 스크롤 탑
                            withAnimation {
                                proxy.scrollTo("GRID_TOP", anchor: .top)
                            }
                        }
                    }
                }
                .navigationTitle("PhotoSearch")
                .onAppear {
                    viewModel.setupIfNeeded()
                }
                
                if viewModel.authState == .denied {
                    permissionOverlay
                }
            }
            // 번역 세션 준비 + 클로저 주입
            .translationTask(viewModel.translationConfiguration) { session in
                do {
                    try await session.prepareTranslation()
                    viewModel.translatedText = { text in
                        print(text)
                        let result = try await session.translate(text)
                        print(result.targetText)
                        return result.targetText
                    }
                } catch {
                    // TODO: 필요 시 에러 처리
                }
            }
            .onAppear { viewModel.configureTranslation() }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("사진 검색…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)                 // ✅ 포커스 바인딩
                .onSubmit {                                // ✅ 이제 검색이 아니라
                    isSearchFocused = false                //    키보드 내리기
                    if !viewModel.query.isEmpty {
                        scrollToTopFlag.toggle()
                    }
                }
                .onChange(of: viewModel.query) { _, _ in      // ✅ 타이핑 중 자동 검색
                    viewModel.search()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.search()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            Text("사진 접근 권한이 필요합니다.")
                .font(.headline)

            Text("설정 > 개인정보 보호 > 사진에서 이 앱에 대한 접근을 허용해 주세요.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("설정 열기")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(radius: 8)
        )
        .padding()
    }
    
}

#Preview {
    MainView()
}
