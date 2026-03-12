import 'package:flutter/foundation.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/core/models/product_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';

class HomeProvider extends ChangeNotifier {
  final FirestoreService _service = FirestoreService();

  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = false;
  String? _error;

  List<ProductModel> get products => _products;
  List<Map<String, dynamic>> get categories =>
      _categories.isNotEmpty ? _categories : AppConstants.categories;
  bool get loading => _loading;
  String? get error => _error;

  /// Returns all products as the legacy Map format (for widgets that expect Map)
  /// Falls back to AppConstants.products when Firestore has no products yet.
  List<Map<String, dynamic>> get productMaps {
    if (_products.isNotEmpty) {
      return _products.map((p) => p.toProductMap()).toList();
    }
    return AppConstants.products;
  }

  Future<void> loadData() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getProducts(),
        _service.getCategories(),
      ]);
      _products = results[0] as List<ProductModel>;
      final cats = results[1] as List<Map<String, dynamic>>;
      // If Firestore has categories, use them; otherwise fall back to constants
      if (cats.isNotEmpty) _categories = cats;
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> filteredProducts({
    String category = 'All',
    String query = '',
    String sort = 'popular',
  }) {
    var list = productMaps;

    if (category != 'All') {
      list = list
          .where((p) =>
              (p['category'] as String).toLowerCase() ==
              category.toLowerCase())
          .toList();
    }

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list
          .where((p) =>
              (p['name'] as String).toLowerCase().contains(q) ||
              (p['brand'] as String).toLowerCase().contains(q))
          .toList();
    }

    if (sort == 'low') {
      list.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
    } else if (sort == 'high') {
      list.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
    } else if (sort == 'rating') {
      list.sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
    }

    return list;
  }
}
