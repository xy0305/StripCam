//
//  StreamerInfoSheet.swift
//  StripCam
//
//  主播信息弹层（头像、状态、标签等）。
//

import SwiftUI

struct StreamerInfoSheet: View {
    let model: PlayableModel
    @EnvironmentObject private var favorites: FavoritesStore

    private var isFavorited: Bool { favorites.contains(model.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Spacing.lg) {
                    RemoteAvatar(url: model.avatarURL)
                        .frame(width: 96, height: 96)

                    Text(model.username)
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        statusBadge
                        genderBadge
                        if model.isHd { tagBadge("HD") }
                        if model.isNew { tagBadge("新主播") }
                        if model.isLovense { tagBadge("Lovense") }
                    }

                    HStack(spacing: 24) {
                        stat(value: formatPopularity(model.viewersCount), label: "观看")
                        if !model.country.isEmpty {
                            stat(value: model.country, label: "国家")
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.top, AppConstants.Spacing.xl)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favorites.toggle(model)
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorited ? .red : AppConstants.Colors.primaryText)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text("主播信息")
                        .font(.headline)
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.2), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var genderBadge: some View {
        Text(genderText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppConstants.Colors.secondaryBackground, in: Capsule())
            .foregroundStyle(AppConstants.Colors.secondaryText)
    }

    private func tagBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
        }
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

    private var statusColor: Color {
        model.status == "public" ? AppConstants.Colors.liveStatus : AppConstants.Colors.offlineStatus
    }

    private var genderText: String {
        switch model.gender {
        case "female": return "女性"
        case "male": return "男性"
        case "maleFemale": return "男女"
        case "femaleTranny": return "女变"
        case "maleTranny": return "男变"
        case "group": return "群体"
        case "tranny": return "变性人"
        case "trannies": return "多个变性人"
        default: return model.gender.isEmpty ? "未知" : model.gender
        }
    }
}
