'use strict';

const express = require('express');
const cors = require('cors');
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const path = require('path');
const fs = require('fs-extra');
const { exec } = require('child_process');
const { PDFParse } = require('pdf-parse');
const PDFDocument = require('pdfkit');

// Fix for chalk - import properly
let chalk;
try {
  chalk = require('chalk');
} catch (e) {
  // Fallback if chalk fails
  chalk = {
    cyan: (text) => text,
    green: (text) => text,
    yellow: (text) => text,
    red: (text) => text,
    white: (text) => text,
    gray: (text) => text,
    bold: {
      cyan: (text) => text,
      green: (text) => text,
      yellow: (text) => text,
      red: (text) => text,
      white: (text) => text
    }
  };
}

const app = express();
const PORT = process.env.PORT || 3000;

// ─────────────────────────────────────────────────────────────────────────────
// Constants & Paths
// ─────────────────────────────────────────────────────────────────────────────

const TEMP_DIR = path.join(__dirname, 'temp');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const AUTH_DIR = path.join(__dirname, '.wwebjs_auth');
const WEB_CACHE_DIR = path.join(__dirname, '.wwebjs_cache');
const CHROME_PATH = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const GS_DEFAULT_PATH = 'C:\\Program Files\\gs\\gs10.03.1\\bin\\gswin64c.exe';

let config = {};
let chatCache = [];
let printerCache = [];
let globalClientReference = null;
let isRecoveringSession = false;
let clientIsReady = false;
let sessionRecoveryAttempts = 0;
let readyWatchdog = null;
let syncStatePoll = null;
let syncStatusInterval = null;
let authenticatedAt = 0;
let activeWhatsAppClient = null;
let currentOrderDir = null;
let currentOrderFolderKey = null;
let currentQrCode = null;

const MAX_SESSION_RECOVERY_ATTEMPTS = 3;
const READY_TIMEOUT_MS = 30000;
const SYNC_STATE_POLL_MS = 3000;

const IMAGE_EXTS = new Set(['jpg', 'jpeg', 'png']);
const DOC_EXTS = new Set(['pdf', 'doc', 'docx']);
const ALL_EXTS = new Set([...IMAGE_EXTS, ...DOC_EXTS]);

const MIME_MAP = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/pdf': 'pdf',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
};

const DEFAULT_CONFIG = {
  documentPagePrice: 0.50,
  imagePagePrice: 0.75,
  blankPageSeparator: true,
  fetchMessageLimit: 100,
  beepNotification: true
};

const IMAGE_PRINT_GAP_MS = 600;
const MIN_SPOOLER_WAIT_MS = 4000;
const MS_PER_IMAGE_PRINT = 1500;
const MS_PER_DOC_JOB = 3000;

const printLog = {
  info: (msg) => console.log(msg),
  success: (msg) => console.log(msg),
  warn: (msg) => console.log(msg),
  error: (msg) => console.log(msg),
  raw: (msg) => console.log(msg)
};

// ─────────────────────────────────────────────────────────────────────────────
// Localization
// ─────────────────────────────────────────────────────────────────────────────

