import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';
import 'package:purecuts/core/constants/feature_flags.dart';

/// Production-safe PayU service:
/// - SALT never exists in app code
/// - hash generation/verification delegated to backend
/// - supports all methods through CheckoutPro (UPI/Cards/NB/Wallets)
class PayUPaymentService implements PayUCheckoutProProtocol {
  PayUPaymentService()
    : _checkoutPro = PayUCheckoutProFlutter(_singleton),
      _backendBaseUrl = FeatureFlags.payuBackendBaseUrl,
      _merchantKey = FeatureFlags.payuMerchantKey,
      _environment = FeatureFlags.payuEnvironment {
    _singleton._bind(this);
  }

  static final _ServiceProxy _singleton = _ServiceProxy();

  final PayUCheckoutProFlutter _checkoutPro;
  final String _backendBaseUrl;
  final String _merchantKey;
  final String _environment;

  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Map<String, dynamic>? _activeTxn;

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  String generateTxnId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return 'PC$ms';
  }

  Future<String> startCheckout({
    required String userId,
    required String amount,
    required String productInfo,
    required String firstName,
    required String email,
    required String phone,
  }) async {
    final txnId = generateTxnId();

    _activeTxn = {
      'txnid': txnId,
      'amount': _normalizeAmount(amount),
      'productinfo': productInfo,
      'firstname': firstName,
      'email': email,
      'phone': phone,
      'userId': userId,
    };

    // Pre-flight call: creates initiated payment record in backend + validates payload.
    final preflight = await _requestHash({
      'txnid': txnId,
      'amount': _activeTxn!['amount'],
      'productinfo': productInfo,
      'firstname': firstName,
      'email': email,
      'phone': phone,
      'userId': userId,
    });

    final resolvedKey =
        (preflight['key'] ?? _merchantKey).toString().trim().isNotEmpty
        ? (preflight['key'] ?? _merchantKey).toString().trim()
        : _merchantKey;
    final resolvedEnvironment =
        (preflight['environment'] ?? _environment).toString().trim().isNotEmpty
        ? (preflight['environment'] ?? _environment).toString().trim()
        : _environment;

    final normalizedUserId = userId.trim().isNotEmpty ? userId.trim() : phone;
    final userCredential = '$resolvedKey:$normalizedUserId';

    _activeTxn!['amount'] = _normalizeAmount(_activeTxn!['amount'].toString());

    final payUPaymentParams = {
      PayUPaymentParamKey.key: resolvedKey,
      PayUPaymentParamKey.amount: _activeTxn!['amount'],
      PayUPaymentParamKey.productInfo: productInfo,
      PayUPaymentParamKey.firstName: firstName,
      PayUPaymentParamKey.email: email,
      PayUPaymentParamKey.phone: phone,
      PayUPaymentParamKey.android_surl: FeatureFlags.payuAndroidSuccessUrl,
      PayUPaymentParamKey.android_furl: FeatureFlags.payuAndroidFailureUrl,
      PayUPaymentParamKey.ios_surl: FeatureFlags.payuIosSuccessUrl,
      PayUPaymentParamKey.ios_furl: FeatureFlags.payuIosFailureUrl,
      PayUPaymentParamKey.environment: resolvedEnvironment,
      // Required for saved-card related flows; prevents "user_credentials is missing" errors.
      PayUPaymentParamKey.userCredential: userCredential,
      PayUPaymentParamKey.transactionId: txnId,
      PayUPaymentParamKey.additionalParam: {
        PayUAdditionalParamKeys.udf1: userId,
        PayUAdditionalParamKeys.udf2: 'purecuts',
      },
      PayUPaymentParamKey.enableNativeOTP: true,
    };

    final payUCheckoutProConfig = {
      PayUCheckoutProConfigKeys.merchantName: 'PureCuts',
      PayUCheckoutProConfigKeys.showExitConfirmationOnCheckoutScreen: true,
      PayUCheckoutProConfigKeys.showExitConfirmationOnPaymentScreen: true,
      PayUCheckoutProConfigKeys.autoSelectOtp: true,
      PayUCheckoutProConfigKeys.merchantResponseTimeout: 30000,
      // Prevent SDK from forcing saved-card storage paths when credentials are not available.
      PayUCheckoutProConfigKeys.enableSavedCard: false,
      // Keep method ordering broad to surface all options.
      PayUCheckoutProConfigKeys.paymentModesOrder: [
        {'UPI': ''},
        {'CARD': ''},
        {'NB': ''},
        {'WALLET': ''},
      ],
    };

    await _checkoutPro.openCheckoutScreen(
      payUPaymentParams: payUPaymentParams,
      payUCheckoutProConfig: payUCheckoutProConfig,
    );

    return txnId;
  }

  String _normalizeAmount(String rawAmount) {
    final parsed = double.tryParse(rawAmount.trim());
    if (parsed == null || parsed <= 0) {
      return rawAmount.trim();
    }
    return parsed.toStringAsFixed(2);
  }

  Future<Map<String, dynamic>> _requestHash(
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_backendBaseUrl/generate-hash');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final map = _decodeJson(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        map['ok'] != true) {
      throw Exception(map['error']?.toString() ?? 'Unable to generate hash.');
    }

    return map;
  }

  Future<Map<String, dynamic>> _verifyPayment(
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_backendBaseUrl/verify-payment');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final map = _decodeJson(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        map['ok'] != true) {
      throw Exception(map['error']?.toString() ?? 'Unable to verify payment.');
    }

    return map;
  }

  Map<String, dynamic> _decodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return {'raw': decoded};
    } catch (_) {
      return {'raw': source};
    }
  }

  Map<String, dynamic> _normalizeResponse(dynamic response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    if (response is String && response.trim().isNotEmpty) {
      return _decodeJson(response);
    }
    return <String, dynamic>{};
  }

  Future<void> _handleTerminalCallback({
    required String status,
    required dynamic response,
  }) async {
    final txn = _activeTxn;
    if (txn == null) return;

    final payload = _normalizeResponse(response);
    final verifyPayload = {
      'status': status,
      'hash': payload['hash'] ?? '',
      'txnid': payload['txnid'] ?? txn['txnid'],
      'amount': payload['amount'] ?? txn['amount'],
      'productinfo': payload['productinfo'] ?? txn['productinfo'] ?? '',
      'firstname': payload['firstname'] ?? txn['firstname'] ?? '',
      'email': payload['email'] ?? txn['email'] ?? '',
      'key': payload['key'] ?? _merchantKey,
      'additionalCharges': payload['additionalCharges'] ?? '',
      'mihpayid': payload['mihpayid'] ?? '',
      'mode': payload['mode'] ?? '',
      'userId': txn['userId'] ?? '',
      'udf1': payload['udf1'] ?? txn['userId'] ?? '',
      'udf2': payload['udf2'] ?? 'purecuts',
      'udf3': payload['udf3'] ?? '',
      'udf4': payload['udf4'] ?? '',
      'udf5': payload['udf5'] ?? '',
    };

    try {
      final verifyResult = await _verifyPayment(verifyPayload);
      _eventsController.add({
        'type': 'verify',
        'txnid': txn['txnid'],
        ...verifyResult,
      });
    } catch (error) {
      _eventsController.add({
        'type': 'error',
        'txnid': txn['txnid'],
        'message': error.toString(),
      });
    }
  }

  @override
  Future<void> generateHash(Map response) async {
    final txn = _activeTxn;
    if (txn == null) return;

    try {
      final hashString =
          (response[PayUHashConstantsKeys.hashString] ??
                  response['hash_string'] ??
                  '')
              .toString();

      String resolvedHashName =
          (response[PayUHashConstantsKeys.hashName] ??
                  response['hash_name'] ??
                  response['name'] ??
                  '')
              .toString()
              .trim();

      if (resolvedHashName.isEmpty) {
        resolvedHashName = _deriveHashNameFromHashString(hashString);
      }

      final hashPayload = {
        if (resolvedHashName.isNotEmpty) 'hashName': resolvedHashName,
        'hashString': hashString,
        'txnid': txn['txnid'],
        'amount': txn['amount'],
        'productinfo': txn['productinfo'],
        'firstname': txn['firstname'],
        'email': txn['email'],
        'userId': txn['userId'],
      };

      final hashResponse = await _requestHash(hashPayload);
      final hash = (hashResponse['hash'] ?? '').toString();
      if (hash.isEmpty) {
        throw Exception('Empty hash returned by backend.');
      }

      if (resolvedHashName.isNotEmpty) {
        await _checkoutPro.hashGenerated(hash: {resolvedHashName: hash});
      } else {
        // Fallback: provide hash under common SDK names when callback omits hashName.
        await _checkoutPro.hashGenerated(
          hash: {
            'payment_hash': hash,
            'get_sdk_configuration': hash,
            'get_checkout_details': hash,
            'get_all_offer_details': hash,
            'quickPayEvent': hash,
          },
        );
      }
    } catch (error) {
      _eventsController.add({
        'type': 'error',
        'txnid': txn['txnid'],
        'message': 'Hash generation failed: $error',
      });
    }
  }

  String _deriveHashNameFromHashString(String hashString) {
    final raw = hashString.trim();
    if (raw.isEmpty) return '';

    // Typical callback format: merchantKey|hashName|payload|
    final segments = raw.split('|');
    if (segments.length >= 2) {
      final candidate = segments[1].trim();
      if (candidate.isNotEmpty && !candidate.startsWith('{')) {
        return candidate;
      }
    }
    return '';
  }

  @override
  Future<void> onPaymentSuccess(dynamic response) async {
    await _handleTerminalCallback(status: 'success', response: response);
  }

  @override
  Future<void> onPaymentFailure(dynamic response) async {
    await _handleTerminalCallback(status: 'failure', response: response);
  }

  @override
  Future<void> onPaymentCancel(Map? response) async {
    final txn = _activeTxn;
    if (txn == null) return;

    _eventsController.add({
      'type': 'cancel',
      'txnid': txn['txnid'],
      'message': 'Payment cancelled by user.',
    });

    await _handleTerminalCallback(
      status: 'cancelled',
      response: response ?? {},
    );
  }

  @override
  Future<void> onError(Map? response) async {
    final txn = _activeTxn;
    _eventsController.add({
      'type': 'error',
      'txnid': txn?['txnid'] ?? '',
      'message': response?.toString() ?? 'Unknown PayU error',
    });
  }

  void dispose() {
    _eventsController.close();
  }
}

class _ServiceProxy implements PayUCheckoutProProtocol {
  PayUPaymentService? _service;

  void _bind(PayUPaymentService service) {
    _service = service;
  }

  @override
  generateHash(Map response) => _service?.generateHash(response);

  @override
  onError(Map? response) => _service?.onError(response);

  @override
  onPaymentCancel(Map? response) => _service?.onPaymentCancel(response);

  @override
  onPaymentFailure(response) => _service?.onPaymentFailure(response);

  @override
  onPaymentSuccess(response) => _service?.onPaymentSuccess(response);
}
