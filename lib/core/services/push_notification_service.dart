import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important app notifications.',
    importance: Importance.max,
  );

  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _initializeLocalNotifications();
      await _messaging.setAutoInitEnabled(true);

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        '[PushNotificationService] Permission status: ${settings.authorizationStatus}',
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final androidPermissionGranted = await androidPlugin
          ?.requestNotificationsPermission();
      debugPrint(
        '[PushNotificationService] Android runtime notification permission granted: ${androidPermissionGranted ?? 'unknown'}',
      );

      final currentSettings = await _messaging.getNotificationSettings();
      debugPrint(
        '[PushNotificationService] Effective notification settings: ${currentSettings.authorizationStatus}',
      );

      await _messaging.subscribeToTopic('all_users');

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          '[PushNotificationService] Foreground push received: ${message.notification?.title} | ${message.notification?.body} | data=${message.data}',
        );
        unawaited(_showForegroundNotification(message));
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint(
          '[PushNotificationService] Notification opened from background: ${message.notification?.title} | ${message.notification?.body} | data=${message.data}',
        );
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[PushNotificationService] Notification opened from terminated state: ${initialMessage.notification?.title} | ${initialMessage.notification?.body} | data=${initialMessage.data}',
        );
      }

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
        await _registerToken(token);
      });

      final token = await _messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        debugPrint('[PushNotificationService] Initial FCM token acquired.');
        await _registerToken(token);
      } else {
        debugPrint('[PushNotificationService] Initial FCM token is empty.');
      }
    } catch (e, st) {
      debugPrint('[PushNotificationService] initialize failed: $e\n$st');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'PureCuts';
    final body =
        notification?.body ?? message.data['message']?.toString() ?? '';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Used for important app notifications.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> syncTokenForCurrentUser() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _registerToken(token);
    } catch (e, st) {
      debugPrint(
        '[PushNotificationService] syncTokenForCurrentUser failed: $e\n$st',
      );
    }
  }

  Future<void> _registerToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      debugPrint(
        '[PushNotificationService] Skip token registration: user not signed in',
      );
      return;
    }

    try {
      final callable = _functions.httpsCallable('registerFcmToken');
      await callable.call({'fcmToken': token});
      debugPrint('[PushNotificationService] FCM token registered for uid=$uid');
    } catch (e, st) {
      debugPrint('[PushNotificationService] registerFcmToken failed: $e\n$st');
    }
  }
}
