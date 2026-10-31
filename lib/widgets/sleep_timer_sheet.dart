import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../theme/app_theme.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key, required this.controller});

  final PlayerController controller;
  static const _minutes = [5, 10, 15, 30, 45, 60];

  static Future<void> show(BuildContext context, PlayerController controller) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SleepTimerSheet(controller: controller),
      );

  static String formatRemaining(Duration value) {
    final seconds = (value.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final remaining = controller.sleepTimerRemaining;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sleep timer',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    controller.sleepAfterTrack
                        ? 'Setelah lagu ini selesai'
                        : remaining == null
                            ? 'Berhenti otomatis'
                            : 'Sisa ${formatRemaining(remaining)}',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                      builder: (context, area) => Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final minutes in _minutes)
                                SizedBox(
                                  width: (area.maxWidth - 10) / 2,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          controller.sleepTimerDuration ==
                                                  Duration(minutes: minutes)
                                              ? AppColors.accent
                                              : AppColors.textPrimary,
                                      backgroundColor:
                                          controller.sleepTimerDuration ==
                                                  Duration(minutes: minutes)
                                              ? AppColors.accent.withOpacity(.1)
                                              : null,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      side: BorderSide(
                                          color:
                                              controller.sleepTimerDuration ==
                                                      Duration(minutes: minutes)
                                                  ? AppColors.accent
                                                  : AppColors.borderSubtle),
                                    ),
                                    onPressed: () {
                                      controller.setSleepTimer(
                                          Duration(minutes: minutes));
                                      Navigator.pop(context);
                                    },
                                    child: Text('$minutes menit'),
                                  ),
                                ),
                            ],
                          )),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.music_note_rounded,
                        color: AppColors.accent),
                    title: const Text('Setelah lagu ini selesai'),
                    trailing: controller.sleepAfterTrack
                        ? Icon(Icons.check_rounded,
                            color: AppColors.accent)
                        : null,
                    onTap: () {
                      controller.setSleepAfterTrack();
                      Navigator.pop(context);
                    },
                  ),
                  if (controller.hasSleepTimer) ...[
                    Divider(color: AppColors.borderSubtle),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timer_off_outlined),
                      title: const Text('Matikan timer'),
                      onTap: () {
                        controller.cancelSleepTimer();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
