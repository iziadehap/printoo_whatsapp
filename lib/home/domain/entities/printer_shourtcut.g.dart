// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'printer_shourtcut.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PrinterShourtcutAdapter extends TypeAdapter<PrinterShourtcut> {
  @override
  final typeId = 0;

  @override
  PrinterShourtcut read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PrinterShourtcut(
      printerNumber: (fields[0] as num).toInt(),
      printerName: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, PrinterShourtcut obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.printerNumber)
      ..writeByte(1)
      ..write(obj.printerName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterShourtcutAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
