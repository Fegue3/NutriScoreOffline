import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Cliente HTTP baixo nível para OFF. Não trata throttling aqui.
/// Expõe helpers que devolvem JSON + headers relevantes (ETag, Retry-After).
class OffClient {
  final http.Client _http;
  final String baseUrl;
  final String userAgent;

  OffClient(this._http, {this.baseUrl = kOffBaseUrl, this.userAgent = kUserAgent});

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

class _HttpResult {
  final int status;
  final String body;
  final Map<String, String> headers;
  _HttpResult({required this.status, required this.body, required this.headers});
}

class _JsonResult {
  final Map<String, dynamic>? json;
  final String? etag;
  final bool notModified;
  _JsonResult({required this.json, required this.etag, required this.notModified});
}

class _HttpException implements Exception {
  final int status;
  final String body;
  _HttpException(this.status, this.body);
  @override
  String toString() => 'HTTP $status: $body';
}

class _RateLimitedException implements Exception {
  final int? retryAfter; // em segundos, se enviado
  _RateLimitedException({this.retryAfter});
  @override
  String toString() => 'Rate limited. Retry-After: ${retryAfter ?? '?'}s';
}
