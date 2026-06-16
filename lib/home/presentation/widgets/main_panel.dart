import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/fullscreen_doc_widget.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/fullscreen_image_viewer.dart';
import '../../domain/entities/print_job_file.dart';
import '../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import './pdf_thumbnail.dart';

final thumbnailScaleProvider = StateProvider<double>((ref) => 90.0);

class MainPanel extends ConsumerWidget {
  const MainPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaState = ref.watch(mediaProvider);
    final selectedCustomer = ref.watch(selectedCustomerProvider);
    final blankSep = ref.watch(blankPageSeparatorProvider);
    final globalCopies = ref.watch(globalCopiesProvider);
    final globalDuplex = ref.watch(globalDuplexProvider);
    final logMessage = ref.watch(logMessageProvider);
    final thumbSize = ref.watch(thumbnailScaleProvider);
    final printers = ref.watch(printersProvider);

    final activePrinter = ref.watch(activePrinterProvider);
    // 1. Safe helper states extracted from our file list array
    //final currentFiles = mediaState.valueOrNull ?? [];

    //final imagesList = currentFiles.where((f) => f.type == 'image');
    // final docsList = currentFiles.where((f) => f.type == 'document');

    // final allImagesSelected =
    //     imagesList.isNotEmpty && imagesList.every((f) => f.selected);
    // final allDocsSelected =
    //     docsList.isNotEmpty && docsList.every((f) => f.selected);
    // final everythingSelected =
    //     currentFiles.isNotEmpty && currentFiles.every((f) => f.selected);