const i18n = {
  sys_loaded: "[✅] Configuration loaded successfully.",
  sys_created_default: "[ℹ️] Created default config.json file.",
  sys_save_failed: "[❌] Failed to save configuration:",
  sys_cache_built: "[✅] Cached {count} individual chats successfully.",
  sys_cache_building: "Building chat cache & indexing system printers concurrently...",
  sys_auth_success: "Session authenticated successfully.",
  sys_syncing: "[ℹ️] Syncing with WhatsApp — please wait...",
  sys_sync_still: "[ℹ️] Still syncing... ({seconds}s). If this takes too long, a new QR code will appear.",
  sys_loading: "[ℹ️] Loading WhatsApp: {percent}% — {message}",
  sys_loading_done: "[ℹ️] WhatsApp loaded — finishing setup...",
  sys_ready_timeout: "[⚠️] WhatsApp did not finish loading in time (stale session after phone logout).",
  sys_auth_failed: "Authentication failed:",
  sys_disconnected: "WhatsApp disconnected:",
  sys_session_cleared: "[⚠️] WhatsApp session is no longer valid ({reason}). Clearing saved session...",
  sys_reconnect_prompt: "[ℹ️] Starting a fresh connection — scan the QR code below when it appears.",
  sys_init_failed: "[⚠️] Could not start WhatsApp connection:",
  sys_recovery_exhausted: "[❌] Could not restore WhatsApp after several attempts. Delete the .wwebjs_auth folder and restart.",
  sys_session_logged_out_runtime: "[⚠️] Logged out from WhatsApp on your phone or another device ({reason}).",
  sys_restart_after_logout: "[ℹ️] Session cleared. Start the application again and scan the QR code to sign in.",
  sys_qr_prompt: "Scan the QR code with WhatsApp:",
  sys_connected: "Connected to WhatsApp Web! System Ready.",
  sys_fatal: "Fatal system error:",

  err_no_media: "[⚠️] No printable files found for this customer today.",
  err_no_printers: "[❌] No printers detected on this machine.",
  err_download_fail: "[❌] Download failed (msg {index}): {msg}",
  err_print_image_fail: "[❌] Failed to print image: {file} — {msg}",

  info_fetching: "[ℹ️] Fetching last {limit} messages from: {name}",
  info_found_media: "[⬇️] Found {count} media message(s) from today. Downloading...",
  info_routing: "[ℹ️] Routing to printer: {printer}",
  info_spooling_img: "[🖨️] Printing {count} image(s) × {copies} copie(s) → {printer}",
  info_spooling_doc: "[🖨️] Printing document {index} ({file}) × {copies} copie(s), {duplex} → {printer}",
  info_duplex_simplex: "one-sided",
  info_duplex_duplex: "double-sided",
  info_wait_spooler: "[ℹ️] Waiting {seconds}s for print jobs to finish before cleanup...",
  info_order_success: "[✅] All files processed successfully. Ready for next customer.",
  info_customer_folder_refresh: "[ℹ️] Removing previous folder for {folder} and creating a new one...",
  info_customer_folder_ready: "[ℹ️] Download folder: temp/{folder}",
  info_customer_folder_cleaned: "[ℹ️] Cleaned up folder for {folder}.",

  status_on: "ON ✅",
  status_off: "OFF ❌",
  available_printers: "📠 Available Windows Printers:\n",
};

