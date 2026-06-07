import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(mediaProvider).valueOrNull ?? [];
    final selected = files.where((f) => f.selected).toList();
    final printer = ref.watch(activePrinterProvider);

    return Container(
      height: 50,
      color: AppColors.bgSidebar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '${selected.length} files selected',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 16),
          if (selected.isNotEmpty)
            Text(
              'Total: ${selected.fold<int>(0, (sum, f) => sum + (f.pages * f.copies))} pages',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: selected.isEmpty || printer == null ? null : () {
              _triggerPrint(context, ref);
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('PRINT (Ctrl+P)', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.btnPrimaryText,
              disabledBackgroundColor: AppColors.bgCard,
              disabledForegroundColor: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _triggerPrint(BuildContext context, WidgetRef ref) async {
    final files = ref.read(mediaProvider).valueOrNull ?? [];
    final selected = files.where((f) => f.selected).toList();
    if (selected.isEmpty) {
      _snack(context, 'No files selected for printing.', isError: true);
      return;
    }
    final printer = ref.read(activePrinterProvider);
    if (printer == null) {
      _snack(context, 'No printer selected.', isError: true);
      return;
    }
    final blankSep = ref.read(blankPageSeparatorProvider);
    try {
      await ref.read(appRepositoryProvider).printJobs(
        printerName: printer,
        blankPageSeparator: blankSep,
        jobs: selected,
      );
      if (context.mounted) _snack(context, 'Print job sent successfully!');
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Print failed: ${e.toString()}', isError: true);
      }
    }
  }

  void _snack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppColors.textPrimary)),
      backgroundColor: isError ? AppColors.red : AppColors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }
}
