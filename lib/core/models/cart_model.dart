import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purecuts/core/utils/product_image_contract.dart';
import 'package:purecuts/core/utils/tier_pricing.dart';

class CartItem {
  final String id;
  final String name;
  final String brand;
  final String image;
  final int price;
  final int basePrice;
  final String pricingType;
  final List<PricingTier> pricingTiers;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.image,
    required this.price,
    this.basePrice = 0,
    this.pricingType = '',
    this.pricingTiers = const [],
    this.quantity = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'image': image,
      'price': price,
      'basePrice': basePrice,
      'pricingType': pricingType,
      'pricingTiers': pricingTiers
          .map((tier) => tier.toMap())
          .toList(growable: false),
      'quantity': quantity,
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      brand: (map['brand'] ?? '').toString(),
      image: (map['image'] ?? '').toString(),
      price: (map['price'] is num)
          ? (map['price'] as num).toInt()
          : int.tryParse((map['price'] ?? '0').toString()) ?? 0,
      basePrice: (map['basePrice'] is num)
          ? (map['basePrice'] as num).toInt()
          : int.tryParse(
                  (map['basePrice'] ?? map['price'] ?? '0').toString(),
                ) ??
                0,
      pricingType: (map['pricingType'] ?? '').toString().trim(),
      pricingTiers: parsePricingTiers(map['pricingTiers']),
      quantity: (map['quantity'] is num)
          ? (map['quantity'] as num).toInt()
          : int.tryParse((map['quantity'] ?? '1').toString()) ?? 1,
    );
  }
}

class CartModel extends ChangeNotifier {
  static const String _storageKey = 'purecuts_cart_items_v1';
  static const String _storageListKey = 'purecuts_cart_items_v1_list';
  static const String _storageUserMetaKey = 'purecuts_cart_last_user_v1';
  static const int _maxPreviewItems = 3;
  static Future<SharedPreferences>? _prefsFuture;
  final List<CartItem> _items;
  final List<String> _previewOrder = <String>[];
  int _addEventTick = 0;
  String? _lastAddedProductId;
  String? _lastAddedImage;
  String _activeUserKey = 'guest';
  StreamSubscription<fb_auth.User?>? _authSub;

  CartModel._(this._items) {
    _rebuildPreviewFromItems();
    _bindAuthChanges();
  }

  factory CartModel.empty() => CartModel._(<CartItem>[]);

  static Future<CartModel> create() async {
    final userKey = _userStorageKey();
    var items = await _loadFromStorage(userKey: userKey);

    // On some hot-restart cycles plugins may not be fully ready on first read.
    // Retry once shortly after to avoid returning a false-empty cart state.
    if (items.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final retried = await _loadFromStorage(userKey: userKey);
      if (retried.isNotEmpty) {
        items = retried;
      }
    }

    final model = CartModel._(items);
    model._activeUserKey = userKey;
    return model;
  }

  static Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  List<CartItem> get items => List.unmodifiable(_items);

  List<CartItem> get previewItems {
    final byId = <String, CartItem>{for (final item in _items) item.id: item};
    return _previewOrder
        .map((id) => byId[id])
        .whereType<CartItem>()
        .toList(growable: false);
  }

  int get addEventTick => _addEventTick;

  String? get lastAddedProductId => _lastAddedProductId;

  String? get lastAddedImage => _lastAddedImage;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int get totalPrice =>
      _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  bool hasItem(String id) => _items.any((e) => e.id == id);

  bool _isTierPricingEnabled(CartItem item) {
    final type = item.pricingType.trim().toLowerCase();
    return item.pricingTiers.isNotEmpty && (type.isEmpty || type == 'tier');
  }

  CartItem _repriceForQuantity(CartItem item) {
    if (!_isTierPricingEnabled(item)) return item;
    final unitPrice = unitPriceForQuantity(
      quantity: item.quantity,
      basePrice: item.basePrice,
      pricingTiers: item.pricingTiers,
    );

    return CartItem(
      id: item.id,
      name: item.name,
      brand: item.brand,
      image: item.image,
      price: unitPrice,
      basePrice: item.basePrice,
      pricingType: item.pricingType,
      pricingTiers: item.pricingTiers,
      quantity: item.quantity,
    );
  }

  int quantityOf(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    return idx >= 0 ? _items[idx].quantity : 0;
  }