function t(key, variables = {}) {
  let text = i18n[key] || key;
  for (const [k, v] of Object.entries(variables)) {
    text = text.replace(new RegExp(`{${k}}`, 'g'), v);
  }
  return text;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core Business Logic
// ─────────────────────────────────────────────────────────────────────────────

function resolveGhostscriptPath() {
  const gsRoot = 'C:\\Program Files\\gs';
  try {
    if (fs.existsSync(gsRoot)) {
      const versions = fs.readdirSync(gsRoot).filter(d => d.startsWith('gs'));
      if (versions.length > 0) {
        versions.sort().reverse();
        const candidate = path.join(gsRoot, versions[0], 'bin', 'gswin64c.exe');
        if (fs.existsSync(candidate)) {
          return candidate;
        }
      }
    }
  } catch (_) { }
  return GS_DEFAULT_PATH;
}

async function loadConfig() {
  try {
    if (await fs.pathExists(CONFIG_PATH)) {
      const data = await fs.readJson(CONFIG_PATH);
      config = { ...DEFAULT_CONFIG, ...data };
    } else {
      await fs.writeJson(CONFIG_PATH, DEFAULT_CONFIG, { spaces: 2 });
      printLog.info(t('sys_created_default'));
      config = { ...DEFAULT_CONFIG };
    }
  } catch (err) {
    config = { ...DEFAULT_CONFIG };
  }
}

async function saveConfig() {
  try {
    await fs.writeJson(CONFIG_PATH, config, { spaces: 2 });
  } catch (err) {
    console.error(t('sys_save_failed'), err.message);
  }
}

function detectPrinters() {
  return new Promise((resolve) => {
    exec(
      'powershell -NoProfile -Command "Get-Printer | Select-Object -ExpandProperty Name"',
      (err, stdout) => {
        if (err || !stdout) {
          return resolve([]);
        }
        resolve(stdout.split('\n').map(p => p.trim()).filter(Boolean));
      }
    );
  });
}

function transformRawChat(c) {
  let parsedName = (c.name || '').trim();
  let detectedPhone = '';

  const title = (c.formattedTitle || c.name || '').trim();
  const phoneMatch = title.match(/(\+?\d[\d\s]{7,}\d)/);

  if (phoneMatch) {
    detectedPhone = phoneMatch[1].replace(/[^0-9]/g, '');
  }

  if (!detectedPhone && c.id && c.id.user) {
    let raw = c.id.user;
    if (raw.includes(':')) {
      raw = raw.split(':')[0];
    }
    raw = raw.replace(/@c\.us$/, '');
    raw = raw.replace(/[^0-9]/g, '');
    if (raw.length >= 10 && raw.length <= 15) {
      detectedPhone = raw;
    }
  }

  if (detectedPhone.length > 15 || (detectedPhone.startsWith('1') && detectedPhone.length > 13)) {
    detectedPhone = '';
  }

  const isNameJustNumber = /^[0-9+\s\-()]+$/.test(parsedName);
  if (isNameJustNumber || parsedName.toLowerCase().includes('c.us')) {
    parsedName = '';
  }

  let displayPhone = '';
  if (detectedPhone) {
    if (detectedPhone.startsWith('20') && detectedPhone.length >= 12) {
      displayPhone = `+20 ${detectedPhone.substring(2, 4)} ${detectedPhone.substring(4, 8)} ${detectedPhone.substring(8)}`;
    } else {
      displayPhone = `+${detectedPhone}`;
    }
  }

  return {
    id: c.id._serialized,
    name: parsedName,
    number: detectedPhone,
    displayPhone,
    lastMessageTimestamp: c.timestamp || Math.floor(Date.now() / 1000),
    raw: c
  };
}

async function buildChatCache(client) {
  printLog.info(t('sys_cache_building'));
  const chats = await client.getChats();
  chatCache = chats.filter(c => !c.isGroup).map(transformRawChat);
  printLog.success(t('sys_cache_built', { count: chatCache.length }));
}

function searchChats(query) {
  const cleanQuery = query.toLowerCase().replace(/[^0-9a-z]/g, '').trim();
  if (!cleanQuery) return [];

  const isNumericSearch = /^\d+$/.test(cleanQuery);

  let matches = chatCache.filter((c) => {
    const nameClean = (c.name || '').toLowerCase().replace(/[+\s]/g, '');
    const numClean = (c.number || '');
    if (isNumericSearch) {
      return numClean.endsWith(cleanQuery) || numClean.includes(cleanQuery);
    }
    return nameClean.includes(cleanQuery);
  });

  return matches.sort((a, b) => b.lastMessageTimestamp - a.lastMessageTimestamp);
}

function getRelativeTime(timestamp) {
  if (!timestamp) return 'N/A';
  const deltaMs = Date.now() - (timestamp * 1000);
  const deltaMin = Math.floor(deltaMs / (60 * 1000));
  if (deltaMin < 60) return `${Math.max(0, deltaMin)}m`;
  const deltaHrs = Math.floor(deltaMin / 60);
  if (deltaHrs < 24) return `${deltaHrs}h`;
  const deltaDays = Math.floor(deltaHrs / 24);
  return `${deltaDays}d`;
}

function isWithinDaysRange(timestampSeconds, daysLookback) {
  const msgDate = new Date(timestampSeconds * 1000);
  const now = new Date();

  msgDate.setHours(0, 0, 0, 0);
  const targetDate = new Date(now);
  targetDate.setHours(0, 0, 0, 0);

  const diffTime = targetDate - msgDate;
  const diffDays = diffTime / (1000 * 60 * 60 * 24);

  return diffDays >= 0 && diffDays <= daysLookback;
}

function guessExtension(mimetype, filename) {
  if (filename) {
    const ext = path.extname(filename).replace('.', '').toLowerCase();
    if (ext) return ext;
  }
  return MIME_MAP[mimetype] || null;
}

async function getPdfPageCountWithGhostscript(filepath) {
  const gsPath = resolveGhostscriptPath();
  const gsFile = filepath.replace(/\\/g, '/');
  return new Promise((resolve) => {
    const cmd = `"${gsPath}" -q -dNODISPLAY -dNOSAFER -c "(${gsFile}) (r) file runpdfbegin pdfpagecount = quit"`;
    exec(cmd, (err, stdout) => {
      if (err || !stdout) {
        resolve(1);
        return;
      }
      const pages = parseInt(String(stdout).trim(), 10);
      resolve(!isNaN(pages) && pages >= 1 ? pages : 1);
    });
  });
}

async function getPdfPageCount(filepath) {
  let parser = null;
  try {
    const buffer = await fs.readFile(filepath);
    parser = new PDFParse({ data: buffer });
    const info = await parser.getInfo();
    if (info.total && info.total >= 1) {
      return info.total;
    }
  } catch (_) {
    // fall through to Ghostscript
  } finally {
    if (parser) {
      await parser.destroy().catch(() => { });
    }
  }
  return getPdfPageCountWithGhostscript(filepath);
}

function sanitizeFolderKey(key) {
  const safe = String(key || '').replace(/[^0-9a-zA-Z_-]/g, '');
  return safe || 'unknown';
}

function getCustomerOrderDir(folderKey) {
  return path.join(TEMP_DIR, sanitizeFolderKey(folderKey));
}

async function prepareCustomerOrderDir(folderKey) {
  const safeKey = sanitizeFolderKey(folderKey);
  const orderDir = getCustomerOrderDir(safeKey);
  await fs.ensureDir(TEMP_DIR);
  if (await fs.pathExists(orderDir)) {
    printLog.info(t('info_customer_folder_refresh', { folder: safeKey }));
    await fs.remove(orderDir);
  }
  await fs.ensureDir(orderDir);
  currentOrderFolderKey = safeKey;
  currentOrderDir = orderDir;
  printLog.info(t('info_customer_folder_ready', { folder: safeKey }));
  return orderDir;
}

async function cleanupCurrentCustomerOrderDir() {
  if (!currentOrderDir) return;
  const folderKey = currentOrderFolderKey;
  try {
    await fs.remove(currentOrderDir);
  } catch (_) { }
  if (folderKey) {
    printLog.info(t('info_customer_folder_cleaned', { folder: folderKey }));
  }
  currentOrderDir = null;
  currentOrderFolderKey = null;
}

async function createBlankPage() {
  const baseDir = currentOrderDir || TEMP_DIR;
  const dest = path.join(baseDir, `blank_${Date.now()}.pdf`);
  await new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 0 });
    const stream = fs.createWriteStream(dest);
    doc.pipe(stream);
    doc.end();
    stream.on('finish', resolve);
    stream.on('error', reject);
  });
  return dest;
}

