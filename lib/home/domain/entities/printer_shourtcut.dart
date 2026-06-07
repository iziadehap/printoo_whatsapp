import 'package:hive_ce/hive.dart';

part 'printer_shourtcut.g.dart';

@HiveType(typeId: 0)
class PrinterShourtcut {
  @HiveField(0)
  final int printerNumber;
  @HiveField(1)
  final String printerName;

  PrinterShourtcut({required this.printerNumber, required this.printerName});

  factory PrinterShourtcut.fromJson(Map<String, dynamic> json) {
    return PrinterShourtcut(
      printerNumber: json['printerNumber'],
      printerName: json['printerName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'printerNumber': printerNumber, 'printerName': printerName};
  }
}
