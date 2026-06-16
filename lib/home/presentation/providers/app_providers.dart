import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printoo_whatsapp/home/domain/entities/printer_shourtcut.dart';
import 'package:printoo_whatsapp/home/domain/repositories/app_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../data/repositories/app_repository_impl.dart';
import '../../domain/entities/app_status.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/print_job_file.dart';

Future<void> init(WidgetRef ref) async {
  await getFromCashGlobalCopies(ref);
  ref.read(socketProvider); // Initialize WebSocket connection!
}

// Repository Provider
final appRepositoryProvider = Provider<AppRepository>((ref) {
  return AppRepositoryImpl();
});

// Status Notifier
class StatusNotifier extends StateNotifier<AppStatus> {
  final AppRepository _repository;
  final Ref _ref;

  StatusNotifier(this._repository, this._ref) : super(const AppStatus()) {
    _startPolling();
  }

  Timer? _timer;

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final printers = _ref.read(printersProvider);
      final needPrinters = printers.isEmpty;
      final needStatus = !state.whatsappConnected;

      if (needStatus || needPrinters) {
        try {
          debugPrint('[Status] Polling check...');
          final status = await _repository.getStatus();
          debugPrint('[Status] Status received: ${status.whatsappConnected}');
          state = status;

          if (needPrinters) {
            _ref.read(printersProvider.notifier).refresh();
          }
        } catch (e) {
          debugPrint('[Status] Polling failed: $e');
        }
      }
    });
  }

  void updateStatus(AppStatus status) {
    state = status;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final statusProvider = StateNotifierProvider<StatusNotifier, AppStatus>((ref) {
  final repository = ref.watch(appRepositoryProvider);
  return StatusNotifier(repository, ref);
});

// Printers Notifier
class PrintersNotifier extends StateNotifier<List<String>> {
  final AppRepository _repository;
  final Ref _ref;

  PrintersNotifier(this._repository, this._ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final currentPrinters = state;
      final currentIndex = _ref.read(selectedPrinterIndexProvider);
      String? oldActivePrinterName;
      if (currentIndex >= 0 && currentIndex < currentPrinters.length) {
        oldActivePrinterName = currentPrinters[currentIndex];
      }

      final list = await _repository.getPrinters();
      state = list;
      debugPrint(
        '[PrintersNotifier] Loaded ${state.length} printer(s): $state',
      );

      if (oldActivePrinterName != null && !list.contains(oldActivePrinterName)) {
        _ref.read(selectedPrinterIndexProvider.notifier).state = 0;
        debugPrint(
          '[PrintersNotifier] Reset active printer to default (index 0) because "$oldActivePrinterName" is offline.',
        );
      } else if (list.isNotEmpty && (currentIndex < 0 || currentIndex >= list.length)) {
        _ref.read(selectedPrinterIndexProvider.notifier).state = 0;
      }
    } catch (e, stack) {
      debugPrint('[PrintersNotifier] Failed to load printers: $e');
      debugPrint('  → stack: $stack');
      state = [];
    }
  }

  Future<void> refresh() async {
    await _load();
  }
}

final printersProvider = StateNotifierProvider<PrintersNotifier, List<String>>((
  ref,
) {
  final repository = ref.watch(appRepositoryProvider);
  return PrintersNotifier(repository, ref);
});

// Printer Selection Provider
final selectedPrinterIndexProvider = StateProvider<int>((ref) => 0);
final savedPrinterShortcutsProvider = StateProvider<List<PrinterShourtcut>?>(
  (ref) => null,
);
final activePrinterProvider = StateProvider<String?>((ref) {
  final printers = ref.watch(printersProvider);
  final index = ref.watch(selectedPrinterIndexProvider);
  if (index < 0 || index >= printers.length) return null;
  return printers[index];
});
Future<void> selectPrinter(WidgetRef ref, int number) async {
  final repository = ref.read(appRepositoryProvider);

  // 1. نجبر التطبيق دائماً على جلب أحدث البيانات المسجلة بداخل الـ Hive لمنع قراءة كاش قديم
  try {
    final freshData = await repository.getSavedPrinterShortcuts();
    // تحديث الـ Provider الأساسي لكي تشعر به شاشة الـ Settings وأي مكان آخر فوراً
    ref.read(savedPrinterShortcutsProvider.notifier).state = freshData;
  } catch (e) {
    debugPrint('[selectPrinter] Error fetching fresh shortcuts: $e');
    // إذا حدث خطأ، تأكد من عدم ترك الـ state فارغة تماماً لكي لا يعلق الأبليكيشن
    if (ref.read(savedPrinterShortcutsProvider) == null) {
      ref.read(savedPrinterShortcutsProvider.notifier).state = [];
    }
  }

  // جلب البيانات المحدثة الآن من الـ State
  final currentShortcuts = ref.read(savedPrinterShortcutsProvider) ?? [];

  // إذا كانت الضغطة قادمة من شاشة الإعدادات لمجرد التحديث المبدئي (رقم -1)، نكتفي بالجلب فقط ونخرج
  if (number == -1) return;

  // 2. البحث عن الطابعة المرتبطة برقم الاختصار المضغوط
  for (var shortcut in currentShortcuts) {
    if (shortcut.printerNumber == number) {
      final printers = ref.read(printersProvider);
      final printerIndex = printers.indexOf(shortcut.printerName);

      // التأكد من أن الطابعة متواجدة في قائمة طابعات الماك الحالية
      if (printerIndex != -1) {
        // 🌟 السطر السحري: تحديث الـ Index المسؤول عن تغيير الـ Dropdown والـ UI فوراً!
        ref.read(selectedPrinterIndexProvider.notifier).state = printerIndex;

        debugPrint(
          '[selectPrinter] Switched successfully to printer: ${shortcut.printerName} (Index: $printerIndex)',
        );
      } else {
        debugPrint(
          '[selectPrinter] Printer "${shortcut.printerName}" found in shortcuts but layout claims it is offline.',
        );
      }
      break;
    }
  }
}

