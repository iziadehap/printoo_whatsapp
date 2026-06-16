import '../entities/app_status.dart';
import '../entities/customer.dart';
import '../entities/media.dart';
import '../entities/print_job_file.dart';
import '../entities/printer_shourtcut.dart';

abstract class AppRepository {
  Future<AppStatus> getStatus();
  Future<List<String>> getPrinters();
  Future<int> getSavedCopyCount();
  Future<void> putSavedCopyCount(int count);
  Future<List<PrinterShourtcut>> getSavedPrinterShortcuts();
  Future<void> putPrinterFromCash(List<PrinterShourtcut> printerShortcuts);
  Future<void> putSavedPrinterShortcuts(
    List<PrinterShourtcut> printerShortcuts,
  );
  Future<List<Customer>> searchCustomers(String query);
  Future<List<Customer>> getRecentChats();
  Future<MediaFetchResult> fetchMedia(String chatId, dynamic daysLookback);
  Future<void> printJobs({
    required String printerName,
    required bool blankPageSeparator,
    required List<PrintJobFile> jobs,
  });
  Future<void> logout();
  Future<void> clear();
}
