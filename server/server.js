'use strict';

const express = require('express');
const cors = require('cors');
const http = require('http'); // ✨ مطلوب لربط الـ WebSockets
const { Server } = require('socket.io'); // ✨ مكتبة الـ WebSockets
const Queue = require('better-queue'); // ✨ مكتبة إدارة الطوابير (FIFO)
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const path = require('path');
const fs = require('fs-extra');
const { exec } = require('child_process');
const os = require('os');
const { PDFParse } = require('pdf-parse');
const PDFDocument = require('pdfkit');

const app = express();
const server = http.createServer(app); // ✨ ربط express بـ http server
const io = new Server(server, { cors: { origin: "*" } }); // ✨ تفعيل الـ WebSockets متاح لكل الفرونت إند
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
const MAC_CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

let config = {};
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
const DOC_EXTS = new Set(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf']);
const ALL_EXTS = new Set([...IMAGE_EXTS, ...DOC_EXTS]);

const MIME_MAP = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/pdf': 'pdf',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
  'text/plain': 'txt',
  'application/rtf': 'rtf'
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

// ─────────────────────────────────────────────────────────────────────────────
// ✨ 1. الـ Queue System (طابور الطباعة والتحويل الموحد)
// ─────────────────────────────────────────────────────────────────────────────

// الطابور ده هيستقبل أي عملية طباعة وينفذها واحدة ورا التانية بالتتابع (FIFO) عشان السيرفر ميهنجش
const printQueue = new Queue(async (task, cb) => {
  try {
    console.log(`[📦 Queue] Starting background job for folder: ${task.customerFolder || 'unknown'}`);
    await processPrintJobInBackground(task.images, task.documents, task.printer, task.copies, task.duplex, task.useSeparator);
    cb(null, true);
  } catch (err) {
    console.error(`[❌ Queue] Error executing print task:`, err.message);
    cb(err);
  }
}, { concurrent: 1 }); // concurrent: 1 بتضمن إن مفيش ملفين يتطبعوا أو يتحولوا في نفس الثانية

// ─────────────────────────────────────────────────────────────────────────────
// ✨ 2. الـ Garbage Collector (التنظيف التلقائي للملفات القديمة)
// ─────────────────────────────────────────────────────────────────────────────

function startGarbageCollector() {
  // بيشتغل مرة كل 24 ساعة
  setInterval(async () => {
    console.log('[🧹 Garbage Collector] Checking for old customer folders...');
    try {
      if (!(await fs.pathExists(TEMP_DIR))) return;
      const items = await fs.readdir(TEMP_DIR);
      const now = Date.now();
      const ONE_DAY_MS = 24 * 60 * 60 * 1000;

      for (const item of items) {
        const itemPath = path.join(TEMP_DIR, item);
        const stat = await fs.stat(itemPath);

        // لو الفولدر بقاله أكتر من 24 ساعة ملمسش، بيمسحه فوراً لتوفير مساحة الهارد
        if (stat.isDirectory() && (now - stat.mtimeMs > ONE_DAY_MS)) {
          await fs.remove(itemPath);
          console.log(`[🗑️ Cleaned] Removed stale folder: ${item}`);
        }
      }
    } catch (err) {
      console.error('[❌ Garbage Collector] Error during cleaning:', err.message);
    }
  }, 24 * 60 * 60 * 1000);
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
        if (fs.existsSync(candidate)) return candidate;
      }
    }
  } catch (_) { }
  return GS_DEFAULT_PATH;
}

async function convertOfficeToPdf(filepath) {
  const ext = path.extname(filepath).toLowerCase();
  if (ext === '.pdf' || IMAGE_EXTS.has(ext.replace('.', ''))) return filepath;

  const outputDir = path.dirname(filepath);
  const pdfPath = filepath.replace(new RegExp(`${ext}$`, 'i'), '.pdf');

  return new Promise((resolve) => {
    const cmd = `libreoffice --headless --convert-to pdf --outdir "${outputDir}" "${filepath}"`;
    exec(cmd, (err) => {
      if (err) {
        console.error(`[❌] LibreOffice conversion failed for ${ext}:`, err.message);
        resolve(filepath);
      } else {
        console.log(`[✅] Office Document (${ext}) successfully converted to PDF: ${path.basename(pdfPath)}`);
        resolve(pdfPath);
      }
    });
  });
}

