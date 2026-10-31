import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum PlayerVisualTheme {
  cover('Sampul', Icons.crop_square_rounded),
  vinyl('Piringan', Icons.album_outlined),
  cassette('Kaset', Icons.video_label_outlined);

  const PlayerVisualTheme(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Only the disc animates. Playback and the native queue stay independent.
class PlayerVisual extends StatefulWidget {
  const PlayerVisual(
      {super.key,
      required this.theme,
      required this.imageUrl,
      required this.size,
      required this.playing,
      this.accentColor});
  final PlayerVisualTheme theme;
  final String? imageUrl;
  final double size;
  final bool playing;
  final Color? accentColor;
  @override
  State<PlayerVisual> createState() => _PlayerVisualState();
}

class _PlayerVisualState extends State<PlayerVisual>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlayerVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final animate = (widget.theme == PlayerVisualTheme.vinyl ||
            widget.theme == PlayerVisualTheme.cassette) &&
        widget.playing &&
        _foreground &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_rotation.isAnimating) _rotation.repeat();
    if (!animate && _rotation.isAnimating) _rotation.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotation.dispose();
    super.dispose();
  }

  Widget _cover(double size, {bool round = false}) => ClipRRect(
      borderRadius: BorderRadius.circular(round ? size : 16),
      child: SizedBox.square(
          dimension: size,
          child: widget.imageUrl == null
              ? ColoredBox(
                  color: AppColors.elevated,
                  child: const Icon(Icons.music_note_rounded, size: 44))
              : CachedNetworkImage(
                  imageUrl: widget.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(
                      color: AppColors.elevated,
                      child: const Icon(Icons.music_note_rounded, size: 44)))));
  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox.square(
        dimension: size,
        child: switch (widget.theme) {
          PlayerVisualTheme.cover => _cover(size),
          PlayerVisualTheme.vinyl => RepaintBoundary(
                child: Stack(children: [
              Positioned(
                  left: size * .02,
                  top: size * .12,
                  child: SizedBox.square(
                    dimension: size * .82,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x80000000),
                                blurRadius: 24,
                                offset: Offset(0, 12))
                          ]),
                      child: Stack(alignment: Alignment.center, children: [
                        Positioned.fill(
                            child: CustomPaint(painter: _Grooves())),
                        RotationTransition(
                            turns: _rotation,
                            child: SizedBox.square(
                                dimension: size * .82,
                                child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                          width: size * .30,
                                          height: size * .30,
                                          decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFFD9DFDE))),
                                      _cover(size * .27, round: true),
                                      Container(
                                          width: size * .025,
                                          height: size * .025,
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFF080B0E),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF98A2A8),
                                                  width: 1.5))),
                                    ]))),
                      ]),
                    ),
                  )),
              Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                tween: Tween(
                    begin: widget.playing ? 1 : 0, end: widget.playing ? 1 : 0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                curve: Curves.easeInOutCubic,
                builder: (_, engagement, __) => CustomPaint(
                    painter: _Tonearm(engagement,
                        accentColor: widget.accentColor)),
              )),
            ])),
          PlayerVisualTheme.cassette => Center(
                child: RepaintBoundary(
              child: SizedBox(
                width: size,
                height: size * .64,
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _CassetteBody())),
                  Positioned(
                      left: size * .12,
                      top: size * .055,
                      width: size * .76,
                      height: size * .13,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: widget.imageUrl == null
                              ? ColoredBox(
                                  color: widget.accentColor ?? AppColors.accent)
                              : CachedNetworkImage(
                                  imageUrl: widget.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => ColoredBox(
                                      color: widget.accentColor ??
                                          AppColors.accent)))),
                  for (final x in [.17, .59])
                    Positioned(
                        left: size * x,
                        top: size * .255,
                        width: size * .24,
                        height: size * .24,
                        child: RotationTransition(
                            turns: _rotation,
                            child: CustomPaint(painter: _TapeReel()))),
                ]),
              ),
            )),
        });
  }
}

class _Grooves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final bounds = Offset.zero & size;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = const RadialGradient(
            colors: [
              Color(0xFF282A2D),
              Color(0xFF111214),
              Color(0xFF08090B),
              Color(0xFF303236)
            ],
            stops: [0, .35, .975, 1],
          ).createShader(bounds));
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .55;
    for (double r = radius * .40; r < radius * .97; r += 1.7) {
      final band = ((r / 13).floor() % 3);
      groove.color = Color.fromRGBO(170, 177, 185, band == 0 ? .16 : .075);
      canvas.drawCircle(center, r, groove);
    }
    // Broad reflections stay fixed under the light as the record label turns.
    canvas.drawCircle(
        center,
        radius * .982,
        Paint()
          ..shader = const SweepGradient(
            transform: GradientRotation(-math.pi / 3),
            colors: [
              Colors.transparent,
              Color(0x263F464E),
              Color(0x55858E97),
              Color(0x103F464E),
              Colors.transparent,
              Color(0x44717B84),
              Colors.transparent
            ],
            stops: [0, .12, .20, .28, .48, .70, 1],
          ).createShader(bounds));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    edge.color = const Color(0xFF42464C);
    canvas.drawCircle(center, radius - .7, edge);
    edge.color = const Color(0xFF08090B);
    canvas.drawCircle(center, radius * .385, edge..strokeWidth = 2);
    canvas.drawCircle(center, radius * .36, edge..strokeWidth = .7);
  }

  @override
  bool shouldRepaint(covariant _Grooves oldDelegate) => false;
}

