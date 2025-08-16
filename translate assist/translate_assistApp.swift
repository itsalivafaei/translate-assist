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
import OSLog
import Carbon.HIToolbox
import Combine
import UniformTypeIdentifiers

@main
struct translate_assistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep the app windowless; use Settings for hotkey configuration.
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Translate Assist") {
                    NotificationCenter.default.post(name: .openAboutRequested, object: nil)
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Translate Assist") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}
// MARK: - SwiftUI Settings
private struct SettingsView: View {
    @State private var selection: HotkeyOption = HotkeyOption.current()
    @State private var showingImport = false

    var body: some View {
        Form {
            Picker("Global Hotkey", selection: $selection) {
                ForEach(HotkeyOption.allCases, id: \.self) { opt in
                    Text(opt.displayLabel).tag(opt)
                }
            }
            .onChange(of: selection) { _, newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: HotkeyOption.userDefaultsKey)
                NotificationCenter.default.post(name: .hotkeyPreferenceDidChange, object: nil)
            }

            Divider()
            Text("Import/Export")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Import Termbank JSONL…") { importTermbankJSONL() }
                Button("Import Senses CSV…") { importSensesCSV() }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { selection = HotkeyOption.current() }
    }

    private func importTermbankJSONL() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try ImportService.importTermbankJSONL(from: url)
                    BannerCenter.shared.show(message: "Imported termbank.jsonl")
                } catch {
                    BannerCenter.shared.show(message: "Import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func importSensesCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try ImportService.importSensesCSV(from: url, termIdMapper: { Int64($0) })
                    BannerCenter.shared.show(message: "Imported senses.csv")
                } catch {
                    BannerCenter.shared.show(message: "Import failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let metrics: MetricsProvider = ProvidersBootstrap.makeMetricsProvider()
    private lazy var translationService: TranslationService = {
        let tp = ProvidersBootstrap.makeTranslationProvider(metrics: metrics)
        let llm = ProvidersBootstrap.makeLLMEnhancer(primary: "gemini", metrics: metrics)
        let ex = ProvidersBootstrap.makeExamplesProvider()
        let gl = ProvidersBootstrap.makeGlossaryProvider()
        return TranslationService(
            translationProvider: tp,
            llmEnhancer: llm,
            examplesProvider: ex,
            glossary: gl,
            metrics: metrics
        )
    }()
    private lazy var orchestrationVM: OrchestrationVM = {
        OrchestrationVM(service: translationService)
    }()
    private let logger = Logger(subsystem: "com.klewrsolutions.translate-assist", category: "menubar")
    private let termbank = TermbankService()
    private let srs = SRSService()
    private var aboutWindowController: NSWindowController?

    // Global hotkey state
    private var hotKeyRefCtrlT: EventHotKeyRef?
    private var hotKeyRefCtrlShiftT: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        registerGlobalHotkeys()
        // Register Services provider (requires NSServices in Info.plist)
        NSApp.servicesProvider = ServicesProvider.shared
        NSUpdateDynamicServices()
        DatabaseManager.shared.start()
        // Start reachability monitoring for proactive Offline banners
        NetworkReachability.shared.start()
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

        // Observe hotkey preference changes to re-register
        NotificationCenter.default.addObserver(forName: .hotkeyPreferenceDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.registerGlobalHotkeys()
        }

        // Close popover when requested by SwiftUI view (Esc)
        NotificationCenter.default.addObserver(forName: .menubarPopoverRequestClose, object: nil, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        // Service trigger → open popover with incoming text
        NotificationCenter.default.addObserver(forName: .menubarServiceTrigger, object: nil, queue: .main) { [weak self] note in
            guard let strongSelf = self else { return }
            let incoming = note.object as? String ?? ""
            strongSelf.openPopoverAndEmitPayload(incoming)
        }

        // About command from the app menu
        NotificationCenter.default.addObserver(forName: .openAboutRequested, object: nil, queue: .main) { [weak self] _ in
            self?.openAbout()
        }

        // UI Tests hook: auto-open popover on launch when requested
        if ProcessInfo.processInfo.arguments.contains("-UITestOpenPopover") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                self.togglePopover(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unregister hotkeys and handler
        if let hk = hotKeyRefCtrlT { UnregisterEventHotKey(hk) }
        if let hk = hotKeyRefCtrlShiftT { UnregisterEventHotKey(hk) }
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }
        NetworkReachability.shared.stop()
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
            button.setAccessibilityLabel("Translate Assist")
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configurePopover() {
        // Default transient behavior; keep pinned/open for UI automation
        if ProcessInfo.processInfo.arguments.contains("-UITestOpenPopover") {
            popover.behavior = .applicationDefined
            popover.animates = false
        } else {
            popover.behavior = .transient
        }
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverHeight)
        popover.contentViewController = NSHostingController(rootView: MenubarPopoverView(translationService: translationService, orchestrationVM: orchestrationVM, termbank: termbank, srs: srs))
        popover.delegate = self
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showStatusMenu(anchor: button, event: event)
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // In UI tests, keep our app foreground to reduce accidental popover closes
            if ProcessInfo.processInfo.arguments.contains("-UITestOpenPopover") {
                NSApp.activate(ignoringOtherApps: true)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            // Focus input when opening
            NotificationCenter.default.post(name: .menubarPopoverDidOpen, object: nil)
            NotificationCenter.default.post(name: .menubarPopoverShouldFocusInput, object: nil)
        }
    }

    private func showStatusMenu(anchor: NSView, event: NSEvent) {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let about = NSMenuItem(title: "About Translate Assist", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())

        let exportCSV = NSMenuItem(title: "Export Senses (CSV)…", action: #selector(exportSensesCSV), keyEquivalent: "")
        exportCSV.target = self
        menu.addItem(exportCSV)

        let exportJSONL = NSMenuItem(title: "Export Termbank (JSONL)…", action: #selector(exportTermbankJSONL), keyEquivalent: "")
        exportJSONL.target = self
        menu.addItem(exportJSONL)

        let exportTerms = NSMenuItem(title: "Export Terms (CSV)…", action: #selector(exportTermsCSV), keyEquivalent: "")
        exportTerms.target = self
        menu.addItem(exportTerms)

        let exportExamples = NSMenuItem(title: "Export Examples (CSV)…", action: #selector(exportExamplesCSV), keyEquivalent: "")
        exportExamples.target = self
        menu.addItem(exportExamples)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: anchor)
    }

    private func openPopoverAndEmitPayload(_ text: String) {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            NotificationCenter.default.post(name: .menubarServicePayload, object: text)
            NotificationCenter.default.post(name: .menubarPopoverShouldFocusInput, object: nil)
        }
    }

    // MARK: - Export handlers (Phase 9)
    @objc private func exportSensesCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "senses.csv"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try CSVExportService.exportSensesCSV(to: url)
                    BannerCenter.shared.show(message: "Exported senses.csv")
                } catch {
                    BannerCenter.shared.show(message: "Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func exportTermbankJSONL() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "termbank.jsonl"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try JSONLExportService.exportTermbankJSONL(to: url)
                    BannerCenter.shared.show(message: "Exported termbank.jsonl")
                } catch {
                    BannerCenter.shared.show(message: "Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func exportTermsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "terms.csv"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try CSVExportService.exportTermsCSV(to: url)
                    BannerCenter.shared.show(message: "Exported terms.csv")
                } catch {
                    BannerCenter.shared.show(message: "Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func exportExamplesCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "examples.csv"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try CSVExportService.exportExamplesCSV(to: url)
                    BannerCenter.shared.show(message: "Exported examples.csv")
                } catch {
                    BannerCenter.shared.show(message: "Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @objc private func openAbout() {
        if let wc = aboutWindowController {
            wc.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "About Translate Assist"
        window.center()
        let wc = NSWindowController(window: window)
        aboutWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Global hotkeys (Ctrl+T, Ctrl+Shift+T)

    private func registerGlobalHotkeys() {
        // Unregister existing first
        if let hk = hotKeyRefCtrlT { UnregisterEventHotKey(hk); hotKeyRefCtrlT = nil }
        if let hk = hotKeyRefCtrlShiftT { UnregisterEventHotKey(hk); hotKeyRefCtrlShiftT = nil }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData = userData, let eventRef = eventRef else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                delegate.handleHotKeyEvent(eventRef)
            }
            return noErr
        }, 1, &eventType, userData, &hotKeyHandler)
        if status != noErr {
            logger.error("Failed to install hotkey handler: status=\(status)")
            NotificationCenter.default.post(name: .menubarShowBanner, object: "Hotkey handler failed to install. Shortcuts may not work.")
        }

        let ctrl: UInt32 = UInt32(controlKey)
        let shift: UInt32 = UInt32(shiftKey)
        let tKeyCode: UInt32 = 17 // 'T' on US keyboard

        let option = HotkeyOption.current()
        switch option {
        case .ctrlT:
            let id = EventHotKeyID(signature: OSType(1), id: 1)
            let s = RegisterEventHotKey(tKeyCode, ctrl, id, GetApplicationEventTarget(), 0, &hotKeyRefCtrlT)
            if s != noErr {
                logger.error("Failed to register Ctrl+T hotkey: status=\(s)")
                NotificationCenter.default.post(name: .menubarShowBanner, object: "Could not register Ctrl+T. Try Ctrl+Shift+T or change in Preferences.")
            }
        case .ctrlShiftT:
            let id = EventHotKeyID(signature: OSType(1), id: 2)
            let s = RegisterEventHotKey(tKeyCode, ctrl | shift, id, GetApplicationEventTarget(), 0, &hotKeyRefCtrlShiftT)
            if s != noErr {
                logger.error("Failed to register Ctrl+Shift+T hotkey: status=\(s)")
                NotificationCenter.default.post(name: .menubarShowBanner, object: "Could not register Ctrl+Shift+T. Try Ctrl+T or change in Preferences.")
            }
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr else { return }
        switch hotKeyID.id {
        case 1, 2:
            logger.debug("Global hotkey pressed id=\(hotKeyID.id)")
            togglePopover(nil)
        default:
            break
        }
    }
}

// MARK: - Notifications used to coordinate focus and cancellation between AppKit and SwiftUI
extension Notification.Name {
    static let menubarPopoverWillClose = Notification.Name("menubar.popover.willClose")
    static let menubarPopoverDidOpen = Notification.Name("menubar.popover.didOpen")
    static let menubarPopoverShouldFocusInput = Notification.Name("menubar.popover.focusInput")
    static let menubarShowBanner = Notification.Name("menubar.popover.showBanner")
    static let menubarPopoverRequestClose = Notification.Name("menubar.popover.requestClose")
    static let menubarServicePayload = Notification.Name("menubar.servicePayload")
    static let menubarServiceTrigger = Notification.Name("menubar.serviceTrigger")
    static let openAboutRequested = Notification.Name("app.openAboutRequested")
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        // Broadcast so views can cancel any in-flight operations immediately
        NotificationCenter.default.post(name: .menubarPopoverWillClose, object: nil)
    }
}

// MARK: - Services provider to receive selected text
@objc final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    // This selector name should be referenced by NSServices in Info.plist to show in Services menu
    // Signature per Cocoa Services: pasteboard, userData, error
    @objc func translateAssistService(_ pboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        if let str = pboard.string(forType: .string) {
            NotificationCenter.default.post(name: .menubarServiceTrigger, object: str)
        }
    }
}

// MARK: - Lightweight banner center for transient notices
final class BannerCenter: ObservableObject {
    static let shared = BannerCenter()
    @Published private var message: String? = nil
    private var hideTask: Task<Void, Never>?

    func show(message: String, autoHideSeconds: Double = 3.0) {
        self.message = message
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(autoHideSeconds * 1_000_000_000))
            await MainActor.run { self?.message = nil }
        }
    }

    @ViewBuilder
    func view() -> some View {
        if let message = message, !message.isEmpty {
            Text(message)
                .font(.caption)
                .padding(6)
                .background(.thinMaterial)
                .cornerRadius(6)
                .transition(.opacity)
                .zIndex(1)
        }
    }
}

// MARK: - SwiftUI popover root view for Phase 7 shell
private struct MenubarPopoverView: View {
    @State private var inputText: String = ""
    @FocusState private var focusInput: Bool
    @State private var isTranslating: Bool = false
    @State private var currentTask: Task<Void, Never>? = nil
    @State private var cancellables: Set<AnyCancellable> = []
    // Phase 8: persona and domain controls
    @State private var selectedPersona: PersonaPreset = .engineerRead
    @State private var domainAI: Bool = true
    @State private var domainBusiness: Bool = false
    private let translationService: TranslationService
    @ObservedObject private var vm: OrchestrationVM
    private let termbank: TermbankService
    private let srs: SRSService

    init(translationService: TranslationService, orchestrationVM: OrchestrationVM, termbank: TermbankService, srs: SRSService) {
        self.translationService = translationService
        self.vm = orchestrationVM
        self.termbank = termbank
        self.srs = srs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .accessibilityHidden(true)
                Text("Translate Assist")
                    .font(.headline)
                    .accessibilityLabel("Translate Assist header")
                Spacer()
            }
            .overlay(alignment: .topTrailing) {
                BannerCenter.shared.view()
            }

            TextField("Paste or type text…", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...5)
                .focused($focusInput)
                .accessibilityLabel("Input text to translate")
                .accessibilityHint("Enter text to translate into Persian")

            // Offline/banner area
            if !NetworkReachability.shared.isOnline {
                Text("Offline — showing cache when possible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Persona & Domain controls
            VStack(alignment: .leading, spacing: 8) {
                Picker("Persona", selection: $selectedPersona) {
                    ForEach(PersonaPreset.allCases, id: \.self) { p in
                        Text(p.display).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityLabel("Persona preset")

                HStack(spacing: 8) {
                    Toggle(isOn: $domainAI) { Text("AI/CS") }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("AI and Computer Science domain")
                    Toggle(isOn: $domainBusiness) { Text("Business") }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Business domain")
                }
            }
            Divider()

            HStack {
                Button {
                    startTranslate()
                } label: {
                    if vm.isTranslating {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Translating…")
                    } else {
                        Text("Translate")
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isTranslating)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Translate button")

                Spacer()

                if let banner = vm.banner, !banner.isEmpty {
                    Button("Retry") {
                        rerunIfPossible()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Retry translation")
                }

                if !NetworkReachability.shared.isOnline {
                    Button("Try MT Cache") {
                        rerunIfPossible()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Try using cached MT")
                }

                Button("Save") { saveCurrentToTermbank() }
                    .disabled(vm.chosenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Clear") { inputText.removeAll() }
                    .disabled(inputText.isEmpty)
            }

            // Results area (Phase 8: bind VM outputs; basic visuals only)
            if !vm.chosenText.isEmpty || vm.isTranslating {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Primary chosen translation
                        if !vm.chosenText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(vm.chosenText)
                                    .font(.title3)
                                    .bold()
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(confidenceColor(vm.confidence))
                                        .frame(width: 8, height: 8)
                                    Text(String(format: "%.0f%%", vm.confidence * 100))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(.thinMaterial)
                            .cornerRadius(8)
                            .accessibilityLabel("Primary translation")
                            .accessibilityHint("Confidence score shown next to the translation")
                        }

                        // Explanation
                        if !vm.explanation.isEmpty {
                            Text(vm.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Divider()

                        // Alternatives (collapsed)
                        if !vm.alternatives.isEmpty {
                            DisclosureGroup("Alternatives") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(vm.alternatives, id: \.self) { alt in
                                        Text(alt)
                                            .font(.callout)
                                            .multilineTextAlignment(.leading)
                                            .padding(.vertical, 2)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .accessibilityLabel("Alternative translations")
                        }

                        // Examples
                        if !vm.examples.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Examples")
                                    .font(.subheadline)
                                    .bold()
                                ForEach(Array(vm.examples.enumerated()), id: \.offset) { _, ex in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.srcText)
                                            .font(.footnote)
                                        Text(ex.dstText)
                                            .font(.callout)
                                        Text(ex.provenance)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.08))
                                    .cornerRadius(6)
                                }
                            }
                            .accessibilityLabel("Example sentences")
                        }

                        // Term detail (saved senses/examples)
                        DisclosureGroup("Term detail") {
                            TermDetailView(lemma: inputText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()

            Text("Hotkey: \(HotkeyOption.current().displayLabel)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hotkey: \(HotkeyOption.current().accessibilityLabel)")

            Divider()

            DisclosureGroup("History (last 5)") {
                HistoryListView { text in
                    inputText = text
                    rerunIfPossible()
                }
                .frame(maxHeight: 100)
            }

            DisclosureGroup("Due Reviews") {
                ReviewsListView { termId, success in
                    do {
                        try srs.recordReview(for: termId, success: success)
                        BannerCenter.shared.show(message: success ? "Marked Done" : "Marked Again")
                    } catch {
                        BannerCenter.shared.show(message: "Review failed: \(error.localizedDescription)")
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(16)
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
        .onAppear(perform: prefillFromPasteboard)
        .onAppear(perform: loadRecentHistory)
        .onReceive(NotificationCenter.default.publisher(for: .menubarPopoverShouldFocusInput)) { _ in
            focusInput = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .menubarPopoverWillClose)) { _ in
            currentTask?.cancel()
            currentTask = nil
            isTranslating = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .menubarShowBanner)) { output in
            if let message = output.object as? String {
                BannerCenter.shared.show(message: message)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkReachabilityChanged)) { output in
            if let online = output.object as? Bool {
                if !online {
                    BannerCenter.shared.show(message: AppDomainError.offline.bannerMessage)
                } else {
                    BannerCenter.shared.show(message: "Back online")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menubarServicePayload)) { output in
            if let incoming = output.object as? String, inputText.isEmpty {
                inputText = incoming
                focusInput = true
            }
        }
        .onAppear {
            // Auto-focus on appear for keyboard-driven openings
            DispatchQueue.main.async { focusInput = true }
        }
        .onChange(of: vm.banner) { _, newValue in
            if let message = newValue, !message.isEmpty {
                BannerCenter.shared.show(message: message)
            }
        }
        .onChange(of: selectedPersona) { _, _ in rerunIfPossible() }
        .onChange(of: domainAI) { _, _ in rerunIfPossible() }
        .onChange(of: domainBusiness) { _, _ in rerunIfPossible() }
        .onExitCommand(perform: closePopover)
    }

    private func startTranslate() {
        let term = inputText
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        vm.start(
            term: term,
            src: nil,
            dst: "fa",
            context: nil,
            persona: selectedPersona.personaString,
            domainPriority: effectiveDomains()
        )
    }

    private func saveCurrentToTermbank() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let primary = SenseInput(
            canonical: vm.chosenText,
            variants: vm.alternatives.first,
            domain: domainAI ? "AI/CS" : (domainBusiness ? "Business" : nil),
            notes: nil,
            style: selectedPersona.personaString,
            source: "mt+llm",
            confidence: vm.confidence
        )
        do {
            let termId = try termbank.saveTerm(src: "en", dst: "fa", lemma: text, primarySense: primary, examples: [])
            try srs.recordReview(for: termId, success: true)
            BannerCenter.shared.show(message: "Saved to termbank")
        } catch {
            BannerCenter.shared.show(message: "Save failed: \(error.localizedDescription)")
        }
    }

    private func prefillFromPasteboard() {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Only prefill if user has not typed anything in the current session
            if inputText.isEmpty {
                inputText = str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func loadRecentHistory() {
        // Non-blocking small read; best-effort
        if let recent = try? InputHistoryDAO.recent(limit: 1), inputText.isEmpty, let first = recent.first {
            inputText = first
        }
    }

    private func closePopover() {
        NotificationCenter.default.post(name: .menubarPopoverRequestClose, object: nil)
    }

    private func rerunIfPossible() {
        let term = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        vm.cancel()
        startTranslate()
    }

    private func effectiveDomains() -> [String] {
        var list: [String] = []
        if domainAI { list.append("AI/CS") }
        if domainBusiness { list.append("Business") }
        if list.isEmpty { list = ["AI/CS", "Business"] }
        return list
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 0.8 { return .green }
        if value >= 0.6 { return .yellow }
        if value >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Phase 9 subviews
private struct HistoryListView: View {
    let onSelect: (String) -> Void
    var body: some View {
        if let items = try? InputHistoryDAO.recent(limit: 5), !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { text in
                    Button(action: { onSelect(text) }) {
                        Text(text)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            Text("No history yet").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ReviewsListView: View {
    let recordAction: (Int64, Bool) -> Void
    @State private var items: [ReviewItem] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text("No reviews due").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.termId) { item in
                    HStack {
                        Text(item.lemma)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Button("Again") { recordAction(item.termId, false) }
                            .controlSize(.mini)
                        Button("Done") { recordAction(item.termId, true) }
                            .controlSize(.mini)
                    }
                }
            }
        }
        .task { items = (try? loadDueReviewItems()) ?? [] }
    }

    private struct ReviewItem { let termId: Int64; let lemma: String }
    private func loadDueReviewItems() throws -> [ReviewItem] {
        let logs = try SRSService().dueNow(limit: 10)
        var seen = Set<Int64>()
        var items: [ReviewItem] = []
        for log in logs {
            if seen.contains(log.termId) { continue }
            seen.insert(log.termId)
            if let term = try TermDAO.fetchById(log.termId) {
                items.append(ReviewItem(termId: term.id, lemma: term.lemma))
            }
        }
        return items
    }
}

private struct TermDetailView: View {
    let lemma: String
    @State private var senses: [Sense] = []
    @State private var examples: [ExampleSentence] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if senses.isEmpty && examples.isEmpty {
                Text("No saved term yet").font(.caption).foregroundStyle(.secondary)
            } else {
                if !senses.isEmpty {
                    Text("Senses").font(.caption).foregroundStyle(.secondary)
                    ForEach(senses, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.canonical).font(.callout)
                            HStack(spacing: 6) {
                                if let d = s.domain { Text(d).font(.caption2).foregroundStyle(.secondary) }
                                if let st = s.style { Text(st).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                if !examples.isEmpty {
                    Text("Saved Examples").font(.caption).foregroundStyle(.secondary)
                    ForEach(examples, id: \.id) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.srcText).font(.footnote)
                            Text(e.dstText).font(.callout)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let term = try? TermDAO.fetchByLemma(lemma, limit: 1).first else { return }
        if let list = try? SenseDAO.fetchForTerm(term.id, limit: 10) { senses = list }
        if let list = try? ExampleDAO.fetchForTerm(term.id, limit: 10) { examples = list }
    }
}

// MARK: - Hotkey options and notifications
enum HotkeyOption: String, CaseIterable {
    case ctrlT
    case ctrlShiftT

    static let userDefaultsKey = "hotkey_option"

    static func current() -> HotkeyOption {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey), let opt = HotkeyOption(rawValue: raw) {
            return opt
        }
        return .ctrlT
    }

    var displayLabel: String {
        switch self {
        case .ctrlT: return "Ctrl+T"
        case .ctrlShiftT: return "Ctrl+Shift+T"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ctrlT: return "Control T"
        case .ctrlShiftT: return "Control Shift T"
        }
    }
}

extension Notification.Name {
    static let hotkeyPreferenceDidChange = Notification.Name("hotkey.preference.changed")
}

// MARK: - Persona presets for Phase 8 UI (adheres to Apple Human Interface Guidelines: clarity & consistency)
private enum PersonaPreset: String, CaseIterable {
    case engineerRead
    case businessWrite
    case casualLearn

    var display: String {
        switch self {
        case .engineerRead: return "Engineer·Read"
        case .businessWrite: return "Business·Write"
        case .casualLearn: return "Casual·Learn"
        }
    }

    var personaString: String {
        switch self {
        case .engineerRead: return "engineer_read"
        case .businessWrite: return "business_write"
        case .casualLearn: return "casual_learn"
        }
    }
}
