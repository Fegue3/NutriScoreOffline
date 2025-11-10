// DTOs (Data Transfer Objects) mínimos lidos da OFF.
// -----------------------------------------------------------------------------
// O que são DTOs?
// DTO = “Data Transfer Object”. São estruturas de dados simples (sem lógica de
// negócio) usadas para **transportar informação entre camadas** e/ou serviços.
// Aqui, os DTOs isolam a app do formato bruto do Open Food Facts (OFF),
// permitindo:
//   - Mapear apenas os **campos necessários** (poupa dados e reduz acoplamento);
//   - Centralizar a **transformação de JSON → objetos**;
//   - Proteger o resto do código de mudanças no payload remoto.
// -----------------------------------------------------------------------------

/// Resposta de **pesquisa** do Open Food Facts (OFF) com lista de produtos.
/// (DTO sem lógica: apenas contém os campos usados pelo NutriScore.)
class OffSearchResponseDto {
  /// Lista de produtos devolvidos pela pesquisa.
  final List<OffProductDto> products;

  OffSearchResponseDto({required this.products});

  /// Constrói a resposta a partir de JSON do OFF.
  ///
  /// - Lê `products` (lista);
  /// - Filtra para `Map<String, dynamic>`;
  /// - Mapeia para [OffProductDto].
  factory OffSearchResponseDto.fromJson(Map<String, dynamic> json) {
    final list = (json['products'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(OffProductDto.fromJson)
        .toList();
    return OffSearchResponseDto(products: list);
  }
}

/// Produto mínimo lido do OFF para listagens/páginas de detalhe.
/// (DTO de transporte — sem comportamentos; apenas dados.)
///
/// Inclui:
/// - Identificador (barcode);
/// - Nome e marcas;
/// - Letra NutriScore (a–e), se disponível;
/// - URL de imagem pequena (para listas);
/// - Bloco `nutriments` tal como exposto pelo OFF (quando presente).
class OffProductDto {
  /// Barcode (código de barras) do produto (string).
  final String code;

  /// Nome do produto (pode vir localizado; usa-se `product_name` ou `product_name_en`).
  final String? name;

  /// Marcas associadas (string conforme OFF).
  final String? brands;

  /// Letra do NutriScore (`a`..`e`) quando disponível.
  final String? nutriScore;

  /// URL de imagem pequena (thumbnail) para listagens.
  final String? imageSmallUrl;

  /// Bloco de nutrimentos conforme o OFF (mapa bruto), se existir.
  final Map<String, dynamic>? nutriments;

  OffProductDto({
    required this.code,
    this.name,
    this.brands,
    this.nutriScore,
    this.imageSmallUrl,
    this.nutriments,
  });

  /// Constrói um [OffProductDto] a partir de `json` do OFF.
  ///
  /// Campos mapeados:
  /// - `code` → [code]
  /// - `product_name` (ou `product_name_en` como fallback) → [name]
  /// - `brands` → [brands]
  /// - `nutriscore_grade` (ou `nutrition_grades` como fallback) → [nutriScore]
  /// - `image_small_url` → [imageSmallUrl]
  /// - `nutriments` (se for `Map<String, dynamic>`) → [nutriments]
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

/// Resposta de **detalhe de produto** individual do OFF.
/// (DTO com metadados de cache condicional.)
///
/// Transporta:
/// - [product]: o produto (se existir no payload);
/// - [etag]: cabeçalho HTTP `ETag`, quando devolvido pelo servidor;
/// - [notModified]: *flag* para respostas **304 Not Modified** (sem alterações).
class OffProductResponseDto {
  /// Produto devolvido (ou `null` em 304 / não encontrado).
  final OffProductDto? product;

  /// Valor de `ETag` devolvido pelo servidor (para cache condicional).
  final String? etag;

  /// Indica se a resposta foi **304 Not Modified**.
  final bool notModified;

  OffProductResponseDto({this.product, this.etag, this.notModified = false});

  /// Constrói a partir do JSON HTTP do OFF, aceitando `etag` e *flag* 304.
  ///
  /// - Quando [json] é `null`, [product] fica `null` (caso típico de 304);
  /// - Caso contrário, lê `json['product']` e mapeia via [OffProductDto.fromJson].
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
