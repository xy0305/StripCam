//
//  QualitySelectionPanel.swift
//  StripCam
//
//  清晰度 / 线路选择面板，右侧滑入（参照 AngelLive 的 QualitySelectionPanel）。
//

import SwiftUI

struct QualitySelectionPanel: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isShowing: Bool

    private var cdnGroups: [(label: String, items: [StreamInfo])] {
        var order: [String] = []
        var map: [String: [StreamInfo]] = [:]
        for s in viewModel.streams {
            if map[s.cdn] == nil { order.append(s.cdn) }
            map[s.cdn, default: []].append(s)
        }
        return order.map { (label: $0, items: map[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.lg) {
                    ForEach(Array(cdnGroups.enumerated()), id: \.offset) { _, group in
                        cdnSection(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("清晰度")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                if let name = viewModel.currentStream?.name {
                    Text("当前：\(name)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 8)

            Button {
                isShowing = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func cdnSection(_ group: (label: String, items: [StreamInfo])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(group.label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(group.items) { stream in
                    row(stream)
                }
            }
            .padding(4)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(_ stream: StreamInfo) -> some View {
        let selected = viewModel.currentStream?.url == stream.url
        return Button {
            viewModel.play(stream)
            isShowing = false
        } label: {
            HStack(spacing: 10) {
                Text(stream.isAuto ? "自动（最高画质）" : stream.name)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.8))

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.2) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
