import 'dart:async';

/// Controlador de *rate limiting* e concorrência para chamadas à API do OFF.
///
/// Estrutura:
/// - **TokenBucket**: limita o número de pedidos por janela temporal (ex.: 10/min para *search*);
/// - **NetThrottle**: aplica os *buckets* por tipo de operação (search vs product) e
///   um **limite global de concorrência**; inclui *exponential backoff* básico
///   (com *jitter*) para lidar com erros transitórios (ex.: 429/503).
///
/// Objetivo:
/// - Ser um “bom cidadão” perante o OFF, respeitando *rate limits* e evitando *spikes*.
/// - Evitar *flooding* da rede e melhorar estabilidade percebida.
class TokenBucket {
  /// Capacidade máxima de *tokens* por janela (ex.: 10).
  final int capacity;

  /// Duração da janela de *refill* (ex.: 1 minuto).
  final Duration refillEvery;

  int _tokens;
  Timer? _refill;

  /// Cria um *token bucket* simples com reabastecimento integral a cada janela.
  TokenBucket({required this.capacity, required this.refillEvery})
      : _tokens = capacity;

  /// Tenta consumir um *token*. Aguarda até haver *tokens* disponíveis.
  ///
  /// Implementação simples:
  /// - Se não há tokens, agenda um *refill* para o fim da janela;
  /// - Faz *polling* leve (80 ms) até repor tokens e prosseguir.
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

/// Orquestrador de *rate limiting* por canal + concorrência global.
///
/// - Usa dois buckets: [searchBucket] e [productBucket];
/// - Garante que no máximo [maxConcurrent] pedidos correm em simultâneo;
/// - Envolve a execução com *exponential backoff* simples para falhas transitórias.
class NetThrottle {
  /// Bucket para **pesquisas** (ex.: limite 10/min).
  final TokenBucket searchBucket;

  /// Bucket para **produto individual** (ex.: limite 100/min).
  final TokenBucket productBucket;

  /// Limite global de **concorrência** (pedidos simultâneos).
  final int maxConcurrent;

  int _running = 0;

  NetThrottle({
    required this.searchBucket,
    required this.productBucket,
    this.maxConcurrent = 2,
  });

  /// Gate de concorrência global (bloqueia até haver *slot* livre).
  Future<void> _acquire() async {
    while (_running >= maxConcurrent) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _running++;
  }

  /// Liberta um *slot* de concorrência.
  void _release() => _running = (_running - 1).clamp(0, maxConcurrent);

  /// Executa uma **pesquisa**, respeitando o *bucket* de search e a concorrência.
  Future<T> runSearch<T>(Future<T> Function() fn) async {
    await searchBucket.take();
    await _acquire();
    try {
      return await _withBackoff(fn);
    } finally {
      _release();
    }
  }

  /// Executa um pedido de **produto**, respeitando o *bucket* de produto e a concorrência.
  Future<T> runProduct<T>(Future<T> Function() fn) async {
    await productBucket.take();
    await _acquire();
    try {
      return await _withBackoff(fn);
    } finally {
      _release();
    }
  }

  /// *Exponential backoff* básico com pequeno *jitter* para erros transitórios.
  ///
  /// Estratégia:
  /// - Tenta até 5 vezes no total (0..4 *retries*);
  /// - Atraso base: `300ms * 2^attempt`, com *jitter* ~25%;
  /// - Em caso de exceção após o limite, relança (propaga ao chamador).
  ///
  /// **Sugestão**: Integrar códigos HTTP específicos (429/503) quando a camada HTTP
  /// expuser essa informação — aqui assume-se qualquer exceção como transitória.
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
