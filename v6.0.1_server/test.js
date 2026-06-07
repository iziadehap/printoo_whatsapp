// test.js - Complete API Testing Script
// Run with: node test.js

const axios = require('axios');

const API_BASE_URL = 'http://localhost:3000/api';
let TEST_CHAT_ID = null; // Will be auto-filled from search
let TEST_PRINTER = null; // Will be auto-filled from printers list

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  magenta: '\x1b[35m'
};

function log(color, ...args) {
  console.log(color, ...args, colors.reset);
}

function printSection(title) {
  console.log('\n' + '='.repeat(60));
  log(colors.bright + colors.cyan, `📌 ${title}`);
  console.log('='.repeat(60));
}

function printSuccess(message) {
  log(colors.green, `✅ ${message}`);
}

function printError(message) {
  log(colors.red, `❌ ${message}`);
}

function printInfo(message) {
  log(colors.blue, `ℹ️ ${message}`);
}

function printWarning(message) {
  log(colors.yellow, `⚠️ ${message}`);
}

async function testEndpoint(method, endpoint, data = null, description) {
  try {
    const url = `${API_BASE_URL}${endpoint}`;
    let response;
    
    if (method === 'GET') {
      response = await axios.get(url);
    } else {
      response = await axios.post(url, data);
    }
    
    if (response.data.success) {
      printSuccess(`${description} - Status: ${response.status}`);
      return response.data;
    } else {
      printError(`${description} - Failed: ${response.data.error}`);
      return null;
    }
  } catch (error) {
    if (error.response) {
      printError(`${description} - Error ${error.response.status}: ${error.response.data.error || error.message}`);
    } else if (error.request) {
      printError(`${description} - No response from server. Is the server running?`);
    } else {
      printError(`${description} - ${error.message}`);
    }
    return null;
  }
}

async function testStatus() {
  printSection('Testing GET /api/status');
  const result = await testEndpoint('GET', '/status', null, 'Get WhatsApp status');
  
  if (result) {
    if (result.whatsappConnected) {
      printSuccess(`WhatsApp is CONNECTED and ready!`);
    } else if (result.qrCode) {
      printWarning(`WhatsApp NOT connected. QR code available - scan with WhatsApp mobile`);
      printInfo(`QR Code length: ${result.qrCode.length} characters`);
    } else {
      printWarning(`WhatsApp NOT connected. Waiting for authentication...`);
    }
  }
  return result;
}

async function testPrinters() {
  printSection('Testing GET /api/printers');
  const result = await testEndpoint('GET', '/printers', null, 'Get system printers');
  
  if (result && result.printers) {
    printSuccess(`Found ${result.printers.length} printer(s):`);
    result.printers.forEach((printer, index) => {
      console.log(`   ${index + 1}. ${printer}`);
    });
    
    // Set first printer as test printer
    if (result.printers.length > 0) {
      TEST_PRINTER = result.printers[0];
      printInfo(`Test printer selected: "${TEST_PRINTER}"`);
    }
  }
  return result;
}

async function testSearch(query) {
  printSection(`Testing GET /api/search?q=${query}`);
  const result = await testEndpoint('GET', `/search?q=${encodeURIComponent(query)}`, null, `Search for "${query}"`);
  
  if (result && result.results) {
    printSuccess(`Found ${result.results.length} chat(s):`);
    result.results.forEach((chat, index) => {
      console.log(`   ${index + 1}. ${chat.name || 'No name'} - ${chat.displayPhone || chat.number}`);
      console.log(`      ID: ${chat.id}`);
      console.log(`      Last message: ${chat.relativeTime} ago`);
      
      // Store first chat ID for testing
      if (index === 0 && !TEST_CHAT_ID) {
        TEST_CHAT_ID = chat.id;
        printInfo(`Test chat selected: ${chat.id}`);
      }
    });
  }
  return result;
}

async function testFetchMedia(chatId, daysLookback = 0) {
  printSection(`Testing POST /api/fetch-media (daysLookback: ${daysLookback})`);
  
  if (!chatId) {
    printError('No chat ID available. Run search test first.');
    return null;
  }
  
  const result = await testEndpoint('POST', '/fetch-media', {
    chatId: chatId,
    daysLookback: daysLookback
  }, `Fetch media from chat (last ${daysLookback === 0 ? 'today only' : `${daysLookback} days`})`);
  
  if (result) {
    printSuccess(`Files downloaded to: ${result.customerFolder}`);
    
    if (result.images && result.images.length > 0) {
      printInfo(`📸 Images found: ${result.images.length}`);
      result.images.forEach((img, idx) => {
        console.log(`   ${idx + 1}. ${img.filename}`);
      });
    } else {
      printWarning('No images found in selected date range');
    }
    
    if (result.documents && result.documents.length > 0) {
      printInfo(`📄 Documents found: ${result.documents.length}`);
      result.documents.forEach((doc, idx) => {
        console.log(`   ${idx + 1}. ${doc.filename} (${doc.pages} pages)`);
      });
    } else {
      printWarning('No documents found in selected date range');
    }
    
    return result;
  }
  return null;
}

