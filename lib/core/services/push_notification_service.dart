import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:purecuts/core/navigation/app_navigator.dart';
import 'package:purecuts/core/models/order_model.dart';
import 'package:purecuts/features/orders/checkout_screen.dart';
import 'package:purecuts/features/products/product_detail_screen.dart';
import 'package:purecuts/features/cart/cart_screen.dart';
import 'package:purecuts/features/orders/order_details_screen.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  static const String _payuRecoveryPayloadPrefix = 'payu_recovery:';

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
        _handleNotificationMessage(message);
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[PushNotificationService] Notification opened from terminated state: ${initialMessage.notification?.title} | ${initialMessage.notification?.body} | data=${initialMessage.data}',
        );
        _handleNotificationMessage(initialMessage);
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
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = (response.payload ?? '').trim();
    if (payload.isEmpty) return;

    if (payload.startsWith(_payuRecoveryPayloadPrefix)) {
      unawaited(_openRecoveredPaymentCheckout());
      return;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      final eventType = (data['eventType'] ?? '').toString().trim();
      if (eventType.isEmpty) return;

      if (eventType == 'back_in_stock') {
        final productId = (data['productId'] ?? '').toString().trim();
        if (productId.isNotEmpty) {
          unawaited(_openProductDetailScreen(productId));
        }
      } else if (eventType == 'abandoned_cart') {
        unawaited(_openCartScreen());
      } else if (eventType == 'order_placed') {
        final orderId = (data['orderId'] ?? '').toString().trim();
        if (orderId.isNotEmpty) {
          unawaited(_openOrderDetailsScreen(orderId));
        }
      }
    } catch (e, st) {
      debugPrint('[PushNotificationService] Failed to parse notification tap payload: $e\n$st');
    }
  }

  void _handleNotificationMessage(RemoteMessage message) {
    final data = message.data;
    final eventType = (data['eventType'] ?? '').toString().trim();
    if (eventType.isEmpty) return;

    if (eventType == 'back_in_stock') {
      final productId = (data['productId'] ?? '').toString().trim();
      if (productId.isNotEmpty) {
        unawaited(_openProductDetailScreen(productId));
      }
    } else if (eventType == 'abandoned_cart') {
      unawaited(_openCartScreen());
    } else if (eventType == 'order_placed') {
      final orderId = (data['orderId'] ?? '').toString().trim();
      if (orderId.isNotEmpty) {
        unawaited(_openOrderDetailsScreen(orderId));
      }
    }
  }

  Future<void> _openProductDetailScreen(String productId, {int attempts = 0}) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      if (attempts >= 6) return;
      await Future.delayed(const Duration(milliseconds: 350));
      return _openProductDetailScreen(productId, attempts: attempts + 1);
    }

    try {
      final snap = await _firestore.collection('products').doc(productId).get();
      if (snap.exists) {
        final productData = snap.data() ?? {};
        productData['id'] = snap.id;
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: productData),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to load product detail from notification redirect: $e');
    }
  }

  Future<void> _openCartScreen({int attempts = 0}) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      if (attempts >= 6) return;
      await Future.delayed(const Duration(milliseconds: 350));
      return _openCartScreen(attempts: attempts + 1);
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => const CartScreen(),
      ),
    );
  }

  Future<void> _openOrderDetailsScreen(String orderId, {int attempts = 0}) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      if (attempts >= 6) return;
      await Future.delayed(const Duration(milliseconds: 350));
      return _openOrderDetailsScreen(orderId, attempts: attempts + 1);
    }

    try {
      final snap = await _firestore.collection('orders').doc(orderId).get();
      if (snap.exists) {
        final map = snap.data() ?? {};
        map['id'] = snap.id;
        final order = OrderModel.fromMap(map);
        navigator.push(
          MaterialPageRoute(
            builder: (_) => OrderDetailsScreen(order: order),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to load order details from notification redirect: $e');
    }
  }

  Future<void> _openRecoveredPaymentCheckout({int attempts = 0}) async {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      if (attempts >= 6) return;
      await Future.delayed(const Duration(milliseconds: 350));
      return _openRecoveredPaymentCheckout(attempts: attempts + 1);
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            const CheckoutScreen(autoFinalizeRecoveredPayuOrder: true),
      ),
    );
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'PureCuts';
    final body =
        notification?.body ?? message.data['message']?.toString() ?? '';

    final payloadString = jsonEncode({
      ...message.data,
      'title': title,
      'body': body,
    });

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
      payload: payloadString,
    );
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    int? id,
    String? payload,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    await _localNotifications.show(
      id ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
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
      payload: payload,
    );
  }

  Future<void> showPayuRecoveryNotification({String? txnId}) {
    final resolvedTxnId = (txnId ?? '').trim();
    final uniqueId = DateTime.now().millisecondsSinceEpoch.remainder(
      2147483647,
    );
    return showLocalNotification(
      id: uniqueId,
      title: 'Payment completed',
      body: 'Your payment is successful. Open checkout to complete your order.',
      payload: '$_payuRecoveryPayloadPrefix$resolvedTxnId',
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
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final callable = _functions.httpsCallable('registerFcmToken');
      await callable.call({'fcmToken': token});
      debugPrint('[PushNotificationService] FCM token registered for uid=$uid');
    } catch (e, st) {
      debugPrint('[PushNotificationService] registerFcmToken failed: $e\n$st');
    }
  }
}
