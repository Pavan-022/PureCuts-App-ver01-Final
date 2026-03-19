class ProductModel {
  final String id;
  final String name;
  final String brand;
  final String category;
  final String subCategory;
  final int price;
  final int originalPrice;
  final double rating;
  final int reviews;
  final String image;
  final List<String> additionalImages;
  final List<String> images;
  final String tag;
  final List<String> tags;
  final String size;
  final String deliveryTime;
  final String highlights;
  final String howToUse;
  final String homeSection;
  final bool isPopular;
  final bool isRecommended;
  final bool showInStartFirstOrder;
  final bool showInRecommendedSalon;
  final bool showInMostBought;
  final bool showInPopularProducts;

  const ProductModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    this.subCategory = '',
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.reviews,
    required this.image,
    this.additionalImages = const [],
    this.images = const [],
    this.tag = '',
    this.tags = const [],
    this.size = '',
    this.deliveryTime = '',
    this.highlights = '',
    this.howToUse = '',
    this.homeSection = '',
    this.isPopular = false,
    this.isRecommended = false,
    this.showInStartFirstOrder = false,
    this.showInRecommendedSalon = false,
    this.showInMostBought = false,
    this.showInPopularProducts = false,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, String id) {
    List<String> toStringList(dynamic raw) {
      if (raw is! Iterable) return <String>[];
      try {
        return raw
            .where((e) => e != null)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      } catch (_) {
        return <String>[];
      }
    }

    final additionalImages = toStringList(map['additionalImages']);
    final images = toStringList(map['images']);
    final parsedTags = toStringList(map['tags']);
    final singleTag = (map['tag'] ?? '').toString().trim();
    final tags = <String>{...parsedTags};
    if (singleTag.isNotEmpty) tags.add(singleTag);

    final thumbnail =
        (map['image'] ?? map['imageUrl'] ?? '').toString().trim().isNotEmpty
        ? (map['image'] ?? map['imageUrl']).toString().trim()
        : (images.isNotEmpty
              ? images.first
              : (additionalImages.isNotEmpty ? additionalImages.first : ''));

    return ProductModel(
      id: id,
      name: map['name'] ?? '',
      brand: map['brand'] ?? '',
      category: map['category'] ?? '',
      subCategory:
          map['subCategory'] ?? map['subcategory'] ?? map['sub_category'] ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      originalPrice: (map['originalPrice'] as num?)?.toInt() ?? 0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      reviews: (map['reviews'] as num?)?.toInt() ?? 0,
      image: thumbnail,
      additionalImages: additionalImages,
      images: images,
      tag: singleTag,
      tags: tags.toList(growable: false),
      size: map['size'] ?? '',
      deliveryTime: map['deliveryTime'] ?? '',
      highlights: map['highlights'] ?? map['shortDescription'] ?? '',
      howToUse: map['howToUse'] ?? map['how_to_use'] ?? map['usage'] ?? '',
      homeSection:
          map['homeSection'] ?? map['home_section'] ?? map['section'] ?? '',
      isPopular: map['isPopular'] ?? false,
      isRecommended: map['isRecommended'] ?? false,
      showInStartFirstOrder: map['showInStartFirstOrder'] ?? false,
      showInRecommendedSalon: map['showInRecommendedSalon'] ?? false,
      showInMostBought: map['showInMostBought'] ?? false,
      showInPopularProducts: map['showInPopularProducts'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'brand': brand,
      'category': category,
      'subCategory': subCategory,
      'price': price,
      'originalPrice': originalPrice,
      'rating': rating,
      'reviews': reviews,
      'image': image,
      'additionalImages': additionalImages,
      'images': images,
      'tag': tag,
      'tags': tags,
      'size': size,
      'deliveryTime': deliveryTime,
      'highlights': highlights,
      'howToUse': howToUse,
      'how_to_use': howToUse,
      'usage': howToUse,
      'homeSection': homeSection,
      'isPopular': isPopular,
      'isRecommended': isRecommended,
      'showInStartFirstOrder': showInStartFirstOrder,
      'showInRecommendedSalon': showInRecommendedSalon,
      'showInMostBought': showInMostBought,
      'showInPopularProducts': showInPopularProducts,
    };
  }

  /// Convert to the legacy product map format used by widgets/cart.
  Map<String, dynamic> toProductMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'category': category,
      'subCategory': subCategory,
      'price': price,
      'originalPrice': originalPrice,
      'rating': rating,
      'reviews': reviews,
      'image': image,
      'imageUrl': image,
      'additionalImages': additionalImages,
      'images': images,
      'tag': tag,
      'tags': tags,
      'size': size,
      'deliveryTime': deliveryTime,
      'highlights': highlights,
      'howToUse': howToUse,
      'how_to_use': howToUse,
      'usage': howToUse,
      'homeSection': homeSection,
      'isPopular': isPopular,
      'isRecommended': isRecommended,
      'showInStartFirstOrder': showInStartFirstOrder,
      'showInRecommendedSalon': showInRecommendedSalon,
      'showInMostBought': showInMostBought,
      'showInPopularProducts': showInPopularProducts,
    };
  }
}
