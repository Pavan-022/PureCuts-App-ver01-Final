import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/core/widgets/sticky_cart_bar.dart';
import 'package:purecuts/features/home/home_provider.dart';

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  String? _selectedBrand;

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final allProducts = home.productMaps;

    // Extract unique brands
    final brands = allProducts
        .map((p) => p['brand'] as String)
        .toSet()
        .toList()
      ..sort();

    final filtered = _selectedBrand == null
        ? allProducts
        : allProducts
            .where((p) => p['brand'] == _selectedBrand)
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: const Text(
                'Brands',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            // Brand chips
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _BrandChip(
                      label: 'All',
                      selected: _selectedBrand == null,
                      onTap: () => setState(() => _selectedBrand = null),
                    ),
                    ...brands.map((b) => _BrandChip(
                          label: b,
                          selected: _selectedBrand == b,
                          onTap: () =>
                              setState(() => _selectedBrand = b),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Product count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${filtered.length} product${filtered.length != 1 ? 's' : ''}${_selectedBrand != null ? ' by $_selectedBrand' : ''}',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Products grid
            Expanded(
              child: home.loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No products found',
                            style: TextStyle(color: AppColors.textHint),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.63,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              ProductCard(product: filtered[i]),
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

class _BrandChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BrandChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? null
              : Border.all(color: AppColors.divider, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
