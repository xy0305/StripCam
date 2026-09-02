//
//  FavoritesView.swift
//  StripCam
//
//  本地收藏列表。
//

import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var playingModel: PlayableModel?

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: AppConstants.Spacing.md)
    ]

    var body: some View {
        Group {
            if favorites.items.isEmpty {
                ContentUnavailableView(
                    "还没有收藏",
                    systemImage: "heart",
                    description: Text("在直播间点击 ♥ 即可收藏到本地")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppConstants.Spacing.lg) {
                        ForEach(favorites.items) { saved in
                            Button {
                                playingModel = PlayableModel(saved: saved)
                            } label: {
                                SavedCard(saved: saved)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    favorites.toggle(saved)
                                } label: {
                                    Label("取消收藏", systemImage: "heart.slash.fill")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppConstants.Spacing.lg)
                    .padding(.vertical, AppConstants.Spacing.md)
                }
            }
        }
        .fullScreenCover(item: $playingModel) { model in
            PlayerView(model: model)
        }
    }
}

private struct SavedCard: View {
    let saved: SavedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: saved.coverURL)
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if saved.isHd {
                        Text("HD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous))

            HStack(spacing: 8) {
                RemoteAvatar(url: saved.avatarURL)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.username.isEmpty ? "主播" : saved.username)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)
                    Text(formatPopularity(saved.viewersCount) + " 观看")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
    }
}
