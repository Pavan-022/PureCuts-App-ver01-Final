import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/core/widgets/shimmer_widgets.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/support_chat/widgets/support_chat_fab.dart';

class ProductListScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialBrand;
  final String? initialTag;
  const ProductListScreen({
    super.key,
    this.initialCategory,
    this.initialBrand,
    this.initialTag,
  });

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  static const int _pageSize = 20;

  String _selectedCategory = 'All';
  String? _selectedBrand;
  String? _selectedTag;
  String _sort = 'popular';
  final _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();

  final List<Map<String, dynamic>> _pagedProducts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastProductDoc;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _pagingError;

  String _searchQuery = '';

  String _normalizeToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s,_-]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesSelectedTag(String rawTag) {
    final selected = _normalizeToken(_selectedTag ?? '');
    if (selected.isEmpty) return true;

    final normalizedTag = _normalizeToken(rawTag);
    if (normalizedTag.isEmpty) return false;

    if (normalizedTag.contains(selected) || selected.contains(normalizedTag)) {
      return true;
    }

    final tokens = normalizedTag
        .split(RegExp(r'[,|/&_-]+'))
        .map((t) => _normalizeToken(t))
        .where((t) => t.isNotEmpty);

    return tokens.any(
      (token) => token.contains(selected) || selected.contains(token),
    );
  }

  String _tagSearchSource(Map<String, dynamic> product) {
    final primary = (product['tag'] ?? '').toString().trim();
    final rawTags = product['tags'];

    final multiTags = rawTags is List
        ? rawTags
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final merged = <String>{};
    if (primary.isNotEmpty) merged.add(primary);
    merged.addAll(multiTags);

    return merged.join(', ');
  }

  Future<void> _refreshProducts() async {
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (_isInitialLoading) return;
    setState(() {
      _isInitialLoading = true;
      _isLoadingMore = false;
      _pagingError = null;
      _hasMore = true;
      _lastProductDoc = null;
      _pagedProducts.clear();
    });

    try {
      final result = await _firestoreService.getProductsPage(
        limit: _pageSize,
        startAfterDoc: null,
      );

      if (!mounted) return;
      setState(() {
        _pagedProducts
          ..clear()
          ..addAll(result.products.map((p) => p.toProductMap()));
        _lastProductDoc = result.lastDocument;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pagingError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  Future<void> _loadMorePage() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _pagingError = null;
    });

    try {
      final result = await _firestoreService.getProductsPage(
        limit: _pageSize,
        startAfterDoc: _lastProductDoc,
      );

      if (!mounted) return;
      setState(() {
        _pagedProducts.addAll(result.products.map((p) => p.toProductMap()));
        _lastProductDoc = result.lastDocument;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pagingError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onProductScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final threshold = position.maxScrollExtent * 0.75;
    if (position.pixels >= threshold) {
      _loadMorePage();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
    if (widget.initialBrand != null && widget.initialBrand!.trim().isNotEmpty) {
      _selectedBrand = widget.initialBrand!.trim();
    }
    if (widget.initialTag != null && widget.initialTag!.trim().isNotEmpty) {
      _selectedTag = widget.initialTag!.trim();
    }

    _scrollController.addListener(_onProductScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController
      ..removeListener(_onProductScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final categories = [
      'All',
      ...home.categories.map((c) => (c['name'] ?? '').toString()),
    ].where((c) => c.trim().isNotEmpty).toSet().toList();

    if (_selectedCategory != 'All' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final products = _pagedProducts
        .where((p) {
          if (_selectedCategory == 'All') return true;
          return (p['category'] ?? '').toString().trim().toLowerCase() ==
              _selectedCategory.trim().toLowerCase();
        })
        .where((p) {
          if (_searchQuery.trim().isEmpty) return true;
          final search = _normalizeToken(_searchQuery);
          final name = _normalizeToken((p['name'] ?? '').toString());
          final brand = _normalizeToken((p['brand'] ?? '').toString());
          final category = _normalizeToken((p['category'] ?? '').toString());
          final text = '$name $brand $category';
          return text.contains(search);
        })
        .where((p) {
          if ((_selectedBrand ?? '').trim().isEmpty) return true;
          return (p['brand'] ?? '').toString().trim().toLowerCase() ==
              _selectedBrand!.trim().toLowerCase();
        })
        .where((p) {
          if ((_selectedTag ?? '').trim().isEmpty) return true;
          return _matchesSelectedTag(_tagSearchSource(p));
        })
        .toList();

    if (_sort == 'low') {
      products.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
    } else if (_sort == 'high') {
      products.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
    } else if (_sort == 'rating') {
      products.sort(
        (a, b) => (b['rating'] as num).compareTo(a['rating'] as num),
      );
    }

    final legacyProducts = home
        .filteredProducts(
          category: _selectedCategory,
          query: _searchQuery,
          sort: _sort,
        )
        .where((p) {
          if ((_selectedBrand ?? '').trim().isEmpty) return true;
          return (p['brand'] ?? '').toString().trim().toLowerCase() ==
              _selectedBrand!.trim().toLowerCase();
        })
        .where((p) {
          if ((_selectedTag ?? '').trim().isEmpty) return true;
          return _matchesSelectedTag(_tagSearchSource(p));
        })
        .toList();

    final hasActiveFiltering =
        _selectedCategory != 'All' ||
        (_selectedBrand ?? '').trim().isNotEmpty ||
        (_selectedTag ?? '').trim().isNotEmpty ||
        _searchQuery.trim().isNotEmpty ||
        _sort != 'popular';

    final displayedProducts = hasActiveFiltering && legacyProducts.isNotEmpty
        ? legacyProducts
        : products;

    final title = (_selectedTag ?? '').trim().isNotEmpty
        ? _selectedTag!
        : (_selectedBrand ?? '').trim().isNotEmpty
        ? _selectedBrand!
        : 'Products';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFB69DF8),
                Color(0xFFC4B5FD),
                Color(0xFFDDD6FE),
                Color(0xFFEDE9FE),
                Colors.white,
              ],
              stops: [0.0, 0.18, 0.42, 0.70, 1.0],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: _refreshProducts,
            tooltip: 'Refresh products',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: AppColors.textPrimary),
              onSelected: (v) => setState(() => _sort = v),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'popular',
                  child: Text('Most Popular'),
                ),
                const PopupMenuItem(value: 'rating', child: Text('Top Rated')),
                const PopupMenuItem(
                  value: 'low',
                  child: Text('Price: Low to High'),
                ),
                const PopupMenuItem(
                  value: 'high',
                  child: Text('Price: High to Low'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search products...',
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textHint,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: AppColors.textHint,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Category chips
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: categories.length,
              itemBuilder: (_, i) {
                final cat = categories[i];
                final selected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if ((_selectedBrand ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Brand: $_selectedBrand',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if ((_selectedTag ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tag: $_selectedTag',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _selectedTag = null),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Product count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  '${products.length} products',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Grid
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              child: _isInitialLoading
                  ? GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                      itemCount: 6,
                      itemBuilder: (_, __) => const ProductCardShimmer(),
                    )
                  : displayedProducts.isEmpty
                  ? ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 280,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  color: AppColors.textHint,
                                  size: 52,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No products found',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_pagingError != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _pagingError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                      itemCount:
                          displayedProducts.length + (_isLoadingMore ? 2 : 0),
                      itemBuilder: (_, i) {
                        if (i >= displayedProducts.length) {
                          return const ProductCardShimmer();
                        }
                        return ProductCard(product: displayedProducts[i]);
                      },
                    ),
            ),
          ),
          if (!_isInitialLoading && _isLoadingMore)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: SizedBox(
                height: 22,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          const StickyCartBar(),
        ],
      ),
      floatingActionButton: const SupportChatFab(),
    );
  }
}
