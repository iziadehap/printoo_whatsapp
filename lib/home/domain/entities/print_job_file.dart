import 'package:flutter/material.dart';

class PrintJobFile {
  final String id;
  final String filename;
  final String absolutePath;
  final String type; // 'document' | 'image'
  final int pages;
  final int sizeBytes;
  int copies;
  String duplex; // 'simplex' | 'duplex'
  int? startPage;
  int? endPage;
  bool selected;
  final String? originalType;

  PrintJobFile({
    required this.id,
    required this.filename,
    required this.absolutePath,
    required this.type,
    required this.pages,
    required this.sizeBytes,
    this.copies = 1,
    this.duplex = 'duplex',
    this.startPage,
    this.endPage,
    this.selected = true,
    this.originalType,
  });

  PrintJobFile copyWith({
    int? copies,
    String? duplex,
    int? startPage,
    int? endPage,
    bool? selected,
    bool clearStartPage = false,
    bool clearEndPage = false,
  }) => PrintJobFile(
    id: id,
    filename: filename,
    absolutePath: absolutePath,
    type: type,
    pages: pages,
    sizeBytes: sizeBytes,
    copies: copies ?? this.copies,
    duplex: duplex ?? this.duplex,
    startPage: clearStartPage ? null : (startPage ?? this.startPage),
    endPage: clearEndPage ? null : (endPage ?? this.endPage),
    selected: selected ?? this.selected,
    originalType: originalType,
  );

  factory PrintJobFile.fromJson(Map<String, dynamic> json) => PrintJobFile(
    id: json['id']?.toString() ?? UniqueKey().toString(),
    filename: json['filename'] ?? 'unknown',
    absolutePath: json['absolutePath'] ?? '',
    type: json['type'] ?? 'image',
    pages: json['pages'] ?? 0,
    sizeBytes: json['sizeBytes'] ?? 0,
    originalType: json['originalType'],
  );

  Map<String, dynamic> toJson() => {
    'absolutePath': absolutePath,
    'type': type,
    'copies': copies,
    'duplex': duplex,
    if (type == 'document' && startPage != null) 'startPage': startPage,
    if (type == 'document' && endPage != null) 'endPage': endPage,
    if (originalType != null) 'originalType': originalType,
  };
}
