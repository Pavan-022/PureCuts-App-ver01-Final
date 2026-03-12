import 'package:flutter/foundation.dart';

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
}

class CartModel extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int get totalPrice => _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  bool hasItem(String id) => _items.any((e) => e.id == id);

  int quantityOf(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    return idx >= 0 ? _items[idx].quantity : 0;
  }

  void add(Map<String, dynamic> product) {
    final idx = _items.indexWhere((e) => e.id == product['id']);
    if (idx >= 0) {
      _items[idx].quantity++;
    } else {
      _items.add(CartItem(
        id: product['id'],
        name: product['name'],
        brand: product['brand'],
        image: product['image'],
        price: product['price'],
      ));
    }
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
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