async function downloadMediaInRange(chat, orderDir, daysLookback) {
  const downloadDir = orderDir || currentOrderDir || TEMP_DIR;
  await fs.ensureDir(downloadDir);

  const messages = await chat.fetchMessages({ limit: config.fetchMessageLimit });

  const filteredMessages = messages.filter(m => m.hasMedia && isWithinDaysRange(m.timestamp, daysLookback));

  if (filteredMessages.length === 0) {
    printLog.warn(t('err_no_media'));
    return { images: [], docs: [] };
  }

  printLog.info(t('info_found_media', { count: filteredMessages.length }));

  const images = [];
  const docs = [];

  for (const [i, msg] of filteredMessages.entries()) {
    try {
      const media = await msg.downloadMedia();
      if (!media) continue;

      const ext = guessExtension(media.mimetype, media.filename);
      if (!ext || !ALL_EXTS.has(ext)) continue;

      const originalName = media.filename ? path.parse(media.filename).name : `file_${Date.now()}`;
      const cleanOriginal = originalName.replace(/[^\w\s]/gi, '');
      const filename = `${cleanOriginal}_${Date.now()}_${i}.${ext}`;
      const filepath = path.join(downloadDir, filename);

      await fs.writeFile(filepath, Buffer.from(media.data, 'base64'));

      if (IMAGE_EXTS.has(ext)) {
        images.push(filepath);
      } else {
        docs.push(filepath);
      }
    } catch (err) {
      printLog.error(t('err_download_fail', { index: i, msg: err.message }));
    }
  }

  return { images, docs };
}

async function printImage(filepath, printer, copies = 1) {
  const cmd = `mspaint /pt "${filepath}" "${printer.trim()}"`;
  for (let i = 0; i < copies; i++) {
    await new Promise((resolve) => {
      exec(cmd, (err) => {
        if (err) {
          printLog.error(t('err_print_image_fail', { file: path.basename(filepath), msg: err.message }));
        }
        resolve();
      });
    });
    if (i < copies - 1) {
      await new Promise((r) => setTimeout(r, IMAGE_PRINT_GAP_MS));
    }
  }
}

async function printAllImages(images, printer, copies) {
  for (let i = 0; i < images.length; i++) {
    await printImage(images[i], printer, copies);
    if (i < images.length - 1) {
      await new Promise((r) => setTimeout(r, IMAGE_PRINT_GAP_MS));
    }
  }
}

