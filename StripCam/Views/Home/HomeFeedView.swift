//
//  HomeFeedView.swift
//  StripCam
//
//  分类直播网格 + 分页加载。
//

import SwiftUI

@MainActor
final class HomeFeedViewModel: ObservableObject {
    let category: StripchatCategory

    @Published private(set) var models: [StripModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?

    private var page = 0

    init(category: StripchatCategory) {
        self.category = category
    }

    func refresh() async {
        page = 0
        hasMore = true
        models = []
        errorMessage = nil
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            page += 1
            let fetched = try await StripchatAPI.shared.fetchModels(category: category, page: page)
            if fetched.count < StripchatAPI.pageSize {
                hasMore = false
            }
            // 去重（接口分页偶尔重叠）
            let existing = Set(models.map(\.id))
            models.append(contentsOf: fetched.filter { !existing.contains($0.id) })
        } catch {
            page -= 1
            if models.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct HomeFeedView: View {
    @StateObject private var viewModel: HomeFeedViewModel
    @State private var playingModel: PlayableModel?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: AppConstants.Spacing.md)
    ]

    init(category: StripchatCategory) {
        _viewModel = StateObject(wrappedValue: HomeFeedViewModel(category: category))
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.models.isEmpty {
                errorView(error)
            } else {
                grid
            }
        }
        .task { await viewModel.refresh() }
        .fullScreenCover(item: $playingModel) { model in
            PlayerView(model: model)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppConstants.Spacing.lg) {
                ForEach(viewModel.models) { model in
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

            footer
        }
        .refreshable { await viewModel.refresh() }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding(.vertical, AppConstants.Spacing.lg)
        } else if !viewModel.hasMore && !viewModel.models.isEmpty {
            Text("没有更多了")
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
                .padding(.vertical, AppConstants.Spacing.lg)
        } else {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { await viewModel.loadMore() }
                }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
