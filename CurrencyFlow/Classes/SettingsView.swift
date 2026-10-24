import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ExchangeStore

    var body: some View {
        TabView {
            currenciesTab
                .tabItem {
                    Label("Currencies", systemImage: "list.bullet.rectangle")
                }
            updatesTab
                .tabItem {
                    Label("Updates", systemImage: "clock.arrow.circlepath")
                }
            displayTab
                .tabItem {
                    Label("Display", systemImage: "textformat.123")
                }
            dataTab
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .padding(12)
    }

    // MARK: Currencies tab

    private var currenciesTab: some View {
        CurrenciesSettingsSection()
            .environmentObject(store)
    }

    // MARK: Updates tab

    private var updatesTab: some View {
        Form {
            Section("Automatic Updates") {
                Picker("Update rates:", selection: $store.autoUpdateInterval) {
                    ForEach(UpdateInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Toggle("Update rates when the app opens", isOn: $store.refreshOnLaunch)
                HStack {
                    Text("Last update attempt:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let attempt = store.lastFetchAttempt {
                        Text(attempt.formatted(.dateTime.month().day().hour().minute().second()))
                    } else {
                        Text("Never")
                    }
                }
                .font(.callout)
            }

            Section("Provider") {
                HStack {
                    Text("Current source:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.providerName)
                        .monospacedDigit()
                }
                .font(.callout)
                Text("The app queries free public rate providers (no account or API key required) and falls back automatically if one is unreachable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Display tab

    private var displayTab: some View {
        Form {
            Section("Number Display") {
                Picker("Decimal places:", selection: $store.fractionDigits) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("6").tag(6)
                }
                Text("Rates are rounded for display only; exports and copies keep full precision.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Board Order") {
                Toggle("Sort rows alphabetically by name", isOn: $store.sortAlphabetical)
                HStack {
                    Text("Anchor row:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(CurrencyData.flag(for: store.anchorCode)) \(store.anchorCode)")
                        .font(.headline)
                    Button("Reset to base") {
                        store.resetAnchorToBase()
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Data tab

    private var dataTab: some View {
        Form {
            Section("Saved Results") {
                HStack {
                    Text("\(store.records.count) saved conversion(s)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export CSV…") { store.exportCSV() }
                        .disabled(store.records.isEmpty)
                    Button("Export TXT…") { store.exportTXT() }
                        .disabled(store.records.isEmpty)
                }
                .font(.callout)
                Button("Clear All Saved Results", role: .destructive) {
                    store.clearRecords()
                }
                .disabled(store.records.isEmpty)
            }

            Section("Rate Cache") {
                Text("Latest rates are cached on disk so the app works instantly on the next launch even without a network connection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Cache location:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("~/Library/Application Support/CurrencyFlow/")
                        .font(.caption)
                        .monospaced()
                        .textSelection(.enabled)
                }
                .font(.callout)
            }

            Section("About") {
                HStack {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.appVersion)
                        .monospacedDigit()
                }
                .font(.callout)
                Text("CurrencyFlow — professional exchange board for macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Currencies section (larger, own view)

private struct CurrenciesSettingsSection: View {
    @EnvironmentObject private var store: ExchangeStore
    @State private var search = ""

    private var allCurrencies: [CurrencyInfo] {
        CurrencyData.meta.sorted {
            CurrencyData.name(for: $0.code).localizedCaseInsensitiveCompare(CurrencyData.name(for: $1.code)) == .orderedAscending
        }
    }

    private var filtered: [CurrencyInfo] {
        guard !search.isEmpty else { return allCurrencies }
        return allCurrencies.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Base Currency")
                    .font(.headline)
                Spacer()
                PopOverBasePicker()
            }

            Divider()

            HStack {
                Text("Watched Currencies")
                    .font(.headline)
                Spacer()
                Button("Majors") { store.watchPopular() }
                Button("All") { store.watchAll() }
                Button("None") { store.unwatchAll() }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search currencies…", text: $search)
                    .textFieldStyle(.roundedBorder)
            }

            Text("\(store.selected.count) currencies watched — rows appear on the board in selection order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(filtered) { info in
                Button {
                    store.toggleWatch(info.code)
                } label: {
                    HStack(spacing: 8) {
                        Text(info.flag)
                            .font(.system(size: 18))
                        Text(info.name)
                            .font(.callout)
                        Text(info.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Image(systemName: store.selected.contains(info.code) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.selected.contains(info.code) ? Color.accentColor : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .padding(.top, 4)
    }
}

private struct PopOverBasePicker: View {
    @EnvironmentObject private var store: ExchangeStore
    @State private var pickerPresented = false

    var body: some View {
        Button {
            pickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(CurrencyData.flag(for: store.baseCurrency))
                    .font(.system(size: 16))
                Text(store.baseCurrency)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $pickerPresented, arrowEdge: .bottom) {
            CurrencyPickerPopover(
                selectedCode: store.baseCurrency,
                watchedCodes: store.selected
            ) { code in
                store.setBase(code)
                pickerPresented = false
            }
        }
    }
}
