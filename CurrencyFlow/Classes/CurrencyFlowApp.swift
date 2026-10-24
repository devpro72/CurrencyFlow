import SwiftUI

// MARK: - Focused value plumbing for menu commands

private struct ExchangeStoreKey: FocusedValueKey {
    typealias Value = ExchangeStore
}

extension FocusedValues {
    var exchangeStore: ExchangeStore? {
        get { self[ExchangeStoreKey.self] }
        set { self[ExchangeStoreKey.self] = newValue }
    }
}

// MARK: - App

@main
struct CurrencyFlowApp: App {
    @StateObject private var store = ExchangeStore()
    @FocusedValue(\.exchangeStore) private var focusedStore: ExchangeStore?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.automatic)
        .commands {
            CommandMenu("Exchange") {
                Button("Refresh Rates") {
                    Task { await focusedStore?.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(focusedStore == nil)

                Divider()

                Button("Save Current Board") {
                    focusedStore?.saveBoard()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(focusedStore == nil)

                Button("Copy Current Board") {
                    focusedStore?.copyBoard()
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(focusedStore == nil)

                Divider()

                Button("Export Saved as CSV…") {
                    focusedStore?.exportCSV()
                }
                .disabled(focusedStore == nil || focusedStore?.records.isEmpty == true)

                Button("Export Saved as TXT…") {
                    focusedStore?.exportTXT()
                }
                .disabled(focusedStore == nil || focusedStore?.records.isEmpty == true)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 560, height: 480)
        }
    }
}
