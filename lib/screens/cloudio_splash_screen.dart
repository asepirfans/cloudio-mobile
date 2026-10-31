import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows the supplied Cloudio logo before entering the main app.
class CloudioSplashScreen extends StatefulWidget {
  const CloudioSplashScreen({
    super.key,
    required this.nextScreenBuilder,
    this.holdDuration = const Duration(milliseconds: 1000),
  });

  final WidgetBuilder nextScreenBuilder;
  final Duration holdDuration;

  @override
  State<CloudioSplashScreen> createState() => _CloudioSplashScreenState();
}

class _CloudioSplashScreenState extends State<CloudioSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _introController.forward();
    });
    Future.delayed(widget.holdDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: widget.nextScreenBuilder),
      );
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Logo Cloudio',
              child: Image.asset(
                'assets/images/cloudio-app-icon.png',
                width: 160,
                height: 160,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: _introController,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _introController,
                    curve: Curves.easeOut,
                  ),
                ),
                child: const _CloudioWordmark(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudioWordmark extends StatelessWidget {
  const _CloudioWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'InstrumentSans',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        children: [
          TextSpan(
              text: 'Cloud', style: TextStyle(color: AppColors.textPrimary)),
          TextSpan(text: 'io', style: TextStyle(color: AppColors.accent)),
        ],
      ),
    );
  }
}
