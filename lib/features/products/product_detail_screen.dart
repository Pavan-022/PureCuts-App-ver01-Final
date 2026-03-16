import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:purecuts/core/models/cart_model.dart';
import 'package:purecuts/core/services/firestore_service.dart';
import 'package:purecuts/core/theme/app_theme.dart';
import 'package:purecuts/core/widgets/product_card.dart';
import 'package:purecuts/features/auth/providers/auth_provider.dart';
import 'package:purecuts/features/cart/cart_screen.dart';
import 'package:purecuts/features/home/home_provider.dart';
import 'package:purecuts/features/orders/order_provider.dart';
import 'package:purecuts/features/products/detail/product_models.dart';
import 'package:purecuts/features/products/detail/product_repository.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ProductRepository _repository = ProductRepository();
  final FirestoreService _firestoreService = FirestoreService();
  final ImagePicker _imagePicker = ImagePicker();
  final PageController _pageController = PageController();
  ProductState? _productState;
  bool _detailsExpanded = false;
  int _selectedDetailsTab = 0;
  bool _loadingDetail = false;
  bool _isWishlisted = false;
  bool _wishlistActionInProgress = false;
  bool _checkingReviewEligibility = false;
  bool _canReview = false;
  bool _submittingReview = false;

  String get _currentUserId => context.read<AuthProvider>().user?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _productState = ProductState(product: _fallbackProduct(widget.product));
    _productState!.addListener(_onProductStateChanged);
    _loadWishlistState();
    _checkReviewEligibility();
    _loadProductDetail();
  }

  @override
  void dispose() {
    _productState?.removeListener(_onProductStateChanged);
    _productState?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onProductStateChanged() {
    if (mounted) setState(() {});
  }

  Product _fallbackProduct(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString();
    return Product.fromMap(id, raw);
  }

  Future<void> _loadProductDetail() async {
    final productId = (widget.product['id'] ?? '').toString().trim();
    if (productId.isEmpty) return;
    setState(() => _loadingDetail = true);
    try {
      var product = await _repository.getProductById(productId);

      if (product.variants.isEmpty) {
        try {
          final fallbackVariants = await _firestoreService.getProductVariants(
            productId,
          );
          if (fallbackVariants.isNotEmpty) {
            product = Product(
              id: product.id,
              name: product.name,
              brand: product.brand,
              description: product.description,
              images: product.images,
              variants: fallbackVariants,
              rating: product.rating,
              reviewCount: product.reviewCount,
              reviews: product.reviews,
            );
          }
          debugPrint(
            '[ProductDetail] Fallback variants fetched: ${fallbackVariants.length} for productId=$productId',
          );
        } catch (e, st) {
          debugPrint(
            '[ProductDetail] Fallback variant fetch failed for productId=$productId: $e\n$st',
          );
        }
      }

      if (!mounted || _productState == null) return;
      _productState!.replaceProduct(product);
    } catch (e, st) {
      debugPrint(
        '[ProductDetail] Failed to load product detail for productId=$productId: $e\n$st',
      );
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Product get _product => _productState!.product;
  ProductVariant? get _selectedVariant => _productState!.selectedVariant;

  String get _productId {
    final idFromState = _product.id.trim();
    if (idFromState.isNotEmpty) return idFromState;
    return (widget.product['id'] ?? '').toString().trim();
  }

  Future<void> _loadWishlistState() async {
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    final productId = _productId;
    if (uid.isEmpty || productId.isEmpty) return;

    try {
      final liked = await _firestoreService.isProductFavorited(
        uid: uid,
        productId: productId,
      );
      if (!mounted) return;
      setState(() => _isWishlisted = liked);
    } catch (e, st) {
      debugPrint('[ProductDetail] Failed to load wishlist state: $e\n$st');
      // Keep UI resilient even if this request fails.
    }
  }

  Map<String, dynamic> _favoriteSnapshot() {
    return {
      'name': _product.name,
      'brand': _product.brand,
      'image': _displayImage,
      'price': _currentPrice,
      'category': (widget.product['category'] ?? '').toString(),
    };
  }

  Future<void> _toggleWishlist() async {
    if (_wishlistActionInProgress) return;

    final messenger = ScaffoldMessenger.of(context);
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    final productId = _productId;
    if (uid.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please sign in to save favourites.')),
      );
      return;
    }
    if (productId.isEmpty) return;

    final nextValue = !_isWishlisted;
    setState(() {
      _isWishlisted = nextValue;
      _wishlistActionInProgress = true;
    });

    try {
      await _firestoreService.setProductFavorited(
        uid: uid,
        productId: productId,
        isFavorited: nextValue,
        productData: _favoriteSnapshot(),
      );
    } catch (e, st) {
      debugPrint('[ProductDetail] Failed to toggle favourite: $e\n$st');
      if (!mounted) return;
      setState(() => _isWishlisted = !nextValue);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update favourite. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _wishlistActionInProgress = false);
      }
    }
  }

  Future<void> _shareProduct() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Share feature will be enabled soon.')),
    );
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

  Widget _buildImage(String imagePath, {BoxFit fit = BoxFit.contain}) {
    final resolved = _normalizeImagePath(imagePath);
    final placeholder = Container(
      color: const Color(0xFFF0F0F5),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 64, color: Color(0xFFCCCCD8)),
      ),
    );
    if (resolved.isEmpty) return placeholder;
    if (resolved.startsWith('assets/')) {
      return Image.asset(
        resolved,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return Image.network(
      resolved,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  String _normalizeKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _resolveBrandLogo(HomeProvider home, String brandName) {
    final normalizedBrand = _normalizeKey(brandName);
    if (normalizedBrand.isEmpty) return '';

    for (final brand in home.brands) {
      final candidateName = (brand['name'] ?? '').toString();
      if (_normalizeKey(candidateName) == normalizedBrand) {
        final logo = (brand['image'] ?? brand['logo'] ?? brand['icon'] ?? '')
            .toString()
            .trim();
        if (logo.isNotEmpty) return logo;
      }
    }

    return '';
  }

  Widget _buildBrandLogo(String imagePath) {
    final resolved = _normalizeImagePath(imagePath);
    final placeholder = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.storefront_outlined,
        size: 22,
        color: AppColors.textHint,
      ),
    );

    if (resolved.isEmpty) return placeholder;

    final imageWidget = resolved.startsWith('assets/')
        ? Image.asset(
            resolved,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          )
        : Image.network(
            resolved,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 46, height: 46, child: imageWidget),
    );
  }

  List<String> _toCleanList(dynamic raw) {
    if (raw == null) return const [];

    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return const [];

    final parts = text
        .split(RegExp(r'\n|•|\||;'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return parts.isNotEmpty ? parts : [text];
  }

  List<String> _extractHighlights() {
    final candidates = [
      widget.product['highlights'],
      widget.product['highlight'],
      widget.product['keyHighlights'],
      widget.product['features'],
      widget.product['benefits'],
    ];

    for (final candidate in candidates) {
      final items = _toCleanList(candidate);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  List<String> _extractHowToUse() {
    final candidates = [
      widget.product['howToUse'],
      widget.product['how_to_use'],
      widget.product['usage'],
      widget.product['directions'],
      widget.product['instructions'],
    ];

    for (final candidate in candidates) {
      final items = _toCleanList(candidate);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  Future<void> _checkReviewEligibility() async {
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    final productId = _productId;
    final localOrderProvider = context.read<OrderProvider>();
    final localBought =
        localOrderProvider.hasBought(productId) ||
        localOrderProvider.hasBought(_baseProductId(productId));

    if (localBought) {
      if (!mounted) return;
      setState(() {
        _canReview = true;
        _checkingReviewEligibility = false;
      });
      return;
    }

    if (uid.isEmpty || productId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _canReview = false;
        _checkingReviewEligibility = false;
      });
      return;
    }

    setState(() => _checkingReviewEligibility = true);
    try {
      final allowed = await _firestoreService.hasUserPurchasedProduct(
        uid: uid,
        productId: productId,
      );
      if (!mounted) return;
      setState(() => _canReview = allowed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _canReview = false);
    } finally {
      if (mounted) setState(() => _checkingReviewEligibility = false);
    }
  }

  String _baseProductId(String value) {
    final id = value.trim();
    final sep = id.indexOf('::');
    if (sep <= 0) return id;
    return id.substring(0, sep);
  }

  Future<void> _showReviewEligibilityMessage() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Review locked',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only users who have bought this product can write a review. Place an order first, then you can share your rating, images, and videos.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ReviewModel? get _myReview {
    final uid = _currentUserId;
    if (uid.isEmpty) return null;
    for (final review in _product.reviews) {
      if (review.id == uid) return review;
    }
    return null;
  }

  Future<void> _deleteMyReview() async {
    final uid = _currentUserId;
    if (uid.isEmpty || _productId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('This will remove your review from this product.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await _firestoreService.deleteProductReview(
        uid: uid,
        productId: _productId,
      );
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Review deleted.')),
      );
      await _loadProductDetail();
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Could not delete review: $e')),
      );
    }
  }

  Future<void> _openReviewComposer([ReviewModel? initialReview]) async {
    final uid = _currentUserId;
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to write a review.')),
      );
      return;
    }

    if (!_canReview && initialReview == null) {
      await _showReviewEligibilityMessage();
      return;
    }

    final commentController = TextEditingController(
      text: initialReview?.comment ?? '',
    );
    var ratingValue = initialReview?.rating ?? 5.0;
    final pickedFiles = <XFile>[];
    final existingMediaUrls = <String>[...?(initialReview?.mediaUrls)];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        initialReview == null
                            ? 'Write a Review'
                            : 'Edit Review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Rating: ${ratingValue.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Slider(
                        value: ratingValue,
                        min: 1,
                        max: 5,
                        divisions: 8,
                        label: ratingValue.toStringAsFixed(1),
                        onChanged: (v) => setModalState(() => ratingValue = v),
                      ),
                      TextField(
                        controller: commentController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Share your experience with this product',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final images = await _imagePicker
                                  .pickMultiImage();
                              if (images.isEmpty) return;
                              setModalState(() => pickedFiles.addAll(images));
                            },
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Add Images'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final image = await _imagePicker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 85,
                              );
                              if (image == null) return;
                              setModalState(() => pickedFiles.add(image));
                            },
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Use Camera'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final video = await _imagePicker.pickVideo(
                                source: ImageSource.gallery,
                              );
                              if (video == null) return;
                              setModalState(() => pickedFiles.add(video));
                            },
                            icon: const Icon(Icons.videocam_outlined),
                            label: const Text('Add Video'),
                          ),
                        ],
                      ),
                      if (pickedFiles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Selected media',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(pickedFiles.length, (i) {
                            final file = pickedFiles[i];
                            return _PickedReviewMediaTile(
                              file: file,
                              onRemove: () =>
                                  setModalState(() => pickedFiles.removeAt(i)),
                            );
                          }),
                        ),
                      ],
                      if (existingMediaUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Existing media',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(existingMediaUrls.length, (
                            i,
                          ) {
                            final url = existingMediaUrls[i];
                            return _ExistingReviewMediaTile(
                              url: url,
                              onRemove: () => setModalState(
                                () => existingMediaUrls.removeAt(i),
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingReview
                              ? null
                              : () async {
                                  final comment = commentController.text.trim();
                                  if (comment.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter your review comment.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(context);
                                  final navigator = Navigator.of(ctx);
                                  final userName =
                                      context.read<AuthProvider>().user?.name ??
                                      'Verified Buyer';

                                  setState(() => _submittingReview = true);
                                  try {
                                    final uploadedMediaUrls =
                                        await _firestoreService
                                            .uploadReviewMedia(
                                              uid: uid,
                                              productId: _productId,
                                              files: pickedFiles,
                                            );

                                    await _firestoreService.submitProductReview(
                                      uid: uid,
                                      productId: _productId,
                                      userName: userName,
                                      rating: ratingValue,
                                      comment: comment,
                                      mediaUrls: [
                                        ...existingMediaUrls,
                                        ...uploadedMediaUrls,
                                      ],
                                    );

                                    if (!mounted) return;
                                    navigator.pop();
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          initialReview == null
                                              ? 'Review submitted!'
                                              : 'Review updated!',
                                        ),
                                      ),
                                    );
                                    await _loadProductDetail();
                                  } catch (e) {
                                    if (mounted) {
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.toString().replaceFirst(
                                              'StateError: ',
                                              '',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _submittingReview = false);
                                    }
                                  }
                                },
                          child: Text(
                            _submittingReview
                                ? 'Submitting...'
                                : 'Submit Review',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailsTabBody({
    required String description,
    required List<String> highlights,
    required List<String> howToUse,
  }) {
    final hasDescription = description.trim().isNotEmpty;

    if (_selectedDetailsTab == 0) {
      final content = hasDescription
          ? description
          : 'No description available for this product.';
      final shouldCollapse = content.length > 210;
      final displayText = (!_detailsExpanded && shouldCollapse)
          ? '${content.substring(0, 210).trim()}...'
          : content;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.42,
            ),
          ),
          if (shouldCollapse)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() => _detailsExpanded = !_detailsExpanded);
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_detailsExpanded ? 'Read Less' : 'Read More'),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final items = _selectedDetailsTab == 1 ? highlights : howToUse;
    final fallback = _selectedDetailsTab == 1
        ? 'No highlights available for this product.'
        : 'How-to-use instructions are not available yet.';

    if (items.isEmpty) {
      return Text(
        fallback,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      );
    }

    final shouldCollapse = items.length > 4;
    final displayItems = (!_detailsExpanded && shouldCollapse)
        ? items.take(4).toList()
        : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shouldCollapse)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _detailsExpanded = !_detailsExpanded);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_detailsExpanded ? 'Read Less' : 'Read More'),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _recommendedItems(List<Map<String, dynamic>> all) {
    final currentId = _product.id;
    final currentCategory = _normalizeKey(
      (widget.product['category'] ?? '').toString(),
    );
    final currentBrand = _normalizeKey(_product.brand);
    final candidates = all
        .where((p) => (p['id'] ?? '').toString() != currentId)
        .toList();
    final explicit = candidates.where((p) {
      final section = _normalizeKey(
        (p['homeSection'] ?? p['home_section'] ?? p['section'] ?? '')
            .toString(),
      );
      final tag = _normalizeKey((p['tag'] ?? '').toString());
      return section == 'recommended_salon' ||
          section == 'recommended' ||
          tag == 'recommended';
    }).toList();
    if (explicit.isNotEmpty) return explicit.take(6).toList();
    final scored = List<Map<String, dynamic>>.from(candidates)
      ..sort((a, b) {
        int score(Map<String, dynamic> p) {
          var s = 0;
          final cat = _normalizeKey((p['category'] ?? '').toString());
          final br = _normalizeKey((p['brand'] ?? '').toString());
          if (cat.isNotEmpty && cat == currentCategory) s += 200;
          if (br.isNotEmpty && br == currentBrand) s += 120;
          s += (((p['rating'] as num?) ?? 0) * 10).round();
          s += (((p['reviews'] as num?) ?? 0) / 25).round();
          return s;
        }

        return score(b).compareTo(score(a));
      });
    return scored.take(6).toList();
  }

  int get _currentPrice {
    final v = _selectedVariant?.price ?? 0;
    if (v > 0) return v;
    return ((widget.product['price'] as num?) ?? 0).toInt();
  }

  String get _cartItemId {
    final baseId = _product.id;
    final variantId = (_selectedVariant?.id ?? '').trim();
    if (baseId.isEmpty) return '';
    return variantId.isEmpty ? baseId : '$baseId::$variantId';
  }

  String get _displaySize {
    final v = (_selectedVariant?.shadeName ?? '').trim();
    if (v.isNotEmpty) return v;
    return (widget.product['size'] ?? '').toString().trim();
  }

  String get _displayImage {
    final imgs = _productState?.displayImages ?? const <String>[];
    final idx = _productState?.selectedImageIndex ?? 0;
    if (imgs.isNotEmpty && idx >= 0 && idx < imgs.length) return imgs[idx];
    if (_product.images.isNotEmpty) return _product.images.first;
    return (widget.product['image'] ?? '').toString();
  }

  Map<String, dynamic> get _cartPayload {
    final baseName = _product.name.trim();
    final variantName = (_selectedVariant?.shadeName ?? '').trim();
    final composedName = variantName.isEmpty
        ? baseName
        : '$baseName • $variantName';
    return {
      ...widget.product,
      'id': _cartItemId,
      'name': composedName,
      'brand': _product.brand,
      'image': _displayImage,
      'price': _currentPrice,
      'size': _displaySize,
      'variantId': (_selectedVariant?.id ?? '').trim(),
      'variantName': variantName,
    };
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final recommended = _recommendedItems(home.productMaps);

    final name = _product.name.trim().isNotEmpty
        ? _product.name
        : (widget.product['name'] ?? '').toString();
    final brand = _product.brand.trim().isNotEmpty
        ? _product.brand
        : (widget.product['brand'] ?? '').toString();
    final brandLogo = _resolveBrandLogo(home, brand);
    final tag = (widget.product['tag'] ?? '').toString();
    final description = _product.description.trim().isNotEmpty
        ? _product.description
        : (widget.product['description'] ?? '').toString();
    final highlights = _extractHighlights();
    final howToUse = _extractHowToUse();
    final reviewItems = _product.reviews.take(10).toList();
    final derivedReviewCount = reviewItems.isNotEmpty ? reviewItems.length : 0;
    final reviews = [
      _product.reviewCount,
      derivedReviewCount,
      ((widget.product['reviews'] as num?) ?? 0).toInt(),
    ].reduce((a, b) => a > b ? a : b);
    final derivedRating = reviewItems.isNotEmpty
        ? reviewItems.fold<double>(0.0, (sum, review) => sum + review.rating) /
              reviewItems.length
        : 0.0;
    final rating = derivedRating > 0
        ? derivedRating
        : (_product.rating > 0
              ? _product.rating
              : ((widget.product['rating'] as num?) ?? 0).toDouble());
    final myReview = _myReview;
    final price = _currentPrice;
    final originalPrice = ((widget.product['originalPrice'] as num?) ?? 0)
        .toInt();
    final hasDiscount = originalPrice > price;
    final discountPct = hasDiscount
        ? (((originalPrice - price) / originalPrice) * 100).round()
        : 0;
    final variants = _product.variants;

    final imageList = _productState?.displayImages ?? const <String>[];
    final selectedImageIndex = _productState?.selectedImageIndex ?? 0;
    final carouselImages = imageList.isNotEmpty
        ? imageList
        : (_product.images.isNotEmpty
              ? _product.images
              : [(widget.product['image'] ?? '').toString()]);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _CircleIconButton(
            icon: Icons.arrow_back_ios_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ),
        actions: [
          if (_loadingDetail)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CircleIconButton(
              icon: _isWishlisted
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              iconColor: _isWishlisted
                  ? const Color(0xFFE53935)
                  : AppColors.textPrimary,
              onTap: _toggleWishlist,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _CircleIconButton(
              icon: Icons.ios_share_outlined,
              onTap: _shareProduct,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomCartBar(
        cartItem: _cartPayload,
        displaySize: _displaySize,
        displayPrice: price,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. IMAGE CAROUSEL ─────────────────────────────────────────
            _ProductImageCarousel(
              images: carouselImages,
              selectedIndex: selectedImageIndex,
              pageController: _pageController,
              onPageChanged: (i) => _productState?.setImageIndex(i),
              buildImage: _buildImage,
            ),

            // ── 2. MAIN PRODUCT INFO CARD ─────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand pill + tag
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            brand.isNotEmpty ? brand.toUpperCase() : 'BRAND',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (tag.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Product name
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),

                  // Rating badge
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D7A22),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$reviews Ratings',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Divider(height: 1, color: Color(0xFFF0F0F5)),
                  ),

                  // Price section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹$price',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 10),
                          Text(
                            '₹$originalPrice',
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$discountPct% OFF',
                              style: const TextStyle(
                                color: Color(0xFF2D7A22),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      'MRP inclusive of all taxes',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Divider(height: 1, color: Color(0xFFF0F0F5)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Text(
                      'Choose Shade',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (variants.isNotEmpty)
                    SizedBox(
                      height: 66,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        scrollDirection: Axis.horizontal,
                        itemCount: variants.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final variant = variants[i];
                          final isSelected = _selectedVariant?.id == variant.id;
                          final shadeName = variant.shadeName.isNotEmpty
                              ? variant.shadeName
                              : variant.value;

                          return GestureDetector(
                            onTap: () => _productState?.selectVariant(variant),
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: variant.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : const Color(0xFFD9D9E3),
                                      width: isSelected ? 2.5 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withOpacity(0.2),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 88,
                                  child: Text(
                                    shadeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Text(
                        'No variants available for this product.',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── 3. PRODUCT DETAILS TABBED CARD ───────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product Details',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final tab in const [
                        'Description',
                        'Highlights',
                        'How to use',
                      ])
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedDetailsTab = const [
                                  'Description',
                                  'Highlights',
                                  'How to use',
                                ].indexOf(tab);
                                _detailsExpanded = false;
                              });
                            },
                            child: Column(
                              children: [
                                Text(
                                  tab,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        _selectedDetailsTab ==
                                            const [
                                              'Description',
                                              'Highlights',
                                              'How to use',
                                            ].indexOf(tab)
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color:
                                        _selectedDetailsTab ==
                                            const [
                                              'Description',
                                              'Highlights',
                                              'How to use',
                                            ].indexOf(tab)
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    height: 1,
                    color: const Color(0xFFE9E9EF),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _buildDetailsTabBody(
                      description: description,
                      highlights: highlights,
                      howToUse: howToUse,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Delivery section removed as requested.

            // ── 5. BRAND CARD ─────────────────────────────────────────────
            _SectionCard(
              child: Row(
                children: [
                  _buildBrandLogo(brandLogo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brand.isNotEmpty ? brand : 'Brand',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Tap to explore all products',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── 6. RATINGS & REVIEWS (UI ONLY) ───────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Ratings & Reviews',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_checkingReviewEligibility)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton.icon(
                          onPressed: () => _openReviewComposer(myReview),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(
                            myReview != null
                                ? 'Edit Review'
                                : (_canReview
                                      ? 'Write Review'
                                      : 'Bought users only'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFF5B70A),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$reviews ratings',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (reviewItems.isNotEmpty)
                    ...reviewItems.map(
                      (review) => _ReviewPreviewTile(
                        isOwnReview: review.id == _currentUserId,
                        userName: review.userName,
                        rating: review.rating,
                        comment: review.comment,
                        mediaUrls: review.mediaUrls,
                        onEdit: review.id == _currentUserId
                            ? () => _openReviewComposer(review)
                            : null,
                        onDelete: review.id == _currentUserId
                            ? _deleteMyReview
                            : null,
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No reviews for this product yet.',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Be the first one to review this product.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _openReviewComposer,
                            icon: const Icon(
                              Icons.rate_review_outlined,
                              size: 16,
                            ),
                            label: const Text('Write a review'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 7. RECOMMENDED SECTION ────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recommended for you',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Curated picks for your salon',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            if (recommended.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Recommendations will appear here soon.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              )
            else
              SizedBox(
                height: 250,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: recommended.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(
                    width: 174,
                    child: ProductCard(product: recommended[i]),
                  ),
                ),
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE CAROUSEL
// ─────────────────────────────────────────────────────────────────────────────

class _ProductImageCarousel extends StatelessWidget {
  final List<String> images;
  final int selectedIndex;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final Widget Function(String, {BoxFit fit}) buildImage;

  const _ProductImageCarousel({
    required this.images,
    required this.selectedIndex,
    required this.pageController,
    required this.onPageChanged,
    required this.buildImage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Main swipeable image
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: pageController,
              itemCount: images.length,
              onPageChanged: onPageChanged,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 16),
                child: buildImage(images[i], fit: BoxFit.contain),
              ),
            ),
          ),

          if (images.length > 1) ...[
            // Pill dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                final active = i == selectedIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : const Color(0xFFD1D1D8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),

            // Clickable thumbnail strip
            SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final active = i == selectedIndex;
                  return GestureDetector(
                    onTap: () {
                      pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                      );
                      onPageChanged(i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? AppColors.primary
                              : const Color(0xFFE0E0E8),
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: buildImage(images[i], fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION CARD WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER / PINCODE FIELD removed (no longer used).

class _ReviewPreviewTile extends StatelessWidget {
  final String userName;
  final double rating;
  final String comment;
  final List<String> mediaUrls;
  final bool isOwnReview;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ReviewPreviewTile({
    required this.userName,
    required this.rating,
    required this.comment,
    this.mediaUrls = const [],
    this.isOwnReview = false,
    this.onEdit,
    this.onDelete,
  });

  bool _isVideoUrl(String url) {
    final value = url.toLowerCase();
    return value.contains('.mp4') ||
        value.contains('.mov') ||
        value.contains('.avi') ||
        value.contains('.mkv') ||
        value.contains('/video/');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  userName.trim().isNotEmpty ? userName : 'Reviewer',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isOwnReview)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit?.call();
                    } else if (value == 'delete') {
                      onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit review'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete review'),
                    ),
                  ],
                ),
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFFF5B70A),
              ),
              const SizedBox(width: 2),
              Text(
                rating > 0 ? rating.toStringAsFixed(1) : '0.0',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.trim().isNotEmpty
                ? comment
                : 'Review text will be available here.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mediaUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = mediaUrls[i];
                  final isVideo = _isVideoUrl(url);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 62,
                      height: 62,
                      color: const Color(0xFFEFEFF5),
                      child: isVideo
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                const ColoredBox(color: Color(0xFFE8E8F0)),
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: AppColors.textSecondary,
                                    size: 24,
                                  ),
                                ),
                              ],
                            )
                          : Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.textHint,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExistingReviewMediaTile extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;

  const _ExistingReviewMediaTile({required this.url, required this.onRemove});

  bool get _isVideo {
    final value = url.toLowerCase();
    return value.contains('.mp4') ||
        value.contains('.mov') ||
        value.contains('.avi') ||
        value.contains('.mkv') ||
        value.contains('.webm') ||
        value.contains('/video/');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 84,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E6EF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _isVideo
                      ? Container(
                          color: const Color(0xFFE9E9F2),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 28,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFE9E9F2),
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isVideo ? 'Video' : 'Image',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickedReviewMediaTile extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _PickedReviewMediaTile({required this.file, required this.onRemove});

  bool get _isVideo {
    final value = file.name.toLowerCase();
    return value.endsWith('.mp4') ||
        value.endsWith('.mov') ||
        value.endsWith('.avi') ||
        value.endsWith('.mkv') ||
        value.endsWith('.webm');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 84,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E6EF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _isVideo
                      ? Container(
                          color: const Color(0xFFE9E9F2),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 28,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : FutureBuilder<Uint8List>(
                          future: file.readAsBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Container(
                                color: const Color(0xFFE9E9F2),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFE9E9F2),
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.textHint,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CIRCLE ICON BUTTON (AppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM CART BAR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomCartBar extends StatelessWidget {
  final Map<String, dynamic> cartItem;
  final String displaySize;
  final int displayPrice;

  const _BottomCartBar({
    required this.cartItem,
    required this.displaySize,
    required this.displayPrice,
  });

  @override
  Widget build(BuildContext context) {
    final cartId = (cartItem['id'] ?? '').toString();

    return SafeArea(
      top: false,
      child: Consumer<CartModel>(
        builder: (_, cart, __) {
          final qty = cart.quantityOf(cartId);
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Price info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (displaySize.isNotEmpty)
                        Text(
                          displaySize,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Text(
                        '₹$displayPrice',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const Text(
                        'Incl. all taxes',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Add to Cart / qty stepper + checkout
                SizedBox(
                  width: qty == 0 ? 170 : 225,
                  height: 50,
                  child: qty == 0
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: cartId.isEmpty
                              ? null
                              : () => cart.add(cartItem),
                          child: const Text(
                            'Add to cart',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            Container(
                              width: 104,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: IconButton(
                                      onPressed: () => cart.remove(cartId),
                                      icon: const Icon(
                                        Icons.remove,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$qty',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Expanded(
                                    child: IconButton(
                                      onPressed: () => cart.add(cartItem),
                                      icon: const Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CartScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Checkout',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
