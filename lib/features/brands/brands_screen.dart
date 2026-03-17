import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/products/product_list_screen.dart';

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().loadData();
    });
  }

  String _normalizeImagePath(String raw) {
    final path = raw.trim();
    if (path.isEmpty) return '';

    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    if (path.startsWith('gs://')) {
      final withoutScheme = path.substring(5);
      final slash = withoutScheme.indexOf('/');
      if (slash <= 0 || slash == withoutScheme.length - 1) return path;
      final bucket = withoutScheme.substring(0, slash);
      final objectPath = withoutScheme.substring(slash + 1);
      return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(objectPath)}?alt=media';
    }

    if (path.startsWith('assets/')) return path;

    return 'https://firebasestorage.googleapis.com/v0/b/purecuts-11a7c.firebasestorage.app/o/${Uri.encodeComponent(path)}?alt=media';
  }

  Widget _buildBrandLogo(String imagePath, String brandName) {
    final resolved = _normalizeImagePath(imagePath);

    if (resolved.isEmpty) {
      return Center(
        child: Text(
          (brandName.trim().isNotEmpty ? brandName.trim()[0] : '?')
              .toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (resolved.startsWith('assets/')) {
      return Image.asset(
        resolved,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            (brandName.trim().isNotEmpty ? brandName.trim()[0] : '?')
                .toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Image.network(
      resolved,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          (brandName.trim().isNotEmpty ? brandName.trim()[0] : '?')
              .toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final brands = home.brands;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Lavender gradient covering the top area
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Brands',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${brands.length} available',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: home.loading
                      ? const Center(child: CircularProgressIndicator())
                      : brands.isEmpty
                      ? const Center(
                          child: Text(
                            'No brands available',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1.22,
                              ),
                          itemCount: brands.length,
                          itemBuilder: (_, i) {
                            final brand = brands[i];
                            final name = (brand['name'] ?? '').toString();
                            final image = (brand['image'] ?? brand['logo'] ?? '')
                                .toString();

                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProductListScreen(initialBrand: name),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: _buildBrandLogo(image, name),
                                ),
                              ),
                            );
                          },
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
