import 'dart:math' as math;
import 'package:flutter/material.dart';

class MiniAudioVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color? color;
  final double height;
  final int barCount;

  const MiniAudioVisualizer({
    super.key,
    required this.isPlaying,
    this.color,
    this.height = 18.0,
    this.barCount = 4,
  });

  @override
  State<MiniAudioVisualizer> createState() => _MiniAudioVisualizerState();
}

class _MiniAudioVisualizerState extends State<MiniAudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Base phase offsets for natural equalizer frequency bars
  final List<double> _phases = [0.0, 1.8, 0.9, 2.5, 1.4];
  final List<double> _speeds = [1.2, 1.8, 1.5, 2.1, 1.0];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MiniAudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor =
        widget.color ?? Theme.of(context).colorScheme.primary;
    final count = widget.barCount.clamp(3, 5);

    return SizedBox(
      height: widget.height,
      width: (count * 3.5) + ((count - 1) * 2.5),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(count, (index) {
              final speed = _speeds[index % _speeds.length];
              final phase = _phases[index % _phases.length];

              // Natural sine-based oscillation
              final wave = math.sin((t * speed) + phase).abs();
              const minHeight = 3.0;
              final maxHeight = widget.height;
              final targetHeight = widget.isPlaying
                  ? minHeight + (wave * (maxHeight - minHeight))
                  : minHeight;

              return Container(
                width: 3.5,
                height: targetHeight,
                decoration: BoxDecoration(
                  color: activeColor.withOpacity(widget.isPlaying ? 0.95 : 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
