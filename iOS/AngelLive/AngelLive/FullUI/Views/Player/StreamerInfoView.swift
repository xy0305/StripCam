//
//  StreamerInfoView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import UIKit
import AngelLiveCore
import AngelLiveDependencies

/// 使用 UILabel 实现的标题，避免 SwiftUI Text 的自动平衡换行
private struct RoomTitleLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        label.textColor = UIColor(white: 0.95, alpha: 1)
        label.numberOfLines = 2
        label.lineBreakMode = .byCharWrapping
        label.lineBreakStrategy = []
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        // 空字符串兜底
        uiView.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : text
    }
 
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// 主播信息视图
struct StreamerInfoView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast
    @State private var isFavoriteAnimating = false
    @State private var showStreamerInfo = false
    // 账号关注（同步到平台账号，如 Chaturbate）
    @State private var accountFollowing: Bool?
    @State private var accountFollowBusy = false

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { room in
            if !viewModel.currentRoom.userId.isEmpty, !room.userId.isEmpty {
                return room.liveType == viewModel.currentRoom.liveType && room.userId == viewModel.currentRoom.userId
            }
            return room.liveType == viewModel.currentRoom.liveType && room.roomId == viewModel.currentRoom.roomId
        })
    }

    /// 当前平台插件是否支持账号关注
    private var supportsAccountFollow: Bool {
        PlatformCapability.supports(.accountFollow, for: viewModel.currentRoom.liveType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 直播间标题（置顶，加大加粗）
            RoomTitleLabel(text: viewModel.currentRoom.roomTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 主播信息行
            HStack(spacing: 12) {
                // 主播头像（可点击）
                Button {
                    showStreamerInfo = true
                } label: {
                    Group {
                        if !viewModel.currentRoom.userHeadImg.isEmpty,
                           let avatarURL = URL(string: viewModel.currentRoom.userHeadImg) {
                            KFAnimatedImage(avatarURL)
                                .configure { view in
                                    view.framePreloadCount = 2
                                }
                                .placeholder {
                                    avatarFallback
                                }
                                .aspectRatio(contentMode: .fill)
                        } else {
                            avatarFallback
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    // 主播名称
                    Text(viewModel.currentRoom.userName.orDash)
                        .font(.headline)
                        .foregroundStyle(Color(white: 0.9))

                    // 人气信息
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(formatPopularity(viewModel.currentRoom.liveWatchedCount ?? "0"))
                            .font(.caption)
                    }
                    .foregroundStyle(Color(white: 0.7))
                }

                Spacer()

                // 账号关注（同步到平台账号，如 Chaturbate）
                if supportsAccountFollow {
                    Button {
                        Task { await toggleAccountFollow() }
                    } label: {
                        Group {
                            if accountFollowBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color(white: 0.85))
                            } else {
                                Image(systemName: (accountFollowing == true) ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundStyle((accountFollowing == true) ? Color.orange : Color(white: 0.7))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.1))
                        )
                    }
                    .disabled(accountFollowBusy)
                }

                // 收藏按钮
                Button(action: {
                    Task {
                        await toggleFavorite()
                    }
                }) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isFavorited ? .red : Color(white: 0.7))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.1))
                        )
                }
                .changeEffect(
                    .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart.slash.fill")
                            .foregroundStyle(.red)
                    }, value: isFavoriteAnimating
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(room: viewModel.currentRoom)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: viewModel.currentRoom.roomId) {
            await refreshAccountFollowState()
        }
    }

    /// 头像兜底（URL 为空 / 加载失败）
    private var avatarFallback: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(6)
            )
    }

    // MARK: - 账号关注（同步到平台账号）

    private struct PluginFollowStatusDTO: Decodable {
        let following: Bool?
        let loggedIn: Bool?
    }

    private var accountFollowPluginId: String? {
        SandboxPluginCatalog.platform(for: viewModel.currentRoom.liveType)?.pluginId
    }

    @MainActor
    private func refreshAccountFollowState() async {
        guard supportsAccountFollow,
              let pluginId = accountFollowPluginId,
              !viewModel.currentRoom.roomId.isEmpty else {
            accountFollowing = nil
            return
        }
        let roomId = viewModel.currentRoom.roomId
        let result: PluginFollowStatusDTO? = try? await LiveParsePlugins.shared.callDecodable(
            pluginId: pluginId,
            function: "isFollowing",
            payload: ["roomId": roomId]
        )
        guard !Task.isCancelled, viewModel.currentRoom.roomId == roomId else { return }
        if let result {
            accountFollowing = result.following == true
        } else {
            accountFollowing = nil
        }
    }

    @MainActor
    private func toggleAccountFollow() async {
        guard !accountFollowBusy,
              let pluginId = accountFollowPluginId,
              !viewModel.currentRoom.roomId.isEmpty else { return }
        let currentlyFollowing = accountFollowing == true
        let roomId = viewModel.currentRoom.roomId
        accountFollowBusy = true
        defer { accountFollowBusy = false }

        do {
            let result: PluginFollowStatusDTO = try await LiveParsePlugins.shared.callDecodable(
                pluginId: pluginId,
                function: "setFollowing",
                payload: ["roomId": roomId, "follow": !currentlyFollowing]
            )
            guard viewModel.currentRoom.roomId == roomId else { return }
            let following = result.following ?? !currentlyFollowing
            accountFollowing = following
            presentToast(ToastValue(
                icon: Image(systemName: following ? "star.fill" : "star.slash"),
                message: following ? "已关注 · 已同步到平台账号" : "已取消关注"
            ))
        } catch {
            let message = (error as? LiveParsePluginError)?.errorDescription ?? error.localizedDescription
            let hint = message.contains("登录") ? message : "关注失败：\(message)"
            presentToast(ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: hint
            ))
        }
    }

    // MARK: - 收藏操作

    @MainActor
    private func toggleFavorite() async {
        let wasFavorited = isFavorited
        do {
            if wasFavorited {
                try await favoriteModel.removeFavoriteRoom(room: viewModel.currentRoom)
            } else {
                try await favoriteModel.addFavorite(room: viewModel.currentRoom)
            }
            // 成功后触发动画 + Toast(跟列表入口对齐)
            isFavoriteAnimating.toggle()
            if favoriteModel.favoriteICloudSyncEnabled, let syncError = favoriteModel.lastSyncError {
                presentToast(ToastValue(
                    icon: Image(systemName: "icloud.slash"),
                    message: (wasFavorited ? "已取消收藏" : "已收藏") + " · iCloud 同步失败：\(syncError.displayText)"
                ))
            } else {
                presentToast(ToastValue(
                    icon: Image(systemName: wasFavorited ? "heart.slash.fill" : "heart.fill"),
                    message: wasFavorited ? "已取消收藏" : "收藏成功"
                ))
            }
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            presentToast(ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: wasFavorited ? "取消收藏失败：\(errorMessage)" : "收藏失败：\(errorMessage)"
            ))
            Logger.warning("收藏操作失败: \(error)", category: .favorite)
        }
    }
}
