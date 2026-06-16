# Printoo WhatsApp — Print Bot POS

[![Flutter](https://img.shields.io/badge/Flutter-3.12%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-339933?logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS-blue)](https://github.com/iziadehap/printoo_whatsapp)
[![License](https://img.shields.io/badge/License-ISC-green.svg)](https://opensource.org/licenses/ISC)

Desktop POS terminal for print shops. Connects **WhatsApp** customer chats to local printers through a keyboard-first Flutter UI and a headless Node.js backend.

---

## Table of contents

- [Why Printoo](#why-printoo)
- [Features](#features)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [API reference](#api-reference)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Workflow](#workflow)
- [Platform support](#platform-support)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

---

## Why Printoo

**Problem:** Customers send files via WhatsApp. The official desktop app is slow for retail — staff click through chats, download files manually, open viewers, and set printer options for every order.

**Solution:** Printoo pulls attachments into a print workspace, organizes them per customer, and lets staff set copies, duplex, and printer targets in seconds.

| Before | With Printoo |
|--------|--------------|
| Manual downloads per chat | One-click media fetch |
| Scattered files on disk | Auto-organized temp folders |
| Repeated printer setup | Global + per-file controls |
| Mouse-heavy workflow | Keyboard shortcuts |

---

## Features

- **WhatsApp integration** — QR login, chat search, fetch images/PDFs/Docs from recent messages
- **Smart search** — Debounced sidebar; type `*1`, `*2`, or `*99` to set day lookback (1d, 2d, 99d)
- **Media workspace** — Thumbnail grid with per-file and global copies, duplex, and page range
- **Batch printing** — Multi-file jobs with optional blank-page separators between customers
- **Printer shortcuts** — Map `Ctrl/Cmd + 1–9` to system printers (saved with Hive CE)
- **Live status** — Connection indicator and in-app QR when disconnected

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter Desktop (printoo_whatsapp)                         │
│  Riverpod · Dio · Hive CE · window_manager                  │
│                                                             │
│  Sidebar ── Main Panel ── TopBar / BottomBar                │
│  (search,   (thumbnails,   (status, print,                 │
│   QR)       controls)       settings)                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP  localhost:3000
┌──────────────────────────▼──────────────────────────────────┐
│  Node.js API (v6.0.1_server / serverv2.js)                  │
│  Express · whatsapp-web.js · pdf-parse · Ghostscript        │
│                                                             │
│  WhatsApp Web  →  Download media  →  OS print spooler       │
└─────────────────────────────────────────────────────────────┘
```

> **Note:** The Flutter app uses `/printoo/*` routes. Run **`serverv2.js`**, not `server.js` (`/api/*`).

---

## Project structure

### Flutter client

| Path | Role |
|------|------|
| `lib/main.dart` | Entry point, Hive init, window sizing |
| `lib/home/presentation/home_shell.dart` | Layout and global keyboard shortcuts |
| `lib/home/presentation/widgets/` | `top_bar`, `sidebar`, `main_panel`, `bottom_bar` |
| `lib/home/presentation/providers/app_providers.dart` | Riverpod state (status, printers, media, search) |
| `lib/home/data/repositories/app_repository_impl.dart` | API + local storage |
| `lib/home/data/datasources/api_client.dart` | Dio client → `http://localhost:3000` |
| `lib/setting/setting_screen.dart` | Printer shortcut mapping |
| `lib/core/theme/app_theme.dart` | Dark navy-slate theme |

### Node.js server

| Path | Role |
|------|------|
| `v6.0.1_server/serverv2.js` | **Production API** (`/printoo/*`) |
| `v6.0.1_server/server.js` | Legacy API (`/api/*`) |
| `v6.0.1_server/config.json` | Pricing, limits, separator, beep |
| `v6.0.1_server/temp/` | Downloaded customer files (runtime) |
| `v6.0.1_server/.wwebjs_auth/` | WhatsApp session — **do not commit** |

---

## Tech stack

| Layer | Stack |
|-------|-------|
| UI | Flutter Desktop, Riverpod 2, window_manager, pdfx, qr_flutter |
| Networking | Dio |
| Local storage | Hive CE |
| Backend | Node.js, Express, whatsapp-web.js, Puppeteer (Chrome) |
| Printing | OS spooler, Ghostscript (Windows) |

---

## Getting started

### Prerequisites

**Flutter**

- Flutter SDK (Dart `^3.12.0`)
- **Windows:** Visual Studio — Desktop development with C++
- **macOS:** Xcode Command Line Tools

**Backend**

- Node.js 18+ and npm
- Google Chrome (Puppeteer)
- Ghostscript on Windows — `C:\Program Files\gs\gs10.03.1\bin\gswin64c.exe`
- At least one OS printer installed

### Install and run

**1. Clone**

```bash
git clone https://github.com/iziadehap/printoo_whatsapp.git
cd printoo_whatsapp
```

**2. Start the server**

```bash
cd v6.0.1_server
npm install
node serverv2.js
```

On first launch, scan the QR code in the terminal (or Flutter sidebar): WhatsApp → **Linked Devices** → **Link a device**. Wait for `Connected to WhatsApp Web`.

**3. Start the Flutter app**

```bash
cd ..
flutter pub get
flutter run -d windows   # or: -d macos
```

Default window: **1200×700** (minimum **1000×700**).

---

## Configuration

### Server — `v6.0.1_server/config.json`

```json
{
  "documentPagePrice": 0.5,
  "imagePagePrice": 0.75,
  "blankPageSeparator": true,
  "fetchMessageLimit": 100,
  "beepNotification": true
}
```

| Key | Description |
|-----|-------------|
| `documentPagePrice` | Price per document page |
| `imagePagePrice` | Price per image page |
| `blankPageSeparator` | Blank page between separate print jobs |
| `fetchMessageLimit` | Max messages scanned per chat fetch |
| `beepNotification` | Terminal beep after successful print |

### API base URL

Set in `lib/home/data/datasources/api_client.dart` (default: `http://localhost:3000`).

---

## API reference

Base path: `/printoo` (via `serverv2.js`)

| Method | Endpoint | Body / query | Description |
|--------|----------|--------------|-------------|
| `GET` | `/printoo/status` | — | Connection state + QR code |
| `GET` | `/printoo/printers` | — | System printer list |
| `GET` | `/printoo/search` | `?q=<query>` | Search WhatsApp chats |
| `POST` | `/printoo/fetch-media` | `{ chatId, daysLookback }` | Download chat media |
| `POST` | `/printoo/print` | `{ printer, files, blankPageSeparator }` | Send print jobs |
| `POST` | `/printoo/clear` | — | Clear temp cache |
| `POST` | `/printoo/logout` | — | Destroy session and reset |

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl/Cmd + P` | Print selected files |
| `Ctrl/Cmd + A` | Toggle select all files |
| `Ctrl/Cmd + 1` … `9` | Switch to mapped printer |

Configure printer numbers in **Settings**.

---

## Workflow

1. Start `serverv2.js` and confirm WhatsApp is connected.
2. Launch the Flutter app.
3. Search for a customer in the sidebar.
4. Select a result — media loads in the main panel.
5. Adjust selection, copies, and duplex.
6. Choose a printer and press **Print** or `Ctrl/Cmd + P`.
7. Use **Open Folder** to view downloaded files on disk.

---

## Platform support

| Platform | Flutter UI | Full print pipeline |
|----------|------------|---------------------|
| Windows | Yes | Yes (primary target) |
| macOS | Yes | Limited (server paths are Windows-oriented) |
| Linux | Yes | Not supported out of the box |

---

## Security

- **Session tokens** live in `v6.0.1_server/.wwebjs_auth/` — never commit or share this folder.
- **Customer files** are stored temporarily under `v6.0.1_server/temp/`.
- The API has **no auth** and targets localhost. Do not expose it publicly without TLS and authentication.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| App shows "Disconnected" | Run `serverv2.js`; check terminal for errors or QR |
| API 404 | Use `serverv2.js`, not `server.js` |
| No printers | Install a printer in the OS; restart the server |
| WhatsApp won't connect | Delete `.wwebjs_auth/`, restart, scan a new QR |
| Print fails (Windows) | Install Ghostscript; verify default printer |

---

## Development

```bash
# Hive code generation
dart run build_runner build --delete-conflicting-outputs

# Analyze & test
flutter analyze
flutter test
```

---

## License

ISC (backend). Add a license for the Flutter app before public release.
 
**Versions:** Flutter UI v6.0.0 · Backend v6.1.0