Future<void> savePrinterShortcut(
  WidgetRef ref,
  List<PrinterShourtcut> printerShourtcuts,
) async {
  final repository = ref.read(appRepositoryProvider);

  ref.read(savedPrinterShortcutsProvider.notifier).state = printerShourtcuts;

  await repository.putPrinterFromCash(printerShourtcuts);
}

Future<void> clearCash(WidgetRef ref) async {
  final repository = ref.read(appRepositoryProvider);

  await repository.clear();
}

// Search Notifier
class SearchNotifier extends StateNotifier<AsyncValue<List<Customer>>> {
  final AppRepository _repository;

  SearchNotifier(this._repository) : super(const AsyncValue.data([]));

  Timer? _debounce;

  void search(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      state = const AsyncValue.loading();
      try {
        final results = await _repository.searchCustomers(query);
        debugPrint(
          '[SearchNotifier] Found ${results.length} result(s) for "$query"',
        );
        state = AsyncValue.data(results);
      } catch (e, stack) {
        debugPrint('[SearchNotifier] Search failed for "$query": $e');
        debugPrint('  → stack: $stack');
        state = AsyncValue.error(e, stack);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, AsyncValue<List<Customer>>>((ref) {
      final repository = ref.watch(appRepositoryProvider);
      return SearchNotifier(repository);
    });

// Recent Chats Notifier
class RecentChatsNotifier extends StateNotifier<AsyncValue<List<Customer>>> {
  final AppRepository _repository;

  RecentChatsNotifier(this._repository) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final results = await _repository.getRecentChats();
      state = AsyncValue.data(results);
    } catch (e, stack) {
      debugPrint('[RecentChatsNotifier] Failed to load recent chats: $e');
      state = AsyncValue.error(e, stack);
    }
  }
}

final recentChatsProvider =
    StateNotifierProvider<RecentChatsNotifier, AsyncValue<List<Customer>>>((
      ref,
    ) {
      final repository = ref.watch(appRepositoryProvider);
      return RecentChatsNotifier(repository);
    });

// Socket Provider
final socketProvider = Provider<IO.Socket>((ref) {
  debugPrint(
    '[Socket] Initializing socket connection to http://localhost:3000...',
  );
  final socket = IO.io(
    'http://localhost:3000',
    IO.OptionBuilder().setTransports(['websocket']).enableAutoConnect().build(),
  );

  socket.onConnect((_) {
    debugPrint('[Socket] Connected to server');
  });

  socket.onDisconnect((_) {
    debugPrint('[Socket] Disconnected from server');
  });

  socket.on('new_whatsapp_message', (data) {
    debugPrint('[Socket] new_whatsapp_message event: $data');
    // Refresh recent chats list automatically
    ref.read(recentChatsProvider.notifier).load();

    // Auto-fetch active customer media if they sent the message
    final activeCustomer = ref.read(selectedCustomerProvider);
    if (activeCustomer != null &&
        data != null &&
        data['chatId'] == activeCustomer.id) {
      final days = ref.read(daysLookbackProvider);
      ref.read(mediaProvider.notifier).fetch(activeCustomer.id, days);
    }
  });

  socket.on('whatsapp_status', (data) {
    debugPrint('[Socket] whatsapp_status event: $data');
    if (data != null) {
      final connected = data['connected'] ?? false;
      final qrCode = data['qrCode'];
      ref
          .read(statusProvider.notifier)
          .updateStatus(
            AppStatus(whatsappConnected: connected, qrCode: qrCode),
          );
    }
  });

  ref.onDispose(() {
    socket.dispose();
  });

  return socket;
});

// Selected Customer Provider
final selectedCustomerProvider = StateProvider<Customer?>((ref) => null);

// Days Lookback Provider
final daysLookbackProvider = StateProvider<int>((ref) => 1);

// Customer Folder Provider
final customerFolderProvider = StateProvider<String?>((ref) => null);

// Media Notifier
class MediaNotifier extends StateNotifier<AsyncValue<List<PrintJobFile>>> {
  final AppRepository _repository;
  final Ref _ref;

