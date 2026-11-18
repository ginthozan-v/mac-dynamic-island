import Foundation

/// Files parked on the island. Stored as bookmarks so moved files are still found.
@MainActor
@Observable
final class ShelfStore {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }

    private(set) var items: [Item] = []
    private let defaultsKey = "shelf.bookmarks"
    /// False for previews: keeps the shelf in memory and never touches saved settings.
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        if persistent { load() }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url))
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard persistent else { return }
        let bookmarks = items.compactMap { try? $0.url.bookmarkData() }
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    private func load() {
        let bookmarks = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        items = bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Item(url: url)
        }
    }
}
