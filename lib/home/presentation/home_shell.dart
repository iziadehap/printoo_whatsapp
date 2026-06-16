import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printoo_whatsapp/home/presentation/providers/app_providers.dart';
import 'package:printoo_whatsapp/core/theme/app_theme.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/bottom_bar.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/main_panel.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/sidebar.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/top_bar.dart';
import 'package:printoo_whatsapp/home/presentation/widgets/customer_order_dialog.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // اعتراض الأزرار من جذور المحرك لمنع نظام الماك من سرقتها 🔇
    ServicesBinding.instance.keyboard.addHandler(_handleGlobalKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      init(ref);
    });
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleGlobalKeyEvent);
    super.dispose();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
      final isControlPressed = HardwareKeyboard.instance.isControlPressed;

      // 1. خطف اختصار التحديد الكل (Cmd + A أو Ctrl + A)
      if (event.logicalKey == LogicalKeyboardKey.keyA &&
          (isMetaPressed || isControlPressed)) {
        ref.read(mediaProvider.notifier).toggleAllFiles();
        return true; // تم التعامل مع الزر بنجاح
      }

      // 2. خطف اختصارات الأرقام ديناميكياً من 1 إلى 9 (سواء بـ Ctrl أو Cmd على الماك)
      if (isControlPressed || isMetaPressed) {
        final keyLabel = event.logicalKey.keyLabel;
        // التأكد أن الزر المضغوط هو رقم بين 1 و 9
        if (keyLabel.length == 1 && RegExp(r'[1-9]').hasMatch(keyLabel)) {
          final int printerNumber = int.parse(keyLabel);

          // استدعاء دالة جلب واختيار الطابعة الذكية
          print('==========');
          print('==========');
          print(printerNumber);
          selectPrinter(ref, printerNumber);

          return true; // اقطع الصوت ومنع الماك من فتح الـ Spaces 🔇
        }
      }
    }
    return false; // مرر باقي الأزرار للنظام بشكل طبيعي
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // اختصارات الطباعة فقط (تم تنظيف التكرار والأرقام من هنا)
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _triggerPrint(context),
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
            _triggerPrint(context),
      },
      child: Scaffold(
        body: Column(
          children: [
            const TopBar(),
            Expanded(
              child: Row(
                children: [
                  const Sidebar(),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: MainPanel()),
                ],
              ),
            ),
            const BottomBar(),
          ],
        ),
      ),
    );
  }

  void _triggerPrint(BuildContext context) {
    final customer = ref.read(selectedCustomerProvider);
    if (customer == null) {
      _snack(context, 'No customer selected.', isError: true);
      return;
    }
    showCustomerOrderDialog(context: context, ref: ref, customer: customer);
  }

  void _snack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: isError ? AppColors.red : AppColors.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
