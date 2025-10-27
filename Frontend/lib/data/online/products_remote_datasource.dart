import 'dto.dart';
import 'off_client.dart';
import 'net_throttle.dart';

/// DataSource remoto puro (sem SQLite aqui).
class ProductsRemoteDataSource {
  final OffClient client;
  final NetThrottle throttle;

  ProductsRemoteDataSource({required this.client, required this.throttle});

  /// Pesquisa textual limitada e leve.
  Future<List<OffProductDto>> search(String q, {int limit = 30}) async {
    return throttle.runSearch(() async {
      final json = await client.search(q, pageSize: limit, page: 1);
      final dto = OffSearchResponseDto.fromJson(json);
      return dto.products;
    });
  }

  /// Produto por barcode, com suporte a ETag/304.
  Future<(OffProductDto?, String? etag, bool notModified)> getByBarcode(String barcode, {String? etag}) async {
    return throttle.runProduct(() async {
      final res = await client.productByBarcode(barcode, etag: etag);
      if (res.notModified) return (null, res.etag, true);
      final dto = OffProductResponseDto.fromHttpJson(res.json, etag: res.etag);
      return (dto.product, dto.etag, false);
    });
  }
}
