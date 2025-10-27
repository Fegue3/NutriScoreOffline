import 'dart:async';

/// Token bucket simples por canal (search / product), + limite de concorrência global.
class TokenBucket {
  final int capacity;
  final Duration refillEvery;
  int _tokens;
  Timer? _refill;

  TokenBucket({required this.capacity, required this.refillEvery})
      : _tokens = capacity;

  Future<void> take() async {
    while (_tokens <= 0) {
      // aguarda próximo refill tick
      if (_refill == null) {
        _refill = Timer(refillEvery, () {
          _tokens = capacity;
          _refill = null;
        });
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
    _tokens--;
  }
}

class NetThrottle {
  final TokenBucket searchBucket;
  final TokenBucket productBucket;

  final int maxConcurrent;
  int _running = 0;

  NetThrottle({
    required this.searchBucket,
    required this.productBucket,
    this.maxConcurrent = 2,
  });

  /// Gate de concorrência global
  Future<void> _acquire() async {
    while (_running >= maxConcurrent) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _running++;
  }

  void _release() => _running = (_running - 1).clamp(0, maxConcurrent);

  /// Executa respeitando bucket + concorrência.
  Future<T> runSearch<T>(Future<T> Function() fn) async {
    await searchBucket.take();
    await _acquire();
    try {
      return await _withBackoff(fn);
    } finally {
      _release();
    }
  }

  Future<T> runProduct<T>(Future<T> Function() fn) async {
    await productBucket.take();
    await _acquire();
    try {
      return await _withBackoff(fn);
    } finally {
      _release();
    }
  }

  /// Exponential backoff básico com jitter pequeno para 429/503.
  Future<T> _withBackoff<T>(Future<T> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        // Sobe após 4 tentativas
        if (attempt >= 4) rethrow;
        final baseMs = 300 * (1 << attempt);
        final jitterMs = (baseMs * 0.25).toInt();
        final wait = Duration(milliseconds: baseMs + (jitterMs ~/ 2));
        await Future.delayed(wait);
        attempt++;
      }
    }
  }
}
