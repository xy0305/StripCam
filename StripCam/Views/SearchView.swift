//
//  SearchView.swift
//  StripCam
//
//  主播搜索（本地过滤用户名）。
//

import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword = ""
    @Published private(set) var results: [StripModel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func search() async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await StripchatAPI.shared.search(keyword: kw)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var playingModel: PlayableModel?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: AppConstants.Spacing.md)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppConstants.Spacing.lg) {
                ForEach(viewModel.results) { model in
                    Button {
                        playingModel = PlayableModel(model: model)
                    } label: {
                        LiveRoomCard(model: model)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppConstants.Spacing.lg)
            .padding(.vertical, AppConstants.Spacing.md)
        }
        .searchable(text: $viewModel.keyword, prompt: "输入主播用户名")
        .onSubmit(of: .search) {
            Task { await viewModel.search() }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.results.isEmpty && !viewModel.keyword.isEmpty {
                ContentUnavailableView("未找到主播", systemImage: "magnifyingglass")
            }
        }
        .fullScreenCover(item: $playingModel) { model in
            PlayerView(model: model)
        }
    }
}
