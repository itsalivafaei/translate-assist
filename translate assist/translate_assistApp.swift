//
//  translate_assistApp.swift
//  translate assist
//
//  Created by monono on 8/11/25.
//

import SwiftUI
import AppKit
import Foundation
import SQLite3

@main
struct translate_assistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep the app windowless for a pure menubar experience in Phase 0.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        DatabaseManager.shared.start()
        // Phase 4: opportunistic cache maintenance on launch
        try? CacheService.pruneIfOversized(maxEntriesPerTable: 10_000)
        // Also schedule periodic cleanup on app activation events
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            try? CacheService.evictExpired()
        }
        // Optional periodic cleanup timer to keep caches healthy in long sessions
        let interval = max(5, Constants.cacheMaintenanceIntervalMinutes)
        Timer.scheduledTimer(withTimeInterval: TimeInterval(interval * 60), repeats: true) { _ in
            try? CacheService.evictExpired()
            try? CacheService.pruneIfOversized(maxEntriesPerTable: 10_000)
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            // Prefer a template symbol for proper dark/light adaption
            if let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Translate Assist") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "TA"
            }
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverHeight)
        popover.contentViewController = NSHostingController(rootView: PopoverRootView())
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}

// Minimal placeholder root view for the popover in Phase 0
private struct PopoverRootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                Text("Translate Assist")
                    .font(.headline)
                Spacer()
            }
            Text("Phase 0: Bootstrap complete. Menu bar active; popover ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
