import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ExchangeStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.records.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
        .navigationTitle("Saved Results")
        .navigationSubtitle("\(store.records.count)")
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Quick Export CSV") { store.exportCSV() }
                Button("Quick Export TXT") { store.exportTXT() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .fixedSize()
            .help("Export saved conversions")
            .disabled(store.records.isEmpty)

            Spacer()

            Button {
                store.clearRecords()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .help("Clear all saved conversions")
            .disabled(store.records.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: List

    private var recordList: some View {
        List(store.records) { record in
            recordRow(record)
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            if !store.records.isEmpty {
                HStack {
                    Spacer()
                    Text("Exported files keep full precision")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func recordRow(_ record: ConversionRecord) -> some View {
        // Anchor row first (like the reference app), then every other currency.
        let order = [record.anchorCode] + store.displayOrder().filter { $0 != record.anchorCode }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.date, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .trailing, spacing: 0) {
                ForEach(order, id: \.self) { code in
                    HStack(spacing: 7) {
                        Spacer(minLength: 0)
                        Text(valueString(in: record, for: code))
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(code == record.anchorCode ? Color.primary : Color.secondary)
                            .lineLimit(1)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 15)
                        Text(CurrencyData.flag(for: code))
                            .font(.system(size: 13))
                        Text(code)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2.5)
                    .contentShape(Rectangle())
                }
            }

            Text(rateNote(for: record))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Copy Full Board") {
                var text = ""
                for code in order {
                    text += "\(valueString(in: record, for: code)) \(code)"
                    text += code == order.last ? "" : " = "
                }
                ClipboardService.copy(text)
            }
            Button("Copy Summary") {
                ClipboardService.copy("\(ExchangeStore.plainString(record.anchorValue)) \(record.anchorCode) — \(store.recordSummary(record, limit: 12))")
            }
            Divider()
            Button("Delete", role: .destructive) {
                withAnimation {
                    store.deleteRecord(record)
                }
            }
        }
    }

    private func valueString(in record: ConversionRecord, for code: String) -> String {
        let value = code == record.anchorCode
            ? record.anchorValue
            : (record.items[code] ?? 0)
        return ExchangeStore.plainString(value)
    }

    /// Bottom note, e.g. "1 kuwaiti dinar = 0.31997 GBP".
    private func rateNote(for record: ConversionRecord) -> String {
        let target = store.displayOrder().first { $0 != record.anchorCode }
        guard let target,
              let value = record.items[target],
              record.anchorValue > 0 else { return "" }
        let rate = value / record.anchorValue
        let name = CurrencyData.name(for: record.anchorCode)
        return "1 \(name) = \(String(format: "%.5f", rate)) \(target)"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No saved results")
                .font(.headline)
            Text("Type an amount in any currency row, then press the Save button in the top bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
