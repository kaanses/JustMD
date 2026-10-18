#if canImport(Sparkle)
import Combine
import Sparkle
import SwiftUI

/// Self-updating for the direct-download build only. Sparkle is linked into the
/// "JustMD Direct" target alone: the App Store updates its own copy and rejects apps
/// that carry an updater, so in the App Store build this file compiles to nothing.
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func check() { controller.checkForUpdates(nil) }
}

struct UpdateCommands: Commands {
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.check() }
                .disabled(!updater.canCheck)
        }
    }
}
#endif