    return Container(
      color: AppColors.bgBase,
      child: Column(
        children: [
          // Media Grid
          Expanded(
            child: mediaState.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 280,
                    maxWidth: 400,
                  ),
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to fetch media',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e.toString().replaceAll('Exception: ', ''),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.btnPrimaryText,
                        ),
                        onPressed: () {
                          if (selectedCustomer != null) {
                            ref
                                .read(mediaProvider.notifier)
                                .fetch(
                                  selectedCustomer.id,
                                  ref.read(daysLookbackProvider),
                                );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              data: (files) {
                if (files.isEmpty) {
                  return const Center(
                    child: Text(
                      'No files found. Select a customer and fetch media.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    alignment: WrapAlignment.start,
                    children: files.map((file) {
                      return MediaFileCard(
                        file: file,
                        globalCopies: globalCopies,
                        globalDuplex: globalDuplex,
                        thumbSize: thumbSize,
                        onToggleSelected: () {
                          ref
                              .read(mediaProvider.notifier)
                              .toggleSelected(file.id);
                        },
                        onUpdate: (updated) {
                          ref
                              .read(mediaProvider.notifier)
                              .updateFile(file.id, updated);
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),

          // Global Settings Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.bgSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      // Use constraints to give the box a bounded max width while inside an unconstrained parent Row
                      constraints: const BoxConstraints(maxWidth: 260),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.border.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.print_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),

                          // Expanded safely takes up the rest of the 260px container width
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value:
                                      (activePrinter != null &&
                                          printers.contains(activePrinter))
                                      ? activePrinter
                                      : null,
                                  isExpanded:
                                      true, // Forces text truncation to work inside the bounded space
                                  alignment: Alignment.centerLeft,
                                  dropdownColor: AppColors.bgSurface,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: AppColors.textSecondary,
                                  ),
                                  items: printers.map((printer) {
                                    return DropdownMenuItem<String>(
                                      value: printer,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          printer,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (printer) {
                                    if (printer != null && printer.isNotEmpty) {
                                      final index = printers.indexOf(printer);
                                      if (index != -1) {
                                        ref
                                                .read(
                                                  selectedPrinterIndexProvider
                                                      .notifier,
                                                )
                                                .state =
                                            index;
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              onPressed: () async {
                                ref.read(logMessageProvider.notifier).state =
                                    'INFO: Refreshing printer list...';
                                await ref
                                    .read(printersProvider.notifier)
                                    .refresh();
                                ref.read(logMessageProvider.notifier).state =
                                    'INFO: Printer list refreshed successfully.';
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.photo_size_select_large,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(
                      width: 130,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: thumbSize,
                          min: 70.0,
                          max: 160.0,
                          activeColor: AppColors.accent,
                          inactiveColor: AppColors.border,
                          onChanged: (newSize) {
                            ref.read(thumbnailScaleProvider.notifier).state =
                                newSize;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Checkbox(
                      value: blankSep,
                      onChanged: (v) {
                        ref.read(blankPageSeparatorProvider.notifier).state =
                            v ?? false;
                      },
                      activeColor: AppColors.accent,
                    ),
                    const Text(
                      'Blank Page Separator',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Copies: ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.remove, size: 16),
                          onPressed: () {
                            if (globalCopies > 1) {
                              final newCopies = globalCopies - 1;
                              ref.read(globalCopiesProvider.notifier).state =
                                  newCopies;
                              ref
                                  .read(mediaProvider.notifier)
                                  .updateGlobalCopies(newCopies);
                            }
                          },
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          globalCopies.toString(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.add, size: 16),
                          onPressed: () {
                            final newCopies = globalCopies + 1;
                            ref.read(globalCopiesProvider.notifier).state =
                                newCopies;
                            ref
                                .read(mediaProvider.notifier)
                                .updateGlobalCopies(newCopies);
                          },
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Duplex: ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Switch(
                            value: globalDuplex,
                            onChanged: (v) {
                              ref.read(globalDuplexProvider.notifier).state = v;
                              ref
                                  .read(mediaProvider.notifier)
                                  .updateGlobalDuplex(v ? 'duplex' : 'simplex');
                            },
                            activeColor: AppColors.accent,
                          ),
                        ),
                      ],
                    ), // ───── Button 1: Images ─────
                    SizedBox(
                      width: 130,
                      height: 32,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .isNotEmpty ??
                                      false)
                              ? Icons.check_circle_rounded
                              : Icons.image_outlined,
                          size: 14,
                        ),
                        label: Text(
                          (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .isNotEmpty ??
                                      false)
                              ? 'Deselect Images'
                              : 'All Images',
                        ),
                        onPressed: () =>
                            ref.read(mediaProvider.notifier).toggleAllImages(),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .isNotEmpty ??
                                      false)
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.bgCard,
                          foregroundColor:
                              (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'image')
                                          .isNotEmpty ??
                                      false)
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          side: BorderSide(
                            color:
                                (mediaState.valueOrNull
                                            ?.where((f) => f.type == 'image')
                                            .every((f) => f.selected) ??
                                        false) &&
                                    (mediaState.valueOrNull
                                            ?.where((f) => f.type == 'image')
                                            .isNotEmpty ??
                                        false)
                                ? AppColors.accent
                                : AppColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    // ───── Button 2: Documents ─────
                    SizedBox(
                      width: 130,
                      height: 32,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .isNotEmpty ??
                                      false)
                              ? Icons.check_circle_rounded
                              : Icons.picture_as_pdf_outlined,
                          size: 14,
                        ),
                        label: Text(
                          (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .isNotEmpty ??
                                      false)
                              ? 'Deselect Docs'
                              : 'All Docs',
                        ),
                        onPressed: () => ref
                            .read(mediaProvider.notifier)
                            .toggleAllDocuments(),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .isNotEmpty ??
                                      false)
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.bgCard,
                          foregroundColor:
                              (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .every((f) => f.selected) ??
                                      false) &&
                                  (mediaState.valueOrNull
                                          ?.where((f) => f.type == 'document')
                                          .isNotEmpty ??
                                      false)
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          side: BorderSide(
                            color:
                                (mediaState.valueOrNull
                                            ?.where((f) => f.type == 'document')
                                            .every((f) => f.selected) ??
                                        false) &&
                                    (mediaState.valueOrNull
                                            ?.where((f) => f.type == 'document')
                                            .isNotEmpty ??
                                        false)
                                ? AppColors.accent
                                : AppColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    // ───── Button 3: Everything Master Button ─────
                    SizedBox(
                      width: 130,
                      height: 32,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          (mediaState.valueOrNull?.isNotEmpty ?? false) &&
                                  (mediaState.valueOrNull?.every(
                                        (f) => f.selected,
                                      ) ??
                                      false)
                              ? Icons.layers_clear_outlined
                              : Icons.layers_outlined,
                          size: 14,
                        ),
                        label: Text(
                          (mediaState.valueOrNull?.isNotEmpty ?? false) &&
                                  (mediaState.valueOrNull?.every(
                                        (f) => f.selected,
                                      ) ??
                                      false)
                              ? 'Deselect All'
                              : 'Select All',
                        ),
                        onPressed: () =>
                            ref.read(mediaProvider.notifier).toggleAllFiles(),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              (mediaState.valueOrNull?.isNotEmpty ?? false) &&
                                  (mediaState.valueOrNull?.every(
                                        (f) => f.selected,
                                      ) ??
                                      false)
                              ? AppColors.red.withOpacity(0.1)
                              : AppColors.bgCard,
                          foregroundColor:
                              (mediaState.valueOrNull?.isNotEmpty ?? false) &&
                                  (mediaState.valueOrNull?.every(
                                        (f) => f.selected,
                                      ) ??
                                      false)
                              ? AppColors.red
                              : AppColors.textSecondary,
                          side: BorderSide(
                            color:
                                (mediaState.valueOrNull?.isNotEmpty ?? false) &&
                                    (mediaState.valueOrNull?.every(
                                          (f) => f.selected,
                                        ) ??
                                        false)
                                ? AppColors.red.withOpacity(0.5)
                                : AppColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Log Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.bgDeep,
            width: double.infinity,
            child: Text(
              logMessage,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Refined Card UI Component ───────────────────────────────────────────────

class MediaFileCard extends StatelessWidget {
  final PrintJobFile file;
  final int globalCopies;
  final bool globalDuplex;
  final double thumbSize;
  final VoidCallback onToggleSelected;
  final Function(PrintJobFile) onUpdate;

  const MediaFileCard({
    required this.file,
    required this.globalCopies,
    required this.globalDuplex,
    required this.thumbSize,
    required this.onToggleSelected,
    required this.onUpdate,
    super.key,
  });

  Widget _buildThumbnailCanvas(BuildContext context) {
    if (file.type == 'document') {
      return PdfThumbnail(absolutePath: file.absolutePath, size: thumbSize);
    }

    return Image.file(
      dart_io.File(file.absolutePath),
      width: thumbSize,
      height: thumbSize,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: thumbSize,
        height: thumbSize,
        color: AppColors.bgSurface,
        child: Icon(
          Icons.broken_image_outlined,
          color: AppColors.textMuted,
          size: thumbSize * 0.35,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = thumbSize + 24;
    final isDoc = file.type == 'document';

    final IconData typeIcon;
    final Color typeColor;

    if (!isDoc) {
      typeIcon = Icons.image_rounded;
      typeColor = Colors.greenAccent;
    } else {
      final origType = file.originalType?.toLowerCase() ?? 'pdf';
      if (origType.contains('doc')) {
        typeIcon = Icons.description;
        typeColor = AppColors.blue;
      } else if (origType.contains('xls')) {
        typeIcon = Icons.table_chart;
        typeColor = Colors.green;
      } else if (origType.contains('ppt')) {
        typeIcon = Icons.slideshow;
        typeColor = Colors.orange;
      } else {
        typeIcon = Icons.picture_as_pdf;
        typeColor = AppColors.red;
      }
    }

    return InkWell(
      onTap: onToggleSelected,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: cardWidth,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: file.selected ? AppColors.bgSelected : AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: file.selected ? AppColors.accent : AppColors.border,
            width: file.selected ? 1.5 : 1,
          ),
          boxShadow: file.selected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail Stack
            Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    bool isDoc = file.type == 'document';

                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierDismissible: true,
                        barrierColor: Colors.black87,
                        pageBuilder: (_, __, ___) => isDoc
                            ? FullScreenDocViewer(file: file)
                            : FullScreenImageViewer(file: file),
                        transitionsBuilder: (_, anim, __, child) =>
                            FadeTransition(opacity: anim, child: child),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildThumbnailCanvas(context),
                    ),
                  ),
                ),

                // Native System Selection Checkbox Anchor
                Positioned(
                  top: 4,
                  left: 4,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: file.selected,
                      onChanged: (_) => onToggleSelected(),
                      activeColor: AppColors.accent,
                    ),
                  ),
                ),

                // Visual Type Badge
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(typeIcon, size: 12, color: typeColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Filename Label
            Text(
              file.filename,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Sub-metrics layout specifications
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isDoc ? '${file.pages} pgs' : 'Image',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _fmtSize(file.sizeBytes),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(
                color: AppColors.border,
                height: 1,
                thickness: 0.5,
              ),
            ),

            // Control Tray Panel (Keeps exact same sizing footprint when unselected)
            Opacity(
              opacity: file.selected ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !file.selected,
                child: GestureDetector(
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Elegant Copies Control Bar
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (file.copies > 1) {
                                  onUpdate(
                                    file.copyWith(copies: file.copies - 1),
                                  );
                                }
                              },
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(6),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.remove,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Container(
                              alignment: Alignment.center,
                              constraints: const BoxConstraints(minWidth: 22),
                              child: Text(
                                file.copies.toString(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => onUpdate(
                                file.copyWith(copies: file.copies + 1),
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(6),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.add,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Duplex Control Configured cleanly as a Checkbox Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '2-Sided',
                            style: TextStyle(
                              color: isDoc
                                  ? AppColors.textSecondary
                                  : Colors.transparent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          isDoc
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: file.duplex == 'duplex',
                                    activeColor: AppColors.accent,
                                    onChanged: (bool? checked) {
                                      if (checked != null) {
                                        onUpdate(
                                          file.copyWith(
                                            duplex: checked
                                                ? 'duplex'
                                                : 'simplex',
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                )
                              : const SizedBox(width: 20, height: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// // Dummy Full Screen Viewer Placeholder to prevent compile errors
// class _FullScreenImageViewer extends StatelessWidget {
//   final PrintJobFile file;
//   const _FullScreenImageViewer({required this.file});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: GestureDetector(
//         onTap: () => Navigator.of(context).pop(),
//         child: Center(child: Image.file(dart_io.File(file.absolutePath))),
//       ),
//     );
//   }
// }
// ── Full-Screen Overlay Canvas UI ────────────────────────────────────────────

// class _FullScreenImageViewer extends StatefulWidget {
//   final PrintJobFile file;
//   const _FullScreenImageViewer({required this.file});

//   @override
//   State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
// }

// class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
//   final TransformationController _transformCtrl = TransformationController();

//   @override
//   void dispose() {
//     _transformCtrl.dispose();
//     super.dispose();
//   }

//   void _resetZoom() => _transformCtrl.value = Matrix4.identity();

//   @override
//   Widget build(BuildContext context) {
//     return KeyboardListener(
//       focusNode: FocusNode()..requestFocus(),
//       autofocus: true,
//       onKeyEvent: (_) => Navigator.of(context).pop(),
//       child: Scaffold(
//         backgroundColor: Colors.transparent,
//         body: Stack(
//           children: [
//             GestureDetector(
//               onTap: () => Navigator.of(context).pop(),
//               child: Container(color: Colors.black),
//             ),

//             Center(
//               child: GestureDetector(
//                 onDoubleTap: _resetZoom,
//                 child: InteractiveViewer(
//                   transformationController: _transformCtrl,
//                   minScale: 0.5,
//                   maxScale: 8.0,
//                   child: widget.file.type == 'document'
//                       ? PdfThumbnail(
//                           absolutePath: widget.file.absolutePath,
//                           size: 340,
//                         )
//                       : Image.file(
//                           dart_io.File(widget.file.absolutePath),
//                           fit: BoxFit.contain,
//                           errorBuilder: (_, __, ___) => const Center(
//                             child: Icon(
//                               Icons.broken_image_outlined,
//                               color: AppColors.textMuted,
//                               size: 64,
//                             ),
//                           ),
//                         ),
//                 ),
//               ),
//             ),

//             Positioned(
//               top: 0,
//               left: 0,
//               right: 0,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 16,
//                   vertical: 14,
//                 ),
//                 decoration: BoxDecoration(
//                   gradient: LinearGradient(
//                     begin: Alignment.topCenter,
//                     end: Alignment.bottomCenter,
//                     colors: [Colors.black.withOpacity(0.8), Colors.transparent],
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     Material(
//                       color: Colors.white.withOpacity(0.12),
//                       borderRadius: BorderRadius.circular(20),
//                       child: InkWell(
//                         borderRadius: BorderRadius.circular(20),
//                         onTap: () => Navigator.of(context).pop(),
//                         child: const Padding(
//                           padding: EdgeInsets.all(8),
//                           child: Icon(
//                             Icons.close,
//                             color: Colors.white,
//                             size: 20,
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Text(
//                         widget.file.filename,
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontSize: 14,
//                           fontWeight: FontWeight.w500,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     Material(
//                       color: Colors.white.withOpacity(0.12),
//                       borderRadius: BorderRadius.circular(20),
//                       child: InkWell(
//                         borderRadius: BorderRadius.circular(20),
//                         onTap: _resetZoom,
//                         child: const Padding(
//                           padding: EdgeInsets.all(8),
//                           child: Icon(
//                             Icons.zoom_out_map,
//                             color: Colors.white,
//                             size: 18,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             Positioned(
//               bottom: 20,
//               left: 0,
//               right: 0,
//               child: Center(
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 14,
//                     vertical: 8,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Colors.black54,
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                   child: const Text(
//                     'Pinch to zoom  ·  Double-tap to reset  ·  Tap background to exit',
//                     style: TextStyle(color: Colors.white70, fontSize: 11),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
