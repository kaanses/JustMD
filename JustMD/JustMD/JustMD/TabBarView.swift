import SwiftUI

private let bgPage = NSColor(name: nil) { app in
    app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)   // #0a0a0a
        : NSColor(red: 0.961, green: 0.937, blue: 0.878, alpha: 1)   // #f5efe0
}

private let tabSelectedBg = NSColor(name: nil) { app in
    app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(white: 1.0, alpha: 0.08)   // subtle white lift on dark bg
        : NSColor(white: 0.0, alpha: 0.07)   // subtle dark press on light bg
}

private let tabTextColor = NSColor(name: nil) { app in
    app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1)   // #d4d4d4
        : NSColor(red: 0.227, green: 0.173, blue: 0.0, alpha: 1)     // #3a2c00
}

private let tabMutedColor = NSColor(name: nil) { app in
    app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.267, green: 0.267, blue: 0.333, alpha: 1)   // #444455
        : NSColor(red: 0.627, green: 0.533, blue: 0.314, alpha: 1)   // #a08850
}

struct TabBarView: View {
    @ObservedObject var tabState: TabState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabState.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isSelected: tab.id == tabState.selectedTabID,
                        onSelect: { tabState.selectedTabID = tab.id },
                        onClose: { tabState.close(id: tab.id) }
                    )
                }
            }
        }
        .frame(height: 36)
        .background(Color(bgPage))
    }
}

private struct TabItemView: View {
    let tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.isErrorTab ? "Error" : tab.filename)
                .lineLimit(1)
                .font(.system(size: 12))
                .foregroundColor(tab.isUnavailable ? Color(tabMutedColor) : Color(tabTextColor))
            if tab.isLargeFile {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(tabMutedColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(isSelected ? Color(tabSelectedBg) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
