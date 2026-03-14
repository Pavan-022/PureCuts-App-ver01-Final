// lib/core/models/order_provider.dart
import 'package:flutter/foundation.dart';

class OrderProvider extends ChangeNotifier {
  // productId → full product map
  final Map<String, Map<String, dynamic>> _boughtProducts = {};

  List<Map<String, dynamic>> get boughtProducts =>
      _boughtProducts.values.toList();

  bool hasBought(String productId) => _boughtProducts.containsKey(productId);

  /// Call this after a successful order confirmation
  void addOrderedItems(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final id = item['id'] as String?;
      if (id != null && id.isNotEmpty) {
        _boughtProducts[id] = item;
      }
    }
    notifyListeners();
  }
}
