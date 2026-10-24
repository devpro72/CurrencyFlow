import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export via NSSavePanel

enum ExportService {

    /// Shows a save panel and writes the text to the chosen destination.
    static func save(text: String, defaultName: String, `extension`: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        let type = UTType(filenameExtension: `extension`) ?? UTType.plainText
        panel.allowedContentTypes = [type]
        panel.message = "Export the saved conversions."

        let result = panel.runModal()
        guard result == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSPasteboard.general.clearContents()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

// MARK: - Copy helper

enum ClipboardService {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Base currency picker (popover with search)

struct CurrencyPickerPopover: View {
    var selectedCode: String?
    var watchedCodes: [String] = []
    var onSelect: (String) -> Void

    @State private var search = ""
    @State private var listOnlyWatched = false

    private var currencies: [CurrencyInfo] {
        CurrencyData.meta.sorted {
            CurrencyData.name(for: $0.code).localizedCaseInsensitiveCompare(CurrencyData.name(for: $1.code)) == .orderedAscending
        }
        .filtered(by: search, watched: listOnlyWatched, watchedCodes: watchedCodes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search currency or code…", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            Toggle("Show watched currencies only", isOn: $listOnlyWatched)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            Divider()

            List(currencies) { info in
                Button {
                    onSelect(info.code)
                } label: {
                    HStack(spacing: 8) {
                        Text(info.flag)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.name)
                                .font(.callout)
                            Text(info.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        if selectedCode == info.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .frame(width: 360, height: 460)
    }
}

extension Array where Element == CurrencyInfo {
    func filtered(by search: String, watched: Bool, watchedCodes: [String]) -> [CurrencyInfo] {
        var list = self
        if watched && !watchedCodes.isEmpty {
            let set = Set(watchedCodes)
            list = list.filter { set.contains($0.code) }
        }
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.code.localizedCaseInsensitiveContains(search)
            }
        }
        return list
    }
}

// MARK: - Window accessor (to scope the key monitor to this window)

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if window != nsView.window {
                window = nsView.window
            }
        }
    }
}

// MARK: - Board summary builder (for copy actions)

extension ExchangeStore {
    /// Plain-text board summary, e.g. `300 KWD = 1,000 GBP = 848.74 EUR …`
    func boardSummary(from anchorValue: Double, anchor code: String, items: [String: Double], order: [String]) -> String {
        var text = "\(ExchangeStore.plainString(anchorValue)) \(code)"
        for target in order where target != code {
            guard let value = items[target] else { continue }
            text += " = \(ExchangeStore.plainString(value)) \(target)"
        }
        return text
    }

    func copyBoard() {
        guard let amount = parseAnchor() else { return }
        var items: [String: Double] = [:]
        for target in selected {
            guard let value = convertedValue(for: target), value.isFinite else { continue }
            items[target] = value
        }
        let summary = boardSummary(
            from: amount,
            anchor: anchorCode,
            items: items,
            order: displayOrder()
        )
        ClipboardService.copy(summary)
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