class _Tonearm extends CustomPainter {
  const _Tonearm(this.engagement, {this.accentColor});
  final double engagement;
  final Color? accentColor;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 320);
    const pivot = Offset(281, 43);
    final metal = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF54616C), Color(0xFFE6EDF0), Color(0xFF71818B)],
      ).createShader(const Rect.fromLTWH(257, 20, 46, 48));
    canvas.drawCircle(pivot + const Offset(2, 4), 20,
        Paint()..color = const Color(0x66000000));
    canvas.drawCircle(pivot, 18, Paint()..color = const Color(0xFF111A22));
    canvas.drawCircle(pivot, 14, metal);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-.50 * (1 - engagement));
    // Counterweight, bent chrome arm and cartridge share one moving assembly.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-9, -26, 18, 17), const Radius.circular(4)),
        Paint()..color = const Color(0xFF29333B));
    canvas.drawLine(
        const Offset(0, -20),
        const Offset(0, 0),
        Paint()
          ..color = const Color(0xFF8998A2)
          ..strokeWidth = 5);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(-5, 53)
      ..quadraticBezierTo(-5, 61, -11, 69)
      ..lineTo(-50, 116);
    canvas.drawPath(
        path.shift(const Offset(3, 4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x66000000)
          ..strokeWidth = 8);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7A8994),
                Color(0xFFE1E9EF),
                Color(0xFF7D8C97)
              ]).createShader(const Rect.fromLTWH(-60, 0, 70, 120))
          ..strokeWidth = 6);
    canvas.drawPath(
        path.shift(const Offset(-1, 0)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xA8E5F4FF)
          ..strokeWidth = 1.2);
    canvas.save();
    canvas.translate(-50, 116);
    canvas.rotate(.69);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-7, -5, 14, 25), const Radius.circular(3)),
        Paint()..color = const Color(0xFF253A4A));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-6, 10, 12, 9), const Radius.circular(2)),
        Paint()..color = accentColor ?? AppColors.accent);
    canvas.drawLine(
        const Offset(0, 19),
        const Offset(0, 24),
        Paint()
          ..color = const Color(0xFFDCE9EE)
          ..strokeWidth = 1.5);
    canvas.restore();
    canvas.drawCircle(Offset.zero, 6, Paint()..color = const Color(0xFF33434E));
    canvas.drawCircle(Offset.zero, 2, Paint()..color = const Color(0xFFD0DCE3));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Tonearm oldDelegate) =>
      engagement != oldDelegate.engagement ||
      accentColor != oldDelegate.accentColor;
}

class _CassetteBody extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 205);
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, 316, 201), const Radius.circular(16));
    canvas.drawShadow(
        Path()..addRRect(body), const Color(0xAA000000), 12, true);
    canvas.drawRRect(
        body,
        Paint()
          ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF354853),
                Color(0xFF14212A),
                Color(0xFF293B46)
              ]).createShader(const Rect.fromLTWH(0, 0, 320, 205)));
    canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF61737E));
    final label = RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 16, 264, 142), const Radius.circular(10));
    canvas.drawRRect(label, Paint()..color = const Color(0xFFB6D5E7));
    final window = RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 78, 236, 76), const Radius.circular(25));
    canvas.drawRRect(window, Paint()..color = const Color(0xFF0A1117));
    canvas.drawRRect(
        window,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF738F9F));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(135, 94, 50, 42), const Radius.circular(5)),
        Paint()..color = const Color(0xFF40372F));
    for (double y = 98; y < 136; y += 4) {
      canvas.drawLine(
          Offset(138, y),
          Offset(182, y),
          Paint()
            ..color = const Color(0xFF1C1A18)
            ..strokeWidth = 1);
    }
    final head = Path()
      ..moveTo(73, 170)
      ..lineTo(247, 170)
      ..lineTo(265, 202)
      ..lineTo(55, 202)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFF111C24));
    canvas.drawPath(
        head,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF536874)
          ..strokeWidth = 1);
    for (final x in [89.0, 231.0]) {
      canvas.drawCircle(
          Offset(x, 186), 7, Paint()..color = const Color(0xFF060C11));
      canvas.drawCircle(
          Offset(x, 186), 4, Paint()..color = const Color(0xFF7D8E98));
    }
    for (final point in [
      const Offset(14, 15),
      const Offset(306, 15),
      const Offset(14, 190),
      const Offset(306, 190)
    ]) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFF9AABB6));
      canvas.drawLine(
          point - const Offset(2, 0),
          point + const Offset(2, 0),
          Paint()
            ..color = const Color(0xFF20303B)
            ..strokeWidth = 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CassetteBody oldDelegate) => false;
}

class _TapeReel extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1A1614));
    canvas.drawCircle(
        center, radius * .71, Paint()..color = const Color(0xFFA1AEB4));
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi * 2 / 3);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  -radius * .17, -radius * .59, radius * .34, radius * .37),
              const Radius.circular(3)),
          Paint()..color = const Color(0xFF14202A));
      canvas.restore();
    }
    canvas.drawCircle(
        center, radius * .17, Paint()..color = const Color(0xFF15232D));
  }

  @override
  bool shouldRepaint(covariant _TapeReel oldDelegate) => false;
}
