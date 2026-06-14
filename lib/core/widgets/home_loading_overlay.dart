import 'dart:math';
import 'package:flutter/material.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/core/theme/app_theme.dart';

/// A premium full-screen loading overlay shown while home data is fetched.
///
/// Features:
/// - Lavender gradient background matching the app palette
/// - Animated logo with a gentle pulse + soft glow ring
/// - Three bouncing dots in brand purple
/// - Smooth fade-out when [visible] transitions to false
class HomeLoadingOverlay extends StatefulWidget {
  final bool visible;
  const HomeLoadingOverlay({super.key, required this.visible});

  @override
  State<HomeLoadingOverlay> createState() => _HomeLoadingOverlayState();
}

class _HomeLoadingOverlayState extends State<HomeLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _dotsController;
  late final AnimationController _glowController;
  late final AnimationController _fadeController;

  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  bool _shouldRender = true;

  @override
  void initState() {
    super.initState();

    // Logo pulse: gentle scale 0.96 → 1.04 over 1.4s
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Glow ring: subtle opacity pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Bouncing dots: 1.6s loop
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // Fade out controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: widget.visible ? 1.0 : 0.0,
    );

    _shouldRender = widget.visible;
  }

  @override
  void didUpdateWidget(covariant HomeLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      setState(() => _shouldRender = true);
      _fadeController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _fadeController.reverse().then((_) {
        if (mounted) setState(() => _shouldRender = false);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotsController.dispose();
    _glowController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldRender) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFA99DE7),
              Color(0xFFB6ACEA),
              Color(0xFFC5BDF0),
              Color(0xFFDDD6FE),
              Color(0xFFEDE9FE),
              Colors.white,
            ],
            stops: [0.0, 0.15, 0.30, 0.50, 0.72, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              // Animated glow ring behind logo
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, child) {
                  return Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: _glowAnim.value,
                          ),
                          blurRadius: 60,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) {
                    return Transform.scale(
                      scale: _pulseAnim.value,
                      child: child,
                    );
                  },
                  child: Image.asset(
                    AppConstants.logoPath,
                    width: 180,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Tagline
              const Text(
                'ONE-STOP PLATFORM FOR SALONS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1A1230),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(flex: 2),
              // Bouncing dots
              _BouncingDots(controller: _dotsController),
              const SizedBox(height: 16),
              // Loading text
              Text(
                'Setting up your store...',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots that bounce in sequence, creating a wave-like loading animation.
class _BouncingDots extends StatelessWidget {
  final AnimationController controller;
  const _BouncingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: controller,
          builder: (_, _) {
            // Each dot is offset by 0.2 in the animation cycle
            final progress = (controller.value - index * 0.2) % 1.0;
            // Use a sine curve for smooth bounce (only bounce in first half)
            final bounce = progress < 0.5
                ? sin(progress * 2 * pi * 0.5) * 10
                : 0.0;
            final opacity = progress < 0.5
                ? 0.5 + 0.5 * sin(progress * 2 * pi * 0.5)
                : 0.4;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.translate(
                offset: Offset(0, -bounce),
                child: Opacity(
                  opacity: opacity.clamp(0.3, 1.0),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
