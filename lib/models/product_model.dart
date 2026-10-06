// ============================================================
// lib/models/product_model.dart
//
// UPDATE: added `originalPrice` + `discountPercent` fields for
// discounted pricing.
//
//   - `price`           = current selling price (UNCHANGED meaning —
//                          every existing screen that reads p.price
//                          keeps working exactly as before).
//   - `discountPercent` = 0 when no discount is active.
//   - `originalPrice`   = the pre-discount price, only meaningful when
//                          discountPercent > 0. Stored explicitly
//                          (rather than re-derived every time) so it
//                          survives price-rounding and stays stable.
//   - `hasDiscount` is a derived getter, not stored.
//
// Both new fields default to 0, so existing Firestore documents
// (created before this feature shipped) parse safely as "no discount"
// with zero migration needed — identical pattern to how `imageUrl`
// was introduced.
// ============================================================
class ProductModel {
  final String   id;
  final String   tagNumber;
  final String   name;
  final String   category;
  final double   price;
  final int      stock;
  final String   description;
  final String   warehouse;
  final String   imageUrl;
  final double   originalPrice;
  final double   discountPercent;
  final DateTime createdAt;

  ProductModel({
    required this.id,
    required this.tagNumber,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.description     = '',
    this.warehouse        = 'Main Warehouse',
    this.imageUrl         = '',
    this.originalPrice    = 0,
    this.discountPercent  = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// True only when a real, currently-cheaper discount is active.
  /// Guards against stale data where discountPercent > 0 but
  /// originalPrice was never set (or is <= price).
  bool get hasDiscount => discountPercent > 0 && originalPrice > price;

  Map<String, dynamic> toJson() => {
    'id':              id,
    'tagNumber':       tagNumber,
    'name':            name,
    'category':        category,
    'price':           price,
    'stock':           stock,
    'description':     description,
    'warehouse':       warehouse,
    'imageUrl':         imageUrl,
    'originalPrice':    originalPrice,
    'discountPercent':  discountPercent,
    'createdAt':       createdAt.toIso8601String(),
  };

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
    id:              json['id']              as String? ?? '',
    tagNumber:       json['tagNumber']       as String? ?? 'FF-????',
    name:            json['name']            as String? ?? '',
    category:        json['category']        as String? ?? 'Other',
    price:           (json['price']          as num?)?.toDouble() ?? 0,
    stock:           (json['stock']          as num?)?.toInt()    ?? 0,
    description:     json['description']     as String? ?? '',
    warehouse:       json['warehouse']       as String? ?? 'Main Warehouse',
    imageUrl:        json['imageUrl']        as String? ?? '',
    originalPrice:   (json['originalPrice']  as num?)?.toDouble() ?? 0,
    discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
    createdAt:       json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  ProductModel copyWith({
    String?   id,
    String?   tagNumber,
    String?   name,
    String?   category,
    double?   price,
    int?      stock,
    String?   description,
    String?   warehouse,
    String?   imageUrl,
    double?   originalPrice,
    double?   discountPercent,
    DateTime? createdAt,
  }) => ProductModel(
    id:              id              ?? this.id,
    tagNumber:       tagNumber       ?? this.tagNumber,
    name:            name            ?? this.name,
    category:        category        ?? this.category,
    price:           price           ?? this.price,
    stock:           stock           ?? this.stock,
    description:     description     ?? this.description,
    warehouse:       warehouse       ?? this.warehouse,
    imageUrl:        imageUrl        ?? this.imageUrl,
    originalPrice:   originalPrice   ?? this.originalPrice,
    discountPercent: discountPercent ?? this.discountPercent,
    createdAt:       createdAt       ?? this.createdAt,
  );
}