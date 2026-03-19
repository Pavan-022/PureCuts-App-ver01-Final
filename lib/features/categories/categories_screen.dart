import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';
import 'package:purecuts/features/home/home_provider.dart';

class CategoriesScreen extends StatefulWidget {
  final String? initialCategory;

  const CategoriesScreen({super.key, this.initialCategory});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _selectedCategory = 'All';
  String? _selectedSubCategory;
  final FirestoreService _firestoreService = FirestoreService();
  Set<String> _purchasedProductIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      _selectedCategory = widget.initialCategory!;
    }
    _resolvePurchasedProducts();
  }

  String _baseProductId(String value) {
    final id = value.trim();
    if (id.isEmpty) return '';
    final sep = id.indexOf('::');
    if (sep <= 0) return id;
    return id.substring(0, sep);
  }

  Future<void> _resolvePurchasedProducts() async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() => _purchasedProductIds = <String>{});
      return;
    }

    try {
      final purchased = await _firestoreService.getUserPurchasedProducts(
        uid: uid,
      );
      if (!mounted) return;
      setState(() {
        _purchasedProductIds = purchased
            .map((p) => _baseProductId((p['id'] ?? '').toString()))
            .where((id) => id.isNotEmpty)
            .toSet();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _purchasedProductIds = <String>{});
    }
  }

  void _selectCategory(String categoryName) {
    setState(() {
      _selectedCategory = categoryName;
      _selectedSubCategory = null;
    });
  }

  String _normalize(String value) => value.trim().toLowerCase();

  List<Map<String, dynamic>> _productsForSubCategory(
    HomeProvider home,
    String category,
    String subCategory,
  ) {
    final exact = home.filteredProducts(
      category: category,
      subCategory: subCategory,
    );
    if (exact.isNotEmpty) return exact;

    final inCategory = home.filteredProducts(category: category);
    final needle = _normalize(subCategory);

    return inCategory.where((product) {
      final productSub =
          (product['subCategory'] ?? product['subcategory'] ?? '').toString();
      if (_normalize(productSub) == needle) return true;

      final pathNames = product['categoryPathNames'];
      if (pathNames is List) {
        final joined = pathNames.map((e) => e.toString()).join(' ');
        if (_normalize(joined).contains(needle)) return true;
      }

      final tags = product['tags'];
      if (tags is List) {
        final joined = tags.map((e) => e.toString()).join(' ');
        if (_normalize(joined).contains(needle)) return true;
      }

      final name = (product['name'] ?? '').toString();
      return _normalize(name).contains(needle);
    }).toList(growable: false);
  }

  String _productSubSubCategory(Map<String, dynamic> product) {
    return (product['subSubCategory'] ??
            product['subsubCategory'] ??
            product['sub_sub_category'] ??
            '')
        .toString();
  }

  List<_GrandchildNode> _grandchildrenFor(
    HomeProvider home,
    String category,
    String subCategory,
  ) {
    final items = home.subSubCategoriesFor(category, subCategory);
    return items.map((item) {
      final rawName = (item['name'] ?? '').toString();
      final key = _normalize(rawName);
      IconData icon = Icons.category_outlined;
      if (key.contains('developer') || key.contains('peroxide')) {
        icon = Icons.science_outlined;
      } else if (key.contains('gel')) {
        icon = Icons.opacity_outlined;
      } else if (key.contains('cream') || key.contains('mask')) {
        icon = Icons.spa_outlined;
      } else if (key.contains('dye') || key.contains('color')) {
        icon = Icons.brush_outlined;
      }

      return _GrandchildNode(name: rawName, icon: icon);
    }).toList();
  }

  Future<void> _handleSubCategoryTap(
    HomeProvider home,
    String selectedCategory,
    String subCategoryName,
  ) async {
    final next = _selectedSubCategory == subCategoryName ? null : subCategoryName;
    setState(() => _selectedSubCategory = next);

    if (next == null) return;
    final grandchildren = _grandchildrenFor(home, selectedCategory, next);
    if (grandchildren.isEmpty) return;

    final baseProducts = _productsForSubCategory(home, selectedCategory, next);

    await _openGrandchildBottomSheet(
      selectedCategory: selectedCategory,
      selectedSubCategory: next,
      grandchildren: grandchildren,
      baseProducts: baseProducts,
    );
  }

  Future<void> _openGrandchildBottomSheet({
    required String selectedCategory,
    required String selectedSubCategory,
    required List<_GrandchildNode> grandchildren,
    required List<Map<String, dynamic>> baseProducts,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _GrandchildNode? active;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final shown = active == null
                ? baseProducts
                : baseProducts
                      .where((p) {
                        final direct =
                            _normalize(_productSubSubCategory(p)) ==
                            _normalize(active!.name);
                        if (direct) return true;

                        // Graceful fallback for legacy products without subSubCategory.
                        final haystack = [
                          p['name'],
                          p['description'],
                          p['shortDescription'],
                          p['tag'],
                          p['tags'],
                        ].map((v) => v?.toString().toLowerCase() ?? '').join(' ');
                        return haystack.contains(_normalize(active!.name));
                      })
                      .toList();

            return FractionallySizedBox(
              heightFactor: 0.90,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD8D4E6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        '$selectedCategory > $selectedSubCategory',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                      child: Text(
                        active == null
                            ? 'Select a category to refine products'
                            : '${active!.name} • ${shown.length} products',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: grandchildren.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final child = grandchildren[i];
                          final selected = active?.name == child.name;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                active = selected ? null : child;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                    : const Color(0xFFF6F3FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    child.icon,
                                    size: 15,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    child.name,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                              child: Text(
                                'No products for this selection yet',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 0.60,
                                  ),
                              itemCount: shown.length,
                              itemBuilder: (_, i) {
                                final product = shown[i];
                                final productId = _baseProductId(
                                  (product['id'] ?? '').toString(),
                                );
                                return ProductCard(
                                  product: product,
                                  showHeartIcon: false,
                                  showBoughtEarlierBadge:
                                      _purchasedProductIds.contains(productId),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final categories = home.categories;
    final selectedCategory = _resolveSelectedCategory(categories);
    final subCategories = selectedCategory == 'All'
        ? const <Map<String, dynamic>>[]
        : home.subCategoriesFor(selectedCategory);
    final availableSubCategoryNames = subCategories
        .map((item) => item['name'] as String)
        .toSet();
    final selectedSubCategory =
        availableSubCategoryNames.contains(_selectedSubCategory)
        ? _selectedSubCategory
        : null;

    final filtered = selectedSubCategory == null
        ? home.filteredProducts(category: selectedCategory)
        : _productsForSubCategory(home, selectedCategory, selectedSubCategory);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
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
        title: const Text(
          'Categories',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedCategory == 'All'
                          ? 'Explore all categories'
                          : selectedCategory,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedSubCategory == null
                          ? '${filtered.length} products available'
                          : '$selectedSubCategory • ${filtered.length} products',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return _CategoryPill(
                              label: 'All',
                              icon: Icons.apps_rounded,
                              selected: selectedCategory == 'All',
                              onTap: () => _selectCategory('All'),
                            );
                          }

                          final category = categories[index - 1];
                          final name = category['name'] as String;
                          return _CategoryPill(
                            label: name,
                            iconPath:
                                (category['icon'] ?? category['image'])
                                    as String?,
                            selected: selectedCategory == name,
                            onTap: () => _selectCategory(name),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (subCategories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: subCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final item = subCategories[i];
                      final subCategoryName = item['name'] as String;
                      final selected = selectedSubCategory == subCategoryName;

                      return GestureDetector(
                        onTap: () => _handleSubCategoryTap(
                          home,
                          selectedCategory,
                          subCategoryName,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : const Color(0xFFE6E0F8),
                            ),
                          ),
                          child: Text(
                            subCategoryName,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (selectedSubCategory != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _grandchildrenFor(
                      home,
                      selectedCategory,
                      selectedSubCategory,
                    ).isEmpty
                        ? null
                        : () => _openGrandchildBottomSheet(
                              selectedCategory: selectedCategory,
                              selectedSubCategory: selectedSubCategory,
                              grandchildren: _grandchildrenFor(
                                home,
                                selectedCategory,
                                selectedSubCategory,
                              ),
                              baseProducts: filtered,
                            ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'See more categories',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: home.loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.category_outlined,
                              size: 52,
                              color: AppColors.textHint,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No products in this category yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.60,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final product = filtered[i];
                        final productId = _baseProductId(
                          (product['id'] ?? '').toString(),
                        );
                        return ProductCard(
                          product: product,
                          showHeartIcon: false,
                          showBoughtEarlierBadge: _purchasedProductIds.contains(
                            productId,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Consumer<CartModel>(
        builder: (context, cart, _) {
          if (cart.itemCount == 0) return const SizedBox.shrink();
          return const StickyCartBar();
        },
      ),
    );
  }

  String _resolveSelectedCategory(List<Map<String, dynamic>> categories) {
    final categoryNames = categories
        .map((cat) => cat['name'] as String)
        .toSet();
    if (_selectedCategory == 'All' ||
        categoryNames.contains(_selectedCategory)) {
      return _selectedCategory;
    }
    if (widget.initialCategory != null &&
        categoryNames.contains(widget.initialCategory)) {
      return widget.initialCategory!;
    }
    return categories.isNotEmpty ? categories.first['name'] as String : 'All';
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final String? iconPath;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    this.iconPath,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = selected
        ? AppColors.primary.withOpacity(0.10)
        : const Color(0xFFF4F1FB);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 82,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.30)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: iconPath != null
                    ? _CategoryIcon(iconPath: iconPath!, selected: selected)
                    : Icon(
                        icon ?? Icons.category_outlined,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final String iconPath;
  final bool selected;

  const _CategoryIcon({required this.iconPath, required this.selected});

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.category_outlined,
      color: selected ? AppColors.primary : AppColors.textSecondary,
      size: 20,
    );

    if (iconPath.startsWith('assets/')) {
      return Image.asset(
        iconPath,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Image.network(
      iconPath,
      width: 22,
      height: 22,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _GrandchildNode {
  final String name;
  final IconData icon;

  const _GrandchildNode({
    required this.name,
    required this.icon,
  });
}
