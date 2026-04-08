import 'package:purecuts/core/utils/product_image_contract.dart';

class ProductModel {
  final String id;
  final String name;
  final String brand;
  final String productType;
  final int stock;
  final bool manageStock;
  final String category;
  final String categoryName;
  final String parentCategory;
  final String subCategory;
  final String subSubCategory;
  final List<String> selectedCategories;
  final List<String> categoryPathNames;
  final int price;
  final int originalPrice;
  final double rating;
  final int reviews;
  final String image;
  final String thumbnailUrl;
  final String fullImageUrl;
  final List<String> additionalImages;
  final List<String> images;
  final String tag;
  final List<String> tags;
  final String size;
  final String deliveryTime;
  final String highlights;
  final String description;
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
    this.productType = '',
    this.stock = 0,
    this.manageStock = true,
    required this.category,
    this.categoryName = '',
    this.parentCategory = '',
    this.subCategory = '',
    this.subSubCategory = '',
    this.selectedCategories = const [],
    this.categoryPathNames = const [],
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.reviews,
    required this.image,
    this.thumbnailUrl = '',
    this.fullImageUrl = '',
    this.additionalImages = const [],
    this.images = const [],
    this.tag = '',
    this.tags = const [],
    this.size = '',
    this.deliveryTime = '',
    this.highlights = '',
    this.description = '',
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
    String stringValue(dynamic value, {String fallback = ''}) {
      final text = (value ?? fallback).toString().trim();
      return text;
    }

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

    bool boolValue(dynamic value, {bool fallback = false}) {
      if (value is bool) return value;
      final text = (value ?? '').toString().trim().toLowerCase();
      if (text.isEmpty) return fallback;
      if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
        return true;
      }
      if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
        return false;
      }
      return fallback;
    }

    int intValue(dynamic value, {int fallback = 0}) {
      if (value is num) return value.toInt();
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return fallback;
      return int.tryParse(text) ?? fallback;
    }

    List<String> parseTagValues(dynamic raw) {
      if (raw == null) return <String>[];

      if (raw is String) {
        return raw
            .split(RegExp(r'[,|/&;]+'))
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }

      if (raw is Iterable) {
        return raw
            .where((e) => e != null)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }

      final single = raw.toString().trim();
      return single.isEmpty ? <String>[] : <String>[single];
    }

    final additionalImages = toStringList(map['additionalImages']);
    final images = toStringList(map['images']);
    final parsedTags = parseTagValues(map['tags']);
    final singleTag = stringValue(map['tag']);
    final tags = <String>{...parsedTags};
    if (singleTag.isNotEmpty) tags.add(singleTag);

    final thumbnail = resolveThumbnailImage(map);
    final fullImage = resolveFullImage(map);
    final listImage = thumbnail.isNotEmpty
        ? thumbnail
        : (fullImage.isNotEmpty
              ? fullImage
              : (images.isNotEmpty
                    ? images.first
                    : (additionalImages.isNotEmpty
                          ? additionalImages.first
                          : '')));

    return ProductModel(
      id: id,
      name: stringValue(map['name'] ?? map['title'] ?? map['productName']),
      brand: stringValue(
        map['brand'] ?? map['brandName'] ?? map['manufacturer'],
      ),
      productType: stringValue(map['productType'] ?? map['type']),
      stock: intValue(
        map['stock'] ??
            map['quantity'] ??
            map['qty'] ??
            map['inventory'] ??
            map['stockCount'],
      ),
      manageStock: boolValue(map['manageStock'], fallback: true),
      category: stringValue(map['category'] ?? map['categoryName']),
      categoryName: stringValue(map['categoryName'] ?? map['category']),
      parentCategory: stringValue(map['parentCategory']),
      subCategory: stringValue(
        map['subCategory'] ?? map['subcategory'] ?? map['sub_category'],
      ),
      subSubCategory: stringValue(
        map['subSubCategory'] ??
            map['subsubCategory'] ??
            map['sub_sub_category'],
      ),
      selectedCategories: toStringList(map['selectedCategories']),
      categoryPathNames: toStringList(map['categoryPathNames']),
      price: (map['price'] as num?)?.toInt() ?? 0,
      originalPrice: (map['originalPrice'] as num?)?.toInt() ?? 0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      reviews: (map['reviews'] as num?)?.toInt() ?? 0,
      image: listImage,
      thumbnailUrl: thumbnail,
      fullImageUrl: fullImage,
      additionalImages: additionalImages,
      images: images,
      tag: singleTag,
      tags: tags.toList(growable: false),
      size: stringValue(map['size']),
      deliveryTime: stringValue(map['deliveryTime']),
      highlights: stringValue(map['highlights'] ?? map['shortDescription']),
      description: stringValue(
        map['description'] ?? map['shortDescription'] ?? map['highlights'],
      ),
      howToUse: stringValue(
        map['howToUse'] ?? map['how_to_use'] ?? map['usage'],
      ),
      homeSection: stringValue(
        map['homeSection'] ?? map['home_section'] ?? map['section'],
      ),
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
      'productType': productType,
      'stock': stock,
      'manageStock': manageStock,
      'category': category,
      'categoryName': categoryName,
      'parentCategory': parentCategory,
      'subCategory': subCategory,
      'subSubCategory': subSubCategory,
      'subsubCategory': subSubCategory,
      'sub_sub_category': subSubCategory,
      'selectedCategories': selectedCategories,
      'categoryPathNames': categoryPathNames,
      'price': price,
      'originalPrice': originalPrice,
      'rating': rating,
      'reviews': reviews,
      'image': image,
      'thumbnailUrl': thumbnailUrl,
      'thumbnail': thumbnailUrl,
      'thumb': thumbnailUrl,
      'fullImageUrl': fullImageUrl,
      'additionalImages': additionalImages,
      'images': images,
      'tag': tag,
      'tags': tags,
      'size': size,
      'deliveryTime': deliveryTime,
      'highlights': highlights,
      'description': description,
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
      'productType': productType,
      'stock': stock,
      'manageStock': manageStock,
      'category': category,
      'categoryName': categoryName,
      'parentCategory': parentCategory,
      'subCategory': subCategory,
      'subSubCategory': subSubCategory,
      'subsubCategory': subSubCategory,
      'sub_sub_category': subSubCategory,
      'selectedCategories': selectedCategories,
      'categoryPathNames': categoryPathNames,
      'price': price,
      'originalPrice': originalPrice,
      'rating': rating,
      'reviews': reviews,
      'image': image,
      'imageUrl': fullImageUrl.isNotEmpty ? fullImageUrl : image,
      'thumbnailUrl': thumbnailUrl,
      'thumbnail': thumbnailUrl,
      'thumb': thumbnailUrl,
      'fullImageUrl': fullImageUrl,
      'additionalImages': additionalImages,
      'images': images,
      'tag': tag,
      'tags': tags,
      'size': size,
      'deliveryTime': deliveryTime,
      'highlights': highlights,
      'description': description,
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
