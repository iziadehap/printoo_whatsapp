import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart'; // 🌟 1. استيراد الحزمة الجديدة
import 'package:printoo_whatsapp/home/domain/entities/printer_shourtcut.dart';
import 'package:printoo_whatsapp/home/presentation/home_shell.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🌟 2. تأمين تهيئة الـ Window Manager لمنصات الديسكتوب
  await windowManager.ensureInitialized();

  try {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocumentDir.path);
    debugPrint(
      '[Hive] Initialized successfully at path: ${appDocumentDir.path}',
    );
  } catch (e) {
    debugPrint('[Hive] Initialization failed: $e');
  }

  Hive.registerAdapter(PrinterShourtcutAdapter());

  // 🌟 3. إعداد قيود حجم الشاشة ومنع تصغيرها عن 1000x1000
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 700), // الحجم المبدئي عند فتح التطبيق (العرض × الطول)
    minimumSize: Size(1000, 700), // 🛑 أقل حجم مسموح للمستخدم يصغّر الشاشة إليه
    center: true, // فتح النافذة في منتصف شاشة الماك/الويندوز تلقائياً
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  // تطبيق الإعدادات وإظهار النافذة للمستخدم
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: PrintBotApp()));
}

class PrintBotApp extends StatelessWidget {
  const PrintBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Printoo whatsapp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
