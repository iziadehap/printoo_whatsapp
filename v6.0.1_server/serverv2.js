'use strict';

const express = require('express');
const cors = require('cors');
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const path = require('path');
const fs = require('fs-extra');
const { exec } = require('child_process');
const os = require('os');
const { PDFParse } = require('pdf-parse');
const PDFDocument = require('pdfkit');

const app = express();
const PORT = process.env.PORT || 3000;

// ─────────────────────────────────────────────────────────────────────────────
// Constants & Paths
// ─────────────────────────────────────────────────────────────────────────────

const TEMP_DIR = path.join(__dirname, 'temp');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const AUTH_DIR = path.join(__dirname, '.wwebjs_auth');
const WEB_CACHE_DIR = path.join(__dirname, '.wwebjs_cache');

// مسارات ويندوز الأصلية (ممنوع تعديلها)
const CHROME_PATH = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const GS_DEFAULT_PATH = 'C:\\Program Files\\gs\\gs10.03.1\\bin\\gswin64c.exe';

// مسار الماك للاختبار
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
        if (os.platform() === 'darwin') {
            return resolve(['Mac_Virtual_Printer', 'PDF_Dummy_Printer']);
        }
        exec(
            'powershell -NoProfile -Command "Get-Printer | Select-Object -ExpandProperty Name"',
            (err, stdout) => {
                if (err || !stdout) return resolve([]);
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

// دالة البحث الحية المحدثة لإصلاح مشكلة الـ LID والأسماء الفارغة
async function searchChatsLive(query, client) {
    const cleanQuery = query.toLowerCase().replace(/[^0-9a-z]/g, '').trim();
    if (!cleanQuery) return [];

    if (!client || !clientIsReady) {
        console.warn('[⚠️] Cannot search: WhatsApp client is not fully ready.');
        return [];
    }

    console.log(`[🔎] Executing live search for query: "${query}"`);
    const isNumericSearch = /^\d+$/.test(cleanQuery);

    try {
        // 1. جلب قائمة المحادثات الحية
        const liveChats = await client.getChats();
        let formattedChats = liveChats.filter(c => !c.isGroup).map(transformRawChat);

        // 2. الفلترة المبدئية
        let matches = formattedChats.filter((c) => {
            const nameClean = (c.name || '').toLowerCase().replace(/[+\s]/g, '');
            const numClean = (c.number || '');
            if (isNumericSearch) {
                return numClean.endsWith(cleanQuery) || numClean.includes(cleanQuery);
            }
            return nameClean.includes(cleanQuery);
        });

        // 3. الحل الذكي: لو البحث برقم هاتف (سواء رجع بـ اسم فاضي أو مالقينهوش خالص بسبب الـ LID)
        if (isNumericSearch) {
            let formattedJid = cleanQuery;
            if (!formattedJid.endsWith('@c.us')) {
                if (formattedJid.length === 11 && formattedJid.startsWith('01')) {
                    formattedJid = '2' + formattedJid;
                }
                formattedJid = formattedJid + '@c.us'; // الإجبار على الـ JID الأصلي لقراءة الـ Contacts
            }

            // لو النتيجة راجعة بـ LID واسم فاضي، أو مش موجودة خالص، بنجيبها مباشرة بـ c.us
            if (matches.length === 0 || (matches.length > 0 && !matches[0].name)) {
                try {
                    console.log(`[🔎] Resolving/Fetching via absolute standard JID to extract contact name: ${formattedJid}`);
                    const rawChat = await client.getChatById(formattedJid);
                    if (rawChat && !rawChat.isGroup) {
                        const resolvedChat = transformRawChat(rawChat);

                        // لو نجح في جلب الاسم بالـ c.us، نستبدل النتيجة الفاضية القديمة
                        if (matches.length > 0) {
                            matches = [resolvedChat];
                        } else {
                            matches.push(resolvedChat);
                        }
                    }
                } catch (_) {
                    // يتخطى بسلام لو الرقم مش مسجل
                }
            }
        }

        return matches.sort((a, b) => b.lastMessageTimestamp - a.lastMessageTimestamp);
    } catch (err) {
        console.error('[❌] Error during live search execution:', err.message);
        return [];
    }
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
    return ((targetDate - msgDate) / (1000 * 60 * 60 * 24)) <= daysLookback;
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
    try {
        await fs.remove(currentOrderDir);
    } catch (_) { }
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

    if (filteredMessages.length === 0) return { images: [], docs: [] };

    const images = [];
    const docs = [];

    for (const [i, msg] of filteredMessages.entries()) {
        try {
            const media = await msg.downloadMedia();
            if (!media) continue;

            const ext = guessExtension(media.mimetype, media.filename);
            if (!ext || !ALL_EXTS.has(ext)) continue;

            const originalName = media.filename ? path.parse(media.filename).name : `file_${Date.now()}`;
            const filename = `${originalName.replace(/[^\w\s]/gi, '')}_${Date.now()}_${i}.${ext}`;
            const filepath = path.join(downloadDir, filename);

            await fs.writeFile(filepath, Buffer.from(media.data, 'base64'));
            if (IMAGE_EXTS.has(ext)) {
                images.push(filepath);
            } else {
                docs.push(filepath);
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
        await new Promise((resolve) => {
            exec(cmd, () => resolve());
        });
        if (i < copies - 1) await new Promise((r) => setTimeout(r, IMAGE_PRINT_GAP_MS));
    }
}

function printDocumentWithGhostscript(filepath, printer, copies = 1, duplex = 'simplex') {
    return new Promise((resolve) => {
        if (os.platform() === 'darwin') return resolve();
        const gsPath = resolveGhostscriptPath();
        const duplexEntry = duplex === 'duplex' ? '/Duplex true /Tumble false' : '/Duplex false';
        const pageDevice = `<</NumCopies ${copies} ${duplexEntry}>> setpagedevice`;
        const cmd = `"${gsPath}" -dNOPAUSE -dBATCH -dNOSAFER -q -sDEVICE=mswinpr2 -sOutputFile="%printer%${printer.trim()}" -c "${pageDevice}" -f "${filepath}"`;
        exec(cmd, () => resolve());
    });
}

function calcSpoolerWaitMs(imageCount, imageCopies, docJobs) {
    const imageWork = imageCount * imageCopies;
    const docCopySum = docJobs.reduce((sum, j) => sum + j.copies, 0);
    return Math.max(MIN_SPOOLER_WAIT_MS, imageWork * MS_PER_IMAGE_PRINT + docJobs.length * MS_PER_DOC_JOB + docCopySum * 800);
}

async function processPrintJobInBackground(images, documents, printer, copies, duplex, useSeparator) {
    try {
        let docJobs = [];
        let imageCopiesCount = copies;

        for (const image of images) {
            const imgCopies = image.customOverride?.copies ?? copies;
            const imgPrinter = image.customOverride?.printer ?? printer;
            imageCopiesCount = imgCopies;
            console.log(`[🖨️] Processing Image: ${path.basename(image.absolutePath)} x${imgCopies}`);
            await printImage(image.absolutePath, imgPrinter, imgCopies);
        }

        for (const doc of documents) {
            docJobs.push({
                path: doc.absolutePath,
                copies: doc.customOverride?.copies ?? copies,
                printer: doc.customOverride?.printer ?? printer,
                duplex: doc.customOverride?.duplex ?? duplex
            });
        }

        if (documents.length > 0 && useSeparator) {
            const firstDoc = docJobs[0];
            const leadingBlank = await createBlankPage();
            await printDocumentWithGhostscript(leadingBlank, firstDoc.printer, 1, firstDoc.duplex);
        }

        for (const job of docJobs) {
            console.log(`[🖨️] Processing Document: ${path.basename(job.path)} x${job.copies} (${job.duplex})`);
            await printDocumentWithGhostscript(job.path, job.printer, job.copies, job.duplex);
            if (useSeparator) {
                const trailingBlank = await createBlankPage();
                await printDocumentWithGhostscript(trailingBlank, job.printer, 1, job.duplex);
            }
        }

        if (config.beepNotification) process.stdout.write('\u0007');

        const spoolerWaitMs = calcSpoolerWaitMs(images.length, imageCopiesCount, docJobs);
        console.log(`[ℹ️] Spooler finished. Waiting ${Math.ceil(spoolerWaitMs / 1000)}s before folder cleanup...`);
        setTimeout(async () => {
            await cleanupCurrentCustomerOrderDir();
            console.log('[✅] Dynamic customer folder cleaned up successfully.');
        }, spoolerWaitMs);

    } catch (bgError) {
        console.error('[❌] Error inside Background Print Processor:', bgError.message);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Session Management
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
                    return;
                }
                if (state === 'CONNECTED' && (Date.now() - authenticatedAt) > READY_TIMEOUT_MS && !clientIsReady) {
                    clearInterval(syncStatePoll);
                    void recoverFromInvalidSession('CONNECTED_WITHOUT_READY', client);
                }
            } catch (_) { }
        })();
    }, SYNC_STATE_POLL_MS);
}

