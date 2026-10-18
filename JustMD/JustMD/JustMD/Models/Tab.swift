import Foundation

struct Tab: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var content: String
    var isUnavailable: Bool = false
    var isErrorTab: Bool = false

    var filename: String { url.lastPathComponent }
    var isLargeFile: Bool { content.utf8.count > 10_000_000 }

    init(id: UUID = UUID(), url: URL, content: String, isErrorTab: Bool = false) {
        self.id = id
        self.url = url
        self.content = content
        self.isErrorTab = isErrorTab
    }
}
