import 'dart:async';

/// Fila de sincronização simples com **coalescing por chave** e limite de concorrência.
///
/// Objetivo
/// --------
/// Orquestrar tarefas assíncronas “de aquecimento” (ex.: pré-carregar cache de
/// pesquisas ou barcodes) garantindo:
/// 1) **Coalescing por chave**: se uma tarefa com a mesma `key` já estiver
///    em curso, **reaproveita a mesma `Future`** em vez de lançar trabalho
///    duplicado.
/// 2) **Limite de concorrência**: no máximo [concurrency] tarefas correm em
///    simultâneo (as restantes aguardam turno).
///
/// Casos de uso
/// ------------
/// - Prefetch de resultados para queries iguais submetidas em momentos
///   próximos (evita “tempestade” de pedidos iguais);
/// - Atualizações em lote onde cada item é identificado por uma `key` única;
/// - Aquecimento periódico de itens de cache com controlo de paralelismo.
///
/// Semântica
/// ---------
/// - `schedule(key, job)` devolve sempre a **mesma Future** enquanto existir
///   uma tarefa inflight com essa `key`;
/// - Quando a tarefa termina (com sucesso ou erro), a entrada inflight é
///   removida e novas chamadas com a mesma `key` vão agendar novamente;
/// - A concorrência é controlada por um contador simples com *spins* curtos
///   (espera em `Future.delayed`), suficiente para jobs I/O-bound.
///
/// Notas de implementação
/// ----------------------
/// - `Completer<void>` encapsula a conclusão do *job* real;
/// - `_inflight` guarda as Futures por `key` para coalescing;
/// - `_acquire`/`_release` controlam o número de jobs simultâneos;
/// - Erros são propagados via `completeError`, preservando *stack trace*.
class SyncQueue {
  /// Número máximo de tarefas simultâneas.
  final int concurrency;

  int _running = 0;

  /// Tarefas em voo, indexadas pela **chave lógica**.
  final Map<String, Future<void>> _inflight = {};

  /// Cria uma fila com limite de [concurrency] (por omissão 2).
  SyncQueue({this.concurrency = 2});

  /// Agenda um [job] identificado por [key], com **coalescing** e controlo de concorrência.
  ///
  /// Comportamento:
  /// - Se já existir um *job* com a mesma [key] a correr, **devolve essa mesma Future**
  ///   (coalescing) e não agenda outro;
  /// - Caso contrário, cria um `Completer`, guarda-o em `_inflight[key]` e executa
  ///   o *job* quando houver *slot* livre;
  /// - Ao terminar, **liberta** a concorrência, **remove** a [key] do mapa e
  ///   **completa** a Future (ou `completeError` em caso de falha).
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

  /// Aguarda até existir capacidade livre (menos que [concurrency] em execução).
  Future<void> _acquire() async {
    while (_running >= concurrency) {
      await Future.delayed(const Duration(milliseconds: 60));
    }
    _running++;
  }

  /// Liberta um *slot* de execução (com *floor* a zero por segurança).
  void _release() {
    _running = (_running - 1).clamp(0, concurrency);
  }
}
