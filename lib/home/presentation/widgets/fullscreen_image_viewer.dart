// ── Full-Screen image Viewer ───────────────────────────────────────────────────────

import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printoo_whatsapp/home/domain/entities/print_job_file.dart';
import 'package:printoo_whatsapp/core/theme/app_theme.dart';
import 'pdf_thumbnail.dart';

class FullScreenImageViewer extends StatefulWidget {
  final PrintJobFile file;
  const FullScreenImageViewer({required this.file});

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformCtrl = TransformationController();
  PdfControllerPinch? _pdfController;

  @override
  void initState() {
    super.initState();
    if (widget.file.type == 'document') {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.file.absolutePath),
      );
    }
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  void _resetZoom() => _transformCtrl.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (_) => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.black87),
            ),

            Center(
              child: widget.file.type == 'document'
                  ? (_pdfController != null
                        ? PdfViewPinch(controller: _pdfController!)
                        : const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.accent,
                            ),
                          ))
                  : GestureDetector(
                      onDoubleTap: _resetZoom,
                      child: InteractiveViewer(
                        transformationController: _transformCtrl,
                        minScale: 0.5,
                        maxScale: 8.0,
                        child: Image.file(
                          dart_io.File(widget.file.absolutePath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textMuted,
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Could not load image file',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Material(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.file.filename,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Material(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _resetZoom,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.zoom_out_map,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pinch to zoom  ·  Double-tap to reset  ·  Tap outside to close',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ),
            ),

            // Floating Overlay Reference Thumbnail (Loads images or documents seamlessly)
            Positioned(
              bottom: 16,
              right: 16,
              child: Hero(
                tag: 'preview_thumb_${widget.file.id}',
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: widget.file.type == 'document'
                        ? PdfThumbnail(
                            absolutePath: widget.file.absolutePath,
                            size: 64,
                          )
                        : Image.file(
                            dart_io.File(widget.file.absolutePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.bgSurface,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textMuted,
                                size: 28,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
