//
//  FavoritesStore.swift
//  StripCam
//
//  本地收藏（书签）管理，持久化到 UserDefaults。
//

import Foundation
import Combine

final class FavoritesStore: ObservableObject {
    @Published private(set) var items: [SavedModel] = []

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    func toggle(_ model: StripModel) {
        toggle(PlayableModel(model: model))
    }

    func toggle(_ playable: PlayableModel) {
        if let idx = items.firstIndex(where: { $0.id == playable.id }) {
            items.remove(at: idx)
        } else {
            items.insert(SavedModel(playable: playable), at: 0)
        }
        save()
    }

    func toggle(_ saved: SavedModel) {
        if let idx = items.firstIndex(where: { $0.id == saved.id }) {
            items.remove(at: idx)
        } else {
            items.insert(saved, at: 0)
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: AppKeys.favorites) else { return }
        items = (try? decoder.decode([SavedModel].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: AppKeys.favorites)
    }
}
