//
//  PlayerView.swift
//  StripCam
//
//  全屏竖屏直播播放页。渲染用 KSPlayer，控制层参照 AngelLive 的沉浸式布局。
//

import SwiftUI
import KSPlayer

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var showQualityPanel = false
    @State private var showStreamerInfo = false
    @State private var isBuffering = true
    @State private var playbackError: String?
    @State private var hideTask: Task<Void, Never>?

    private var isFavorited: Bool {
        favorites.contains(viewModel.model.id)
    }

    init(model: PlayableModel) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(model: model))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = viewModel.currentStream?.url {
                KSVideoPlayer(coordinator: coordinator, url: url, options: KSOptions())
                    .onStateChanged { _, state in
                        isBuffering = (state == .buffering)
                        if state == .error {
                            playbackError = "播放失败，请稍后重试"
                        }
                    }
                    .id(url)
                    .ignoresSafeArea()
                    .onAppear {
                        // 隐藏 KSPlayer 自带控制层，使用自定义沉浸式控制层
                        coordinator.isMaskShow = false
                    }
            } else if viewModel.errorMessage == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            // 透明点击层（视频之上、控制层之下）
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if isBuffering && playbackError == nil && viewModel.errorMessage == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if let err = playbackError ?? viewModel.errorMessage {
                errorOverlay(err)
            }

            controlsOverlay
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)

            if showQualityPanel {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showQualityPanel = false }
                QualitySelectionPanel(viewModel: viewModel, isShowing: $showQualityPanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
        .task {
            await viewModel.load()
            scheduleHide()
        }
        .onDisappear {
            coordinator.playerLayer?.pause()
            hideTask?.cancel()
        }
    }

    // MARK: - 控制层

    private var controlsOverlay: some View {
        VStack {
            topBar
            Spacer()
            HStack {
                Spacer()
                qualityButton
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(AppConstants.PlayerUI.Opacity.backplate), in: Circle())
            }
            .allowsHitTesting(controlsVisible)

            Button {
                showStreamerInfo = true
            } label: {
                HStack(spacing: 10) {
                    RemoteAvatar(url: viewModel.model.avatarURL)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(viewModel.model.username.prefix(10)))
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(formatPopularity(viewModel.model.viewersCount))
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(AppConstants.PlayerUI.Opacity.backplate), in: Capsule())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(controlsVisible)

            Button {
                favorites.toggle(viewModel.model)
            } label: {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorited ? .red : .white)
                    .frame(width: 28, height: 28)
            }
            .allowsHitTesting(controlsVisible)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .sheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(model: viewModel.model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var qualityButton: some View {
        Button {
            hideTask?.cancel()
            controlsVisible = false
            showQualityPanel = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.and.film")
                    .font(.system(size: 20))
                Text(viewModel.currentStream?.isAuto == true ? "自动" : (viewModel.currentStream?.name ?? "画质"))
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.black.opacity(AppConstants.PlayerUI.Opacity.backplate), in: RoundedRectangle(cornerRadius: 14))
        }
        .allowsHitTesting(controlsVisible)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: AppConstants.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 控制层显隐

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) { controlsVisible.toggle() }
        if controlsVisible {
            scheduleHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = false }
        }
    }
}
