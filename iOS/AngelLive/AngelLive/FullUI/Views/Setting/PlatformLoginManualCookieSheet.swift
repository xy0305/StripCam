//
//  PlatformLoginManualCookieSheet.swift
//  AngelLive
//
//  手动填入 Cookie 登录面板。
//  适用 manifest.loginFlow.kind == "cookie" 的平台（如 PandaTV），
//  或网页登录不可用（Cloudflare 拦截等）时的替代入口。
//

import SwiftUI
import UIKit
import AngelLiveCore
struct PlatformLoginManualCookieSheet: View {
    let entry: LoginPlatformEntry
    let onUseWebLogin: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared

    @State private var cookieText = ""
    @State private var isSaving = false
    @State private var resultMessage: String?
    @State private var resultIsSuccess = false

    private var loginFlow: ManifestLoginFlow { entry.loginFlow }

    var body: some View {
        NavigationStack {
            Form {
                cookieSection
                requirementSection
                actionSection
            }
            .navigationTitle("\(entry.displayName) Cookie 登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onUseWebLogin {
                        Button("网页登录") { onUseWebLogin() }
                    }
                }
            }
            .onAppear(perform: pasteFromClipboardIfEmpty)
        }
    }

    // MARK: - Cookie 输入

    private var cookieSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if cookieText.isEmpty {
                    Text("粘贴 Cookie，例如：\n\(exampleCookie)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $cookieText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Button {
                    cookieText = UIPasteboard.general.string ?? ""
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                }
                Spacer()
                Button(role: .destructive) {
                    cookieText = ""
                    resultMessage = nil
                } label: {
                    Label("清空", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("登录 Cookie")
        } footer: {
            Text(cookieFooter)
        }
    }

    private var requirementSection: some View {
        Section("要求") {
            if !loginFlow.authSignalCookies.isEmpty {
                LabeledContent("必需 Cookie") {
                    Text(loginFlow.authSignalCookies.joined(separator: " + "))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let hint = loginFlow.requiredCookieHint, !hint.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("获取方式") {
                Text("浏览器登录 \(loginFlow.websiteHost ?? "官网") 后，开发者工具 → Application → Cookies 复制")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSaving ? "正在校验…" : "保存并校验")
                    Spacer()
                }
            }
            .disabled(isSaving || cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let resultMessage {
                Label(
                    resultMessage,
                    systemImage: resultIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(resultIsSuccess ? AppConstants.Colors.success : .orange)
            }
        } footer: {
            Text("Cookie 由宿主安全保存，仅提供给该插件使用，不会与其他插件共享。")
        }
    }

    // MARK: - 逻辑

    private var exampleCookie: String {
        loginFlow.authSignalCookies.prefix(2).map { "\($0)=…" }.joined(separator: "; ")
    }

    private var cookieFooter: String {
        let host = loginFlow.websiteHost ?? URL(string: loginFlow.loginURL)?.host() ?? "官网"
        return "在浏览器登录 \(host) 后复制完整 Cookie 粘贴到此处。\(loginFlow.authSignalCookies.count > 1 ? "多条必需 Cookie 需同时包含。" : "")"
    }

    private func pasteFromClipboardIfEmpty() {
        guard cookieText.isEmpty else { return }
        let pasted = UIPasteboard.general.string ?? ""
        guard isValidCookie(pasted) else { return }
        cookieText = pasted
    }

    /// 宽松校验：形如 a=b 的键值对，且包含全部认证信号 Cookie。
    private func isValidCookie(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("=") else { return false }
        return missingSignalCookies(trimmed).isEmpty
    }

    private func missingSignalCookies(_ cookie: String) -> [String] {
        guard !loginFlow.authSignalCookies.isEmpty else { return [] }
        return loginFlow.authSignalCookies.filter { signal in
            cookie.range(
                of: "(^|;\\s*)\(NSRegularExpression.escapedPattern(for: signal))\\s*=",
                options: .regularExpression
            ) == nil
        }
    }

    private func extractUID(from cookie: String) -> String? {
        let uidNames = loginFlow.uidCookieNames ?? []
        for name in uidNames {
            let pairs = cookie.split(separator: ";")
            for pair in pairs {
                let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                if String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines) == name {
                    let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    @MainActor
    private func save() async {
        let cookie = cookieText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { return }

        let missing = missingSignalCookies(cookie)
        guard missing.isEmpty else {
            resultIsSuccess = false
            resultMessage = "缺少必需 Cookie：\(missing.joined(separator: "、"))"
            return
        }

        isSaving = true
        resultMessage = nil
        defer { isSaving = false }

        let shouldValidate = entry.auth?.supportsValidation ?? false
        let result = await PlatformSessionManager.shared.loginWithCookie(
            pluginId: entry.pluginId,
            cookie: cookie,
            uid: extractUID(from: cookie),
            source: .local,
            validateBeforeSave: shouldValidate
        )

        switch result {
        case .valid:
            resultIsSuccess = true
            resultMessage = "✅ 登录成功，Cookie 已保存"
            await syncService.refreshLoginStatus(pluginId: entry.pluginId)
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        case .expired:
            resultIsSuccess = false
            resultMessage = "Cookie 已过期，请重新获取"
        case .invalid(let reason):
            resultIsSuccess = false
            resultMessage = "Cookie 无效：\(reason)"
        case .networkError(let message):
            resultIsSuccess = false
            resultMessage = "网络错误：\(message)"
        }
    }
}

#Preview {
    PlatformLoginManualCookieSheet(
        entry: LoginPlatformEntry(
            pluginId: "panda",
            displayName: "PandaTV",
            liveType: "12",
            loginFlow: ManifestLoginFlow(
                loginURL: "https://m.pandalive.co.kr/my",
                cookieDomains: ["pandalive.co.kr"],
                authSignalCookies: ["sessKey"],
                uidCookieNames: ["sessKey"],
                requiredCookieHint: "需包含 PandaTV 登录态 cookie（sessKey）",
                websiteHost: "pandalive.co.kr"
            ),
            auth: ManifestAuth(supportsValidation: true),
            version: "2.0.4"
        ),
        onUseWebLogin: nil
    )
}
