import 'dto.dart';
import 'off_client.dart';
import 'net_throttle.dart';

/// DataSource **remoto puro** para produtos (Open Food Facts).
///
/// Responsabilidades:
/// - Encapsula chamadas HTTP via [OffClient];
/// - Aplica *rate limiting* / concorrência via [NetThrottle];
/// - Expõe métodos de **pesquisa** e **lookup por barcode**;
/// - **Não** conhece SQLite nem cache local — isso é tratado na camada de repositório.
///
/// Vantagens:
/// - API clara e previsível para a camada superior (repo híbrido/offline-first);
/// - Suporte a `ETag`/`304 Not Modified` para reduzir tráfego.
class ProductsRemoteDataSource {
  /// Cliente HTTP para o OFF.
  final OffClient client;

  /// Controlador de *rate limit* + concorrência.
  final NetThrottle throttle;

  /// Constrói o data source remoto.
  ProductsRemoteDataSource({required this.client, required this.throttle});

  /// Pesquisa textual **leve** no OFF.
  ///
  /// - Respeita *rate limiting* através de [throttle.runSearch].
  /// - Limita resultados a [limit] (por omissão 30).
  /// - Mapeia o JSON para [OffSearchResponseDto] e devolve a lista de [OffProductDto].
  Future<List<OffProductDto>> search(String q, {int limit = 30}) async {
    return throttle.runSearch(() async {
      final json = await client.search(q, pageSize: limit, page: 1);
      final dto = OffSearchResponseDto.fromJson(json);
      return dto.products;
    });
  }

  /// Obtém um **produto por barcode** com suporte a `ETag` / **304 Not Modified**.
  ///
  /// Parâmetros:
  /// - [barcode] código de barras do produto;
  /// - [etag] (opcional) valor de `ETag` previamente guardado para cache condicional.
  ///
  /// Retorna uma *tuple*:
  /// - `OffProductDto?` → produto (ou `null` se 304);
  /// - `String? etag`   → ETag atual (se presente nos *headers*);
  /// - `bool notModified` → `true` quando a resposta foi 304 (sem alterações).
  Future<(OffProductDto?, String? etag, bool notModified)> getByBarcode(
    String barcode, {
    String? etag,
  }) async {
    return throttle.runProduct(() async {
      final res = await client.productByBarcode(barcode, etag: etag);
      if (res.notModified) return (null, res.etag, true);
      final dto = OffProductResponseDto.fromHttpJson(res.json, etag: res.etag);
      return (dto.product, dto.etag, false);
    });
  }
}
