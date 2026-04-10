import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purecuts/core/constants/app_constants.dart';
import 'package:purecuts/core/constants/feature_flags.dart';
import 'package:purecuts/core/models/product_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/services/performance_trace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeProvider extends ChangeNotifier {
  static const int _homeInitialProductLimit = 24;
  static const int _homeMaxProductPool = 1200;
  static const String _homeCacheKey = 'purecuts_home_bootstrap_cache_v1';
  static const Set<String> _hiddenCategoryNames = {
    'nail',
    'beard',
    'wax',
    'offers',
  };

  final FirestoreService _service = FirestoreService();
  static Future<SharedPreferences>? _prefsFuture;

  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _banners = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subCategories = [];
  List<Map<String, dynamic>> _subSubCategories = [];
  List<Map<String, dynamic>> _brands = [];
  bool _loading = false;
  bool _taxonomyLoading = false;
  String? _error;
  bool _hasLoadedOnce = false;
  bool _hasAttemptedFullCatalogLoad = false;

  static Future<SharedPreferences> _prefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }

  dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is List) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonSafe(item)),
      );
    }
    return value.toString();
  }

  List<Map<String, dynamic>> _safeMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  List<ProductModel> _decodeProducts(dynamic value) {
    if (value is! List) return const <ProductModel>[];
    final products = <ProductModel>[];
    for (final row in value.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final id = (map['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      try {
        products.add(ProductModel.fromMap(map, id));
      } catch (_) {
        // Skip malformed cached rows.
      }
    }
    return products;
  }

  Future<bool> _hydrateStartupCache() async {
    if (!FeatureFlags.enableHomeStartupCache) return false;
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_homeCacheKey);
      if (raw == null || raw.trim().isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final payload = Map<String, dynamic>.from(decoded);

      final cachedProducts = _decodeProducts(payload['products']);
      final cachedBanners = _safeMapList(payload['banners']);
      final cachedCategories = _safeMapList(payload['categories']);
      final cachedSubCategories = _safeMapList(payload['subCategories']);
      final cachedSubSubCategories = _safeMapList(payload['subSubCategories']);
      final cachedBrands = _safeMapList(payload['brands']);

      // Startup hydration is considered successful only when product data exists.
      // Categories can still be shown from AppConstants, but an empty product cache
      // should not short-circuit network loading.
      if (cachedProducts.isEmpty) return false;

      _products = cachedProducts;
      _banners = cachedBanners;
      if (cachedCategories.isNotEmpty) _categories = cachedCategories;
      if (cachedSubCategories.isNotEmpty) _subCategories = cachedSubCategories;
      if (cachedSubSubCategories.isNotEmpty) {
        _subSubCategories = cachedSubSubCategories;
      }
      if (cachedBrands.isNotEmpty) _brands = cachedBrands;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistStartupCache() async {
    if (!FeatureFlags.enableHomeStartupCache) return;
    if (_products.isEmpty) return;
    try {
      final prefs = await _prefs();
      final payload = {
        'savedAt': DateTime.now().toIso8601String(),
        'products': _products.map((p) => _jsonSafe(p.toProductMap())).toList(),
        'banners': _jsonSafe(_banners),
        'categories': _jsonSafe(_categories),
        'subCategories': _jsonSafe(_subCategories),
        'subSubCategories': _jsonSafe(_subSubCategories),
        'brands': _jsonSafe(_brands),
      };
      await prefs.setString(_homeCacheKey, jsonEncode(payload));
    } catch (_) {
      // Best-effort cache write only.
    }
  }

  Future<List<Map<String, dynamic>>> _timedListFetch(
    Future<List<Map<String, dynamic>>> future,
    Duration timeout,
  ) async {
    try {
      return await future.timeout(timeout);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<ProductModel>> _fallbackProductsFetch({int limit = 24}) async {
    try {
      final page = await _service
          .getProductsPage(limit: limit)
          .timeout(const Duration(seconds: 12));
      return page.products;
    } catch (_) {
      return const <ProductModel>[];
    }
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    final text = (value ?? fallback).toString().trim();
    return text;
  }

  List<ProductModel> get products => _products;
  List<Map<String, dynamic>> get banners => _banners;

  List<Map<String, dynamic>> get categories {
    final hasRemoteCategories = _categories.isNotEmpty;
    final source = hasRemoteCategories ? _categories : AppConstants.categories;
    final merged = <String, Map<String, dynamic>>{};

    for (final category in source) {
      final normalized = _normalizeCategory(category);
      final key = _normalizedKey(_safeString(normalized['name']));
      if (_hiddenCategoryNames.contains(key)) continue;
      merged[key] = normalized;
    }

    for (final category in AppConstants.categories) {
      final normalized = _normalizeCategory(category);
      final key = _normalizedKey(_safeString(normalized['name']));
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
      final parentKey = _normalizedKey(
        _safeString(normalized['parentCategory']),
      );
      if (_hiddenCategoryNames.contains(parentKey)) continue;
      final key =
          '$parentKey::${_normalizedKey(_safeString(normalized['name']))}';
      merged[key] = normalized;
    }

    for (final subCategory in AppConstants.subCategories) {
      final normalized = _normalizeSubCategory(subCategory);
      final parentKey = _normalizedKey(
        _safeString(normalized['parentCategory']),
      );
      if (_hiddenCategoryNames.contains(parentKey)) continue;
      final key =
          '$parentKey::${_normalizedKey(_safeString(normalized['name']))}';

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
    items.sort(
      (a, b) => _safeString(
        a['name'],
      ).toLowerCase().compareTo(_safeString(b['name']).toLowerCase()),
    );
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
          .where((brand) => _safeString(brand['name']).isNotEmpty)
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
    items.sort(
      (a, b) => _safeString(
        a['name'],
      ).toLowerCase().compareTo(_safeString(b['name']).toLowerCase()),
    );
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
        _safeString(normalized['parentCategory']),
      );
      if (_hiddenCategoryNames.contains(parentCategoryKey)) continue;

      final key =
          '$parentCategoryKey::${_normalizedKey(_safeString(normalized['parentSubCategory']))}::${_normalizedKey(_safeString(normalized['name']))}';
      merged[key] = normalized;
    }

    for (final subSubCategory in AppConstants.subSubCategories) {
      final normalized = _normalizeSubSubCategory(subSubCategory);
      final parentCategoryKey = _normalizedKey(
        _safeString(normalized['parentCategory']),
      );
      if (_hiddenCategoryNames.contains(parentCategoryKey)) continue;
      final key =
          '$parentCategoryKey::${_normalizedKey(_safeString(normalized['parentSubCategory']))}::${_normalizedKey(_safeString(normalized['name']))}';

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
    items.sort(
      (a, b) => _safeString(
        a['name'],
      ).toLowerCase().compareTo(_safeString(b['name']).toLowerCase()),
    );
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

  List<String> _stringList(dynamic raw) {
    if (raw == null) return const <String>[];
    if (raw is Iterable) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String) {
      return raw
          .split(RegExp(r'[,|/&;>]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final value = raw.toString().trim();
    return value.isEmpty ? const <String>[] : <String>[value];
  }

  List<String> _categoryCandidates(Map<String, dynamic> product) {
    final values = <String>{
      _safeString(product['category']),
      _safeString(product['categoryName']),
      _safeString(product['parentCategory']),
    };

    values.addAll(_stringList(product['selectedCategories']));
    values.addAll(_stringList(product['categoryPathNames']));

    return values.where((value) => value.trim().isNotEmpty).toList();
  }

  bool _matchesCategory(Map<String, dynamic> product, String category) {
    if (category.trim().isEmpty || category == 'All') return true;

    final selected = _normalizedKey(category);
    if (selected.isEmpty) return true;

    for (final candidate in _categoryCandidates(product)) {
      final key = _normalizedKey(candidate);
      if (key.isEmpty) continue;
      if (key == selected) return true;
    }

    return false;
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
              _normalizedKey(_safeString(subCategory['parentCategory'])) ==
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
              _normalizedKey(_safeString(subSubCategory['parentCategory'])) ==
                  categoryKey &&
              _normalizedKey(
                    _safeString(subSubCategory['parentSubCategory']),
                  ) ==
                  subCategoryKey,
        )
        .toList();
  }

  String productSubCategory(Map<String, dynamic> product) {
    final direct =
        (product['subCategory'] ??
                product['subcategory'] ??
                product['sub_category'] ??
                '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;

    final path = _stringList(product['categoryPathNames']);
    if (path.length >= 2) return path[1];

    return '';
  }

  String productSubSubCategory(Map<String, dynamic> product) {
    final direct =
        (product['subSubCategory'] ??
                product['subsubCategory'] ??
                product['sub_sub_category'] ??
                '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;

    final path = _stringList(product['categoryPathNames']);
    if (path.length >= 3) return path[2];

    return '';
  }

  Future<void> ensureVisibilityCatalogLoaded() async {
    if (_loading) return;
    if (_hasAttemptedFullCatalogLoad) return;
    await loadData(forceRefresh: true);
  }

  /// Returns all products as the legacy Map format (for widgets that expect Map)
  List<Map<String, dynamic>> get productMaps {
    return _products.map((p) => p.toProductMap()).toList();
  }

  Future<void> _hydrateTaxonomyInBackground() async {
    if (_taxonomyLoading) return;
    _taxonomyLoading = true;
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _service.getCategories(),
        _service.getSubCategories(),
        _service.getSubSubCategories(),
        _service.getBrands(),
      ]);

      final cats = results[0];
      final subCats = results[1];
      final subSubCats = results[2];
      final brands = results[3];
      var changed = false;

      if (cats.isNotEmpty) {
        _categories = cats;
        changed = true;
      }
      if (subCats.isNotEmpty) {
        _subCategories = subCats;
        changed = true;
      }
      if (subSubCats.isNotEmpty) {
        _subSubCategories = subSubCats;
        changed = true;
      }
      if (brands.isNotEmpty) {
        _brands = brands;
        changed = true;
      }

      if (changed) notifyListeners();
    } catch (_) {
      // Best-effort background enrichment only.
    } finally {
      _taxonomyLoading = false;
    }
  }

  Future<void> loadData({bool forceRefresh = false}) async {
    if (_loading) return;
    if (!forceRefresh && _hasLoadedOnce) return;

    await PerformanceTraceService.recordVoid('home_load_time', () async {
      final startupLite =
          FeatureFlags.enableHomeStartupLite &&
          !forceRefresh &&
          !_hasLoadedOnce;
      final canUseStartupCache =
          FeatureFlags.enableHomeStartupCache && startupLite;
      var hydratedFromCache = false;

      if (canUseStartupCache) {
        hydratedFromCache = await _hydrateStartupCache();
        if (hydratedFromCache) {
          notifyListeners();
        }
      }

      _loading = !hydratedFromCache;
      _error = null;
      notifyListeners();

      try {
        final targetPool = startupLite
            ? FeatureFlags.homeStartupProductPool
            : _homeMaxProductPool;
        final fetched = <ProductModel>[];
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        var hasMore = true;
        final productsTimeout = Duration(
          milliseconds: FeatureFlags.homeProductsPageTimeoutMs,
        );

        while (hasMore && fetched.length < targetPool) {
          final remaining = targetPool - fetched.length;
          if (remaining <= 0) break;
          final page = await _service
              .getProductsPage(
                limit: remaining < _homeInitialProductLimit
                    ? remaining
                    : _homeInitialProductLimit,
                startAfterDoc: cursor,
              )
              .timeout(productsTimeout);

          fetched.addAll(page.products);
          cursor = page.lastDocument;
          hasMore = page.hasMore;
        }

        if (fetched.isEmpty) {
          final fallback = await _fallbackProductsFetch(limit: 24);
          if (fallback.isNotEmpty) {
            fetched.addAll(fallback);
          }
        }

        _hasAttemptedFullCatalogLoad =
            forceRefresh ||
            !startupLite ||
            !hasMore ||
            fetched.length >= _homeMaxProductPool;

        final deferTaxonomy =
            FeatureFlags.enableDeferredHomeTaxonomy && startupLite;
        final bannersTimeout = Duration(
          milliseconds: FeatureFlags.homeBannersTimeoutMs,
        );
        final taxonomyTimeout = Duration(
          milliseconds: FeatureFlags.homeTaxonomyTimeoutMs,
        );

        final results = await Future.wait<List<Map<String, dynamic>>>([
          _timedListFetch(
            _service.getBanners(forceRefresh: forceRefresh),
            bannersTimeout,
          ),
          if (deferTaxonomy)
            Future.value(const <Map<String, dynamic>>[])
          else
            _timedListFetch(_service.getCategories(), taxonomyTimeout),
          if (deferTaxonomy)
            Future.value(const <Map<String, dynamic>>[])
          else
            _timedListFetch(_service.getSubCategories(), taxonomyTimeout),
          if (deferTaxonomy)
            Future.value(const <Map<String, dynamic>>[])
          else
            _timedListFetch(_service.getSubSubCategories(), taxonomyTimeout),
          if (deferTaxonomy)
            Future.value(const <Map<String, dynamic>>[])
          else
            _timedListFetch(_service.getBrands(), taxonomyTimeout),
        ]);
        if (fetched.isNotEmpty) {
          _products = fetched;
        }
        _banners = results[0];
        final cats = results[1];
        final subCats = results[2];
        final subSubCats = results[3];
        final brands = results[4];
        // If Firestore has categories, use them; otherwise fall back to constants
        if (cats.isNotEmpty) _categories = cats;
        if (subCats.isNotEmpty) _subCategories = subCats;
        if (subSubCats.isNotEmpty) _subSubCategories = subSubCats;
        if (brands.isNotEmpty) _brands = brands;
        _hasLoadedOnce = true;

        if (deferTaxonomy) {
          unawaited(_hydrateTaxonomyInBackground());
        }

        unawaited(_persistStartupCache());
      } on TimeoutException {
        _error = 'Home data load timed out. Please pull to refresh.';
        if (_products.isEmpty) {
          final fallback = await _fallbackProductsFetch(limit: 24);
          if (fallback.isNotEmpty) {
            _products = fallback;
            _error = null;
            _hasLoadedOnce = true;
            unawaited(_persistStartupCache());
          }
        }
      } catch (e) {
        _error = e.toString();
        if (_products.isEmpty) {
          final fallback = await _fallbackProductsFetch(limit: 24);
          if (fallback.isNotEmpty) {
            _products = fallback;
            _error = null;
            _hasLoadedOnce = true;
            unawaited(_persistStartupCache());
          }
        }
      }

      _loading = false;
      notifyListeners();
    });
  }

  List<Map<String, dynamic>> filteredProducts({
    String category = 'All',
    String? subCategory,
    String? subSubCategory,
    String query = '',
    String sort = 'popular',
  }) {
    var list = List<Map<String, dynamic>>.from(productMaps);

    list = list
        .where((product) => _matchesCategory(product, category))
        .toList();

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