async function autoRotateImageIfLandscape(filepath) {
  if (os.platform() !== 'win32') return filepath;
  return new Promise((resolve) => {
    const cmd = `powershell -Command "$img = [Drawing.Image]::FromFile('${filepath}'); if ($img.Width -gt $img.Height) { $img.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipNone); $img.Save('${filepath}'); write-output 'ROTATED' } $img.Dispose();"`;
    exec(cmd, (err, stdout) => {
      if (!err && stdout.trim() === 'ROTATED') {
        console.log(`[🔄] Auto-rotated landscape image: ${path.basename(filepath)}`);
      }
      resolve(filepath);
    });
  });
}

async function preparePdfForFullPrint(filepath) {
  if (os.platform() !== 'win32') return filepath;
  try {
    const gsPath = resolveGhostscriptPath();
    if (!fs.existsSync(gsPath)) return filepath;

    const outputPath = filepath.replace(/\.pdf$/i, '_fullprint.pdf');
    return new Promise((resolve) => {
      const cmd = `"${gsPath}" -dNOPAUSE -dBATCH -dNOSAFER -sDEVICE=pdfwrite -dPDFFitPage -dUseCropBox -dFIXEDMEDIA -sPAPERSIZE=a4 -dCompatibilityLevel=1.4 -dAutoRotatePages=/All -dPrinted=false -dImageDPI=150 -dColorImageFilter=/FlateEncode -dGrayImageFilter=/FlateEncode -sOutputFile="${outputPath}" "${filepath}"`;
      exec(cmd, (err) => {
        if (err) {
          resolve(filepath);
        } else {
          resolve(outputPath);
        }
      });
    });
  } catch (error) {
    return filepath;
  }
}

