import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/push_notification_service.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/orders/order_provider.dart';

import 'package:purecuts/features/splash/splash_screen.dart';
import 'firebase_options.dart';

late final CartModel _initialCartModel;

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    _initialCartModel = await CartModel.create();
  } catch (_) {
    _initialCartModel = CartModel.empty();
  }
  runApp(const PureCutsApp());
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider<CartModel>.value(value: _initialCartModel),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
      ],
      child: MaterialApp(
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
