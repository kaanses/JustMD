import Foundation

/// Reports when a file changes on disk so open tabs follow the user's editor.
/// Editors save either in place or atomically (write a temp file, rename it over the original);
/// after a rename the old descriptor watches a dead inode, so the watch re-arms on the path.
@MainActor
final class FileWatcher {
    private let onChange: (URL) -> Void
    private var watched: Set<URL> = []
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var pending: Set<URL> = []

    init(onChange: @escaping (URL) -> Void) {
        self.onChange = onChange
    }

    func watch(_ url: URL) {
        guard watched.insert(url).inserted else { return }
        arm(url, attempt: 0)
    }

    func unwatch(_ url: URL) {
        watched.remove(url)
        pending.remove(url)
        sources.removeValue(forKey: url)?.cancel()
    }

    private func arm(_ url: URL, attempt: Int) {
        guard watched.contains(url), sources[url] == nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Mid-save the path can briefly not exist; after ~0.5 s report it so the tab can show it's gone
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.arm(url, attempt: attempt + 1) }
            } else {
                report(url)
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    source.cancel()
                    self.sources[url] = nil
                    self.arm(url, attempt: 0)
                }
                self.report(url)
            }
        }
        source.setCancelHandler { close(fd) }
        sources[url] = source
        source.resume()
    }

    /// One save is often several events (write, attrib, rename); report it once
    private func report(_ url: URL) {
        guard pending.insert(url).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.pending.remove(url) != nil, self.watched.contains(url) else { return }
            self.onChange(url)
        }
    }
}
