//
//  LiveRoomCard.swift
//  StripCam
//
//  直播间卡片（参照 AngelLive 的 LiveRoomCard：封面 + 头像 + 用户名 + 人气）。
//

import SwiftUI

struct LiveRoomCard: View {
    let model: StripModel
    @EnvironmentObject private var favorites: FavoritesStore

    private var isFavorited: Bool {
        favorites.contains(model.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverView
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous))

            HStack(spacing: 8) {
                RemoteAvatar(url: model.avatarURL)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.username.isEmpty ? "主播" : model.username)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                favorites.toggle(model)
            } label: {
                Label(isFavorited ? "取消收藏" : "收藏", systemImage: isFavorited ? "heart.slash.fill" : "heart.fill")
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(formatPopularity(model.viewersCount) + " 观看")
        if model.isHd { parts.append("HD") }
        if model.isNew { parts.append("新主播") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 封面

    private var coverView: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: model.coverURL)
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 44)
            .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if model.isHd {
                Text("HD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
        }
    }

    private var statusColor: Color {
        model.status == "public" ? AppConstants.Colors.liveStatus : AppConstants.Colors.offlineStatus
    }

    private var statusText: String {
        switch model.status {
        case "public": return "直播中"
        case "private": return "私密"
        case "groupShow": return "群秀"
        case "p2p": return "P2P"
        case "virtualPrivate": return "虚拟私密"
        case "idle": return "空闲"
        case "offline": return "离线"
        default: return model.status.isEmpty ? "在线" : model.status
        }
    }
}
