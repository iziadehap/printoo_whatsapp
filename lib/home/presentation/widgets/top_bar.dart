import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printoo_whatsapp/setting/setting_screen.dart';
import '../providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusProvider);

    return Container(
      height:
          50, // زيادة الطول قليلاً ليعطي مساحة تنفس للعناصر (Breathing Room)
      decoration: const BoxDecoration(
        color: AppColors.bgSidebar,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1,
          ), // فاصل سفلي نحيف جداً لإنهاء الـ TopBar
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ─── شعار التطبيق والاسم ───
          const Icon(Icons.print_rounded, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          const Text(
            'PRINT BOT POS',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.border.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'v6.0.0',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(width: 16),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: VerticalDivider(color: AppColors.border, width: 1),
          ),
          const SizedBox(width: 16),

          // ─── كبسولة حالة اتصال الواتساب المحسنة ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: status.whatsappConnected
                  ? AppColors.accent.withOpacity(0.06)
                  : AppColors.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: status.whatsappConnected
                    ? AppColors.accent.withOpacity(0.15)
                    : AppColors.red.withOpacity(0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulsingDot(connected: status.whatsappConnected),
                const SizedBox(width: 8),
                Text(
                  status.whatsappConnected
                      ? 'WhatsApp Connected'
                      : 'WhatsApp Disconnected',
                  style: TextStyle(
                    color: status.whatsappConnected
                        ? AppColors.accent
                        : AppColors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ─── أزرار التحكم والعمليات ───
          TopBarBtn(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onPressed: () => _openSettings(context, ref),
          ),
          const SizedBox(width: 8),
          TopBarBtn(
            icon: Icons.folder_open_outlined,
            label: 'Open Folder',
            onPressed: () => _openCustomerFolder(context, ref),
          ),
          const SizedBox(width: 8),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: VerticalDivider(color: AppColors.border, width: 1),
          ),
          const SizedBox(width: 8),

          TopBarBtn(
            icon: Icons.logout_rounded,
            label: 'Logout',
            isDanger: true,
            onPressed: () => _handleLogout(context, ref),
          ),
        ],
      ),
    );
  }

  void _openCustomerFolder(BuildContext context, WidgetRef ref) async {
    final folder = ref.read(customerFolderProvider);
    if (folder != null) {
      try {
        if (Platform.isMacOS) {
          await Process.run('open', [folder]);
        } else if (Platform.isWindows) {
          await Process.run('explorer.exe', [folder]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [folder]);
        }
        if (context.mounted) {
          _snack(context, 'Opened folder: $folder');
        }
      } catch (e) {
        if (context.mounted) {
          _snack(
            context,
            'Could not open folder: ${e.toString()}',
            isError: true,
          );
        }
      }
    } else {
      _snack(context, 'No active customer folder to open.', isError: true);
    }
  }

  void _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: const Text(
          'Confirm Logout',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'This will destroy the WhatsApp session and reset the terminal. Proceed?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Logout Terminal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(appRepositoryProvider).logout();
        if (context.mounted) {
          _snack(context, 'Logging out, resetting terminal...');
        }
        await Future.delayed(const Duration(seconds: 1));
        exit(0);
      } catch (e) {
        if (context.mounted) {
          _snack(context, 'Logout failed: ${e.toString()}', isError: true);
        }
      }
    }
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingScreen()),
    );
  }

  void _snack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? AppColors.red : AppColors.accent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class PulsingDot extends StatefulWidget {
  final bool connected;
  const PulsingDot({required this.connected, super.key});

  @override
  State<PulsingDot> createState() => PulsingDotState();
}

class PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? AppColors.accent : AppColors.red;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: widget.connected ? _anim.value : 1.0,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── كود الزر المحسن بالكامل مع الـ Hover والـ InkWell السليم ───
class TopBarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDanger;

  const TopBarBtn({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDanger = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isDanger ? AppColors.red : AppColors.textSecondary;

    return Material(
      color: Colors.transparent, // جعل الماتيريال شفاف لكي نتحكم بالخلفية بدقة
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: isDanger
            ? AppColors.red.withOpacity(0.1)
            : AppColors.border.withOpacity(0.4),
        highlightColor: AppColors.border.withOpacity(0.6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.border.withOpacity(0.5),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: baseColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isDanger ? AppColors.red : AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
