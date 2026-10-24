import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ExchangeStore
    @Environment(\.openSettings) private var openSettings

    @FocusState private var focusedAnchor: String?
    @State private var basePickerPresented = false
    @State private var mainWindow: NSWindow?
    @State private var keyMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                board
                Divider()
                StatusBarView()
            }
            .navigationTitle("CurrencyFlow")
            .navigationSubtitle("Live conversion board")
        }
        .focusedSceneValue(\.exchangeStore, store)
        .background(WindowAccessor(window: $mainWindow))
        .onChange(of: store.anchorCode) { _, newCode in
            DispatchQueue.main.async {
                focusedAnchor = newCode
            }
        }
        .onAppear {
            store.start()
            focusedAnchor = store.anchorCode
            installKeyMonitor()
        }
        .onDisappear {
            uninstallKeyMonitor()
        }
    }

    // MARK: Enter / Tab → save board to the Results sidebar

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only respond in this window while an amount field is focused.
            guard event.window === mainWindow,
                  event.window === NSApp.keyWindow,
                  focusedAnchor != nil else { return event }

            switch event.keyCode {
            case 36, 76, 48: // Return, keypad Enter, Tab
                store.saveBoard()
                return nil
            default:
                return event
            }
        }
    }

    private func uninstallKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Set Base Currency…") {
                    basePickerPresented = true
                }
                Divider()
                ForEach(store.selected, id: \.self) { code in
                    Button("\(CurrencyData.flag(for: code))  \(code)") {
                        store.setBase(code)
                    }
                    .disabled(code == store.baseCurrency)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(CurrencyData.flag(for: store.baseCurrency))
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Base · \(store.baseCurrency)")
                            .font(.headline)
                        Text(CurrencyData.name(for: store.baseCurrency))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .popover(isPresented: $basePickerPresented, arrowEdge: .bottom) {
                CurrencyPickerPopover(
                    selectedCode: store.baseCurrency,
                    watchedCodes: store.selected
                ) { code in
                    store.setBase(code)
                    basePickerPresented = false
                }
            }

            Spacer()

            Button {
                store.copyBoard()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy the whole board as text (⇧⌘Y)")
            .disabled(store.parseAnchor() == nil)

            Button {
                store.saveBoard()
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .help("Save this conversion to the sidebar (⌘S)")
            .disabled(store.parseAnchor() == nil)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 6)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Update rates now (⌘R)")
            }

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Board

    @ViewBuilder
    private var board: some View {
        if store.rates.isEmpty && store.status == .offline {
            emptyState(
                icon: "wifi.slash",
                titlex: "No rates available",
                message: store.statusMessage,
                retry: true
            )
        } else if store.rates.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.displayOrder(), id: \.self) { code in
                        row(for: code)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func emptyState(icon: String, titlex: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(titlex)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if retry {
                Button("Try Again") {
                    Task { await store.refresh() }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Row

    private func row(for code: String) -> some View {
        let active = code == store.anchorCode
        let anchorAmount = store.parseAnchor()

        return HStack(spacing: 14) {
            Text(CurrencyData.flag(for: code))
                .font(.system(size: 30))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(code)
                        .font(.headline)
                    Text(CurrencyData.symbol(for: code))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Text(CurrencyData.name(for: code))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                if active {
                    TextField("0", text: $store.anchorText)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .textFieldStyle(.plain)
                        .focused($focusedAnchor, equals: code)
                        .frame(minWidth: 220, maxWidth: 340, alignment: .trailing)
                } else {
                    Text(store.formattedValue(for: code))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(anchorAmount == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                Text(active ? "Press Return or Tab to add to Saved Results" : store.formattedRateLine(for: code))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(active ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !active {
                store.selectAnchor(code)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: store.anchorCode)
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @EnvironmentObject private var store: ExchangeStore

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle()
                    .fill(store.status.dotColor)
                    .frame(width: 8, height: 8)
                Text(store.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            dividerDot

            Text(updatedText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            dividerDot

            Text(nextUpdateText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            dividerDot

            Text("\(store.displayOrder().count) of \(store.rates.count) currencies")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            dividerDot

            Text("\(store.records.count) saved")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Text(store.providerName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            dividerDot

            Text("v\(store.appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var dividerDot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 3, height: 3)
    }

    private var updatedText: String {
        guard let updated = store.lastUpdated else { return "Never updated" }
        return "Updated " + updated.formatted(.relative(presentation: .named))
    }

    private var nextUpdateText: String {
        guard let next = store.nextScheduledUpdate else { return "Auto-update: manual" }
        return "Next auto-update " + next.formatted(.relative(presentation: .named))
    }
}