function printDocumentWithGhostscript(filepath, printer, copies = 1, duplex = 'simplex') {
  return new Promise((resolve) => {
    const gsPath = resolveGhostscriptPath();
    const cleanPrinter = printer.trim();
    const duplexEntry = duplex === 'duplex' ? '/Duplex true /Tumble false' : '/Duplex false';
    const pageDevice = `<</NumCopies ${copies} ${duplexEntry}>> setpagedevice`;
    const cmd = `"${gsPath}" -dNOPAUSE -dBATCH -dNOSAFER -q -sDEVICE=mswinpr2 -sOutputFile="%printer%${cleanPrinter}" -c "${pageDevice}" -f "${filepath}"`;
    exec(cmd, () => resolve());
  });
}

function calcSpoolerWaitMs(imageCount, imageCopies, docJobs) {
  const imageWork = imageCount * imageCopies;
  const docCopySum = docJobs.reduce((sum, j) => sum + j.copies, 0);
  return Math.max(MIN_SPOOLER_WAIT_MS, imageWork * MS_PER_IMAGE_PRINT + docJobs.length * MS_PER_DOC_JOB + docCopySum * 800);
}

async function cleanupTemp() {
  await cleanupCurrentCustomerOrderDir();
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Session Management
// ─────────────────────────────────────────────────────────────────────────────

async function clearAuthSession() {
  await fs.remove(AUTH_DIR).catch(() => { });
  await fs.remove(WEB_CACHE_DIR).catch(() => { });
}

function clearReadyWatchdog() {
  if (readyWatchdog) {
    clearTimeout(readyWatchdog);
    readyWatchdog = null;
  }
}

function clearSyncStatePoll() {
  if (syncStatePoll) {
    clearInterval(syncStatePoll);
    syncStatePoll = null;
  }
}

function clearSyncStatusInterval() {
  if (syncStatusInterval) {
    clearInterval(syncStatusInterval);
    syncStatusInterval = null;
  }
}

function clearAllSyncTimers() {
  clearReadyWatchdog();
  clearSyncStatePoll();
  clearSyncStatusInterval();
}

function startSyncStatusUpdates() {
  clearSyncStatusInterval();
  authenticatedAt = Date.now();
  syncStatusInterval = setInterval(() => {
    if (clientIsReady || isRecoveringSession) {
      clearSyncStatusInterval();
      return;
    }
    const elapsed = Math.round((Date.now() - authenticatedAt) / 1000);
    printLog.info(t('sys_sync_still', { seconds: String(elapsed) }));
  }, 15000);
}

function startSyncStatePoll(client) {
  clearSyncStatePoll();
  syncStatePoll = setInterval(() => {
    if (clientIsReady || isRecoveringSession) {
      clearSyncStatePoll();
      return;
    }
    if (activeWhatsAppClient !== client) {
      clearSyncStatePoll();
      return;
    }
    void (async () => {
      try {
        const state = await client.getState();
        if (!state) return;
        const badStates = ['UNPAIRED', 'UNPAIRED_IDLE', 'TIMEOUT', 'TOS_BLOCK', 'DEPRECATED_VERSION'];
        if (badStates.includes(state)) {
          clearSyncStatePoll();
          void recoverFromInvalidSession(state, client);
          return;
        }
        const stuckMs = Date.now() - authenticatedAt;
        if (state === 'CONNECTED' && stuckMs > READY_TIMEOUT_MS && !clientIsReady) {
          clearSyncStatePoll();
          void recoverFromInvalidSession('CONNECTED_WITHOUT_READY', client);
        }
      } catch (_) { }
    })();
  }, SYNC_STATE_POLL_MS);
}

function armReadyWatchdog(client) {
  clearReadyWatchdog();
  readyWatchdog = setTimeout(() => {
    if (clientIsReady || isRecoveringSession) return;
    if (activeWhatsAppClient !== client) return;
    void recoverFromInvalidSession('READY_TIMEOUT_STALE_SESSION', client);
  }, READY_TIMEOUT_MS);
}

function isRecoverableSessionError(reason) {
  if (reason === undefined || reason === null || reason === '') return false;
  const text = String(reason).toUpperCase();
  const patterns = ['LOGOUT', 'UNPAIRED', 'UNAUTHORIZED', 'UNAUTHENTICATED', 'CONFLICT', 'NOT LOGGED IN', '401', '403', 'READY TIMEOUT', 'STALE SESSION', 'CONNECTED_WITHOUT_READY', 'TARGET CLOSED', 'PROTOCOL ERROR', 'EVALUATION FAILED', 'EXECUTION CONTEXT WAS DESTROYED'];
  return patterns.some((pattern) => text.includes(pattern));
}

function isHardSessionLoss(reason) {
  if (!reason) return false;
  const text = String(reason).toUpperCase();
  return ['LOGOUT', 'UNPAIRED', 'UNAUTHORIZED', 'UNAUTHENTICATED', 'CONFLICT', 'NOT LOGGED IN'].some((pattern) => text.includes(pattern));
}

function scheduleClientRestart() {
  setImmediate(() => {
    createAndStartWhatsAppClient().catch((err) => {
      console.error(`\n${t('sys_fatal')} ${err.message}`);
      process.exit(1);
    });
  });
}

async function recoverFromInvalidSession(reason, client) {
  if (isRecoveringSession) return;
  const reasonText = reason === 'READY_TIMEOUT_STALE_SESSION' ? t('sys_ready_timeout') : reason === 'CONNECTED_WITHOUT_READY' ? t('sys_ready_timeout') : (reason ? String(reason) : 'session invalid');

  if (clientIsReady) {
    printLog.warn(t('sys_session_logged_out_runtime', { reason: reasonText }));
    clearAllSyncTimers();
    await clearAuthSession();
    if (client) {
      await client.destroy().catch(() => { });
    }
    activeWhatsAppClient = null;
    printLog.info(t('sys_restart_after_logout'));
    process.exit(0);
  }

  if (sessionRecoveryAttempts >= MAX_SESSION_RECOVERY_ATTEMPTS) {
    printLog.error(t('sys_recovery_exhausted'));
    process.exit(1);
  }

  isRecoveringSession = true;
  sessionRecoveryAttempts++;
  clearAllSyncTimers();
  printLog.warn(t('sys_session_cleared', { reason: reasonText }));

  if (client && activeWhatsAppClient === client) {
    await client.destroy().catch(() => { });
    activeWhatsAppClient = null;
  }

  await clearAuthSession();
  clientIsReady = false;
  printLog.info(t('sys_reconnect_prompt'));
  isRecoveringSession = false;
  scheduleClientRestart();
}

function buildWhatsAppClientOptions() {
  return {
    authStrategy: new LocalAuth({ clientId: 'print-bot', dataPath: AUTH_DIR }),
    webVersionCache: { type: 'remote', remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html' },
    bypassCSP: true,
    puppeteer: {
      headless: true,
      executablePath: CHROME_PATH,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu'
      ],
      // Add timeout
      timeout: 60000  // 60 seconds
    }
  };
}

function attachWhatsAppClientEvents(client) {
  client.on('qr', (qr) => {
    clearAllSyncTimers();
    currentQrCode = qr;
    printLog.info(t('sys_qr_prompt'));
    qrcode.generate(qr, { small: true });
  });

  client.on('loading_screen', (percent, message) => {
    printLog.info(t('sys_loading', { percent: String(percent), message: message || '' }));
    if (Number(percent) >= 100) {
      printLog.info(t('sys_loading_done'));
    }
  });

  client.on('change_state', (state) => {
    if (clientIsReady || isRecoveringSession) return;
    const badStates = ['UNPAIRED', 'UNPAIRED_IDLE', 'TIMEOUT', 'TOS_BLOCK', 'DEPRECATED_VERSION'];
    if (badStates.includes(state)) {
      void recoverFromInvalidSession(state, client);
    }
  });

  client.on('authenticated', () => {
    currentQrCode = null;
    printLog.success(t('sys_auth_success'));
    printLog.info(t('sys_syncing'));
    armReadyWatchdog(client);
    startSyncStatusUpdates();
    startSyncStatePoll(client);
  });

  client.on('auth_failure', (msg) => {
    const detail = msg ? String(msg) : 'unknown';
    if (isRecoverableSessionError(detail)) {
      printLog.warn(`${t('sys_auth_failed')} ${detail}`);
      void recoverFromInvalidSession(detail, client);
      return;
    }
    printLog.error(`${t('sys_auth_failed')} ${detail}`);
    process.exit(1);
  });

  client.on('disconnected', (reason) => {
    const detail = reason ? String(reason) : '';
    if (!clientIsReady && !isHardSessionLoss(detail)) {
      printLog.warn(`${t('sys_disconnected')} ${detail || 'connection lost'}`);
      return;
    }
    if (isRecoverableSessionError(detail) || isHardSessionLoss(detail)) {
      printLog.warn(`${t('sys_disconnected')} ${detail}`);
      void recoverFromInvalidSession(detail || 'LOGOUT', client);
      return;
    }
    printLog.error(`${t('sys_disconnected')} ${detail}`);
    process.exit(1);
  });

  client.on('ready', async () => {
    if (activeWhatsAppClient !== client) return;
    clearAllSyncTimers();
    clientIsReady = true;
    sessionRecoveryAttempts = 0;
    currentQrCode = null;
    printLog.success(t('sys_connected'));
    await buildChatCache(client);
    printLog.success('WhatsApp client is ready for API requests');
  });
}

async function createAndStartWhatsAppClient() {
  const client = new Client(buildWhatsAppClientOptions());
  globalClientReference = client;
  activeWhatsAppClient = client;
  attachWhatsAppClientEvents(client);

  try {
    await client.initialize();
  } catch (err) {
    if (activeWhatsAppClient !== client) return;
    const msg = err && err.message ? err.message : String(err);
    printLog.warn(`${t('sys_init_failed')} ${msg}`);
    if (isRecoverableSessionError(msg)) {
      void recoverFromInvalidSession(msg, client);
      return;
    }
    throw err;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Express API Routes
// ─────────────────────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

app.get('/api/status', (req, res) => {
  if (clientIsReady) {
    res.json({ success: true, whatsappConnected: true, qrCode: null });
  } else if (currentQrCode) {
    res.json({ success: true, whatsappConnected: false, qrCode: currentQrCode });
  } else {
    res.json({ success: true, whatsappConnected: false, qrCode: null });
  }
});

app.get('/api/printers', (req, res) => {
  res.json({ success: true, printers: printerCache });
});

app.get('/api/search', (req, res) => {
  const { q } = req.query;
  if (!q || typeof q !== 'string') {
    return res.status(400).json({ success: false, error: 'Missing or invalid query parameter "q"' });
  }

  const matches = searchChats(q);
  const results = matches.map(match => ({
    id: match.id,
    name: match.name,
    number: match.number,
    displayPhone: match.displayPhone,
    relativeTime: getRelativeTime(match.lastMessageTimestamp)
  }));

  res.json({ success: true, results });
});

app.post('/api/fetch-media', async (req, res) => {
  try {
    const { chatId, daysLookback = 0 } = req.body;

    if (!chatId || typeof chatId !== 'string') {
      return res.status(400).json({ success: false, error: 'Missing or invalid chatId' });
    }

    if (!clientIsReady || !activeWhatsAppClient) {
      return res.status(503).json({ success: false, error: 'WhatsApp client not ready' });
    }

    const chat = await activeWhatsAppClient.getChatById(chatId);
    if (!chat) {
      return res.status(404).json({ success: false, error: 'Chat not found' });
    }

    const folderKey = sanitizeFolderKey(chatId);
    const orderDir = await prepareCustomerOrderDir(folderKey);

    const { images, docs } = await downloadMediaInRange(chat, orderDir, daysLookback);

    const documents = await Promise.all(docs.map(async (docPath) => {
      const ext = path.extname(docPath).replace('.', '').toLowerCase();
      const pages = ext === 'pdf' ? await getPdfPageCount(docPath) : 1;
      return {
        filename: path.basename(docPath),
        absolutePath: docPath,
        pages
      };
    }));

    const imagesFormatted = images.map(imgPath => ({
      filename: path.basename(imgPath),
      absolutePath: imgPath
    }));

    res.json({
      success: true,
      customerFolder: orderDir,
      documents,
      images: imagesFormatted
    });

  } catch (error) {
    console.error('Error in /api/fetch-media:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/print', async (req, res) => {
  try {
    const { printer, copies = 1, duplex = 'simplex', blankPageSeparator, files } = req.body;

    if (!printer || typeof printer !== 'string') {
      return res.status(400).json({ success: false, error: 'Missing or invalid printer' });
    }

    if (!files || !Array.isArray(files) || files.length === 0) {
      return res.status(400).json({ success: false, error: 'Missing or invalid files array' });
    }

    const useSeparator = blankPageSeparator !== undefined ? blankPageSeparator : config.blankPageSeparator;

    const images = files.filter(f => f.type === 'image');
    const documents = files.filter(f => f.type === 'document');

    let docJobs = [];
    let imageCopiesCount = copies;
    let imagePrinter = printer;

    for (const image of images) {
      const imgCopies = image.customOverride?.copies ?? copies;
      const imgPrinter = image.customOverride?.printer ?? printer;
      imageCopiesCount = imgCopies;
      imagePrinter = imgPrinter;

      printLog.info(t('info_spooling_img', {
        count: 1,
        copies: imgCopies,
        printer: imgPrinter
      }));

      await printImage(image.absolutePath, imgPrinter, imgCopies);
    }

    for (let i = 0; i < documents.length; i++) {
      const doc = documents[i];
      const docCopies = doc.customOverride?.copies ?? copies;
      const docPrinter = doc.customOverride?.printer ?? printer;
      const docDuplex = doc.customOverride?.duplex ?? duplex;

      docJobs.push({
        path: doc.absolutePath,
        copies: docCopies,
        printer: docPrinter,
        duplex: docDuplex
      });
    }

    if (documents.length > 0 && useSeparator) {
      const firstDoc = docJobs[0];
      const leadingBlank = await createBlankPage();
      await printDocumentWithGhostscript(leadingBlank, firstDoc.printer, 1, firstDoc.duplex);
    }

    for (let i = 0; i < docJobs.length; i++) {
      const job = docJobs[i];
      const file = path.basename(job.path);
      const duplexLabel = job.duplex === 'duplex' ? t('info_duplex_duplex') : t('info_duplex_simplex');

      printLog.info(t('info_spooling_doc', {
        index: i + 1,
        file,
        copies: job.copies,
        duplex: duplexLabel,
        printer: job.printer
      }));

      await printDocumentWithGhostscript(job.path, job.printer, job.copies, job.duplex);

      if (useSeparator) {
        const trailingBlank = await createBlankPage();
        await printDocumentWithGhostscript(trailingBlank, job.printer, 1, job.duplex);
      }
    }

    if (config.beepNotification) {
      process.stdout.write('\u0007');
    }

    const spoolerWaitMs = calcSpoolerWaitMs(images.length, imageCopiesCount, docJobs);
    printLog.info(t('info_wait_spooler', { seconds: Math.ceil(spoolerWaitMs / 1000) }));

    setTimeout(async () => {
      await cleanupTemp();
    }, spoolerWaitMs);

    res.json({ success: true, message: 'Jobs spooled successfully' });

  } catch (error) {
    console.error('Error in /api/print:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/config/separator', async (req, res) => {
  try {
    const { enabled } = req.body;
    if (typeof enabled !== 'boolean') {
      return res.status(400).json({ success: false, error: 'Missing or invalid enabled flag (must be boolean)' });
    }

    config.blankPageSeparator = enabled;
    await saveConfig();
    res.json({ success: true, blankPageSeparator: config.blankPageSeparator });

  } catch (error) {
    console.error('Error in /api/config/separator:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/flush', async (req, res) => {
  try {
    await fs.emptyDir(TEMP_DIR);
    res.json({ success: true, message: 'System temp cache cleared successfully' });
  } catch (error) {
    console.error('Error in /api/flush:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/logout', async (req, res) => {
  try {
    if (activeWhatsAppClient) {
      await activeWhatsAppClient.destroy().catch(() => { });
    }
    await clearAuthSession();
    clientIsReady = false;
    activeWhatsAppClient = null;
    currentQrCode = null;

    setTimeout(() => {
      process.exit(0);
    }, 1000);

    res.json({ success: true, message: 'Session destroyed, server resetting' });
  } catch (error) {
    console.error('Error in /api/logout:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Start server
async function bootstrap() {
  console.log('\n╔══════════════════════════════════════════╗');
  console.log('║ WhatsApp Retail Terminal API v6.1.0      ║');
  console.log('╚══════════════════════════════════════════╝\n');

  printerCache = await detectPrinters();
  console.log(`[✅] Detected ${printerCache.length} printer(s)`);

  await loadConfig();
  await fs.ensureDir(TEMP_DIR);

  clientIsReady = false;
  sessionRecoveryAttempts = 0;
  createAndStartWhatsAppClient().catch((err) => {
    console.error(`\n${t('sys_fatal')} ${err.message}`);
    process.exit(1);
  });

  app.listen(PORT, () => {
    console.log(`[✅] REST API server running on http://localhost:${PORT}`);
    console.log('[ℹ️] Available endpoints:');
    console.log('  GET  /api/status');
    console.log('  GET  /api/printers');
    console.log('  GET  /api/search?q=<query>');
    console.log('  POST /api/fetch-media');
    console.log('  POST /api/print');
    console.log('  POST /api/config/separator');
    console.log('  POST /api/flush');
    console.log('  POST /api/logout\n');
  });
}

bootstrap().catch((err) => {
  console.error(`\n${t('sys_fatal')} ${err.message}`);
  process.exit(1);
});