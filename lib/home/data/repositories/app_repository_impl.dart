// =============================================================================
// app_repository_impl.dart  (updated)
// Change: printJobs() now forwards startPage / endPage inside customOverride
// for every document file, enabling Ghostscript's -dFirstPage / -dLastPage.
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:printoo_whatsapp/home/domain/entities/media.dart';
import 'package:printoo_whatsapp/home/domain/entities/printer_shourtcut.dart';
import 'package:printoo_whatsapp/home/domain/repositories/app_repository.dart';

import '../../domain/entities/app_status.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/print_job_file.dart';
import '../datasources/api_client.dart';
import 'package:hive_ce/hive_ce.dart';

class AppRepositoryImpl implements AppRepository {
  // ─── Status ──────────────────────────────────────────────────────────────
  Future<AppStatus> getStatus() async {
    try {
      final r = await ApiClient.dio.get('/printoo/status');
      return AppStatus(
        whatsappConnected: r.data['whatsappConnected'] ?? false,
        qrCode: r.data['qrCode'],
      );
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.getStatus] DioException: ${e.message}');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.getStatus] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  // ─── Printers ─────────────────────────────────────────────────────────────
  Future<List<String>> getPrinters() async {
    try {
      final r = await ApiClient.dio.get('/printoo/printers');
      return List<String>.from(r.data['printers'] ?? []);
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.getPrinters] DioException: ${e.message}');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.getPrinters] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  Future<int> getSavedCopyCount() async {
    try {
      var box = await Hive.openBox('copyCount');
      return box.get('copyCount') ?? 0;
    } catch (e) {
      debugPrint('[AppRepository.getSavedCopyCount] error: $e');
      rethrow;
    }
  }

  Future<void> putSavedCopyCount(int count) async {
    try {
      var box = await Hive.openBox('copyCount');
      await box.put('copyCount', count);
    } catch (e) {
      debugPrint('[AppRepository.putSavedCopyCount] error: $e');
      rethrow;
    }
  }

  Future<List<PrinterShourtcut>> getSavedPrinterShortcuts() async {
    try {
      final box = Hive.isBoxOpen('printerShortcuts')
          ? Hive.box<PrinterShourtcut>('printerShortcuts')
          : await Hive.openBox<PrinterShourtcut>('printerShortcuts');
      return box.values.toList();
    } catch (e) {
      debugPrint('[AppRepository.getSavedPrinterShortcuts] error: $e');
      rethrow;
    }
  }

  Future<void> putPrinterFromCash(
    List<PrinterShourtcut> printerShortcuts,
  ) async {
    try {
      final box = Hive.isBoxOpen('printerShortcuts')
          ? Hive.box<PrinterShourtcut>('printerShortcuts')
          : await Hive.openBox<PrinterShourtcut>('printerShortcuts');
      await box.clear();
      await box.addAll(printerShortcuts);
      debugPrint(
        '[AppRepository.putPrinterFromCash] Saved ${printerShortcuts.length} shortcuts successfully.',
      );
    } catch (e) {
      debugPrint('[AppRepository.putPrinterFromCash] error: $e');
      rethrow;
    }
  }

  Future<void> putSavedPrinterShortcuts(
    List<PrinterShourtcut> printerShortcuts,
  ) async {
    try {
      var box = await Hive.openBox('printerShortcuts');
      await box.put('printerShortcuts', printerShortcuts);
    } catch (e) {
      debugPrint('[AppRepository.putSavedPrinterShortcuts] error: $e');
      rethrow;
    }
  }

  // ─── Search ───────────────────────────────────────────────────────────────
  Future<List<Customer>> searchCustomers(String query) async {
    try {
      final r = await ApiClient.dio.get(
        '/printoo/search',
        queryParameters: {'q': query},
      );

      debugPrint('[AppRepository.searchCustomers] Response: ${r.data}');
      debugPrint('-----------------------------------');
      return (r.data['results'] as List? ?? [])
          .map((e) => Customer.fromJson(e))
          .toList();
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.searchCustomers] DioException: ${e.message}');
      debugPrint('  → query  : $query');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.searchCustomers] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  Future<List<Customer>> getRecentChats() async {
    try {
      final r = await ApiClient.dio.get('/printoo/recent');
      return (r.data['results'] as List? ?? [])
          .map((e) => Customer.fromJson(e))
          .toList();
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.getRecentChats] DioException: ${e.message}');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.getRecentChats] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  // ─── Fetch Media ──────────────────────────────────────────────────────────
  Future<MediaFetchResult> fetchMedia(
    String chatId,
    dynamic daysLookback,
  ) async {
    try {
      final r = await ApiClient.dio.post(
        '/printoo/fetch-media',
        data: {'chatId': chatId, 'daysLookback': daysLookback},
      );
      final data = r.data;
      if (data == null) {
        debugPrint('[AppRepository.fetchMedia] Warning: empty response body.');
        return MediaFetchResult(customerFolder: '', files: []);
      }

      final docs = (data['documents'] as List? ?? []).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        map['type'] = 'document';
        return PrintJobFile.fromJson(map);
      }).toList();

      final imgs = (data['images'] as List? ?? []).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        map['type'] = 'image';
        map['pages'] = 1;
        return PrintJobFile.fromJson(map);
      }).toList();

