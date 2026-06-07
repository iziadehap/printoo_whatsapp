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
  });

  PrintJobFile copyWith({
    int? copies,
    String? duplex,
    int? startPage,
    int? endPage,
    bool? selected,
  }) => PrintJobFile(
    id: id,
    filename: filename,
    absolutePath: absolutePath,
    type: type,
    pages: pages,
    sizeBytes: sizeBytes,
    copies: copies ?? this.copies,
    duplex: duplex ?? this.duplex,
    startPage: startPage ?? this.startPage,
    endPage: endPage ?? this.endPage,
    selected: selected ?? this.selected,
  );

  factory PrintJobFile.fromJson(Map<String, dynamic> json) => PrintJobFile(
    id: json['id']?.toString() ?? UniqueKey().toString(),
    filename: json['filename'] ?? 'unknown',
    absolutePath: json['absolutePath'] ?? '',
    type: json['type'] ?? 'image',
    pages: json['pages'] ?? 0,
    sizeBytes: json['sizeBytes'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'absolutePath': absolutePath,
    'type': type,
    'copies': copies,
    'duplex': duplex,
    if (type == 'document' && startPage != null) 'startPage': startPage,
    if (type == 'document' && endPage != null) 'endPage': endPage,
  };
}
