import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purecuts/core/utils/product_image_contract.dart';

class CartItem {
  final String id;
  final String name;
  final String brand;
  final String image;
  final int price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.image,
    required this.price,
    this.quantity = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'image': image,
      'price': price,
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
      quantity: (map['quantity'] is num)
          ? (map['quantity'] as num).toInt()
          : int.tryParse((map['quantity'] ?? '1').toString()) ?? 1,
    );
  }
}

class CartModel extends ChangeNotifier {
  static const String _storageKey = 'purecuts_cart_items_v1';
  static const String _storageListKey = 'purecuts_cart_items_v1_list';
  static const int _maxPreviewItems = 3;
  static Future<SharedPreferences>? _prefsFuture;
  final List<CartItem> _items;
  final List<String> _previewOrder = <String>[];
  int _addEventTick = 0;
  String? _lastAddedProductId;
  String? _lastAddedImage;

  CartModel._(this._items) {
    _rebuildPreviewFromItems();
  }

  factory CartModel.empty() => CartModel._(<CartItem>[]);

  static Future<CartModel> create() async {
    var items = await _loadFromStorage();

    // On some hot-restart cycles plugins may not be fully ready on first read.
    // Retry once shortly after to avoid returning a false-empty cart state.
    if (items.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final retried = await _loadFromStorage();
      if (retried.isNotEmpty) {
        items = retried;
      }
    }

    return CartModel._(items);
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
    } else {
      _items.add(
        CartItem(
          id: productId,
          name: (product['name'] ?? '').toString(),
          brand: (product['brand'] ?? '').toString(),
          image: selectedImage,
          price: (product['price'] is num)
              ? (product['price'] as num).toInt()
              : int.tryParse((product['price'] ?? '0').toString()) ?? 0,
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
    final items = await _loadFromStorage();
    _items
      ..clear()
      ..addAll(items);
    _rebuildPreviewFromItems();
    notifyListeners();
  }

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
      await prefs.setString(_storageKey, encoded);
      await prefs.setStringList(
        _storageListKey,
        rows.map((e) => jsonEncode(e)).toList(growable: false),
      );
    } catch (e, st) {
      debugPrint('[CartModel] Persist failed: $e\n$st');
      // Ignore persistence failures so cart interactions remain functional.
    }
  }

  static Future<List<CartItem>> _loadFromStorage() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_storageKey);
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
      final rawList = prefs.getStringList(_storageListKey);
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

      return <CartItem>[];
    } catch (e, st) {
      debugPrint('[CartModel] Load failed: $e\n$st');
      // Ignore bad cached payload; cart will continue with empty state.
      return <CartItem>[];
    }
  }
}
