import 'dart:io' as dart_io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                    // build printer slider
                    DropdownMenu<String>(
                      // 🌟 قمنا بتغييرها لتقرأ أحدث طابعة نشطة (سواء تم اختيارها بالاختصار أو بالماوس)
                      initialSelection: activePrinter,
                      label: const Text('Printer'),
                      dropdownMenuEntries: printers.isNotEmpty
                          ? printers.map((printer) {
                              return DropdownMenuEntry(
                                value: printer,
                                label: printer,
                              );
                            }).toList()
                          : [
                              const DropdownMenuEntry(
                                value: '',
                                label: 'Loading printers...',
                                enabled: false,
                              ),
                            ],
                      onSelected: (printer) {
                        if (printer != null && printer.isNotEmpty) {
                          // 🌟 تحديث الـ Index عند قيام المستخدم بالاختيار يدوياً بالماوس
                          final index = printers.indexOf(printer);
                          if (index != -1) {
                            ref
                                    .read(selectedPrinterIndexProvider.notifier)
                                    .state =
                                index;
                          }
                        }
                      },
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
            // Thumbnail Stack: Only internal tap opens preview
            Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierDismissible: true,
                        barrierColor: Colors.black87,
                        pageBuilder: (_, __, ___) =>
                            _FullScreenImageViewer(file: file),
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
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: file.selected,
                      onChanged: (_) => onToggleSelected(),
                      activeColor: AppColors.accent,
                    ),
                  ),
                ),

                // NEW: Visual Type Badge Overlapping Bottom Right Corner
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDoc ? Icons.picture_as_pdf : Icons.image_rounded,
                      size: 12,
                      color: isDoc ? AppColors.red : Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Filename Metadata Label Strings
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

            // Adjustments management tray configurations
            if (file.selected) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(
                  color: AppColors.border,
                  height: 1,
                  thickness: 0.5,
                ),
              ),

              // Absorbs parent layout row click mechanics cleanly
              GestureDetector(
                onTap: () {},
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // const Text(
                        //   'Copies:',
                        //   style: TextStyle(
                        //     color: AppColors.textSecondary,
                        //     fontSize: 10,
                        //     fontWeight: FontWeight.w500,
                        //   ),
                        // ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                if (file.copies > 1)
                                  onUpdate(
                                    file.copyWith(copies: file.copies - 1),
                                  );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.remove_circle_outline,
                                  size: 30,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                file.copies.toString(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => onUpdate(
                                file.copyWith(copies: file.copies + 1),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.add_circle_outline,
                                  size: 30,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (isDoc) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Duplex:',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(
                            height: 18,
                            child: DropdownButton<String>(
                              value: file.duplex,
                              underline: const SizedBox(),
                              iconSize: 12,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.textMuted,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'simplex',
                                  child: Text(
                                    'Simp',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'duplex',
                                  child: Text(
                                    'Dupl',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null)
                                  onUpdate(file.copyWith(duplex: v));
                              },
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              dropdownColor: AppColors.bgSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
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

// ── Full-Screen Overlay Canvas UI ────────────────────────────────────────────

class _FullScreenImageViewer extends StatefulWidget {
  final PrintJobFile file;
  const _FullScreenImageViewer({required this.file});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformCtrl = TransformationController();

  @override
  void dispose() {
    _transformCtrl.dispose();
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
              child: Container(color: Colors.black),
            ),

            Center(
              child: GestureDetector(
                onDoubleTap: _resetZoom,
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 0.5,
                  maxScale: 8.0,
                  child: widget.file.type == 'document'
                      ? PdfThumbnail(
                          absolutePath: widget.file.absolutePath,
                          size: 340,
                        )
                      : Image.file(
                          dart_io.File(widget.file.absolutePath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textMuted,
                              size: 64,
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
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.8), Colors.transparent],
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
                          fontSize: 14,
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
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Pinch to zoom  ·  Double-tap to reset  ·  Tap background to exit',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
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
