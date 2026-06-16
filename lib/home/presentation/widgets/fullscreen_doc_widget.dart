import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printoo_whatsapp/home/domain/entities/print_job_file.dart';

class FullScreenDocViewer extends StatefulWidget {
  final PrintJobFile file;

  const FullScreenDocViewer({super.key, required this.file});

  @override
  State<FullScreenDocViewer> createState() => _FullScreenDocViewerState();
}

class _FullScreenDocViewerState extends State<FullScreenDocViewer> {
  final PdfViewerController _pdfController = PdfViewerController();

  @override
  void dispose() {
    super.dispose();
  }

  void resetZoom() {
    final matrices = _pdfController.calcFitZoomMatrices();
    if (matrices.isNotEmpty) {
      _pdfController.goTo(matrices.first.matrix);
    } else {
      _pdfController.goToPage(pageNumber: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PdfViewer.file(
              widget.file.absolutePath,
              controller: _pdfController,
              params: const PdfViewerParams(
                // Allow infinite zoom out and not limited by width of the app
                useAlternativeFitScaleAsMinScale: false,
                minScale: 0.001,
                maxScale: 50.0,
                // Margin boundary set to infinity so user can scroll / zoom freely
                boundaryMargin: EdgeInsets.all(double.infinity),
              ),
            ),
          ),

          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 30.0, left: 30.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 30.0, right: 30.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  color: Colors.white,
                  onPressed: resetZoom,
                  icon: const Icon(Icons.zoom_out_map),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
