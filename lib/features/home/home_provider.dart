import 'package:flutter/foundation.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/core/models/product_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';

class HomeProvider extends ChangeNotifier {
  static const Set<String> _hiddenCategoryNames = {
    'nail',
    'beard',
    'wax',
    'offers',
  };

  final FirestoreService _service = FirestoreService();

  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _banners = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subCategories = [];
  List<Map<String, dynamic>> _subSubCategories = [];
  List<Map<String, dynamic>> _brands = [];
  bool _loading = false;
  String? _error;

  List<ProductModel> get products => _products;
  List<Map<String, dynamic>> get banners => _banners;

  List<Map<String, dynamic>> get categories {
    final hasRemoteCategories = _categories.isNotEmpty;
    final source = hasRemoteCategories ? _categories : AppConstants.categories;
    final merged = <String, Map<String, dynamic>>{};

    for (final category in source) {
      final normalized = _normalizeCategory(category);
      final key = _normalizedKey(normalized['name'] as String?);
      if (_hiddenCategoryNames.contains(key)) continue;
      merged[key] = normalized;
    }

    for (final category in AppConstants.categories) {
      final normalized = _normalizeCategory(category);
      final key = _normalizedKey(normalized['name'] as String?);
      if (_hiddenCategoryNames.contains(key)) continue;

      if (!hasRemoteCategories) {
        merged.putIfAbsent(key, () => normalized);
        continue;
      }

      // Firestore is source-of-truth when available.
      // Only enrich already-present categories (e.g., fill missing icon).
      if (merged.containsKey(key)) {
        final existing = merged[key] ?? const <String, dynamic>{};
        merged[key] = {
          ...normalized,
          ...existing,
          'icon': (existing['icon'] ?? '').toString().trim().isNotEmpty
              ? existing['icon']
              : normalized['icon'],
        };
      }
    }

    return merged.values.toList();
  }

  List<Map<String, dynamic>> get subCategories {
    final hasRemoteSubCategories = _subCategories.isNotEmpty;
    final source = hasRemoteSubCategories
        ? _subCategories
        : AppConstants.subCategories;
    final merged = <String, Map<String, dynamic>>{};

    for (final subCategory in source) {
      final normalized = _normalizeSubCategory(subCategory);
      final parentKey = _normalizedKey(normalized['parentCategory'] as String?);
      if (_hiddenCategoryNames.contains(parentKey)) continue;
      final key =
          '$parentKey::${_normalizedKey(normalized['name'] as String?)}';
      merged[key] = normalized;
    }

    for (final subCategory in AppConstants.subCategories) {
      final normalized = _normalizeSubCategory(subCategory);
      final parentKey = _normalizedKey(normalized['parentCategory'] as String?);
      if (_hiddenCategoryNames.contains(parentKey)) continue;
      final key =
          '$parentKey::${_normalizedKey(normalized['name'] as String?)}';

      if (!hasRemoteSubCategories) {
        merged.putIfAbsent(key, () => normalized);
        continue;
      }

      // Do not introduce extra fallback sub-categories when Firestore data exists.
      if (merged.containsKey(key)) {
        final existing = merged[key] ?? const <String, dynamic>{};
        merged[key] = {
          ...normalized,
          ...existing,
          'icon': (existing['icon'] ?? '').toString().trim().isNotEmpty
              ? existing['icon']
              : normalized['icon'],
        };
      }
    }

    final items = merged.values.toList();
    items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return items;
  }

