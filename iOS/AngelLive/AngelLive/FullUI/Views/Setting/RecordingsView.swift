//
//  RecordingsView.swift
//  AngelLive
//

import SwiftUI
internal import AVKit
import AngelLiveCore

struct RecordingsView: View {
    @ObservedObject private var manager = LiveRecordingManager.shared
    @State private var previewURL: URL?

    var body: some View {
        List {
            if manager.activeCount > 0 {
                Section("正在录制") {
                    ForEach(manager.items.filter(\.isActive)) { item in
                        recordingRow(item)
                    }
                }
            }

            let finished = manager.items.filter { !$0.isActive }
            Section(finished.isEmpty && manager.activeCount == 0 ? "录像" : "已保存") {
                if finished.isEmpty && manager.activeCount == 0 {
                    Text("还没有录像。打开直播间后点右上角红点即可开始，退出直播间或进后台都会继续录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(finished) { item in
                        recordingRow(item)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            manager.delete(finished[index])
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("录像")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if manager.activeCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部停止") {
                        manager.stopAll()
                    }
                }
            }
        }
        .onAppear {
            manager.reloadFinishedFiles()
        }
        .onChange(of: manager.banner) { _, _ in
            manager.reloadFinishedFiles()
        }
        .fullScreenCover(item: Binding(
            get: { previewURL.map { IdentifiedURL(url: $0) } },
            set: { previewURL = $0?.url }
        )) { item in
            RecordingPlayer(url: item.url)
        }
    }

    @ViewBuilder
    private func recordingRow(_ item: LiveRecordingItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: item.isActive ? "record.circle" : "film")
                    .font(.title3)
                    .foregroundStyle(item.isActive ? .red : .primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.userName.isEmpty ? item.roomTitle : item.userName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(statusText(item))
                    Text(item.durationText)
                    Text(item.sizeText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isActive {
                Button("停止") {
                    manager.stop(id: item.id)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else if let url = manager.shareURL(for: item) {
                Button {
                    previewURL = url
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !item.isActive {
                Button(role: .destructive) {
                    manager.delete(item)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if let url = manager.shareURL(for: item) {
                ShareLink(item: url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
            if !item.isActive {
                Button(role: .destructive) {
                    manager.delete(item)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func statusText(_ item: LiveRecordingItem) -> String {
        switch item.status {
        case .recording: return "录制中"
        case .stopping: return "正在保存"
        case .finished: return "已完成"
        case .failed(let message): return message
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct RecordingPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingsView()
    }
}
