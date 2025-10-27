// DTOs mínimos lidos da OFF.
// Mantém só campos usados no app.

class OffSearchResponseDto {
  final List<OffProductDto> products;

  OffSearchResponseDto({required this.products});

  factory OffSearchResponseDto.fromJson(Map<String, dynamic> json) {
    final list = (json['products'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(OffProductDto.fromJson)
        .toList();
    return OffSearchResponseDto(products: list);
  }
}

class OffProductDto {
  final String code;
  final String? name;
  final String? brands;
  final String? nutriScore; // a-e
  final String? imageSmallUrl;
  final Map<String, dynamic>? nutriments;

  OffProductDto({
    required this.code,
    this.name,
    this.brands,
    this.nutriScore,
    this.imageSmallUrl,
    this.nutriments,
  });

  factory OffProductDto.fromJson(Map<String, dynamic> json) {
    return OffProductDto(
      code: (json['code'] ?? '').toString(),
      name: (json['product_name'] ?? json['product_name_en']) as String?,
      brands: json['brands'] as String?,
      nutriScore: (json['nutriscore_grade'] ?? json['nutrition_grades'])?.toString(),
      imageSmallUrl: json['image_small_url'] as String?,
      nutriments: json['nutriments'] is Map<String, dynamic>
          ? (json['nutriments'] as Map<String, dynamic>)
          : null,
    );
  }
}

class OffProductResponseDto {
  final OffProductDto? product;
  final String? etag;
  final bool notModified;

  OffProductResponseDto({this.product, this.etag, this.notModified = false});

  factory OffProductResponseDto.fromHttpJson(
    Map<String, dynamic>? json, {
    String? etag,
    bool notModified = false,
  }) {
    return OffProductResponseDto(
      product: json == null ? null : OffProductDto.fromJson(json['product'] ?? {}),
      etag: etag,
      notModified: notModified,
    );
  }
}