async function testToggleSeparator(enabled) {
  printSection(`Testing POST /api/config/separator (enabled: ${enabled})`);
  const result = await testEndpoint('POST', '/config/separator', { enabled }, `${enabled ? 'Enable' : 'Disable'} blank page separator`);
  
  if (result) {
    printSuccess(`Blank page separator is now: ${result.blankPageSeparator ? 'ON' : 'OFF'}`);
  }
  return result;
}

async function testPrint(printer, files) {
  printSection('Testing POST /api/print');
  
  if (!printer) {
    printError('No printer available. Run printers test first.');
    return null;
  }
  
  if (!files || files.length === 0) {
    printWarning('No files to print. Run fetch-media test first to download files.');
    return null;
  }
  
  const printData = {
    printer: printer,
    copies: 1,
    duplex: 'simplex',
    blankPageSeparator: true,
    files: files.map(f => ({
      absolutePath: f.absolutePath,
      type: f.type
    }))
  };
  
  printInfo(`Printing ${files.length} file(s) to "${printer}"`);
  
  const result = await testEndpoint('POST', '/print', printData, 'Print files');
  
  if (result) {
    printSuccess('Print jobs spooled successfully!');
  }
  return result;
}

async function testFlush() {
  printSection('Testing POST /api/flush');
  const result = await testEndpoint('POST', '/flush', null, 'Clear temp cache');
  
  if (result) {
    printSuccess('Temporary files cleared successfully');
  }
  return result;
}

async function runAllTests() {
  console.clear();
  log(colors.bright + colors.magenta, `
╔════════════════════════════════════════════════════════════╗
║     WhatsApp Printing API - Complete Test Suite          ║
║                    v1.0 - Local Testing                  ║
╚════════════════════════════════════════════════════════════╝
  `);
  
  printInfo(`API Base URL: ${API_BASE_URL}`);
  printInfo(`Starting tests at: ${new Date().toLocaleString()}`);
  
  // 1. Test Status
  const status = await testStatus();
  if (!status || !status.whatsappConnected) {
    printError('\n⚠️ WhatsApp is not connected!');
    printInfo('Please scan the QR code from the server terminal first.');
    printInfo('Then run this test again.\n');
    return;
  }
  
  // 2. Test Printers
  const printers = await testPrinters();
  if (!printers || printers.printers.length === 0) {
    printError('No printers detected. Cannot continue with print tests.');
    return;
  }
  
  // 3. Test Search (try different queries)
  await testSearch('a'); // Search for any contact with 'a'
  
  if (!TEST_CHAT_ID) {
    await testSearch('1'); // Try numeric search
  }
  
  if (!TEST_CHAT_ID) {
    printError('Could not find any chats. Please ensure you have WhatsApp chats.');
    return;
  }
  
  // 4. Test Fetch Media (today only)
  const mediaToday = await testFetchMedia(TEST_CHAT_ID, 0);
  
  // 5. Test Fetch Media (last 7 days)
  await testFetchMedia(TEST_CHAT_ID, 7);
  
  // 6. Test Toggle Separator
  await testToggleSeparator(false);
  await testToggleSeparator(true);
  
  // 7. Test Print (if files were found)
  if (mediaToday && (mediaToday.images.length > 0 || mediaToday.documents.length > 0)) {
    const filesToPrint = [];
    
    // Add images
    if (mediaToday.images.length > 0) {
      filesToPrint.push({
        absolutePath: mediaToday.images[0].absolutePath,
        type: 'image'
      });
      printInfo(`Found test image: ${mediaToday.images[0].filename}`);
    }
    
    // Add documents
    if (mediaToday.documents.length > 0) {
      filesToPrint.push({
        absolutePath: mediaToday.documents[0].absolutePath,
        type: 'document'
      });
      printInfo(`Found test document: ${mediaToday.documents[0].filename}`);
    }
    
    if (filesToPrint.length > 0) {
      await testPrint(TEST_PRINTER, filesToPrint);
    } else {
      printWarning('No files available to test printing');
    }
  } else {
    printWarning('No media files found in recent chats to test printing');
    printInfo('Send a test image or PDF to a WhatsApp chat and try again.');
  }
  
  // 8. Test Flush (cleanup)
  await testFlush();
  
  // Final summary
  console.log('\n' + '='.repeat(60));
  log(colors.bright + colors.green, '🎉 TEST SUITE COMPLETED!');
  console.log('='.repeat(60));
  printInfo(`WhatsApp Status: ${status?.whatsappConnected ? 'Connected ✅' : 'Disconnected ❌'}`);
  printInfo(`Printers Available: ${printers?.printers.length || 0}`);
  printInfo(`Chats Found: ${TEST_CHAT_ID ? 'Yes ✅' : 'No ❌'}`);
  printInfo(`API Server: Running on ${API_BASE_URL}`);
  console.log('\n');
}

// Run tests with error handling
runAllTests().catch(error => {
  printError(`Test suite failed: ${error.message}`);
  printInfo('Make sure the server is running: npm start or node server.js');
  process.exit(1);
});