//
//  ContentView.swift
//  JustMD
//
//  Created by Kaan on 20.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var tabState: TabState
    let fileCoordinator: FileCoordinator
    let folderAccess: FolderAccess

    var body: some View {
        VStack(spacing: 0) {
            if tabState.tabs.isEmpty {
                // Empty state: centred instructions
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Open a Markdown file to get started")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Drag & drop a file here, use File > Open, or double-click a .md file in Finder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabBarView(tabState: tabState)
                Divider()
                if let tabID = tabState.selectedTabID {
                    DocumentView(tabState: tabState, folderAccess: folderAccess, tabID: tabID)
                } else {
                    Color.clear
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        // Drag-and-drop support
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          (url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown") else { return }
                    Task { @MainActor in
                        fileCoordinator.open(url: url)
                    }
                }
            }
            return true
        }
    }
}