      debugPrint(
        '[AppRepository.fetchMedia] OK — ${docs.length} doc(s), '
        '${imgs.length} image(s) for chatId=$chatId',
      );

      return MediaFetchResult(
        customerFolder: data['customerFolder']?.toString() ?? '',
        files: [...docs, ...imgs],
      );
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.fetchMedia] DioException: ${e.message}');
      debugPrint('  → chatId : $chatId');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.fetchMedia] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  // ─── Print Jobs ───────────────────────────────────────────────────────────
  //
  // UPDATED: `customOverride` now includes `startPage` and `endPage` for
  // document-type files when a custom range was set by the operator.
  // The Node.js backend should pass these to Ghostscript as:
  //   -dFirstPage=<startPage> -dLastPage=<endPage>
  //
  Future<void> printJobs({
    required String printerName,
    required bool blankPageSeparator,
    required List<PrintJobFile> jobs,
  }) async {
    try {
      debugPrint(
        '[AppRepository.printJobs] Sending ${jobs.length} job(s) to "$printerName"',
      );

      await ApiClient.dio.post(
        '/printoo/print',
        data: {
          'printer': printerName,
          'blankPageSeparator': blankPageSeparator,
          'files': jobs.map((j) {
            final override = <String, dynamic>{
              'copies': j.copies,
              'duplex': j.duplex,
            };

            // Attach page-range only for documents with a non-default range
            if (j.type == 'document') {
              final effectiveStart = j.startPage ?? 1;
              final effectiveEnd = j.endPage ?? j.pages;

              // Only send if the operator actually restricted the range
              if (effectiveStart != 1 || effectiveEnd != j.pages) {
                override['startPage'] = effectiveStart;
                override['endPage'] = effectiveEnd;
              }
            }

            return {
              'type': j.type,
              'absolutePath': j.absolutePath,
              'customOverride': override,
            };
          }).toList(),
        },
      );

      debugPrint('[AppRepository.printJobs] Print job accepted by server.');
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.printJobs] DioException: ${e.message}');
      debugPrint('  → printer : $printerName');
      debugPrint('  → status  : ${e.response?.statusCode}');
      debugPrint('  → body    : ${e.response?.data}');
      debugPrint('  → stack   : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.printJobs] Unexpected error: $e');
      debugPrint('  → stack   : $stack');
      rethrow;
    }
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      debugPrint('[AppRepository.logout] Sending logout request...');
      await ApiClient.dio.post('/printoo/logout');
      debugPrint('[AppRepository.logout] Session destroyed.');
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.logout] DioException: ${e.message}');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.logout] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }

  // ─── Clear Cache ──────────────────────────────────────────────────────────
  Future<void> clear() async {
    try {
      debugPrint('[AppRepository.clear] Clearing server temp cache...');
      await ApiClient.dio.post('/printoo/clear');
      debugPrint('[AppRepository.clear] Cache cleared successfully.');
    } on DioException catch (e, stack) {
      debugPrint('[AppRepository.clear] DioException: ${e.message}');
      debugPrint('  → status : ${e.response?.statusCode}');
      debugPrint('  → body   : ${e.response?.data}');
      debugPrint('  → stack  : $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[AppRepository.clear] Unexpected error: $e');
      debugPrint('  → stack  : $stack');
      rethrow;
    }
  }
}