  List<Map<String, dynamic>> get brands {
    if (_brands.isNotEmpty) {
      return _brands
          .map(
            (brand) => {
              ...brand,
              'name': (brand['name'] ?? '').toString(),
              'image': (brand['image'] ?? brand['logo'] ?? '').toString(),
            },
          )
          .where((brand) => (brand['name'] as String).trim().isNotEmpty)
          .toList();
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final product in productMaps) {
      final name = (product['brand'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final key = _normalizedKey(name);
      merged.putIfAbsent(key, () => {'id': key, 'name': name, 'image': ''});
    }
    final items = merged.values.toList();
    items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return items;
  }

  List<Map<String, dynamic>> get subSubCategories {
    final hasRemoteSubSubCategories = _subSubCategories.isNotEmpty;
    final source = hasRemoteSubSubCategories
        ? _subSubCategories
        : AppConstants.subSubCategories;
    final merged = <String, Map<String, dynamic>>{};

    for (final subSubCategory in source) {
      final normalized = _normalizeSubSubCategory(subSubCategory);
      final parentCategoryKey = _normalizedKey(
        normalized['parentCategory'] as String?,
      );
      if (_hiddenCategoryNames.contains(parentCategoryKey)) continue;

      final key =
          '$parentCategoryKey::${_normalizedKey(normalized['parentSubCategory'] as String?)}::${_normalizedKey(normalized['name'] as String?)}';
      merged[key] = normalized;
    }

    for (final subSubCategory in AppConstants.subSubCategories) {
      final normalized = _normalizeSubSubCategory(subSubCategory);
      final parentCategoryKey = _normalizedKey(
        normalized['parentCategory'] as String?,
      );
      if (_hiddenCategoryNames.contains(parentCategoryKey)) continue;
      final key =
          '$parentCategoryKey::${_normalizedKey(normalized['parentSubCategory'] as String?)}::${_normalizedKey(normalized['name'] as String?)}';

      if (!hasRemoteSubSubCategories) {
        merged.putIfAbsent(key, () => normalized);
        continue;
      }

      // Do not inject extra fallback rows when Firestore data exists.
      if (merged.containsKey(key)) {
        final existing = merged[key] ?? const <String, dynamic>{};
        merged[key] = {
          ...normalized,
          ...existing,
          'icon': (existing['icon'] ?? '').toString().trim().isNotEmpty
              ? existing['icon']
              : normalized['icon'],
        };
      }
    }

    final items = merged.values.toList();
    items.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return items;
  }

  bool get loading => _loading;
  String? get error => _error;

  String _normalizedKey(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _normalizeSearchText(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s,_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _productTags(Map<String, dynamic> product) {
    final tags = <String>{};

    final singleTag = (product['tag'] ?? '').toString().trim();
    if (singleTag.isNotEmpty) tags.add(singleTag);

    final rawTags = product['tags'];
    if (rawTags is List) {
      for (final item in rawTags) {
        final value = item.toString().trim();
        if (value.isNotEmpty) tags.add(value);
      }
    } else if (rawTags is String) {
      for (final item in rawTags.split(RegExp(r'[,|/&_-]+'))) {
        final value = item.trim();
        if (value.isNotEmpty) tags.add(value);
      }
    }

    return tags.toList();
  }

  bool _matchesSearchQuery(Map<String, dynamic> product, String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return true;

    final searchableText = _normalizeSearchText(
      [
        product['name'],
        product['brand'],
        product['category'],
        productSubCategory(product),
        productSubSubCategory(product),
        ..._productTags(product),
      ].join(' '),
    );

    if (searchableText.isEmpty) return false;
    if (searchableText.contains(normalizedQuery)) return true;

    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .toList();
    if (queryTokens.isEmpty) return true;

    return queryTokens.every(searchableText.contains);
  }

  Map<String, dynamic> _normalizeCategory(Map<String, dynamic> category) {
    return {
      ...category,
      'name': category['name'] ?? 'Category',
      'icon': category['icon'] ?? category['image'],
    };
  }

  Map<String, dynamic> _normalizeSubCategory(Map<String, dynamic> subCategory) {
    return {
      ...subCategory,
      'name': subCategory['name'] ?? 'Subcategory',
      'parentCategory':
          subCategory['parentCategory'] ??
          subCategory['category'] ??
          subCategory['parent'] ??
          '',
      'icon': subCategory['icon'] ?? subCategory['image'],
    };
  }

  Map<String, dynamic> _normalizeSubSubCategory(
    Map<String, dynamic> subSubCategory,
  ) {
    return {
      ...subSubCategory,
      'name': subSubCategory['name'] ?? 'Sub-subcategory',
      'parentCategory':
          subSubCategory['parentCategory'] ??
          subSubCategory['category'] ??
          subSubCategory['parent'] ??
          '',
      'parentSubCategory':
          subSubCategory['parentSubCategory'] ??
          subSubCategory['subCategory'] ??
          subSubCategory['parentSubcategory'] ??
          subSubCategory['parentSub'] ??
          '',
      'icon': subSubCategory['icon'] ?? subSubCategory['image'],
    };
  }

  List<Map<String, dynamic>> subCategoriesFor(String category) {
    final categoryKey = _normalizedKey(category);
    return subCategories
        .where(
          (subCategory) =>
              _normalizedKey(subCategory['parentCategory'] as String?) ==
              categoryKey,
        )
        .toList();
  }

  List<Map<String, dynamic>> subSubCategoriesFor(
    String category,
    String subCategory,
  ) {
    final categoryKey = _normalizedKey(category);
    final subCategoryKey = _normalizedKey(subCategory);
    return subSubCategories
        .where(
          (subSubCategory) =>
              _normalizedKey(subSubCategory['parentCategory'] as String?) ==
                  categoryKey &&
              _normalizedKey(subSubCategory['parentSubCategory'] as String?) ==
                  subCategoryKey,
        )
        .toList();
  }

  String productSubCategory(Map<String, dynamic> product) {
    return (product['subCategory'] ??
            product['subcategory'] ??
            product['sub_category'] ??
            '')
        .toString();
  }

  String productSubSubCategory(Map<String, dynamic> product) {
    return (product['subSubCategory'] ??
            product['subsubCategory'] ??
            product['sub_sub_category'] ??
            '')
        .toString();
  }

  /// Returns all products as the legacy Map format (for widgets that expect Map)
  List<Map<String, dynamic>> get productMaps {
    return _products.map((p) => p.toProductMap()).toList();
  }

  Future<void> loadData() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getProducts(),
        _service.getBanners(),
        _service.getCategories(),
        _service.getSubCategories(),
        _service.getSubSubCategories(),
        _service.getBrands(),
      ]);
      _products = results[0] as List<ProductModel>;
      _banners = results[1] as List<Map<String, dynamic>>;
      final cats = results[2] as List<Map<String, dynamic>>;
      final subCats = results[3] as List<Map<String, dynamic>>;
      final subSubCats = results[4] as List<Map<String, dynamic>>;
      final brands = results[5] as List<Map<String, dynamic>>;
      // If Firestore has categories, use them; otherwise fall back to constants
      if (cats.isNotEmpty) _categories = cats;
      if (subCats.isNotEmpty) _subCategories = subCats;
      if (subSubCats.isNotEmpty) _subSubCategories = subSubCats;
      if (brands.isNotEmpty) _brands = brands;
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> filteredProducts({
    String category = 'All',
    String? subCategory,
    String? subSubCategory,
    String query = '',
    String sort = 'popular',
  }) {
    var list = List<Map<String, dynamic>>.from(productMaps);

    if (category != 'All') {
      list = list
          .where(
            (p) =>
                _normalizedKey(p['category'] as String?) ==
                _normalizedKey(category),
          )
          .toList();
    }

    final hasStructuredSubCategories = list.any(
      (product) => productSubCategory(product).trim().isNotEmpty,
    );
    if ((subCategory ?? '').trim().isNotEmpty && hasStructuredSubCategories) {
      list = list
          .where(
            (product) =>
                _normalizedKey(productSubCategory(product)) ==
                _normalizedKey(subCategory),
          )
          .toList();
    }

    final hasStructuredSubSubCategories = list.any(
      (product) => productSubSubCategory(product).trim().isNotEmpty,
    );
    if ((subSubCategory ?? '').trim().isNotEmpty &&
        hasStructuredSubSubCategories) {
      list = list
          .where(
            (product) =>
                _normalizedKey(productSubSubCategory(product)) ==
                _normalizedKey(subSubCategory),
          )
          .toList();
    }

    if (query.isNotEmpty) {
      list = list.where((p) => _matchesSearchQuery(p, query)).toList();
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