  void add(Map<String, dynamic> product) {
    final productId = (product['id'] ?? '').toString().trim();
    if (productId.isEmpty) return;
    final idx = _items.indexWhere((e) => e.id == productId);
    final selectedImage = resolveListImage(product);

    if (idx >= 0) {
      _items[idx].quantity++;
      _items[idx] = _repriceForQuantity(_items[idx]);
    } else {
      final rawPrice = (product['price'] is num)
          ? (product['price'] as num).toInt()
          : int.tryParse((product['price'] ?? '0').toString()) ?? 0;
      final rawBasePrice = (product['basePrice'] is num)
          ? (product['basePrice'] as num).toInt()
          : int.tryParse((product['basePrice'] ?? rawPrice).toString()) ??
                rawPrice;
      final pricingType = (product['pricingType'] ?? '').toString().trim();
      final pricingTiers = parsePricingTiers(product['pricingTiers']);
      final initialPrice = unitPriceForQuantity(
        quantity: 1,
        basePrice: rawBasePrice,
        pricingTiers: pricingTiers,
      );

      _items.add(
        CartItem(
          id: productId,
          name: (product['name'] ?? '').toString(),
          brand: (product['brand'] ?? '').toString(),
          image: selectedImage,
          price: initialPrice,
          basePrice: rawBasePrice,
          pricingType: pricingType,
          pricingTiers: pricingTiers,
        ),
      );
    }

    _touchPreview(productId);
    _lastAddedProductId = productId;
    _lastAddedImage = selectedImage;
    _addEventTick++;

    _persist();
    notifyListeners();
  }

  void setQuantity(Map<String, dynamic> product, int quantity) {
    final productId = (product['id'] ?? '').toString().trim();
    if (productId.isEmpty) return;

    final safeQty = quantity < 0 ? 0 : quantity;
    final idx = _items.indexWhere((e) => e.id == productId);

    if (safeQty == 0) {
      if (idx >= 0) {
        _items.removeAt(idx);
        _syncPreviewWithItems();
        _persist();
        notifyListeners();
      }
      return;
    }

    final selectedImage = resolveListImage(product);

    if (idx >= 0) {
      _items[idx].quantity = safeQty;
      _items[idx] = _repriceForQuantity(_items[idx]);
    } else {
      final rawPrice = (product['price'] is num)
          ? (product['price'] as num).toInt()
          : int.tryParse((product['price'] ?? '0').toString()) ?? 0;
      final rawBasePrice = (product['basePrice'] is num)
          ? (product['basePrice'] as num).toInt()
          : int.tryParse((product['basePrice'] ?? rawPrice).toString()) ??
                rawPrice;
      final pricingType = (product['pricingType'] ?? '').toString().trim();
      final pricingTiers = parsePricingTiers(product['pricingTiers']);
      final unitPrice = unitPriceForQuantity(
        quantity: safeQty,
        basePrice: rawBasePrice,
        pricingTiers: pricingTiers,
      );

      _items.add(
        CartItem(
          id: productId,
          name: (product['name'] ?? '').toString(),
          brand: (product['brand'] ?? '').toString(),
          image: selectedImage,
          price: unitPrice,
          basePrice: rawBasePrice,
          pricingType: pricingType,
          pricingTiers: pricingTiers,
          quantity: safeQty,
        ),
      );
    }

    _touchPreview(productId);
    _lastAddedProductId = productId;
    _lastAddedImage = selectedImage;
    _addEventTick++;

    _persist();
    notifyListeners();
  }

  void remove(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      if (_items[idx].quantity > 1) {
        _items[idx].quantity--;
        _items[idx] = _repriceForQuantity(_items[idx]);
      } else {
        _items.removeAt(idx);
      }
      _syncPreviewWithItems();
      _persist();
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    _previewOrder.clear();
    _persist();
    notifyListeners();
  }

  Future<void> reloadFromStorage() async {
    final items = await _loadFromStorage(userKey: _activeUserKey);
    _items
      ..clear()
      ..addAll(items);
    _rebuildPreviewFromItems();
    notifyListeners();
  }

