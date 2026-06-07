import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:printoo_whatsapp/core/theme/app_theme.dart';
import 'package:printoo_whatsapp/home/domain/entities/printer_shourtcut.dart';
import 'package:printoo_whatsapp/home/presentation/providers/app_providers.dart';

class SettingScreen extends ConsumerStatefulWidget {
  const SettingScreen({super.key});

  @override
  ConsumerState<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends ConsumerState<SettingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      selectPrinter(ref, -1); // جلب الاختصارات المحفوظة عند فتح الشاشة
    });
  }

  @override
  Widget build(BuildContext context) {
    final systemPrinters = ref.watch(printersProvider);
    final savedShortcuts = ref.watch(savedPrinterShortcutsProvider) ?? [];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Settings & Configuration',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ─── القسم الأول: إعدادات الطابعات ───
          _buildSectionHeader(
            'Printer Shortcuts',
            'Map key combinations to physical system printers',
          ),
          const SizedBox(height: 12),

          systemPrinters.isEmpty
              ? _buildShimmerLoading() // عرض الـ Shimmer المحدث هنا عند التحميل
              : _buildPrinterShortcutsList(systemPrinters, savedShortcuts),

          const SizedBox(height: 32),

          // ─── القسم الثاني الجديد: الإعدادات العامة ───
          _buildSectionHeader(
            'General System Preferences',
            'Configure core automation and printing engine behaviors',
          ),
          const SizedBox(height: 12),
          _buildGeneralSettingsSection(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }

  // مصفوفة الاختصارات (9 عناصر كاملة)
  Widget _buildPrinterShortcutsList(
    List<String> systemPrinters,
    List<PrinterShourtcut> savedShortcuts,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 9, // عرض كافة الـ 9 طابعات المتاحة للاختصارات
      itemBuilder: (context, index) {
        final printerNumber = index + 1;
        final currentShortcut = savedShortcuts.firstWhere(
          (s) => s.printerNumber == printerNumber,
          orElse: () =>
              PrinterShourtcut(printerNumber: printerNumber, printerName: ''),
        );

        final String? initialSelection =
            systemPrinters.contains(currentShortcut.printerName)
            ? currentShortcut.printerName
            : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$printerNumber',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Shortcut: Ctrl + $printerNumber',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                height: 38,
                child: DropdownButtonFormField<String>(
                  value: initialSelection,
                  hint: const Text(
                    'Not Assigned',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  dropdownColor: AppColors.bgSurface,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppColors.accent),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  items: systemPrinters
                      .map(
                        (String p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final updatedList = List<PrinterShourtcut>.from(
                        savedShortcuts,
                      )..removeWhere((s) => s.printerNumber == printerNumber);
                      updatedList.add(
                        PrinterShourtcut(
                          printerNumber: printerNumber,
                          printerName: val,
                        ),
                      );
                      savePrinterShortcut(ref, updatedList);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // الكود الخاص بالقسم الثاني من الإعدادات العامة (تم إصلاح خطأ الـ ListTile)
  Widget _buildGeneralSettingsSection() {
    final blankPageSeparator = ref.watch(blankPageSeparatorProvider);
    final globalCopies = ref.watch(globalCopiesProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // 🌟 الحل الجذري للـ ListTile Exception عبر إعادة الهيكلة بـ Row و Material شفاف لحماية المظهر الداكن والتأثير البصري
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Blank Page Separator',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Automatically injects a structural blank divider between batch retail files',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: blankPageSeparator,
                      activeColor: AppColors.accent,
                      onChanged: (value) =>
                          ref.read(blankPageSeparatorProvider.notifier).state =
                              value,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(color: AppColors.border, height: 24),

          // التحكم في عدد النسخ الافتراضي الكلي
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default Global Copies',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Current default setup value: $globalCopies copy(ies)',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: globalCopies > 1
                        ? () => ref.read(globalCopiesProvider.notifier).state--
                        : null,
                  ),
                  Text(
                    '$globalCopies',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    onPressed: () =>
                        ref.read(globalCopiesProvider.notifier).state++,
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 24),
          Row(
            children: [
              // ─── النصوص التوضيحية ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Clear Cache Data',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Resets all locally saved printer shortcuts and internal storage configurations.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ─── زرار الـ Clear المحسن ───
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                label: const Text(
                  'Clear Cache',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => clearCash(ref),
                style:
                    OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red, // لون الخط والأيقونة أحمر
                      side: BorderSide(
                        color: AppColors.red.withOpacity(0.4),
                      ), // بوردر أحمر خافت متناسق مع الدارك مود
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ).copyWith(
                      // إضافة Hover Effect ذكي لما الماوس يقف عليه على الديسكتوب
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                        states,
                      ) {
                        if (states.contains(WidgetState.hovered)) {
                          return AppColors.red.withOpacity(
                            0.08,
                          ); // خلفية حمراء خفيفة جداً عند الـ Hover
                        }
                        return Colors.transparent;
                      }),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // محاكي الـ Shimmer Loading المحدث ليعرض 9 بطاقات تحميل متناسقة
  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: AppColors.border.withOpacity(0.4),
      highlightColor: AppColors.bgSurface,
      child: Column(
        children: List.generate(
          9,
          (index) => Container(
            // 🌟 تم تعديله إلى 9 لمطابقة التصميم الجديد أثناء التحميل
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