async function loadConfig() {
  try {
    if (await fs.pathExists(CONFIG_PATH)) {
      const data = await fs.readJson(CONFIG_PATH);
      config = { ...DEFAULT_CONFIG, ...data };
    } else {
      await fs.writeJson(CONFIG_PATH, DEFAULT_CONFIG, { spaces: 2 });
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
    console.error('Failed to save configuration:', err.message);
  }
}

function detectPrinters() {
  return new Promise((resolve) => {
    if (os.platform() === 'darwin') return resolve(['Mac_Virtual_Printer']);
    exec('powershell -NoProfile -Command "Get-Printer | Select-Object -ExpandProperty Name"', (err, stdout) => {
      if (err || !stdout) return resolve([]);
      resolve(stdout.split('\n').map(p => p.trim()).filter(Boolean));
    });
  });
}

function transformRawChat(c) {
  let parsedName = (c.name || '').trim();
  let detectedPhone = '';

  const title = (c.formattedTitle || c.name || '').trim();
  const phoneMatch = title.match(/(\+?\d[\d\s]{7,}\d)/);

  if (phoneMatch) detectedPhone = phoneMatch[1].replace(/[^0-9]/g, '');

  if (!detectedPhone && c.id && c.id.user) {
    let raw = c.id.user;
    if (raw.includes(':')) raw = raw.split(':')[0];
    raw = raw.replace(/@c\.us$/, '').replace(/@lid$/, '').replace(/[^0-9]/g, '');
    if (raw.length >= 10 && raw.length <= 15) detectedPhone = raw;
  }

  if (detectedPhone.length > 15 || (detectedPhone.startsWith('1') && detectedPhone.length > 13)) {
    detectedPhone = '';
  }

  const isNameJustNumber = /^[0-9+\s\-()]+$/.test(parsedName);
  if (isNameJustNumber || parsedName.toLowerCase().includes('c.us') || parsedName.toLowerCase().includes('lid')) {
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

function getRelativeTime(timestamp) {
  if (!timestamp) return 'N/A';
  const deltaMs = Date.now() - (timestamp * 1000);
  const deltaMin = Math.floor(deltaMs / (60 * 1000));
  if (deltaMin < 60) return `${Math.max(0, deltaMin)}m`;
  const deltaHrs = Math.floor(deltaMin / 60);
  if (deltaHrs < 24) return `${deltaHrs}h`;
  return `${Math.floor(deltaHrs / 24)}d`;
}

function isWithinDaysRange(timestampSeconds, daysLookback) {
  const msgDate = new Date(timestampSeconds * 1000);
  const now = new Date();
  msgDate.setHours(0, 0, 0, 0);
  const targetDate = new Date(now);
  targetDate.setHours(0, 0, 0, 0);
  const diffDays = Math.ceil(Math.abs(targetDate - msgDate) / (1000 * 60 * 60 * 24));
  return diffDays <= daysLookback;
}

function guessExtension(mimetype, filename) {
  if (filename) {
    const ext = path.extname(filename).replace('.', '').toLowerCase();
    if (ext) return ext;
  }
  return MIME_MAP[mimetype] || null;
}

async function getPdfPageCountWithGhostscript(filepath) {
  if (os.platform() === 'darwin') return 1;
  const gsPath = resolveGhostscriptPath();
  const gsFile = filepath.replace(/\\/g, '/');
  return new Promise((resolve) => {
    const cmd = `"${gsPath}" -q -dNODISPLAY -dNOSAFER -c "(${gsFile}) (r) file runpdfbegin pdfpagecount = quit"`;
    exec(cmd, (err, stdout) => {
      if (err || !stdout) return resolve(1);
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
    if (info.total && info.total >= 1) return info.total;
  } catch (_) {
  } finally {
    if (parser) await parser.destroy().catch(() => { });
  }
  return getPdfPageCountWithGhostscript(filepath);
}

function sanitizeFolderKey(key) {
  return String(key || '').replace(/[^0-9a-zA-Z_-]/g, '') || 'unknown';
}

function getCustomerOrderDir(folderKey) {
  return path.join(TEMP_DIR, sanitizeFolderKey(folderKey));
}

async function prepareCustomerOrderDir(folderKey) {
  const safeKey = sanitizeFolderKey(folderKey);
  const orderDir = getCustomerOrderDir(safeKey);
  await fs.ensureDir(TEMP_DIR);
  if (await fs.pathExists(orderDir)) await fs.remove(orderDir);
  await fs.ensureDir(orderDir);
  currentOrderFolderKey = safeKey;
  currentOrderDir = orderDir;
  return orderDir;
}

async function cleanupCurrentCustomerOrderDir() {
  if (!currentOrderDir) return;
  try { await fs.remove(currentOrderDir); } catch (_) { }
  currentOrderDir = null;
  currentOrderFolderKey = null;
}

async function createBlankPage() {
  const baseDir = currentOrderDir || TEMP_DIR;
  const dest = path.join(baseDir, `blank_${Date.now()}.pdf`);
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 0, layout: 'portrait', autoFirstPage: true });
    const stream = fs.createWriteStream(dest);
    doc.pipe(stream);
    doc.rect(0, 0, doc.page.width, doc.page.height).fill('#ffffff');
    doc.end();
    stream.on('finish', () => resolve(dest));
    stream.on('error', reject);
  });
}

async function downloadMediaInRange(chat, orderDir, daysLookback) {
  const downloadDir = orderDir || currentOrderDir || TEMP_DIR;
  await fs.ensureDir(downloadDir);

  const messages = await chat.fetchMessages({ limit: config.fetchMessageLimit });
  const filteredMessages = messages.filter(m => m.hasMedia && isWithinDaysRange(m.timestamp, daysLookback));

  if (filteredMessages.length === 0) return { images: [], docs: [] };

  const images = [];
  const docs = [];

  for (const [i, msg] of filteredMessages.entries()) {
    try {
      const media = await msg.downloadMedia();
      if (!media) continue;

      let ext = guessExtension(media.mimetype, media.filename);
      if (!ext || !ALL_EXTS.has(ext)) continue;

      const originalExt = ext;
      const originalName = media.filename ? path.parse(media.filename).name : `file_${Date.now()}`;
      const filename = `${originalName.replace(/[^\w\s]/gi, '')}_${Date.now()}_${i}.${ext}`;
      let filepath = path.join(downloadDir, filename);

      await fs.writeFile(filepath, Buffer.from(media.data, 'base64'));

      if (DOC_EXTS.has(ext) && ext !== 'pdf') {
        filepath = await convertOfficeToPdf(filepath);
        ext = 'pdf';
      }

      if (IMAGE_EXTS.has(ext)) {
        images.push({ absolutePath: filepath, originalType: originalExt });
      } else if (ext === 'pdf') {
        docs.push({ absolutePath: filepath, originalType: originalExt });
      }
    } catch (err) {
      console.error(`[❌] Download failed for msg ${i}:`, err.message);
    }
  }
  return { images, docs };
}

async function printImage(filepath, printer, copies = 1) {
  if (os.platform() === 'darwin') return;
  const cmd = `mspaint /pt "${filepath}" "${printer.trim()}"`;
  for (let i = 0; i < copies; i++) {
    await new Promise((resolve) => { exec(cmd, () => resolve()); });
    if (i < copies - 1) await new Promise((r) => setTimeout(r, IMAGE_PRINT_GAP_MS));
  }
}

// ✨ الدالة المحدثة لاستقبال النطاق المخصص لكل ملف ودعمه عبر Ghostscript
async function printDocumentWithGhostscript(filepath, printer, copies = 1, duplex = 'simplex', startPage = null, endPage = null) {
  if (os.platform() !== 'win32') return;
  try {
    const scaledPdf = await preparePdfForFullPrint(filepath);
    const gsPath = resolveGhostscriptPath();
    if (!fs.existsSync(gsPath)) return;

    const duplexEntry = duplex === 'duplex' ? '/Duplex true /Tumble false' : '/Duplex false';
    const pageDevice = `<<${duplexEntry} /FitToPage true>> setpagedevice`;

    // ✨ حقن الـ flags الخاصة بنطاق الصفحات المختار من واجهة فلاتر
    let pageRangeFlags = '';
    if (startPage !== null && startPage !== undefined) {
      pageRangeFlags += ` -dFirstPage=${startPage}`;
    }
    if (endPage !== null && endPage !== undefined) {
      pageRangeFlags += ` -dLastPage=${endPage}`;
    }

    const cmd = `"${gsPath}" -dNOPAUSE -dBATCH -dNOSAFER -q -sDEVICE=mswinpr2 -sOutputFile="%printer%${printer.trim()}" -dPDFFitPage -dUseCropBox -dFIXEDMEDIA -sPAPERSIZE=a4${pageRangeFlags} -c "${pageDevice}" -f "${scaledPdf}"`;

    console.log(`[🖨️ GS Executing] Printing pages: ${startPage || 1} to ${endPage || 'End'} for file: ${path.basename(filepath)}`);

    for (let c = 0; c < copies; c++) {
      await new Promise((resolve) => { exec(cmd, () => resolve()); });
    }
    if (scaledPdf !== filepath) fs.unlink(scaledPdf).catch(() => { });
  } catch (error) {
    console.error('[⚠️] Print error:', error.message);
  }
}

function calcSpoolerWaitMs(imageCount, imageCopies, docJobs) {
  const imageWork = imageCount * imageCopies;
  const docCopySum = docJobs.reduce((sum, j) => sum + j.copies, 0);
  return Math.max(MIN_SPOOLER_WAIT_MS, imageWork * MS_PER_IMAGE_PRINT + docJobs.length * MS_PER_DOC_JOB + docCopySum * 800);
}

// ✨ تحديث معالجة الخلفية للطابور لقراءة الـ Custom Overrides الخاصة بالـ Ranges
async function processPrintJobInBackground(images, documents, printer, copies, duplex, useSeparator) {
  let docJobs = [];
  let imageCopiesCount = copies;

  for (const image of images) {
    const imgCopies = image.customOverride?.copies ?? copies;
    const imgPrinter = image.customOverride?.printer ?? printer;
    imageCopiesCount = imgCopies;
    await printImage(image.absolutePath, imgPrinter, imgCopies);
  }

  for (const doc of documents) {
    docJobs.push({
      path: doc.absolutePath,
      copies: doc.customOverride?.copies ?? copies,
      printer: doc.customOverride?.printer ?? printer,
      duplex: doc.customOverride?.duplex ?? duplex,
      // ✨ سحب نطاق الصفحات الممرر من الفرونت إند
      startPage: doc.customOverride?.startPage ?? null,
      endPage: doc.customOverride?.endPage ?? null
    });
  }

  if (documents.length > 0 && useSeparator) {
    const firstDoc = docJobs[0];
    const leadingBlank = await createBlankPage();
    await printDocumentWithGhostscript(leadingBlank, firstDoc.printer, 1, firstDoc.duplex);
    fs.unlink(leadingBlank).catch(() => { });
  }

  for (const job of docJobs) {
    await printDocumentWithGhostscript(job.path, job.printer, job.copies, job.duplex, job.startPage, job.endPage);
    if (useSeparator) {
      const trailingBlank = await createBlankPage();
      await printDocumentWithGhostscript(trailingBlank, job.printer, 1, job.duplex);
      fs.unlink(trailingBlank).catch(() => { });
    }
  }

  if (config.beepNotification) process.stdout.write('\u0007');
  const spoolerWaitMs = calcSpoolerWaitMs(images.length, imageCopiesCount, docJobs);
  setTimeout(async () => { await cleanupCurrentCustomerOrderDir(); }, spoolerWaitMs);
}

// ✨ إضافة دالة البحث الحية المفقودة لمنع الـ Crash وحل الـ ReferenceError
async function searchChatsLive(query, client) {
  if (!client) return [];
  try {
    const allChats = await client.getChats();
    const cleanQuery = String(query).toLowerCase().trim();

    return allChats
      .filter(c => !c.isGroup && !c.id._serialized.includes('@g.us')) // استبعاد الجروبات تماماً من البحث
      .map(transformRawChat)
      .filter(chat => {
        const nameMatch = (chat.name || '').toLowerCase().includes(cleanQuery);
        const phoneMatch = (chat.number || '').includes(cleanQuery);
        return nameMatch || phoneMatch;
      })
      .slice(0, 20); // حد أقصى 20 نتيجة لأفضل أداء
  } catch (err) {
    console.error('[❌ Search Error]', err.message);
    return [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Session & Event Handlers
// ─────────────────────────────────────────────────────────────────────────────

async function clearAuthSession() {
  await fs.remove(AUTH_DIR).catch(() => { });
  await fs.remove(WEB_CACHE_DIR).catch(() => { });
}

function clearAllSyncTimers() {
  if (readyWatchdog) { clearTimeout(readyWatchdog); readyWatchdog = null; }
  if (syncStatePoll) { clearInterval(syncStatePoll); syncStatePoll = null; }
  if (syncStatusInterval) { clearInterval(syncStatusInterval); syncStatusInterval = null; }
}

function startSyncStatusUpdates() {
  clearAllSyncTimers();
  authenticatedAt = Date.now();
  syncStatusInterval = setInterval(() => {
    if (clientIsReady || isRecoveringSession) { clearInterval(syncStatusInterval); return; }
    console.log(`[ℹ] Syncing with WhatsApp... (${Math.round((Date.now() - authenticatedAt) / 1000)}s)`);
  }, 15000);
}

function startSyncStatePoll(client) {
  syncStatePoll = setInterval(() => {
    if (clientIsReady || isRecoveringSession || activeWhatsAppClient !== client) { clearInterval(syncStatePoll); return; }
    void (async () => {
      try {
        const state = await client.getState();
        if (!state) return;
        if (['UNPAIRED', 'UNPAIRED_IDLE', 'TIMEOUT', 'TOS_BLOCK', 'DEPRECATED_VERSION'].includes(state)) {
          clearInterval(syncStatePoll);
          void recoverFromInvalidSession(state, client);
        }
      } catch (_) { }
    })();
  }, SYNC_STATE_POLL_MS);
}

async function recoverFromInvalidSession(reason, client) {
  if (reason && reason.toString().toLowerCase().match(/print|ghostscript|pdf|printer|mspaint/)) return;
  if (isRecoveringSession) return;

  if (clientIsReady) {
    clearAllSyncTimers();
    await clearAuthSession();
    if (client) await client.destroy().catch(() => { });
    activeWhatsAppClient = null;
    clientIsReady = false;
    currentQrCode = null;
    io.emit('whatsapp_status', { connected: false, qrCode: null });
    setTimeout(() => { createAndStartWhatsAppClient().catch(() => { }); }, 2000);
    return;
  }

  if (sessionRecoveryAttempts >= MAX_SESSION_RECOVERY_ATTEMPTS) return;

  isRecoveringSession = true;
  sessionRecoveryAttempts++;
  clearAllSyncTimers();

  if (client && activeWhatsAppClient === client) await client.destroy().catch(() => { });
  await clearAuthSession();
  clientIsReady = false;
  isRecoveringSession = false;
  setImmediate(() => { createAndStartWhatsAppClient().catch(() => { }); });
}

function buildWhatsAppClientOptions() {
  const executablePath = os.platform() === 'darwin' ? MAC_CHROME_PATH : CHROME_PATH;
  const options = {
    authStrategy: new LocalAuth({ clientId: 'print-bot', dataPath: AUTH_DIR }),
    webVersionCache: { type: 'remote', remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html' },
    bypassCSP: true,
    puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'], timeout: 60000 }
  };
  if (fs.existsSync(executablePath)) options.puppeteer.executablePath = executablePath;
  return options;
}

function attachWhatsAppClientEvents(client) {
  client.on('qr', (qr) => {
    clearAllSyncTimers();
    currentQrCode = qr;
    qrcode.generate(qr, { small: true });
    io.emit('whatsapp_status', { connected: false, qrCode: qr });
  });

  client.on('authenticated', () => {
    currentQrCode = null;
    readyWatchdog = setTimeout(() => { if (!clientIsReady && activeWhatsAppClient === client) void recoverFromInvalidSession('READY_TIMEOUT', client); }, READY_TIMEOUT_MS);
    startSyncStatusUpdates();
    startSyncStatePoll(client);
  });

  client.on('disconnected', (reason) => {
    const detail = reason ? String(reason) : '';
    if (detail.toLowerCase().match(/print|ghostscript|pdf|printer/)) return;
    void recoverFromInvalidSession(detail || 'LOGOUT', client);
  });

  client.on('ready', async () => {
    if (activeWhatsAppClient !== client) return;
    clearAllSyncTimers();
    clientIsReady = true;
    sessionRecoveryAttempts = 0;
    currentQrCode = null;
    console.log('[🚀] Printoo Engine Live Sync Enabled.');
    io.emit('whatsapp_status', { connected: true, qrCode: null });
  });

  // ✨ التحديث اللحظي الذكي والمحكم لمنع سبام الجروبات نهائياً وحماية الـ Network
  client.on('message', async (msg) => {
    const isGroupMessage = msg.isGroup ||
      msg.from.includes('@g.us') ||
      msg.from.includes('@status');

    if (!isGroupMessage) {
      console.log(`[⚡ Live Event] New private message from: ${msg.from}. Emitting update...`);

      let profilePicUrl = null;
      try { profilePicUrl = await client.getProfilePicUrl(msg.from); } catch (_) { }

      io.emit('new_whatsapp_message', {
        chatId: msg.from,
        body: msg.body,
        timestamp: msg.timestamp,
        profilePicUrl: profilePicUrl || ''
      });
    }
  });
}

async function createAndStartWhatsAppClient() {
  const client = new Client(buildWhatsAppClientOptions());
  globalClientReference = client;
  activeWhatsAppClient = client;
  attachWhatsAppClientEvents(client);
  try { await client.initialize(); } catch (err) {
    setTimeout(() => { if (!clientIsReady) createAndStartWhatsAppClient().catch(() => { }); }, 5000);
  }
}

function formatBytes(bytes, decimals = 2) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(decimals < 0 ? 0 : decimals)) + ' ' + sizes[i];
}

// ─────────────────────────────────────────────────────────────────────────────
// Express API Routes (/printoo)
// ─────────────────────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

app.get('/printoo/status', (req, res) => {
  res.json({ success: true, whatsappConnected: clientIsReady, qrCode: clientIsReady ? null : currentQrCode });
});

app.get('/printoo/printers', (req, res) => { res.json({ success: true, printers: printerCache }); });

app.get('/printoo/recent', async (req, res) => {
  if (!clientIsReady || !activeWhatsAppClient) {
    return res.status(503).json({ success: false, error: 'WhatsApp client not ready' });
  }
  try {
    const liveChats = await activeWhatsAppClient.getChats();
    const sortedChats = liveChats
      .filter(c => !c.isGroup && !c.id._serialized.includes('@g.us')) // حماية إضافية ضد الجروبات
      .map(transformRawChat)
      .sort((a, b) => b.lastMessageTimestamp - a.lastMessageTimestamp)
      .slice(0, 15);

    const results = await Promise.all(sortedChats.map(async (chat) => {
      let profilePicUrl = null;
      try { profilePicUrl = await activeWhatsAppClient.getProfilePicUrl(chat.id); } catch (_) { }
      return {
        id: chat.id,
        name: chat.name,
        number: chat.number,
        displayPhone: chat.displayPhone,
        relativeTime: getRelativeTime(chat.lastMessageTimestamp),
        profilePicUrl: profilePicUrl || ''
      };
    }));

    res.json({ success: true, results });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ✨ الـ API المحدث للبحث لدعم إرجاع صور البروفايل (Profile Pictures)
app.get('/printoo/search', async (req, res) => {
    const { q } = req.query;
    if (!q) return res.status(400).json({ success: false, error: 'Missing query parameter' });
    
    if (!clientIsReady || !activeWhatsAppClient) {
        return res.status(503).json({ success: false, error: 'WhatsApp client not ready' });
    }

    try {
        const matchedChats = await searchChatsLive(q, activeWhatsAppClient);
        
        // 🔥 سحب صور البروفايل لكل نتائج البحث بالتوازي لضمان أقصى سرعة
        const results = await Promise.all(matchedChats.map(async (m) => {
            let profilePicUrl = null;
            try { 
                // طلب الصورة مباشرة من سيرفرات واتساب
                profilePicUrl = await activeWhatsAppClient.getProfilePicUrl(m.id); 
            } catch (_) {}
            
            return { 
                id: m.id, 
                name: m.name, 
                number: m.number, 
                displayPhone: m.displayPhone, 
                relativeTime: getRelativeTime(m.lastMessageTimestamp),
                profilePicUrl: profilePicUrl || '' // ✨ إضافة الفيلد ده عشان الفلاتر يقرأه
            };
        }));

        res.json({ success: true, results });
    } catch (error) {
        console.error('[❌ Search Route Error]', error.message);
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/printoo/fetch-media', async (req, res) => {
  try {
    const { chatId, daysLookback = 0 } = req.body;
    if (!chatId) return res.status(400).json({ success: false, error: 'Missing chatId' });
    if (!clientIsReady || !activeWhatsAppClient) return res.status(503).json({ success: false, error: 'Client not ready' });

    const chat = await activeWhatsAppClient.getChatById(chatId);
    if (!chat) return res.status(404).json({ success: false, error: 'Chat not found' });

    const orderDir = await prepareCustomerOrderDir(chatId);
    const { images, docs } = await downloadMediaInRange(chat, orderDir, daysLookback);

    const documents = await Promise.all(docs.map(async (docObj) => {
      const stats = fs.statSync(docObj.absolutePath);
      return {
        filename: path.basename(docObj.absolutePath),
        absolutePath: docObj.absolutePath,
        pages: path.extname(docObj.absolutePath).toLowerCase() === '.pdf' ? await getPdfPageCount(docObj.absolutePath) : 1,
        sizeBytes: stats.size,
        sizeFormatted: formatBytes(stats.size),
        originalType: docObj.originalType
      };
    }));

    const imagesFormatted = images.map(imgObj => {
      const stats = fs.statSync(imgObj.absolutePath);
      return {
        filename: path.basename(imgObj.absolutePath),
        absolutePath: imgObj.absolutePath,
        sizeBytes: stats.size,
        sizeFormatted: formatBytes(stats.size),
        originalType: imgObj.originalType
      };
    });

    res.json({ success: true, customerFolder: orderDir, documents, images: imagesFormatted });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/printoo/print', (req, res) => {
  try {
    const { printer, copies = 1, duplex = 'simplex', blankPageSeparator, files, customerFolder } = req.body;
    if (!printer || !files || files.length === 0) return res.status(400).json({ success: false, error: 'Invalid data' });

    const useSeparator = blankPageSeparator !== undefined ? blankPageSeparator : config.blankPageSeparator;
    const images = files.filter(f => f.type === 'image');
    const documents = files.filter(f => f.type === 'document');

    // 🔥 دفع المهمة لطابور better-queue لضمان التتابع ومعالجة الـ Range المخصص
    printQueue.push({
      images,
      documents,
      printer,
      copies,
      duplex,
      useSeparator,
      customerFolder
    });

    res.json({ success: true, message: 'Print job added to queue successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/printoo/clear', async (req, res) => {
  try { await fs.emptyDir(TEMP_DIR); res.json({ success: true }); } catch (error) { res.status(500).json({ success: false }); }
});

app.post('/printoo/logout', async (req, res) => {
  try {
    if (activeWhatsAppClient) await activeWhatsAppClient.destroy().catch(() => { });
    await clearAuthSession();
    clientIsReady = false; activeWhatsAppClient = null; currentQrCode = null;
    setTimeout(() => { createAndStartWhatsAppClient().catch(() => { }); }, 2000);
    res.json({ success: true });
  } catch (error) { res.status(500).json({ success: false }); }
});

io.on('connection', (socket) => {
  console.log(`[🔌 Socket] Client connected: ${socket.id}`);
  socket.emit('whatsapp_status', { connected: clientIsReady, qrCode: clientIsReady ? null : currentQrCode });
});

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────
async function bootstrap() {
  printerCache = await detectPrinters();
  await loadConfig();
  await fs.ensureDir(TEMP_DIR);
  startGarbageCollector(); // ✨ تشغيل منظف الملفات الدوري
  createAndStartWhatsAppClient().catch(() => { });

  // 🔥 تشغيل الـ server (بدل app.listen) عشان الـ WebSockets تشتغل صح
  server.listen(PORT, () => { console.log(`[✅] Printoo Master Server running on http://localhost:${PORT}`); });
}

bootstrap().catch(() => { });