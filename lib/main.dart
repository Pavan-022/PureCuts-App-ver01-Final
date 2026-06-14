import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/navigation/app_navigator.dart';
import 'package:purecuts/core/services/deep_link_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/push_notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:purecuts/core/constants/feature_flags.dart';
import 'package:purecuts/features/auth/login/login_screen.dart';
import 'package:purecuts/features/auth/pending_approval_screen.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/main_nav/main_nav_screen.dart';
import 'package:purecuts/features/splash/splash_screen.dart';
import 'package:purecuts/features/orders/order_provider.dart';

import 'firebase_options.dart';

late final CartModel _initialCartModel;

FirebaseOptions _buildFirebaseOptionsFromEnv() {
  final apiKey = dotenv.env['FIREBASE_API_KEY'];
  final appId = dotenv.env['FIREBASE_APP_ID'];
  final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
  final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'];
  final authDomain = dotenv.env['FIREBASE_AUTH_DOMAIN'];
  final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
  final measurementId = dotenv.env['FIREBASE_MEASUREMENT_ID'];

  if (apiKey != null && apiKey.isNotEmpty && appId != null && appId.isNotEmpty && projectId != null && projectId.isNotEmpty && messagingSenderId != null && messagingSenderId.isNotEmpty) {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      authDomain: authDomain,
      storageBucket: storageBucket,
      measurementId: measurementId,
    );
  }
  return DefaultFirebaseOptions.currentPlatform;
}

class _SlideLeftPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideLeftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Curves.easeOutCubic;

    final inAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).chain(CurveTween(curve: curve)).animate(animation);

    final outAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.08, 0),
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);

    return SlideTransition(
      position: outAnimation,
      child: SlideTransition(position: inAnimation, child: child),
    );
  }
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: ".env");
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      final envOptions = _buildFirebaseOptionsFromEnv();
      await Firebase.initializeApp(
        options: envOptions,
      );

      final crashlytics = FirebaseCrashlytics.instance;
      final performance = FirebasePerformance.instance;

      await performance.setPerformanceCollectionEnabled(true);

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        crashlytics.recordFlutterError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      try {
        _initialCartModel = await CartModel.create();
      } catch (_) {
        _initialCartModel = CartModel.empty();
      }

      runApp(const PureCutsApp());
    },
    (error, stack) async {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
  );
}

class PureCutsApp extends StatefulWidget {
  const PureCutsApp({super.key});

  @override
  State<PureCutsApp> createState() => _PureCutsAppState();
}

class _PureCutsAppState extends State<PureCutsApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.instance.initialize();
      unawaited(DeepLinkService.instance.initialize());
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider<CartModel>.value(value: _initialCartModel),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
        ChangeNotifierProxyProvider<AuthProvider, OrderProvider>(
          create: (_) => OrderProvider(),
          update: (_, auth, orders) {
            final resolved = orders ?? OrderProvider();
            resolved.syncAuthUid(auth.user?.uid);
            return resolved;
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'PureCuts',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _SlideLeftPageTransitionsBuilder(),
              TargetPlatform.iOS: _SlideLeftPageTransitionsBuilder(),
              TargetPlatform.macOS: _SlideLeftPageTransitionsBuilder(),
              TargetPlatform.windows: _SlideLeftPageTransitionsBuilder(),
              TargetPlatform.linux: _SlideLeftPageTransitionsBuilder(),
              TargetPlatform.fuchsia: _SlideLeftPageTransitionsBuilder(),
            },
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  Widget? _child;

  @override
  void initState() {
    super.initState();
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    _child = user == null ? const LoginScreen() : const MainNavScreen();
    _resolveStartupDestination();
  }

  Future<void> _resolveStartupDestination() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      final cacheDoc = await userRef
          .get(const GetOptions(source: Source.cache))
          .timeout(
            Duration(
              milliseconds: (FeatureFlags.splashUserDocTimeoutMs / 2).round(),
            ),
          );
      if (cacheDoc.exists) {
        final data = cacheDoc.data() ?? const <String, dynamic>{};
        if (!mounted) return;
        setState(() {
          _child = _isApproved(data)
              ? const MainNavScreen()
              : const PendingApprovalScreen();
        });
        return;
      }
    } catch (_) {
      // Continue to bounded server fetch.
    }

    try {
      final serverDoc = await userRef.get().timeout(
            Duration(milliseconds: FeatureFlags.splashUserDocTimeoutMs),
          );
      if (serverDoc.exists) {
        final data = serverDoc.data() ?? const <String, dynamic>{};
        if (!mounted) return;
        setState(() {
          _child = _isApproved(data)
              ? const MainNavScreen()
              : const PendingApprovalScreen();
        });
        return;
      }
    } catch (_) {
      // Fall through to resilient signed-in fallback.
    }

    if (!mounted) return;
    setState(() {
      _child = const MainNavScreen();
    });
  }

  bool _isApproved(Map<String, dynamic> data) {
    final status = (data['verificationStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return data['accessApproved'] == true ||
        data['isVerified'] == true ||
        status == 'approved';
  }

  @override
  Widget build(BuildContext context) {
    return _child ?? const SizedBox.shrink();
  }
}
