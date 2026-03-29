import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/features/auth/login/login_screen.dart';
import 'package:purecuts/features/auth/pending_approval_screen.dart';
import 'package:purecuts/features/main_nav/main_nav_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _logoScaleAnim;
  late final Animation<double> _taglineSlideAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
    );

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _logoScaleAnim = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.05, 0.62, curve: Curves.easeOutBack),
      ),
    );

    _taglineSlideAnim = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _revealController.forward();

    Future.delayed(const Duration(milliseconds: 1700), () async {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      bool isLoggedIn = false;
      bool isApproved = false;
      if (user != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          if (doc.exists) {
            isLoggedIn = true;
            final data = doc.data() ?? const <String, dynamic>{};
            final status = (data['verificationStatus'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            isApproved =
                data['accessApproved'] == true ||
                data['isVerified'] == true ||
                status == 'approved';
          } else {
            await FirebaseAuth.instance.signOut();
          }
        } catch (_) {
          // Firestore unreachable — sign out to be safe
          await FirebaseAuth.instance.signOut();
        }
      }
      if (!mounted) return;
      final Widget destination = !isLoggedIn
          ? const LoginScreen()
          : (isApproved
                ? const MainNavScreen()
                : const PendingApprovalScreen());
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => destination,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _revealController,
          builder: (_, __) {
            return Container(
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
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Opacity(
                      opacity: _fadeAnim.value,
                      child: Transform.translate(
                        offset: Offset(0, _taglineSlideAnim.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: _logoScaleAnim.value,
                                child: Image.asset(
                                  AppConstants.logoPath,
                                  width: 300,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'ONE-STOP PLATFORM FOR SALONS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF1A1230),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 38,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: 0.75,
                      child: const Text(
                        'Loading your professional experience...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF5C138B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
