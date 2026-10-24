# CurrencyFlow

A professional macOS currency-converter app built with SwiftUI (Xcode 27, macOS 14+).

## Features

- **Conversion board** — every watched currency is a row. Click any row, type an amount,
  and all other rows convert instantly. Press **Return** to jump to the next row.
- **Base currency** — set from the top bar or Settings; used for defaults and statistics.
- **Full currency database** — 160+ ISO-4217 currencies with names, symbols and flags.
- **Saved Results sidebar** — save any conversion board with one click, review and
  delete entries, copy a summary.
- **Export** — saved conversions can be exported as **CSV** or **TXT**
  (sidebar buttons or Exchange menu).
- **Live rates** — free providers, no API key:
  1. ExchangeRate-API (open.er-api.com) — primary
  2. Currency-API via jsDelivr CDN — fallback 1
  3. Frankfurter (European Central Bank) — fallback 2
- **Auto-update** — rates refresh when the app opens and on a schedule
  (hourly / 6h / 12h / daily, configurable in Settings).
- **Offline cache** — the latest rates are cached in
  `~/Library/Application Support/CurrencyFlow/` so the board works instantly,
  even with no connection.
- **Status bar** — live connection state, last update, next scheduled update,
  currency counts, saved count and active provider.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘R | Refresh rates now |
| ⌘S | Save the current board to the sidebar |
| ⇧⌘Y | Copy the current board as text |

## Building

Open `CurrencyFlow.xcodeproj` in Xcode and press **⌘R**, or:

```sh
xcodebuild -project CurrencyFlow.xcodeproj -target CurrencyFlow -configuration Release build
```

The app is sandboxed with Outgoing Network (Client) enabled for the rate providers.
