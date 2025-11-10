import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Cliente HTTP de baixo nível para o **Open Food Facts (OFF)**.
///
/// Responsabilidades:
/// - Executa `GET` com *headers* adequados (inclui `User-Agent`);
/// - Expõe *helpers* que devolvem **JSON + metadados** relevantes
///   (por exemplo: `ETag`, `Retry-After`);
/// - **Não** faz *throttling* nem controlo de concorrência — isso é tratado
///   por camadas superiores (ver `NetThrottle`).
///
/// Erros:
/// - Lança [_RateLimitedException] em **429/503** (inclui `Retry-After` se existir);
/// - Lança [_HttpException] para códigos não 200/304;
/// - Em **304 Not Modified**, devolve `json=null` e `notModified=true`.
class OffClient {
  /// Cliente HTTP subjacente (injeção para permitir *mocking* em testes).
  final http.Client _http;

  /// Base URL do OFF (por omissão `kOffBaseUrl`).
  final String baseUrl;

  /// `User-Agent` enviado em todas as chamadas (por omissão `kUserAgent`).
  final String userAgent;

  /// Construtor.
  OffClient(this._http, {this.baseUrl = kOffBaseUrl, this.userAgent = kUserAgent});

  /// Pedido GET genérico com *headers* padrão + opcionais.
  Future<_HttpResult> _get(Uri uri, {Map<String, String>? extraHeaders}) async {
    final headers = {
      'User-Agent': userAgent,
      'Accept': 'application/json',
      ...?extraHeaders,
    };
    final res = await _http.get(uri, headers: headers);
    return _HttpResult(
      status: res.statusCode,
      body: res.body,
      headers: res.headers,
    );
  }

  /// Obtém **detalhe de produto** por *barcode* via API v2.
  ///
  /// Suporta cache condicional via `If-None-Match` (passando [etag]).
  /// - Em **304** devolve [_JsonResult] com `json=null`, `notModified=true` e
  ///   o `etag` (se presente nos *headers*).
  /// - Em **429/503** lança [_RateLimitedException] (lê `Retry-After`).
  /// - Em códigos != **200/304** lança [_HttpException].
  Future<_JsonResult> productByBarcode(String barcode, {String? etag}) async {
    final uri = Uri.parse('$baseUrl/api/v2/product/$barcode.json');
    final r = await _get(uri, extraHeaders: {
      if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
    });

    if (r.status == 304) {
      return _JsonResult(json: null, etag: r.headers['etag'], notModified: true);
    }
    if (r.status == 429 || r.status == 503) {
      final retryAfter = int.tryParse(r.headers['retry-after'] ?? '');
      throw _RateLimitedException(retryAfter: retryAfter);
    }
    if (r.status != 200) {
      throw _HttpException(r.status, r.body);
    }
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return _JsonResult(json: json, etag: r.headers['etag'], notModified: false);
  }

  /// Executa uma **pesquisa** no OFF (`/cgi/search.pl`).
  ///
  /// Parâmetros:
  /// - [query] termos pesquisados;
  /// - [pageSize] tamanho da página (default `kSearchPageSize`);
  /// - [page] número da página (1-based).
  ///
  /// Erros:
  /// - **429/503** → [_RateLimitedException] (inclui `Retry-After` quando existe);
  /// - Código != **200** → [_HttpException].
  Future<Map<String, dynamic>> search(String query, {int pageSize = kSearchPageSize, int page = 1}) async {
    final uri = Uri.parse('$baseUrl/cgi/search.pl').replace(queryParameters: {
      'json': '1',
      'search_terms': query,
      'search_simple': '1',
      'page_size': '$pageSize',
      'page': '$page',
      'fields': kSearchFields,
    });

    final r = await _get(uri);
    if (r.status == 429 || r.status == 503) {
      final retryAfter = int.tryParse(r.headers['retry-after'] ?? '');
      throw _RateLimitedException(retryAfter: retryAfter);
    }
    if (r.status != 200) {
      throw _HttpException(r.status, r.body);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}

/// Resultado HTTP “cru” (interno): estado, corpo e *headers*.
class _HttpResult {
  final int status;
  final String body;
  final Map<String, String> headers;
  _HttpResult({required this.status, required this.body, required this.headers});
}

/// Resultado JSON com metadados para cache condicional (interno).
class _JsonResult {
  /// Corpo JSON decodificado (ou `null` em 304).
  final Map<String, dynamic>? json;

  /// ETag devolvido pelo servidor (se presente).
  final String? etag;

  /// Indica **304 Not Modified**.
  final bool notModified;

  _JsonResult({required this.json, required this.etag, required this.notModified});
}

/// Exceção genérica de HTTP não-OK (interno).
class _HttpException implements Exception {
  final int status;
  final String body;
  _HttpException(this.status, this.body);
  @override
  String toString() => 'HTTP $status: $body';
}

/// Exceção de **rate limit** (429/503), contendo `Retry-After` (em segundos)
/// quando enviado pelo servidor (interno).
class _RateLimitedException implements Exception {
  final int? retryAfter; // em segundos, se enviado
  _RateLimitedException({this.retryAfter});
  @override
  String toString() => 'Rate limited. Retry-After: ${retryAfter ?? '?'}s';
}
