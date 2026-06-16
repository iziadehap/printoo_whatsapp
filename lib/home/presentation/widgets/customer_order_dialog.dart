// =============================================================================
// customer_order_dialog.dart
// Printoo WhatsApp — Customer Order Dialog / Media Preview Screen
//
// Features implemented:
//   ✅  cached_network_image for profile pictures (no re-download on rebuild)
//   ✅  Prominent page-count badge (amber, large, bold)
//   ✅  No close (X) button — operator must use Print / Cancel
//   ✅  Dynamic printer refresh button (re-triggers GET /printoo/printers)
//   ✅  Per-file print-range control panel (All Pages / Custom Range)
//   ✅  startPage / endPage validation + payload integration
//   ✅  Full Riverpod integration (reads/writes existing providers)
//   ✅  Premium dark-theme UI (AppColors) consistent with existing codebase
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:printoo_whatsapp/core/theme/app_theme.dart';
import 'package:printoo_whatsapp/home/domain/entities/customer.dart';
import 'package:printoo_whatsapp/home/domain/entities/print_job_file.dart';
import 'package:printoo_whatsapp/home/presentation/providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point — call this from any ConsumerWidget / ConsumerState
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the Customer Order Dialog modally.
///
/// [customer]    – The customer whose media files are already loaded into
///                 [mediaProvider] by the time this dialog opens.
/// [profileImageUrl] – Optional WhatsApp profile picture URL.
Future<void> showCustomerOrderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Customer customer,
  String? profileImageUrl,
}) {
  return showDialog(
    context: context,
    // Prevent dismissal by clicking outside — operator must use action buttons
    barrierDismissible: false,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _CustomerOrderDialog(
        customer: customer,
        profileImageUrl: profileImageUrl,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal dialog widget
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerOrderDialog extends ConsumerStatefulWidget {
  const _CustomerOrderDialog({required this.customer, this.profileImageUrl});

  final Customer customer;
  final String? profileImageUrl;

  @override
  ConsumerState<_CustomerOrderDialog> createState() =>
      _CustomerOrderDialogState();
}

class _CustomerOrderDialogState extends ConsumerState<_CustomerOrderDialog> {
  // ── State ──────────────────────────────────────────────────────────────────

  /// ID of the file currently expanded in the print-range panel (null = none)
  String? _expandedFileId;

  /// Whether the printer list is being refreshed
  bool _refreshingPrinters = false;

  /// Map of file IDs to whether their page range is invalid
  final Map<String, bool> _invalidFiles = {};

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns only the files the operator has checked for printing
  List<PrintJobFile> get _selectedFiles =>
      (ref.read(mediaProvider).valueOrNull ?? [])
          .where((f) => f.selected)
          .toList();

  bool get _hasAnyValidationError {
    return _selectedFiles.any((f) => _invalidFiles[f.id] == true);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Re-fetches the printer list from GET /printoo/printers and rebuilds
  /// the dropdown without restarting the app.
  Future<void> _refreshPrinters() async {
    setState(() => _refreshingPrinters = true);
    try {
      await ref.read(printersProvider.notifier).refresh();
      // Brief visual delay so the operator sees the refresh animation
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } catch (e) {
      _showSnack('Failed to refresh printers: $e', isError: true);
    } finally {
      if (mounted) setState(() => _refreshingPrinters = false);
    }
  }

  /// Sends the print payload to POST /printoo/print and closes the dialog.
  Future<void> _submitPrint() async {
    final selected = _selectedFiles;
    if (selected.isEmpty) {
      _showSnack('No files selected for printing.', isError: true);
      return;
    }
    final printer = ref.read(activePrinterProvider);
    if (printer == null) {
      _showSnack('No printer selected.', isError: true);
      return;
    }

    // Validate page ranges before submitting
    for (final file in selected) {
      if (file.type == 'document') {
        final start = file.startPage ?? 1;
        final end = file.endPage ?? file.pages;
        if (start < 1 || end > file.pages || start > end) {
          _showSnack(
            'Invalid page range for "${file.filename}".',
            isError: true,
          );
          return;
        }
      }
    }

    try {
      final blankSep = ref.read(blankPageSeparatorProvider);
      await ref
          .read(appRepositoryProvider)
          .printJobs(
            printerName: printer,
            blankPageSeparator: blankSep,
            jobs: selected,
          );
      if (mounted) {
        Navigator.of(context).pop();
        _showSnack('Print job sent to "$printer" successfully!');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Print failed: ${e.toString()}', isError: true);
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: isError ? AppColors.red : AppColors.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(mediaProvider).valueOrNull ?? [];
    final printers = ref.watch(printersProvider);
    final selectedPrinterIdx = ref.watch(selectedPrinterIndexProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      // Wide modal suited for a desktop print-shop terminal
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Container(
        width: 860,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header (no X button) ────────────────────────────────────────
            _buildHeader(),
            const Divider(height: 1, color: AppColors.border),

            // ── Printer Row ─────────────────────────────────────────────────
            _buildPrinterRow(printers, selectedPrinterIdx),
            const Divider(height: 1, color: AppColors.border),

            // ── File List ───────────────────────────────────────────────────
            Flexible(
              child: files.isEmpty ? _buildEmptyState() : _buildFileList(files),
            ),

            const Divider(height: 1, color: AppColors.border),

            // ── Action Bar ──────────────────────────────────────────────────
            _buildActionBar(files),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header — customer info, profile picture, NO close button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hasImage = (widget.profileImageUrl ?? '').isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // ── Profile picture (cached to prevent re-download on rebuild) ──
          _buildProfileAvatar(hasImage),
          const SizedBox(width: 14),

          // ── Customer meta ───────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.customer.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_outlined,
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.customer.displayPhone,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.access_time_outlined,
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.customer.relativeTime,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Dialog title badge ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accentDim.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.accent.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.print_outlined,
                  size: 12,
                  color: AppColors.accentGlow,
                ),
                SizedBox(width: 6),
                Text(
                  'ORDER PREVIEW',
                  style: TextStyle(
                    color: AppColors.accentGlow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // ── NOTE: No X / close button here by design ────────────────────
          // The operator must use "Print" or "Cancel" in the action bar.
        ],
      ),
    );
  }

  /// Cached network image with a graceful icon placeholder.
  Widget _buildProfileAvatar(bool hasImage) {
    const double size = 44;

    if (!hasImage) {
      return _defaultAvatar(size);
    }

    return CachedNetworkImage(
      imageUrl: widget.profileImageUrl!,
      imageBuilder: (_, imageProvider) => CircleAvatar(
        radius: size / 2,
        backgroundImage: imageProvider,
        backgroundColor: AppColors.bgCard,
      ),
      // Generic icon shown while loading or if URL fails
      placeholder: (_, __) => _defaultAvatar(size),
      errorWidget: (_, __, ___) => _defaultAvatar(size),
      // Cache for 7 days — prevents re-downloading during rapid state updates
      maxWidthDiskCache: 200,
      maxHeightDiskCache: 200,
    );
  }

  Widget _defaultAvatar(double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.bgCard,
      child: const Icon(
        Icons.person_outline_rounded,
        color: AppColors.textMuted,
        size: 22,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Printer selection row with inline refresh button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPrinterRow(List<String> printers, int selectedIdx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: AppColors.bgSurface,
      child: Row(
        children: [
          const Icon(
            Icons.print_rounded,
            size: 14,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const Text(
            'Printer:',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),

          // ── Printer dropdown ─────────────────────────────────────────────
          Expanded(
            child: printers.isEmpty
                ? const Text(
                    'No printers found — click Refresh',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedIdx < printers.length ? selectedIdx : 0,
                      dropdownColor: AppColors.bgCard,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      isExpanded: true,
                      items: List.generate(
                        printers.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(
                            printers[i],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      onChanged: (i) {
                        if (i != null) {
                          ref
                                  .read(selectedPrinterIndexProvider.notifier)
                                  .state =
                              i;
                        }
                      },
                    ),
                  ),
          ),

          const SizedBox(width: 8),

          // ── Refresh button — re-triggers GET /printoo/printers ───────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _refreshingPrinters
                ? const SizedBox(
                    key: ValueKey('spinner'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : TextButton.icon(
                    key: const ValueKey('refresh_btn'),
                    onPressed: _refreshPrinters,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text(
                      'Refresh',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'No files retrieved for this customer.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File list
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFileList(List<PrintJobFile> files) {
    // Group into documents then images for clarity
    final docs = files.where((f) => f.type == 'document').toList();
    final imgs = files.where((f) => f.type == 'image').toList();
    final grouped = [...docs, ...imgs];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: grouped.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) => _buildFileRow(grouped[i]),
    );
  }

  Widget _buildFileRow(PrintJobFile file) {
    final isExpanded = _expandedFileId == file.id;
    final isDoc = file.type == 'document';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: file.selected
            ? AppColors.bgSelected.withOpacity(0.35)
            : AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: file.selected
              ? AppColors.accent.withOpacity(0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Main row ───────────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                ref.read(mediaProvider.notifier).toggleSelected(file.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Checkbox
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: file.selected,
                      onChanged: (_) => ref
                          .read(mediaProvider.notifier)
                          .toggleSelected(file.id),
                      activeColor: AppColors.accent,
                      checkColor: AppColors.bgDeep,
                      side: const BorderSide(
                        color: AppColors.borderActive,
                        width: 1.5,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // File type icon
                  _fileTypeIcon(file),
                  const SizedBox(width: 10),

                  // Filename
                  Expanded(
                    child: Text(
                      file.filename,
                      style: TextStyle(
                        color: file.selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: file.selected
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ── Prominent page count badge ──────────────────────────
                  // Large, amber, instantly readable from a glance
                  if (isDoc) _buildPageCountBadge(file.pages),
                  if (isDoc) const SizedBox(width: 8),

                  // File size
                  Text(
                    _formatBytes(file.sizeBytes),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Copies stepper
                  _buildCopiesStepper(file),
                  const SizedBox(width: 8),

                  // Duplex toggle
                  _buildDuplexToggle(file),

                  // Expand range panel (documents only)
                  if (isDoc) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: isExpanded
                          ? 'Hide page range'
                          : 'Set print range',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() {
                          _expandedFileId = isExpanded ? null : file.id;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.tune_rounded,
                            size: 16,
                            color: isExpanded
                                ? AppColors.accent
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Print Range Panel (expanded for documents) ──────────────────
          if (isDoc && isExpanded) _buildPrintRangePanel(file),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Prominent page count badge
  // A large amber pill — readable at a glance across the operator's desk
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPageCountBadge(int pages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // Amber background — high contrast, immediately draws the eye
        color: const Color(0xFFF59E0B).withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 11,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          Text(
            '$pages',
            style: const TextStyle(
              // Large, bold, unmissable
              color: Color(0xFFFBBF24),
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            pages == 1 ? 'pg' : 'pgs',
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Print Range Control Panel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPrintRangePanel(PrintJobFile file) {
    // Determine current mode: custom if either boundary differs from defaults
    final isCustom =
        (file.startPage != null && file.startPage != 1) ||
        (file.endPage != null && file.endPage != file.pages);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderActive.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section label ───────────────────────────────────────────────
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 12, color: AppColors.blue),
              SizedBox(width: 6),
              Text(
                'PRINT RANGE',
                style: TextStyle(
                  color: AppColors.blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Option dropdown ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Print Option" label + dropdown
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Print Option',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PrintOptionDropdown(
                      isCustom: isCustom,
                      onChanged: (custom) {
                        if (custom) {
                          // Default custom range = page 1 → last page
                          ref
                              .read(mediaProvider.notifier)
                              .updateFile(
                                file.id,
                                file.copyWith(
                                  startPage: 1,
                                  endPage: file.pages,
                                ),
                              );
                        } else {
                          // "All Pages" clears the overrides
                          ref
                              .read(mediaProvider.notifier)
                              .updateFile(
                                file.id,
                                file.copyWith(
                                  clearStartPage: true,
                                  clearEndPage: true,
                                ),
                              );
                          setState(() {
                            _invalidFiles.remove(file.id);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Custom range fields (visible only when custom mode)
              if (isCustom) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: _CustomRangeFields(
                    file: file,
                    onRangeChanged: (start, end) {
                      ref
                          .read(mediaProvider.notifier)
                          .updateFile(
                            file.id,
                            file.copyWith(startPage: start, endPage: end),
                          );
                    },
                    onValidationChanged: (isValid) {
                      setState(() {
                        if (isValid) {
                          _invalidFiles.remove(file.id);
                        } else {
                          _invalidFiles[file.id] = true;
                        }
                      });
                    },
                  ),
                ),
              ],
            ],
          ),

          // ── Helpful note ────────────────────────────────────────────────
          if (isCustom) ...[
            const SizedBox(height: 8),
            Text(
              'Ghostscript will receive -dFirstPage=${file.startPage ?? 1} '
              '-dLastPage=${file.endPage ?? file.pages}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Copies stepper
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCopiesStepper(PrintJobFile file) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(
            icon: Icons.remove,
            enabled: file.copies > 1,
            onTap: () => ref
                .read(mediaProvider.notifier)
                .updateFile(file.id, file.copyWith(copies: file.copies - 1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${file.copies}x',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _stepperButton(
            icon: Icons.add,
            enabled: file.copies < 99,
            onTap: () => ref
                .read(mediaProvider.notifier)
                .updateFile(file.id, file.copyWith(copies: file.copies + 1)),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 13,
          color: enabled ? AppColors.textSecondary : AppColors.textMuted,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Duplex toggle
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDuplexToggle(PrintJobFile file) {
    final isDuplex = file.duplex == 'duplex';
    return Tooltip(
      message: isDuplex ? 'Duplex (double-sided)' : 'Simplex (one-sided)',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => ref
            .read(mediaProvider.notifier)
            .updateFile(
              file.id,
              file.copyWith(duplex: isDuplex ? 'simplex' : 'duplex'),
            ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: isDuplex
                ? AppColors.blueDim.withOpacity(0.25)
                : AppColors.bgSurface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isDuplex
                  ? AppColors.blue.withOpacity(0.5)
                  : AppColors.border,
            ),
          ),
          child: Text(
            isDuplex ? '2S' : '1S',
            style: TextStyle(
              color: isDuplex ? AppColors.blue : AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Action bar — Print and Cancel (the only way to dismiss the dialog)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActionBar(List<PrintJobFile> files) {
    final selectedCount = files.where((f) => f.selected).length;
    final totalPages = files
        .where((f) => f.selected && f.type == 'document')
        .fold<int>(0, (sum, f) => sum + f.pages);
    final hasError = _hasAnyValidationError;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: AppColors.bgSurface,
      child: Row(
        children: [
          // Summary counters
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selectedCount file(s) selected',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (totalPages > 0)
                Text(
                  '$totalPages total doc page(s)',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
            ],
          ),

          const Spacer(),

          // ── Cancel — explicitly labelled, always visible ─────────────────
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),

          // ── Print — primary CTA ──────────────────────────────────────────
          FilledButton.icon(
            onPressed: selectedCount > 0 && !hasError ? _submitPrint : null,
            icon: const Icon(Icons.print_rounded, size: 16),
            label: Text(
              'Print${selectedCount > 0 ? " ($selectedCount)" : ""}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bgDeep,
              disabledBackgroundColor: AppColors.bgCard,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Small helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _fileTypeIcon(PrintJobFile file) {
    if (file.type == 'image') {
      return const Icon(Icons.image_outlined, size: 16, color: AppColors.blue);
    }
    final origType = file.originalType?.toLowerCase() ?? 'pdf';
    if (origType.contains('doc')) {
      return const Icon(
        Icons.description_rounded,
        size: 16,
        color: AppColors.blue,
      );
    } else if (origType.contains('xls')) {
      return const Icon(
        Icons.table_chart_rounded,
        size: 16,
        color: Colors.green,
      );
    } else if (origType.contains('ppt')) {
      return const Icon(
        Icons.slideshow_rounded,
        size: 16,
        color: Colors.orange,
      );
    } else {
      return const Icon(
        Icons.picture_as_pdf_rounded,
        size: 16,
        color: AppColors.red,
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// =============================================================================
// _PrintOptionDropdown
// Stateless helper to avoid rebuilding the whole dialog on selection change
// =============================================================================

class _PrintOptionDropdown extends StatelessWidget {
  const _PrintOptionDropdown({required this.isCustom, required this.onChanged});

  final bool isCustom;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<bool>(
      value: isCustom,
      dropdownColor: AppColors.bgCard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        filled: true,
        fillColor: AppColors.bgSurface,
      ),
      items: const [
        DropdownMenuItem(value: false, child: Text('All Pages')),
        DropdownMenuItem(value: true, child: Text('Custom Range')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// =============================================================================
// _CustomRangeFields
// Start Page / End Page numeric inputs with validation
// =============================================================================

class _CustomRangeFields extends StatefulWidget {
  const _CustomRangeFields({
    required this.file,
    required this.onRangeChanged,
    required this.onValidationChanged,
  });

  final PrintJobFile file;

  /// Called with validated (startPage, endPage) after any change
  final void Function(int start, int end) onRangeChanged;

  final ValueChanged<bool> onValidationChanged;

  @override
  State<_CustomRangeFields> createState() => _CustomRangeFieldsState();
}

class _CustomRangeFieldsState extends State<_CustomRangeFields> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  String? _startError;
  String? _endError;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: '${widget.file.startPage ?? 1}');
    _endCtrl = TextEditingController(
      text: '${widget.file.endPage ?? widget.file.pages}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onValidationChanged(true);
      }
    });
  }

  @override
  void didUpdateWidget(_CustomRangeFields old) {
    super.didUpdateWidget(old);
    // Keep controllers in sync when the provider state changes externally
    final newStart = '${widget.file.startPage ?? 1}';
    final newEnd = '${widget.file.endPage ?? widget.file.pages}';
    if (_startCtrl.text != newStart) _startCtrl.text = newStart;
    if (_endCtrl.text != newEnd) _endCtrl.text = newEnd;
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _validate() {
    final startRaw = int.tryParse(_startCtrl.text);
    final endRaw = int.tryParse(_endCtrl.text);
    final totalPages = widget.file.pages;

    setState(() {
      _startError = null;
      _endError = null;

      if (startRaw == null || startRaw < 1) {
        _startError = 'Min 1';
      }
      if (endRaw == null || endRaw > totalPages) {
        _endError = 'Max $totalPages';
      }
      if (startRaw != null && endRaw != null && startRaw > endRaw) {
        _startError = 'Start > End';
      }
    });

    final isValid = _startError == null && _endError == null;
    widget.onValidationChanged(isValid);

    if (isValid) {
      widget.onRangeChanged(startRaw!, endRaw!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _pageField(
            label: 'Start Page',
            controller: _startCtrl,
            errorText: _startError,
            hint: '1',
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 28),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '→',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ),
        ),
        Expanded(
          child: _pageField(
            label: 'End Page',
            controller: _endCtrl,
            errorText: _endError,
            hint: '${widget.file.pages}',
          ),
        ),
      ],
    );
  }

  Widget _pageField({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            // Allow digits only
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppColors.bgSurface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: errorText != null ? AppColors.red : AppColors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: errorText != null ? AppColors.red : AppColors.blue,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (_) => _validate(),
            onSubmitted: (_) => _validate(),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: const TextStyle(color: AppColors.red, fontSize: 10),
          ),
        ],
      ],
    );
  }
}
