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
  final String tag;
  final String size;
  final String deliveryTime;
  final bool isPopular;
  final bool isRecommended;

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
    this.tag = '',
    this.size = '',
    this.deliveryTime = '',
    this.isPopular = false,
    this.isRecommended = false,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, String id) {
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
      image: map['image'] ?? map['imageUrl'] ?? '',
      tag: map['tag'] ?? '',
      size: map['size'] ?? '',
      deliveryTime: map['deliveryTime'] ?? '',
      isPopular: map['isPopular'] ?? false,
      isRecommended: map['isRecommended'] ?? false,
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
      'tag': tag,
      'size': size,
      'deliveryTime': deliveryTime,
      'isPopular': isPopular,
      'isRecommended': isRecommended,
    };
  }

  /// Convert to the legacy Map<String,dynamic> format used by widgets/cart
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
      'tag': tag,
      'size': size,
      'deliveryTime': deliveryTime,
    };
  }
}
