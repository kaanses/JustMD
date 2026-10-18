import SwiftUI

struct DocumentView: View {
    @ObservedObject var tabState: TabState
    @ObservedObject var folderAccess: FolderAccess
    let tabID: UUID
    @AppStorage(Zoom.storageKey) private var zoom = 1.0
    @AppStorage("showSource") private var showSource = true

    private var tab: Tab? { tabState.tabs.first { $0.id == tabID } }

    var body: some View {
        Group {
            if let tab {
                if tab.isUnavailable {
                    Text("File no longer available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tab.isErrorTab {
                    Text(tab.content)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if let folder = LocalImages.folderNeedingAccess(
                            markdown: tab.content, documentFolder: tab.url.deletingLastPathComponent(),
                            isReadable: { FileManager.default.isReadableFile(atPath: $0.path) }
                        ) {
                            ImageAccessBar(folder: folder) { askForAccess(to: folder) }
                        }
                        documentPanes(tab)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func documentPanes(_ tab: Tab) -> some View {
                    HStack(spacing: 0) {
                        PreviewPane(content: tab.content, folder: tab.url.deletingLastPathComponent(), zoom: zoom, documentID: tab.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showSource {
                            Divider()
                            SourcePane(content: tab.content)
                                .frame(minWidth: 200, maxWidth: 400, maxHeight: .infinity)
                        }
                    }
    }

    /// The sandbox only lets JustMD read the files it was given; images beside them need the folder
    private func askForAccess(to folder: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        panel.prompt = "Show Images"
        panel.message = "JustMD needs your permission to read the images in \u{201C}\(folder.lastPathComponent)\u{201D}."
        panel.begin { response in
            guard response == .OK, let granted = panel.url else { return }
            folderAccess.grant(granted)
            ImageStore.shared.forgetFailures(under: granted)
        }
    }
}

private struct ImageAccessBar: View {
    let folder: URL
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle")
                .foregroundStyle(Color(Theme.textMuted))
            Text("This document has images in \u{201C}\(folder.lastPathComponent)\u{201D} that JustMD needs permission to read.")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.textBody))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Show Images", action: onShow)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(Theme.accentPrimary).opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
