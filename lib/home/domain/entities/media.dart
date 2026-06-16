import 'package:printoo_whatsapp/home/domain/entities/print_job_file.dart';

class MediaFetchResult {
  final String customerFolder;
  final List<PrintJobFile> files;

  MediaFetchResult({required this.customerFolder, required this.files});
}
