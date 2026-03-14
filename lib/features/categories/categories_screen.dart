import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/cart_model.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      _selectedCategory = widget.initialCategory!;
    }
  }

  void _selectCategory(String categoryName) {
    setState(() {
      _selectedCategory = categoryName;
      _selectedSubCategory = null;
    });
  }

  void _toggleSubCategory(String subCategoryName) {
    setState(() {
      _selectedSubCategory = _selectedSubCategory == subCategoryName
          ? null
          : subCategoryName;
    });
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

    final filtered = home.filteredProducts(
      category: selectedCategory,
      subCategory: selectedSubCategory,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7FB),
        elevation: 0,
        centerTitle: true,
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
                        onTap: () => _toggleSubCategory(subCategoryName),
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
                      itemBuilder: (_, i) => ProductCard(product: filtered[i]),
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