  MediaNotifier(this._repository, this._ref) : super(const AsyncValue.data([]));

  Future<void> fetch(String chatId, dynamic daysLookback) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.fetchMedia(chatId, daysLookback);

      // Initialize files with active global settings
      final defaultCopies = _ref.read(globalCopiesProvider);
      final defaultDuplex = _ref.read(globalDuplexProvider)
          ? 'duplex'
          : 'simplex';

      final updatedFiles = result.files
          .map((f) => f.copyWith(copies: defaultCopies, duplex: defaultDuplex))
          .toList();

      _ref.read(customerFolderProvider.notifier).state = result.customerFolder;
      _ref.read(logMessageProvider.notifier).state =
          'INFO: Retrieved ${updatedFiles.length} file(s) for chatId=$chatId. READY.';
      state = AsyncValue.data(updatedFiles);
    } catch (e, stack) {
      debugPrint(
        '[MediaNotifier.fetch] Error fetching media for chatId=$chatId: $e',
      );
      debugPrint('  → stack: $stack');
      _ref.read(customerFolderProvider.notifier).state = null;
      _ref.read(logMessageProvider.notifier).state =
          'ERROR: Failed to fetch media for chatId=$chatId — $e';
      state = AsyncValue.error(e, stack);
    }
  }

  void updateFile(String id, PrintJobFile updated) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data(list.map((f) => f.id == id ? updated : f).toList());
  }

  void toggleSelected(String id) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data(
      list
          .map((f) => f.id == id ? f.copyWith(selected: !f.selected) : f)
          .toList(),
    );
  }

  // Smart Toggle for Images
  void toggleAllImages() {
    final list = state.valueOrNull;
    if (list == null) return;

    final images = list.where((f) => f.type == 'image');
    if (images.isEmpty) return;

    // Check if every single image is currently checked
    final areAllImagesSelected = images.every((f) => f.selected);

    state = AsyncValue.data(
      list.map((f) {
        if (f.type == 'image') {
          // If all were selected, uncheck them. Otherwise, check them all.
          return f.copyWith(selected: !areAllImagesSelected);
        }
        return f;
      }).toList(),
    );
  }

  // Smart Toggle for Documents/Files (Note: Your type badge uses 'document' in the UI code)
  void toggleAllDocuments() {
    final list = state.valueOrNull;
    if (list == null) return;

    final docs = list.where((f) => f.type == 'document');
    if (docs.isEmpty) return;

    final areAllDocsSelected = docs.every((f) => f.selected);

    state = AsyncValue.data(
      list.map((f) {
        if (f.type == 'document') {
          return f.copyWith(selected: !areAllDocsSelected);
        }
        return f;
      }).toList(),
    );
  }

  // Smart Toggle for Everything (Deselect All / Select All Master Button)
  void toggleAllFiles() {
    final list = state.valueOrNull;
    if (list == null) return;
    if (list.isEmpty) return;

    final areAllSelected = list.every((f) => f.selected);

    state = AsyncValue.data(
      list.map((f) => f.copyWith(selected: !areAllSelected)).toList(),
    );
  }

  void updateGlobalCopies(int copies) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data(
      list.map((f) => f.copyWith(copies: copies)).toList(),
    );
  }

  void updateGlobalDuplex(String duplex) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncValue.data(
      list.map((f) => f.copyWith(duplex: duplex)).toList(),
    );
  }
}

final mediaProvider =
    StateNotifierProvider<MediaNotifier, AsyncValue<List<PrintJobFile>>>((ref) {
      final repository = ref.watch(appRepositoryProvider);
      return MediaNotifier(repository, ref);
    });

Future<void> getFromCashGlobalCopies(WidgetRef ref) async {
  final repository = ref.watch(appRepositoryProvider);
  final copyCount = await repository.getSavedCopyCount();
  if (copyCount != 0) {
    ref.read(globalCopiesProvider.notifier).state = copyCount;
  }
}

// Global Settings Providers
final blankPageSeparatorProvider = StateProvider<bool>((ref) => true);
final globalCopiesProvider = StateProvider<int>((ref) => 1);
final globalDuplexProvider = StateProvider<bool>((ref) => true);
final logMessageProvider = StateProvider<String>(
  (ref) => 'INFO: Retrieved 124 files for +20...5543 successfully. READY.',
);

// Thumbnail Scale Provider
final thumbnailScaleProvider = StateProvider<double>((ref) => 90.0);