// ─────────────────────────────────────────────────────────────────────────────
// Rest of Initialization & API
// ─────────────────────────────────────────────────────────────────────────────

function isRecoverableSessionError(reason) {
    if (!reason) return false;
    const text = String(reason).toUpperCase();
    return ['LOGOUT', 'UNPAIRED', 'UNAUTHORIZED', 'UNAUTHENTICATED', 'CONFLICT', 'NOT LOGGED IN', '401', '403', 'READY TIMEOUT', 'STALE SESSION', 'CONNECTED_WITHOUT_READY', 'TARGET CLOSED', 'PROTOCOL ERROR', 'EVALUATION FAILED', 'EXECUTION CONTEXT WAS DESTROYED'].some(p => text.includes(p));
}

function isHardSessionLoss(reason) {
    if (!reason) return false;
    const text = String(reason).toUpperCase();
    return ['LOGOUT', 'UNPAIRED', 'UNAUTHORIZED', 'UNAUTHENTICATED', 'CONFLICT', 'NOT LOGGED IN'].some(p => text.includes(p));
}

async function recoverFromInvalidSession(reason, client) {
    if (isRecoveringSession) return;

    if (clientIsReady) {
        console.warn(`[⚠️] Session invalidated at runtime: ${reason}`);
        clearAllSyncTimers();
        await clearAuthSession();
        if (client) await client.destroy().catch(() => { });
        activeWhatsAppClient = null;
        process.exit(0);
    }

    if (sessionRecoveryAttempts >= MAX_SESSION_RECOVERY_ATTEMPTS) {
        console.error('[❌] Could not restore WhatsApp. Please wipe .wwebjs_auth and restart.');
        process.exit(1);
    }

    isRecoveringSession = true;
    sessionRecoveryAttempts++;
    clearAllSyncTimers();

    if (client && activeWhatsAppClient === client) {
        await client.destroy().catch(() => { });
        activeWhatsAppClient = null;
    }

    await clearAuthSession();
    clientIsReady = false;
    isRecoveringSession = false;

    setImmediate(() => {
        createAndStartWhatsAppClient().catch(() => process.exit(1));
    });
}

