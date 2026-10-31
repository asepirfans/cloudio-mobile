import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/music_recognition_controller.dart';
import '../controllers/player_controller.dart';
import '../services/music_recognition_service.dart';
import '../theme/app_theme.dart';

class MusicRecognitionSheet extends StatefulWidget {
  const MusicRecognitionSheet(
      {super.key, required this.player, this.controller});
  final PlayerController player;
  final MusicRecognitionController? controller;
  static Future<RecognizedMusic?> show(
          BuildContext context, PlayerController player) =>
      showModalBottomSheet<RecognizedMusic>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => MusicRecognitionSheet(player: player));
  @override
  State<MusicRecognitionSheet> createState() => _MusicRecognitionSheetState();
}

class _MusicRecognitionSheetState extends State<MusicRecognitionSheet>
    with WidgetsBindingObserver {
  late final _recognition = widget.controller ?? MusicRecognitionController();
  bool _delivered = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recognition.addListener(_changed);
  }

  void _changed() {
    final result = _recognition.result;
    if (result != null && !_delivered && mounted) {
      _delivered = true;
      Navigator.pop(context, result);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _recognition.busy) {
      unawaited(_recognition.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recognition.removeListener(_changed);
    _recognition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85),
          child: SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: AnimatedBuilder(
                animation: _recognition,
                builder: (context, _) {
                  final phase = _recognition.phase;
                  final listening = phase == RecognitionPhase.listening;
                  final matching = phase == RecognitionPhase.matching ||
                      phase == RecognitionPhase.preparing;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Kenali lagu',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 24),
                    Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent.withOpacity(.12)),
                        child: matching
                            ? const Padding(
                                padding: EdgeInsets.all(30),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                listening
                                    ? Icons.graphic_eq_rounded
                                    : Icons.mic_none_rounded,
                                size: 44,
                                color: AppColors.accent)),
                    const SizedBox(height: 20),
                    Text(
                        switch (phase) {
                          RecognitionPhase.preparing => 'Menyiapkan mikrofon…',
                          RecognitionPhase.listening => 'Mendengarkan…',
                          RecognitionPhase.matching ||
                          RecognitionPhase.found =>
                            'Mencari lagu…',
                          RecognitionPhase.noMatch =>
                            'Belum ketemu. Coba potongan lain.',
                          RecognitionPhase.error =>
                            _recognition.error ?? 'Coba lagi.',
                          RecognitionPhase.ready =>
                            'Dekatkan HP ke sumber musik.',
                        },
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    if (listening) ...[
                      LinearProgressIndicator(
                          value: (_recognition.elapsed.inMilliseconds / 12000)
                              .clamp(0, 1),
                          color: AppColors.accent,
                          backgroundColor: AppColors.borderSubtle),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: matching
                              ? null
                              : listening
                                  ? () => _recognition.cancel()
                                  : () => _recognition.listen(widget.player),
                          child: Text(listening
                              ? 'Batal'
                              : phase == RecognitionPhase.ready
                                  ? 'Dengarkan'
                                  : 'Coba lagi'),
                        )),
                  ]);
                }),
          ))));
}
