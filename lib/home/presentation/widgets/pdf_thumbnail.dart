import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printoo_whatsapp/core/theme/app_theme.dart';

class PdfThumbnail extends StatefulWidget {
  final String absolutePath;
  final double size;

  const PdfThumbnail({
    required this.absolutePath,
    required this.size,
    super.key,
  });

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.absolutePath != widget.absolutePath) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final document = await PdfDocument.openFile(widget.absolutePath);
      final page = await document.getPage(1);
      
      // Render the page to an image.
      // We scale the size slightly for better resolution quality.
      final pageImage = await page.render(
        width: page.width * 1.5,
        height: page.height * 1.5,
        format: PdfPageImageFormat.png,
      );

      if (pageImage != null && mounted) {
        setState(() {
          _imageBytes = pageImage.bytes;
          _loading = false;
        });
      } else if (mounted) {
        setState(() {
          _error = 'Render error';
          _loading = false;
        });
      }

      await page.close();
      await document.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ),
      );
    }

    if (_error != null || _imageBytes == null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.picture_as_pdf,
          color: AppColors.red,
          size: widget.size * 0.5,
        ),
      );
    }

    return Image.memory(
      _imageBytes!,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.picture_as_pdf,
          color: AppColors.red,
          size: widget.size * 0.5,
        ),
      ),
    );
  }
}