function buildWhatsAppClientOptions() {
    const isMac = os.platform() === 'darwin';
    const executablePath = isMac ? MAC_CHROME_PATH : CHROME_PATH;

    const options = {
        authStrategy: new LocalAuth({ clientId: 'print-bot', dataPath: AUTH_DIR }),
        webVersionCache: { type: 'remote', remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html' },
        bypassCSP: true,
        puppeteer: {
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
            timeout: 60000
        }
    };

    if (fs.existsSync(executablePath)) {
        options.puppeteer.executablePath = executablePath;
    }
    return options;
}

function attachWhatsAppClientEvents(client) {
    client.on('qr', (qr) => {
        clearAllSyncTimers();
        currentQrCode = qr;
        qrcode.generate(qr, { small: true });
    });

    client.on('loading_screen', (percent, message) => {
        console.log(`[ℹ] Loading WhatsApp: ${percent}% - ${message || ''}`);
    });

    client.on('change_state', (state) => {
        if (clientIsReady || isRecoveringSession) return;
        if (['UNPAIRED', 'UNPAIRED_IDLE', 'TIMEOUT', 'TOS_BLOCK', 'DEPRECATED_VERSION'].includes(state)) {
            void recoverFromInvalidSession(state, client);
        }
    });

    client.on('authenticated', () => {
        currentQrCode = null;
        console.log('[✅] Authenticated! Syncing...');
        readyWatchdog = setTimeout(() => {
            if (!clientIsReady && !isRecoveringSession && activeWhatsAppClient === client) {
                void recoverFromInvalidSession('READY_TIMEOUT_STALE_SESSION', client);
            }
        }, READY_TIMEOUT_MS);
        startSyncStatusUpdates();
        startSyncStatePoll(client);
    });

    client.on('auth_failure', (msg) => {
        const detail = msg ? String(msg) : 'unknown';
        if (isRecoverableSessionError(detail)) {
            void recoverFromInvalidSession(detail, client);
        } else {
            process.exit(1);
        }
    });

    client.on('disconnected', (reason) => {
        const detail = reason ? String(reason) : '';
        if (isRecoverableSessionError(detail) || isHardSessionLoss(detail)) {
            void recoverFromInvalidSession(detail || 'LOGOUT', client);
        } else {
            process.exit(1);
        }
    });

    client.on('ready', async () => {
        if (activeWhatsAppClient !== client) return;
        clearAllSyncTimers();
        clientIsReady = true;
        sessionRecoveryAttempts = 0;
        currentQrCode = null;
        console.log('[🚀] Printoo Engine is Ready and Live Synchronization is Active.');
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
        const msg = err?.message || String(err);
        if (isRecoverableSessionError(msg)) {
            void recoverFromInvalidSession(msg, client);
        } else {
            throw err;
        }
    }
}
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// ─────────────────────────────────────────────────────────────────────────────
// Express API Routes (/printoo)
// ─────────────────────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

app.use('/printoo', (req, res, next) => {
    console.log(`[📥] Received ${req.method} request on endpoint: /printoo${req.path}`);
    next();
});

app.get('/printoo/status', (req, res) => {
    res.json({
        success: true,
        whatsappConnected: clientIsReady,
        qrCode: clientIsReady ? null : currentQrCode
    });
});

app.get('/printoo/printers', (req, res) => {
    res.json({ success: true, printers: printerCache });
});

app.get('/printoo/search', async (req, res) => {
    const { q } = req.query;
    if (!q || typeof q !== 'string') {
        return res.status(400).json({ success: false, error: 'Missing query parameter "q"' });
    }

    const matchedChats = await searchChatsLive(q, activeWhatsAppClient);

    const results = matchedChats.map(m => ({
        id: m.id,
        name: m.name,
        number: m.number,
        displayPhone: m.displayPhone,
        relativeTime: getRelativeTime(m.lastMessageTimestamp)
    }));
    res.json({ success: true, results });
});
app.post('/printoo/fetch-media', async (req, res) => {
    try {
        const { chatId, daysLookback = 0 } = req.body;
        if (!chatId || typeof chatId !== 'string') {
            return res.status(400).json({ success: false, error: 'Missing or invalid chatId' });
        }
        if (!clientIsReady || !activeWhatsAppClient) {
            return res.status(503).json({ success: false, error: 'WhatsApp client not ready' });
        }

        const chat = await activeWhatsAppClient.getChatById(chatId);
        if (!chat) return res.status(404).json({ success: false, error: 'Chat not found' });

        const orderDir = await prepareCustomerOrderDir(chatId);
        console.log(`[⬇️] Downloading media for chat: ${chat.name || chatId}`);
        const { images, docs } = await downloadMediaInRange(chat, orderDir, daysLookback);

        // معالجة المستندات وإضافة الحجم
        const documents = await Promise.all(docs.map(async (docPath) => {
            const stats = fs.statSync(docPath);
            return {
                filename: path.basename(docPath),
                absolutePath: docPath,
                pages: path.extname(docPath).toLowerCase() === '.pdf' ? await getPdfPageCount(docPath) : 1,
                sizeBytes: stats.size,
                sizeFormatted: formatBytes(stats.size)
            };
        }));

        // معالجة الصور وإضافة الحجم
        const imagesFormatted = images.map(imgPath => {
            const stats = fs.statSync(imgPath);
            return {
                filename: path.basename(imgPath),
                absolutePath: imgPath,
                sizeBytes: stats.size,
                sizeFormatted: formatBytes(stats.size)
            };
        });

        res.json({
            success: true,
            customerFolder: orderDir,
            documents,
            images: imagesFormatted
        });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});
app.post('/printoo/print', (req, res) => {
    try {
        const { printer, copies = 1, duplex = 'simplex', blankPageSeparator, files } = req.body;

        if (!printer || !files || !Array.isArray(files) || files.length === 0) {
            return res.status(400).json({ success: false, error: 'Invalid printer or files data' });
        }

        const useSeparator = blankPageSeparator !== undefined ? blankPageSeparator : config.blankPageSeparator;
        const images = files.filter(f => f.type === 'image');
        const documents = files.filter(f => f.type === 'document');

        console.log(`[🚀] Executing background printing pipeline on printer: ${printer}`);
        processPrintJobInBackground(images, documents, printer, copies, duplex, useSeparator);

        res.json({
            success: true,
            message: 'Print job accepted and running in the background'
        });

    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/printoo/clear', async (req, res) => {
    try {
        await fs.emptyDir(TEMP_DIR);
        res.json({ success: true, message: 'System temp cache cleared successfully' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/printoo/logout', async (req, res) => {
    try {
        if (activeWhatsAppClient) await activeWhatsAppClient.destroy().catch(() => { });
        await clearAuthSession();
        clientIsReady = false;
        activeWhatsAppClient = null;
        currentQrCode = null;
        setTimeout(() => { process.exit(0); }, 1000);
        res.json({ success: true, message: 'Session destroyed, server resetting' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────
async function bootstrap() {
    console.log('\n╔══════════════════════════════════════════╗');
    console.log('║ WhatsApp Retail Terminal API v6.1.0 (T)  ║');
    console.log('╚══════════════════════════════════════════╝\n');

    printerCache = await detectPrinters();
    console.log(`[✅] Detected ${printerCache.length} printer(s)`);

    await loadConfig();
    await fs.ensureDir(TEMP_DIR);

    clientIsReady = false;
    sessionRecoveryAttempts = 0;

    createAndStartWhatsAppClient().catch(() => { });

    app.listen(PORT, () => {
        console.log(`[✅] REST API server running on http://localhost:${PORT}`);
        console.log('[ℹ️] Available endpoints:');
        console.log(`  GET  http://localhost:${PORT}/printoo/status`);
        console.log(`  GET  http://localhost:${PORT}/printoo/printers`);
        console.log(`  GET  http://localhost:${PORT}/printoo/search?q=<query>`);
        console.log(`  POST http://localhost:${PORT}/printoo/fetch-media`);
        console.log(`  POST http://localhost:${PORT}/printoo/print`);
        console.log(`  POST http://localhost:${PORT}/printoo/clear`);
        console.log(`  POST http://localhost:${PORT}/printoo/logout\n`);
    });
}

bootstrap().catch(() => process.exit(1));