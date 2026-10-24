import Foundation
import SwiftUI

/// Central app state: rates, settings, live conversion and the saved-conversions tape.
@MainActor
final class ExchangeStore: ObservableObject {

    // MARK: - Published state

    @Published var rates: [String: Double] = [:]
    @Published var lastUpdated: Date?
    @Published var lastFetchAttempt: Date?
    @Published var providerName: String = "—"
    @Published var status: ConnectionStatus = .loading
    @Published var statusMessage: String = "Starting up…"
    @Published var isRefreshing = false

    @Published var records: [ConversionRecord] = []

    @Published var baseCurrency: String {
        didSet { persistSettings() }
    }
    /// Watched currencies, in display order.
    @Published var selected: [String] {
        didSet { persistSettings() }
    }
    @Published var sortAlphabetical: Bool {
        didSet { persistSettings() }
    }
    @Published var autoUpdateInterval: UpdateInterval {
        didSet {
            persistSettings()
            scheduleTimer()
        }
    }
    @Published var refreshOnLaunch: Bool {
        didSet { persistSettings() }
    }
    @Published var fractionDigits: Int {
        didSet { persistSettings() }
    }

    /// The currency row the user is currently typing in.
    @Published var anchorCode: String
    /// Text of the amount being typed in the anchor row.
    @Published var anchorText: String

    // MARK: - Internal

    private var ready = false
    private var timer: Timer?
    private var didStart = false

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        baseCurrency = d.string(forKey: "cf.base") ?? "USD"
        selected = Self.decodeArray(d.string(forKey: "cf.selected"))
            ?? ["KWD", "GBP", "EUR", "USD", "TRY"]
        sortAlphabetical = d.bool(forKey: "cf.sortAlphabetical")
        autoUpdateInterval = UpdateInterval(rawValue: d.integer(forKey: "cf.interval")) ?? .every6Hours
        refreshOnLaunch = d.object(forKey: "cf.refreshOnLaunch") == nil
            ? true
            : d.bool(forKey: "cf.refreshOnLaunch")
        fractionDigits = d.object(forKey: "cf.digits") == nil
            ? 4
            : d.integer(forKey: "cf.digits")
        anchorCode = d.string(forKey: "cf.anchorCode") ?? (d.string(forKey: "cf.base") ?? "USD")
        anchorText = "1"

        // Load persisted records.
        if let data = try? Data(contentsOf: RatesService.recordsURL),
           let saved = try? JSONDecoder().decode([ConversionRecord].self, from: data) {
            records = saved
        }

