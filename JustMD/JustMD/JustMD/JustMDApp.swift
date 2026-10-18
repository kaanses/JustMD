//
//  JustMDApp.swift
//  JustMD
//
//  Created by Kaan on 20.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct JustMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // These are the shared instances for the whole app lifetime
    private let tabState = TabState()
    private let bookmarkStore = BookmarkStore()
    // Created at launch so folders granted earlier are readable before the first render
    private let folderAccess = FolderAccess()
    private let fileCoordinator: FileCoordinator
    #if canImport(Sparkle)
    @StateObject private var updater = Updater()
    #endif

    init() {
        let ts = tabState
        let bs = bookmarkStore
        let fc = FileCoordinator(tabState: ts, bookmarkStore: bs)
        self.fileCoordinator = fc
        // Wire AppDelegate immediately so application(_:open:) has fileCoordinator
        // available even at cold launch before the window appears.
        appDelegate.tabState = ts
        appDelegate.bookmarkStore = bs
        appDelegate.fileCoordinator = fc
    }

    var body: some Scene {
        // Single window: WindowGroup spawned extra windows (restoration, open events),
        // each rebuilding and rendering the whole document again.
        Window("JustMD", id: "main") {
            ContentView(tabState: tabState, fileCoordinator: fileCoordinator, folderAccess: folderAccess)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(tabState: tabState, fileCoordinator: fileCoordinator, bookmarkStore: bookmarkStore) }
        #if canImport(Sparkle)
        .commands { UpdateCommands(updater: updater) }
        #endif
    }
}
