//
//  CrashRecoveryView.swift
//  AngelLive
//
//  上次启动没走到 UI 就绪时展示，把沙盒里的崩溃/面包屑导出分享。
//

import SwiftUI
import UIKit

struct CrashRecoveryView: View {
    let onContinue: () -> Void
    @State private var exportText = CrashLogStore.exportText()
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("上次启动没有正常进入界面。系统「分析数据」经常没有侧载崩溃记录，这里是 App 自己写下的日志。")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            showShare = true
                        } label: {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("继续进入 App") {
                            CrashLogStore.appendBreadcrumb("user_continue \(ISO8601DateFormatter().string(from: Date()))")
                            CrashLogStore.clearCrashFile()
                            onContinue()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(exportText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("启动异常")
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(items: [exportText])
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
