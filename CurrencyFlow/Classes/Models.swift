import Foundation
import SwiftUI

// MARK: - Currency metadata

struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String
    let flag: String

    var id: String { code }
}

// MARK: - Update scheduling

enum UpdateInterval: Int, CaseIterable, Identifiable {
    case never = 0
    case hourly = 3600
    case every6Hours = 21600
    case every12Hours = 43200
    case daily = 86400

    var id: Int { rawValue }

    var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .never: return "Manually"
        case .hourly: return "Every hour"
        case .every6Hours: return "Every 6 hours"
        case .every12Hours: return "Every 12 hours"
        case .daily: return "Every 24 hours"
        }
    }
}

// MARK: - Connection state

enum ConnectionStatus {
    case loading
    case online
    case offline

    var dotColor: Color {
        switch self {
        case .loading: return .orange
        case .online: return .green
        case .offline: return .red
        }
    }

    var label: String {
        switch self {
        case .loading: return "Updating…"
        case .online: return "Live rates"
        case .offline: return "Offline (cached rates)"
        }
    }
}

// MARK: - Saved conversion record

struct ConversionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    /// Currency the user typed the amount in.
    let anchorCode: String
    /// Amount typed by the user.
    let anchorValue: Double
    /// Every displayed currency and its converted value.
    let items: [String: Double]
}

// MARK: - Persisted rate snapshot

struct RateSnapshot: Codable {
    var rates: [String: Double]
    var updated: Date
    var provider: String
}