        ready = true
    }

    /// Called once from the main window's onAppear.
    func start() {
        guard !didStart else { return }
        didStart = true

        // Instant-load cached rates so the board is populated before the network answers.
        if rates.isEmpty, let cached = RatesService.loadCache() {
            applySnapshot(cached, fromCache: true)
        }
        if refreshOnLaunch {
            Task { await refresh() }
        }
        scheduleTimer()
    }

    func sleepTimer() {
        // Keep running while window opens/closes repeatedly; nothing to pause for now.
    }

    // MARK: - Persistence

    private func persistSettings() {
        guard ready else { return }
        let d = UserDefaults.standard
        d.set(baseCurrency, forKey: "cf.base")
        let data = try? JSONEncoder().encode(selected)
        d.set(String(data: data ?? Data(), encoding: .utf8) ?? "", forKey: "cf.selected")
        d.set(sortAlphabetical, forKey: "cf.sortAlphabetical")
        d.set(autoUpdateInterval.rawValue, forKey: "cf.interval")
        d.set(refreshOnLaunch, forKey: "cf.refreshOnLaunch")
        d.set(fractionDigits, forKey: "cf.digits")
        d.set(anchorCode, forKey: "cf.anchorCode")
    }

    private static func decodeArray(_ json: String?) -> [String]? {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode([String].self, from: data),
              !value.isEmpty else { return nil }
        return value
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: RatesService.recordsURL, options: .atomic)
    }

    // MARK: - Rates lifecycle

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastFetchAttempt = Date()
        statusMessage = "Contacting rate providers…"
        status = .loading
        defer { isRefreshing = false }

        do {
            let snapshot = try await RatesService.fetch()
            applySnapshot(snapshot, fromCache: false)
        } catch {
            status = .offline
            if let cached = RatesService.loadCache() {
                applySnapshot(cached, fromCache: true)
                statusMessage = "Couldn't reach providers — showing cached rates. (\(error.localizedDescription))"
            } else {
                statusMessage = "Couldn't reach providers and no cache exists yet. (\(error.localizedDescription))"
            }
        }
    }

    private func applySnapshot(_ snapshot: RateSnapshot, fromCache: Bool) {
        rates = snapshot.rates
        if !fromCache { lastUpdated = snapshot.updated }
        providerName = snapshot.provider
        if !fromCache { status = .online }
        statusMessage = fromCache
            ? "Cached rates loaded — updating…"
            : "Rates up to date."
        // Reflow the board: other rows recompute on render from the new rates.
    }

    // MARK: - Auto update timer

    func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard let seconds = autoUpdateInterval.seconds else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        _ = seconds
    }

    private func tick() {
        guard let seconds = autoUpdateInterval.seconds,
              let last = lastFetchAttempt,
              Date().timeIntervalSince(last) >= seconds else { return }
        Task { await refresh() }
    }

    var nextScheduledUpdate: Date? {
        guard let seconds = autoUpdateInterval.seconds else { return nil }
        let reference = lastFetchAttempt ?? Date()
        return reference.addingTimeInterval(seconds)
    }

    // MARK: - Conversion core

    func rate(for code: String) -> Double? { rates[code] }

    /// Units of `code` per one unit of the anchor currency.
    func crossRate(for code: String) -> Double? {
        guard let from = rates[anchorCode], let to = rates[code] else { return nil }
        return to / from
    }

    func parseAnchor() -> Double? {
        Self.parseNumber(anchorText)
    }

    static func parseNumber(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        // Accept Arabic-Indic digits just in case.
        let arabic = "٠١٢٣٤٥٦٧٨٩"
        let eastern = "۰۱۲۳۴۵۶۷۸۹"
        var mapped = ""
        for ch in text {
            if let i = arabic.firstIndex(of: ch) {
                let offset = arabic.distance(from: arabic.startIndex, to: i)
                mapped.append(String(offset))
            } else if let i = eastern.firstIndex(of: ch) {
                let offset = eastern.distance(from: eastern.startIndex, to: i)
                mapped.append(String(offset))
            } else {
                mapped.append(ch)
            }
        }
        text = mapped
        // Strip separators, keep digits and the decimal point.
        let allowed = Set("0123456789.")
        text = text.filter { allowed.contains($0) }
        // Multiple dots: keep only the first.
        if text.filter({ $0 == "." }).count > 1 {
            var seen = false
            text = text.reduce(into: "") { out, ch in
                if ch == "." {
                    if !seen { seen = true; out.append(ch) }
                } else {
                    out.append(ch)
                }
            }
        }
        return Double(text)
    }

    func convertedValue(for code: String) -> Double? {
        guard let amount = parseAnchor(), let rate = crossRate(for: code) else { return nil }
        return amount * rate
    }

    // MARK: - Formatting

    var displayFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = fractionDigits
        return f
    }

    static let plainFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        return f
    }()

    /// Clean, locale-stable text for a TextField against rounding drift.
    static func plainString(_ value: Double) -> String {
        Self.plainFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func formattedValue(for code: String) -> String {
        guard let value = convertedValue(for: code) else {
            return parseAnchor() == nil ? "" : "—"
        }
        return displayFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func formattedRateLine(for code: String) -> String {
        guard let rate = crossRate(for: code) else { return "" }
        let digits = max(2, min(fractionDigits, 6))
        return String(format: "1 %@ = %.\(digits)f %@", anchorCode, rate, code)
    }

    // MARK: - Anchor (editable row) management

    /// Clicking a row makes it the anchor; its converted value moves with it.
    func selectAnchor(_ code: String) {
        guard code != anchorCode else { return }
        if let value = convertedValue(for: code), value.isFinite {
            anchorText = Self.plainString(value)
        } else {
            anchorText = ""
        }
        anchorCode = code
        persistSettings()
    }

    func resetAnchorToBase() {
        anchorCode = baseCurrency
        anchorText = "1"
        persistSettings()
    }

    /// Return moves to the next watched row.
    func advanceAnchor() {
        let order = displayOrder()
        guard order.count > 1,
              let index = order.firstIndex(of: anchorCode) else { return }
        let next = order[(index + 1) % order.count]
        selectAnchor(next)
    }

    // MARK: - Settings mutations

    func setBase(_ code: String) {
        guard CurrencyData.byCode[code] != nil else { return }
        baseCurrency = code
        persistSettings()
    }

    func toggleWatch(_ code: String) {
        if let index = selected.firstIndex(of: code) {
            selected.remove(at: index)
        } else {
            selected.append(code)
        }
        persistSettings()
    }

    func watchAll() {
        selected = CurrencyData.meta.map(\.code)
        persistSettings()
    }

    func unwatchAll() {
        selected = selected.filter { $0 == anchorCode }
        persistSettings()
    }

    func watchPopular() {
        var list = CurrencyData.meta.map(\.code).filter { CurrencyData.popularCodes.contains($0) }
        for code in selected where !list.contains(code) {
            list.append(code)
        }
        selected = list
        persistSettings()
    }

    /// Display order of the watched currencies.
    func displayOrder() -> [String] {
        if sortAlphabetical {
            return selected.sorted {
                CurrencyData.name(for: $0).localizedCaseInsensitiveCompare(CurrencyData.name(for: $1)) == .orderedAscending
            }
        }
        return selected
    }

    /// Which currencies actually have live rates, sorted alphabetically for pickers.
    var availableCurrencies: [CurrencyInfo] {
        CurrencyData.meta.sorted {
            CurrencyData.name(for: $0.code).localizedCaseInsensitiveCompare(CurrencyData.name(for: $1.code)) == .orderedAscending
        }
    }

    // MARK: - Saved tape

    func saveBoard() {
        guard let amount = parseAnchor(), amount != 0 else {
            statusMessage = "Nothing to save — type an amount first."
            return
        }
        var items: [String: Double] = [:]
        for code in selected {
            guard let value = convertedValue(for: code), value.isFinite else { continue }
            items[code] = value
        }
        guard !items.isEmpty else {
            statusMessage = "Nothing to save — no currencies watched."
            return
        }
        let record = ConversionRecord(
            id: UUID(),
            date: Date(),
            anchorCode: anchorCode,
            anchorValue: amount,
            items: items
        )
        records.insert(record, at: 0)
        persistRecords()
        statusMessage = "✓ Saved to Results — \(ExchangeStore.plainString(amount)) \(anchorCode)"
    }

    func deleteRecord(_ record: ConversionRecord) {
        records.removeAll { $0.id == record.id }
        persistRecords()
    }

    func clearRecords() {
        records.removeAll()
        persistRecords()
    }

    func recordSummary(_ record: ConversionRecord, limit: Int = 3) -> String {
        let order = displayOrder().filter { $0 != record.anchorCode }
        var parts: [String] = []
        for code in order {
            guard let value = record.items[code] else { continue }
            parts.append("\(Self.plainString(value)) \(code)")
            if parts.count == limit { break }
        }
        let remaining = order.count - min(limit, order.count)
        if remaining > 0 {
            parts.append("+\(remaining) more")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Export

    func exportCSV() {
        let csv = Self.csvString(from: records, order: displayOrder())
        ExportService.save(text: csv, defaultName: "CurrencyFlow Export", extension: "csv")
    }

    func exportTXT() {
        let txt = Self.txtString(from: records, order: displayOrder())
        ExportService.save(text: txt, defaultName: "CurrencyFlow Export", extension: "txt")
    }

    static func csvString(from records: [ConversionRecord], order: [String]) -> String {
        var lines = ["Date,Anchor Code,Anchor Value,Target Currency,Rate (per 1 anchor),Value"]
        let iso = ISO8601DateFormatter()
        for record in records {
            for code in order where code != record.anchorCode {
                guard let value = record.items[code] else { continue }
                let rate = record.anchorValue > 0 ? value / record.anchorValue : 0
                let anchorVal = plainString(record.anchorValue)
                let valueStr = plainString(value)
                let rateStr = String(format: "%.8f", rate)
                lines.append("\(iso.string(from: record.date)),\(record.anchorCode),\(anchorVal),\(code),\(rateStr),\(valueStr)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func txtString(from records: [ConversionRecord], order: [String]) -> String {
        var out = "CurrencyFlow — Saved Conversions\n\(Date())\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        for record in records {
            out += "— \(df.string(from: record.date)) —\n"
            out += "  \(plainString(record.anchorValue)) \(record.anchorCode)\n"
            for code in order where code != record.anchorCode {
                guard let value = record.items[code] else { continue }
                out += "     = \(plainString(value)) \(code)\n"
            }
            out += "\n"
        }
        return out
    }
}