  void _bindAuthChanges() {
    _authSub?.cancel();
    _authSub = fb_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      final nextUserKey = _userStorageKey(user: user);
      if (nextUserKey == _activeUserKey) return;
      unawaited(_switchUserCart(nextUserKey));
    });
  }

  Future<void> _switchUserCart(String nextUserKey) async {
    _activeUserKey = nextUserKey;
    final items = await _loadFromStorage(userKey: nextUserKey);
    _items
      ..clear()
      ..addAll(items);
    _rebuildPreviewFromItems();
    notifyListeners();
  }

  static String _sanitizeUserKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'guest';
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static String _userStorageKey({fb_auth.User? user}) {
    final uid = (user ?? fb_auth.FirebaseAuth.instance.currentUser)?.uid ?? '';
    return _sanitizeUserKey(uid);
  }

  static String _scopedStorageKey(String userKey) => '${_storageKey}_$userKey';

  static String _scopedStorageListKey(String userKey) =>
      '${_storageListKey}_$userKey';

  void _touchPreview(String productId) {
    _previewOrder.remove(productId);
    _previewOrder.add(productId);
    while (_previewOrder.length > _maxPreviewItems) {
      _previewOrder.removeAt(0);
    }
  }

  void _rebuildPreviewFromItems() {
    _previewOrder
      ..clear()
      ..addAll(_items.map((item) => item.id));

    while (_previewOrder.length > _maxPreviewItems) {
      _previewOrder.removeAt(0);
    }
  }

  void _syncPreviewWithItems() {
    final existing = _items.map((item) => item.id).toSet();
    _previewOrder.removeWhere((id) => !existing.contains(id));
    while (_previewOrder.length > _maxPreviewItems) {
      _previewOrder.removeAt(0);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs();
      final rows = _items.map((e) => e.toMap()).toList(growable: false);
      final encoded = jsonEncode(rows);
      await prefs.setString(_scopedStorageKey(_activeUserKey), encoded);
      await prefs.setStringList(
        _scopedStorageListKey(_activeUserKey),
        rows.map((e) => jsonEncode(e)).toList(growable: false),
      );
      await prefs.setString(_storageUserMetaKey, _activeUserKey);
    } catch (e, st) {
      debugPrint('[CartModel] Persist failed: $e\n$st');
      // Ignore persistence failures so cart interactions remain functional.
    }
  }

  static Future<List<CartItem>> _loadFromStorage({
    required String userKey,
  }) async {
    try {
      final prefs = await _prefs();
      final scopedKey = _scopedStorageKey(userKey);
      final scopedListKey = _scopedStorageListKey(userKey);
      final raw = prefs.getString(scopedKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map>()
              .map((e) => CartItem.fromMap(Map<String, dynamic>.from(e)))
              .where((e) => e.id.trim().isNotEmpty && e.quantity > 0)
              .toList(growable: true);
          if (parsed.isNotEmpty) return parsed;
        }
      }

      // Fallback for older/corrupted JSON snapshots.
      final rawList = prefs.getStringList(scopedListKey);
      if (rawList != null && rawList.isNotEmpty) {
        final parsed = rawList
            .map((entry) {
              try {
                final decoded = jsonDecode(entry);
                if (decoded is Map) {
                  return CartItem.fromMap(Map<String, dynamic>.from(decoded));
                }
              } catch (_) {
                // Ignore malformed single row
              }
              return null;
            })
            .whereType<CartItem>()
            .where((e) => e.id.trim().isNotEmpty && e.quantity > 0)
            .toList(growable: true);
        if (parsed.isNotEmpty) return parsed;
      }

      // One-time legacy migration for guest only.
      if (userKey == 'guest') {
        final legacyRaw = prefs.getString(_storageKey);
        if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
          final decoded = jsonDecode(legacyRaw);
          if (decoded is List) {
            final parsed = decoded
                .whereType<Map>()
                .map((e) => CartItem.fromMap(Map<String, dynamic>.from(e)))
                .where((e) => e.id.trim().isNotEmpty && e.quantity > 0)
                .toList(growable: true);
            if (parsed.isNotEmpty) {
              await prefs.setString(scopedKey, legacyRaw);
              await prefs.setStringList(
                scopedListKey,
                parsed
                    .map((e) => jsonEncode(e.toMap()))
                    .toList(growable: false),
              );
              await prefs.remove(_storageKey);
              await prefs.remove(_storageListKey);
              return parsed;
            }
          }
        }
      }

      return <CartItem>[];
    } catch (e, st) {
      debugPrint('[CartModel] Load failed: $e\n$st');
      // Ignore bad cached payload; cart will continue with empty state.
      return <CartItem>[];
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
