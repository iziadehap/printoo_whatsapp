# WhatsApp Retail Terminal Printing API

A headless REST API server for printing WhatsApp media files (images and documents) through a network printer system.

## Features

- ✅ REST API endpoints for all printing operations
- ✅ Automatic WhatsApp session management with QR code authentication
- ✅ Support for multiple printers and print settings
- ✅ Document page counting (PDF via Ghostscript)
- ✅ Blank page separation between documents
- ✅ Configurable pricing and settings
- ✅ Session recovery and watchdog mechanisms

## Installation

1. Install Node.js (v16 or higher)
2. Install Ghostscript from: https://ghostscript.com/releases/gsdnld.html
3. Clone the repository
4. Install dependencies:

```bash
npm install

npm install express cors whatsapp-web.js qrcode-terminal chalk fs-extra pdf-parse pdfkit axios
