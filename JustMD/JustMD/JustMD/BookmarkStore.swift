import Foundation

@MainActor final class BookmarkStore {

    private let storePath: URL

    /// Bookmark data keyed by file URL.
    private(set) var bookmarks: [URL: Data] = [:]

    /// Tracks insertion order so the oldest entry can be evicted at cap.
    private var insertionOrder: [URL] = []

    private static let cap = 20

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storePath = appSupport.appendingPathComponent("JustMD/bookmarks.plist")
        loadFromDisk()
    }

    init(storePath: URL) {
        self.storePath = storePath
        loadFromDisk()
    }

    // MARK: - Public API

    /// Creates a security-scoped bookmark for `url` and persists it.
    func save(url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            insertBookmark(url: url, data: data)
            saveToDisk()
        } catch {
            // Silently ignore — callers don't need to handle bookmark failures
        }
    }

    /// Resolves all stored bookmarks. Removes stale entries. Returns valid URLs.
    func resolveAll() -> [URL] {
        var validURLs: [URL] = []
        var toRemove: [URL] = []
        var toUpdate: [(URL, Data)] = []

        for (url, data) in bookmarks {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    // Refresh the bookmark data
                    if let fresh = try? resolved.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        toUpdate.append((url, fresh))
                    }
                }
                validURLs.append(resolved)
            } catch {
                toRemove.append(url)
            }
        }

        for url in toRemove {
            removeBookmark(url: url)
        }
        for (url, fresh) in toUpdate {
            bookmarks[url] = fresh
        }
        if !toRemove.isEmpty || !toUpdate.isEmpty {
            saveToDisk()
        }

        return validURLs
    }

    /// Most recently opened first (the Open Recent menu)
    var recentFiles: [URL] { insertionOrder.reversed() }

    func removeAll() {
        bookmarks = [:]
        insertionOrder = []
        saveToDisk()
    }

    /// The security-scoped URL to open for a recent file, or nil if it can no longer be found
    func resolve(_ url: URL) -> URL? {
        guard let data = bookmarks[url] else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    // MARK: - Private helpers

    private func insertBookmark(url: URL, data: Data) {
        if bookmarks[url] != nil {
            // Update in place — move to end of insertion order (most recently used)
            insertionOrder.removeAll { $0 == url }
            insertionOrder.append(url)
            bookmarks[url] = data
            return
        }
        if bookmarks.count >= Self.cap {
            // Evict oldest entry
            let oldest = insertionOrder.removeFirst()
            bookmarks.removeValue(forKey: oldest)
        }
        insertionOrder.append(url)
        bookmarks[url] = data
    }

    private func removeBookmark(url: URL) {
        bookmarks.removeValue(forKey: url)
        insertionOrder.removeAll { $0 == url }
    }

    // MARK: - Disk I/O

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        do {
            let raw = try Data(contentsOf: storePath)
            let plist = try PropertyListSerialization.propertyList(from: raw, format: nil)
            // Current format: an ordered list, oldest first. Earlier builds saved an unordered dictionary.
            let entries: [(String, Data)] = (plist as? [[String: Any]])?.compactMap { entry in
                (entry["url"] as? String).flatMap { url in (entry["bookmark"] as? Data).map { (url, $0) } }
            } ?? (plist as? [String: Data]).map { Array($0) } ?? []
            bookmarks = [:]
            insertionOrder = []
            for (key, value) in entries {
                guard let url = URL(string: key) else { continue }
                bookmarks[url] = value
                insertionOrder.append(url)
            }
        } catch {
            // Corrupted plist — start fresh
            bookmarks = [:]
            insertionOrder = []
        }
    }

    private func saveToDisk() {
        do {
            let dir = storePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Ordered, so recency survives a relaunch
            let entries: [[String: Any]] = insertionOrder.compactMap { url in
                bookmarks[url].map { ["url": url.absoluteString, "bookmark": $0] }
            }
            let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
            try data.write(to: storePath, options: .atomic)
        } catch {
            // Non-fatal — bookmarks are still in memory for this session
        }
    }
}
