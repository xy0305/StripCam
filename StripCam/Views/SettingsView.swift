//
//  SettingsView.swift
//  StripCam
//
//  设置：登录 Cookie（我的最爱）、关于。
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppKeys.cookie) private var cookie = ""
    @State private var savedToast = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $cookie)
                    .frame(minHeight: 140)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("登录 Cookie")
            } footer: {
                Text("「我的最爱」需要登录后的 Cookie。用浏览器登录 stripchat.com，复制完整 Cookie 粘贴到这里即可。Cookie 仅保存在本机。")
            }

            Section {
                Button("保存") {
                    cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedToast = true
                }
                .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("数据来源", value: "Stripchat")
                Text("本应用为第三方非官方播放器，与 Stripchat 官方无关。仅供学习交流使用，请遵守当地法律法规。")
                    .font(.footnote)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .alert("已保存", isPresented: $savedToast) {
            Button("好", role: .cancel) {}
        }
    }
}
