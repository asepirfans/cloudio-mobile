import 'package:flutter/material.dart';

import '../controllers/theme_controller.dart';
import '../theme/app_theme.dart';

class ThemeSelectionSheet extends StatelessWidget {
  const ThemeSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ThemeSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final themeController = ThemeController.instance;
        final currentMode = themeController.mode;
        final isLight = Theme.of(context).brightness == Brightness.light;

        return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isLight ? Colors.black12 : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Tema Tampilan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Sesuaikan warna antarmuka Cloudio sesuai kenyamanan mata.',
              style: TextStyle(
                fontSize: 13,
                color: isLight ? const Color(0xFF64748B) : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            _themeTile(
              context: context,
              mode: AppThemeMode.dark,
              title: 'Gelap (Midnight Navy)',
              subtitle: 'Warna biru malam khas Cloudio, nyaman di ruangan redup',
              icon: Icons.nightlight_round,
              selected: currentMode == AppThemeMode.dark,
              onTap: () {
                themeController.setThemeMode(AppThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _themeTile(
              context: context,
              mode: AppThemeMode.light,
              title: 'Terang (Daylight)',
              subtitle: 'Latar cerah bersih, optimal saat berada di luar ruangan',
              icon: Icons.wb_sunny_rounded,
              selected: currentMode == AppThemeMode.light,
              onTap: () {
                themeController.setThemeMode(AppThemeMode.light);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _themeTile(
              context: context,
              mode: AppThemeMode.warm,
              title: 'Hangat (Warm Cokelat)',
              subtitle: 'Nuansa cokelat hangat nan elegan, lembut dan nyaman untuk mata',
              icon: Icons.coffee_rounded,
              selected: currentMode == AppThemeMode.warm,
              onTap: () {
                themeController.setThemeMode(AppThemeMode.warm);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  },
);
  }

  Widget _themeTile({
    required BuildContext context,
    required AppThemeMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: selected
          ? primaryColor.withOpacity(0.12)
          : (isLight ? const Color(0xFFF1F5F9) : AppColors.elevated),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? primaryColor.withOpacity(0.2)
                      : (isLight ? Colors.white : AppColors.card),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? primaryColor : (isLight ? Colors.black87 : Colors.white70),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? primaryColor : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLight ? const Color(0xFF64748B) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: primaryColor,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
