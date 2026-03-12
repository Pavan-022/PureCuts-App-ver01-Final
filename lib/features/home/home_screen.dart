import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/core/widgets/shimmer_widgets.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/cart/cart_screen.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/location/location_picker_sheet.dart';
import 'package:purecuts/features/products/product_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _recommendedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<HomeProvider>().loadData().then((_) {
        if (mounted) _startAutoScroll();
      });
    });
  }

  void _startAutoScroll() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_recommendedScrollController.hasClients) {
        final maxScroll = _recommendedScrollController.position.maxScrollExtent;
        
        // Scroll to end slowly
        _recommendedScrollController.animateTo(
          maxScroll,
          duration: const Duration(seconds: 15),
          curve: Curves.linear,
        ).then((_) {
          // Wait briefly, then scroll back
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_recommendedScrollController.hasClients) {
              _recommendedScrollController.animateTo(
                0,
                duration: const Duration(seconds: 15),
                curve: Curves.linear,
              ).then((_) {
                // Repeat
                _startAutoScroll();
              });
            }
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _recommendedScrollController.dispose();
    super.dispose();
  }

  void _openLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AuthProvider>(),
        child: const LocationPickerSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Lavender gradient covering top half of screen
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: screenHeight * 0.52,
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
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: home.loading ? _buildShimmer() : _buildContent(home),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final user = context.watch<AuthProvider>().user;

    // Line 1: salon name (bold)
    final salonName = (user?.salonName?.isNotEmpty == true)
        ? user!.salonName!
        : 'My Salon';

    // Line 2: picked address → fallback to state, pincode
    String locationLine = 'Tap to set delivery area';
    if (user != null) {
      if (user.address != null && user.address!.isNotEmpty) {
        locationLine = user.address!;
      } else {
        final parts = <String>[];
        if (user.state?.isNotEmpty == true) parts.add(user.state!);
        if (user.pincode?.isNotEmpty == true) parts.add(user.pincode!);
        if (parts.isNotEmpty) locationLine = parts.join(', ');
      }
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // Location + Cart + Avatar row
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _openLocationPicker(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on,
                        color: AppColors.primary, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openLocationPicker(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'DELIVERY TO',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Icon(Icons.expand_more,
                                color: AppColors.primary, size: 14),
                          ],
                        ),
                        Text(
                          salonName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          locationLine,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Cart icon
                Consumer<CartModel>(
                  builder: (_, cart, __) => GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CartScreen())),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          child: const Icon(Icons.shopping_cart_outlined,
                              color: AppColors.textPrimary, size: 22),
                        ),
                        if (cart.itemCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${cart.itemCount}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Avatar with initials
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.20),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.20)),
                  ),
                  child: Center(
                    child: user != null
                        ? Text(
                            (user.ownerName ?? user.name)
                                .trim()
                                .isNotEmpty
                                ? (user.ownerName ?? user.name)
                                    .trim()[0]
                                    .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : const Icon(Icons.person,
                            color: AppColors.primary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProductListScreen())),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x16A855F7),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.search,
                          color: AppColors.textHint, size: 20),
                    ),
                    const Expanded(
                      child: Text(
                        'Search hair color, scissors, shampoos...',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF0EBFF)),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const ShimmerBox(width: double.infinity, height: 120, radius: 16),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            itemCount: 4,
            itemBuilder: (_, __) => const ProductCardShimmer(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(HomeProvider home) {
    final products = home.productMaps;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categories section
          _buildSectionHeader('Categories', 'View All'),
          const SizedBox(height: 12),
          _buildCategoriesGrid(home),
          const SizedBox(height: 20),
          // Recently Ordered horizontal scroll
          _buildSectionHeader('Recently Ordered', null),
          const SizedBox(height: 12),
          _buildRecentlyOrdered(products),
          const SizedBox(height: 20),
          // Recommended section
          Container(
            color: const Color(0xFFFAF8FF),
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recommended for Your Salon',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    controller: _recommendedScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length > 4 ? 4 : products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final p = products[i];
                      return _buildRecommendedCard(p);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Popular Products grid
          _buildSectionHeader('Popular Products', 'See all'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.63,
              ),
              itemCount: products.length,
              itemBuilder: (_, i) => ProductCard(product: products[i]),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProductListScreen())),
              child: Text(
                action,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoriesGrid(HomeProvider home) {
    final cats = home.categories.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: cats.map((cat) {
          return Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProductListScreen())),
              child: Column(
                children: [
                  Container(
                    height: 70,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x10A855F7),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        cat['icon'] as String,
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecentlyOrdered(List<Map<String, dynamic>> products) {
    return SizedBox(
      height: 165,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: products.take(5).length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final p = products[i];
          return SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 110,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          p['image'] as String,
                          height: 110,
                          width: 120,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            height: 110,
                            width: 120,
                            color: AppColors.surface,
                            child: const Icon(Icons.image,
                                color: AppColors.textHint, size: 32),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Consumer<CartModel>(
                        builder: (_, cart, __) => GestureDetector(
                          onTap: () => cart.add(p),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.10),
                                    blurRadius: 6)
                              ],
                            ),
                            child: const Icon(Icons.add,
                                color: AppColors.primary, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p['brand'] as String,
                  style: const TextStyle(
                      color: AppColors.textHint, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  p['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecommendedCard(Map<String, dynamic> p) {
    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12A855F7),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: Stack(
              children: [
                Container(
                  height: 95,
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.asset(
                    p['image'] as String,
                    height: 95,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 95,
                      color: AppColors.surface,
                      child: const Center(
                        child: Icon(Icons.image,
                            color: AppColors.textHint, size: 32),
                      ),
                    ),
                  ),
                ),
                if ((p['tag'] as String).isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        p['tag'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            p['brand'] as String,
                            style: const TextStyle(
                                color: AppColors.textHint, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\u20B9${p['price']}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '\u20B9${p['originalPrice']}',
                          style: TextStyle(
                            color: AppColors.textHint,
                            fontSize: 10,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Consumer<CartModel>(
                  builder: (_, cart, __) => SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                        elevation: 0,
                      ),
                      onPressed: () => cart.add(p),
                      child: const Text('Add to Cart'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
