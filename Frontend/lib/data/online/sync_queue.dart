import 'dart:async';

/// Fila simples com coalescing por chave.
/// Usa para "aquecer" a cache com pesquisas ou barcodes.
class SyncQueue {
  final int concurrency;
  int _running = 0;
  final Map<String, Future<void>> _inflight = {};

  SyncQueue({this.concurrency = 2});

  Future<void> schedule(String key, Future<void> Function() job) {
    if (_inflight.containsKey(key)) return _inflight[key]!;
    final c = Completer<void>();
    _inflight[key] = c.future;

    () async {
      await _acquire();
      try {
        await job();
        c.complete();
      } catch (e, st) {
        c.completeError(e, st);
      } finally {
        _release();
        _inflight.remove(key);
      }
    }();

    return c.future;
  }

  Future<void> _acquire() async {
    while (_running >= concurrency) {
      await Future.delayed(const Duration(milliseconds: 60));
    }
    _running++;
  }

  void _release() {
    _running = (_running - 1).clamp(0, concurrency);
  }
}
