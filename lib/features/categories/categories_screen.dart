import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';
import 'package:purecuts/features/categories/sub_sub_category_screen.dart';
import 'package:purecuts/features/home/home_provider.dart';

class CategoriesScreen extends StatefulWidget {
  final String? initialCategory;

  const CategoriesScreen({super.key, this.initialCategory});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _preferredCategory = 'All';
  Set<String> _purchasedProductIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      _preferredCategory = widget.initialCategory!;
    }
    _resolvePurchasedProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  String _normalized(String value) => value.trim().toLowerCase();

  bool _matchesQuery(String value, String query) {
    if (query.trim().isEmpty) return true;
    return _normalized(value).contains(_normalized(query));
  }

  List<_CategorySectionData> _buildSections(HomeProvider home) {
    final query = _searchQuery.trim();
    final sections = <_CategorySectionData>[];

    for (final category in home.categories) {
      final categoryName = (category['name'] ?? '').toString();
      if (categoryName.trim().isEmpty) continue;

      final allSubs = home.subCategoriesFor(categoryName);
      if (allSubs.isEmpty) continue;

      final categoryMatches = _matchesQuery(categoryName, query);
      final filteredSubs = categoryMatches
          ? allSubs
          : allSubs
                .where((sub) {
                  final subName = (sub['name'] ?? '').toString();
                  return _matchesQuery(subName, query);
                })
                .toList(growable: false);

      if (filteredSubs.isEmpty) continue;

      sections.add(
        _CategorySectionData(
          categoryName: categoryName,
          subCategories: filteredSubs,
          totalSubCategories: allSubs.length,
        ),
      );
    }

    sections.sort((a, b) {
      final aPreferred =
          _normalized(a.categoryName) == _normalized(_preferredCategory);
      final bPreferred =
          _normalized(b.categoryName) == _normalized(_preferredCategory);
      if (aPreferred == bPreferred) return 0;
      return aPreferred ? -1 : 1;
    });

    return sections;
  }

  void _openSubSubCategoryPage(String categoryName, String subCategoryName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubSubCategoryScreen(
          categoryName: categoryName,
          initialSubCategory: subCategoryName,
          purchasedProductIds: _purchasedProductIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final sections = _buildSections(home);

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
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: home.loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7EAF0)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search category or sub-category',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: sections.isEmpty
                        ? const Center(
                            child: Text(
                              'No categories found',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
                            itemCount: sections.length,
                            itemBuilder: (_, i) {
                              final section = sections[i];
                              return _CategorySection(
                                section: section,
                                onTapSubCategory: (subName) =>
                                    _openSubSubCategoryPage(
                                      section.categoryName,
                                      subName,
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
}

class _CategorySectionData {
  final String categoryName;
  final List<Map<String, dynamic>> subCategories;
  final int totalSubCategories;

  const _CategorySectionData({
    required this.categoryName,
    required this.subCategories,
    required this.totalSubCategories,
  });
}

class _CategorySection extends StatelessWidget {
  final _CategorySectionData section;
  final ValueChanged<String> onTapSubCategory;

  const _CategorySection({
    required this.section,
    required this.onTapSubCategory,
  });

  @override
  Widget build(BuildContext context) {
    final shown = section.subCategories.take(8).toList(growable: false);
    final hasMore = section.totalSubCategories > shown.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9EE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.categoryName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shown.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.58,
              ),
              itemBuilder: (_, i) {
                final sub = shown[i];
                final name = (sub['name'] ?? '').toString();
                return _SubCategoryMiniCard(
                  label: name,
                  iconPath: (sub['icon'] ?? sub['image'])?.toString(),
                  onTap: () => onTapSubCategory(name),
                );
              },
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${section.totalSubCategories - shown.length} more',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubCategoryMiniCard extends StatelessWidget {
  final String label;
  final String? iconPath;
  final VoidCallback onTap;

  const _SubCategoryMiniCard({
    required this.label,
    required this.iconPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E5EA)),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  color: Colors.white,
                  child: Center(child: _CategoryIcon(iconPath: iconPath ?? '')),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
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

  const _CategoryIcon({required this.iconPath});

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(
      Icons.category_outlined,
      color: AppColors.textSecondary,
      size: 18,
    );

    final trimmed = iconPath.trim();
    if (trimmed.isEmpty) return fallback;

    if (trimmed.startsWith('assets/')) {
      return Image.asset(
        trimmed,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Image.network(
      trimmed,
      width: 22,
      height: 22,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
