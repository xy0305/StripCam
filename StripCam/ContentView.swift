//
//  ContentView.swift
//  StripCam
//
//  根视图：侧边栏分类 + 内容网格。
//  使用 NavigationSplitView，iPad 上常驻侧边栏，iPhone 上自动折叠为栈式导航。
//

import SwiftUI

enum SidebarItem: Hashable {
    case favorites
    case search
    case settings
    case category(StripchatCategory)
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ContentUnavailableView(
                "请选择分类",
                systemImage: "play.tv.fill",
                description: Text("从左侧选择一个直播分类开始浏览")
            )
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        List {
            Section("我的") {
                NavigationLink(value: SidebarItem.favorites) {
                    Label("❤️ 我的收藏", systemImage: "heart.fill")
                }
                NavigationLink(value: SidebarItem.search) {
                    Label("🔍 搜索主播", systemImage: "magnifyingglass")
                }
            }

            ForEach(StripchatCatalog.sections) { section in
                Section(section.title) {
                    ForEach(section.categories) { category in
                        NavigationLink(value: SidebarItem.category(category)) {
                            Text(category.title)
                        }
                    }
                }
            }

            Section("通用") {
                NavigationLink(value: SidebarItem.settings) {
                    Label("设置", systemImage: "gearshape.fill")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Stripchat")
        .navigationDestination(for: SidebarItem.self) { destination(for: $0) }
    }

    // MARK: - 目标视图

    @ViewBuilder
    private func destination(for item: SidebarItem) -> some View {
        switch item {
        case .favorites:
            FavoritesView()
                .navigationTitle("我的收藏")
                .navigationBarTitleDisplayMode(.inline)
        case .search:
            SearchView()
                .navigationTitle("搜索主播")
                .navigationBarTitleDisplayMode(.inline)
        case .settings:
            SettingsView()
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
        case .category(let category):
            HomeFeedView(category: category)
                .navigationTitle(category.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
