//
//  RemoteImage.swift
//  StripCam
//
//  带占位与淡入的网络图片组件（基于 AsyncImage + URLCache）。
//

import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppConstants.Colors.placeholderGradient())
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary.opacity(0.5))
            )
    }
}

/// 圆形头像版
struct RemoteAvatar: View {
    let url: URL?

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .clipShape(Circle())
    }
}
