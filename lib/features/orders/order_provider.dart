// lib/core/models/order_provider.dart
import 'package:flutter/foundation.dart';
import 'package:purecuts/core/services/firestore_service.dart';

class OrderProvider extends ChangeNotifier {
  OrderProvider({FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;

  // productId → full product map
  final Map<String, Map<String, dynamic>> _boughtProducts = {};
  bool _loading = false;
  String? _loadedUid;

  List<Map<String, dynamic>> get boughtProducts =>
      _boughtProducts.values.toList();
  bool get isLoading => _loading;

  bool hasBought(String productId) => _boughtProducts.containsKey(productId);

  String _baseProductId(String value) {
    final id = value.trim();
    final sep = id.indexOf('::');
    if (sep <= 0) return id;
    return id.substring(0, sep);
  }

  void _storeItem(Map<String, dynamic> item) {
    final id = _baseProductId((item['id'] ?? '').toString());
    if (id.isEmpty) return;
    _boughtProducts[id] = {...item, 'id': id};
  }

  Future<void> loadPurchasedProducts({
    required String uid,
    bool forceRefresh = false,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      clear();
      return;
    }
    if (_loading) return;
    if (!forceRefresh && _loadedUid == cleanUid && _boughtProducts.isNotEmpty) {
      return;
    }

    _loading = true;
    notifyListeners();

    final existing = _loadedUid == cleanUid
        ? List<Map<String, dynamic>>.from(_boughtProducts.values)
        : const <Map<String, dynamic>>[];

    try {
      final remoteItems = await _firestoreService.getUserPurchasedProducts(
        uid: cleanUid,
      );

      _boughtProducts.clear();
      for (final item in remoteItems) {
        _storeItem(item);
      }
      for (final item in existing) {
        _storeItem(item);
      }
      _loadedUid = cleanUid;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _boughtProducts.clear();
    _loadedUid = null;
    _loading = false;
    notifyListeners();
  }

  /// Call this after a successful order confirmation
  void addOrderedItems(List<Map<String, dynamic>> items) {
    for (final item in items) {
      _storeItem(item);
    }
    notifyListeners();
  }
}
