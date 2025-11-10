import 'package:flutter/material.dart';
import 'macro_progress_bar.dart';

/// NutriScore — Cartão de Secção de Macronutrientes
///
/// Mostra um **resumo diário** com:
/// - Cabeçalho de **calorias usadas/objetivo**;
/// - Barras de progresso dos **macros principais** (Proteína, Hidratos, Gordura)
///   com metas;
/// - Barras de nutrientes **adicionais** (Açúcar, Fibra, Sal) com **limites/objetivos
///   recomendados** quando fornecidos.
///
/// Regras:
/// - Se uma meta/limite for `null` ou `<= 0`, o cartão calcula um alvo **não nulo**
///   a partir do valor usado (para manter a barra visível), via [_nonZeroTarget].
///
/// Exemplo de utilização:
/// ```dart
/// MacroSectionCard(
///   kcalUsed: 1450, kcalTarget: 2000,
///   proteinG: 72,  proteinTargetG: 120,
///   carbG: 180,    carbTargetG: 250,
///   fatG: 45,      fatTargetG: 70,
///   sugarsG: 38,   fiberG: 18,   saltG: 1.9,
///   sugarsTargetG: 50, fiberTargetG: 25, saltTargetG: 5,
/// )
/// ```
class MacroSectionCard extends StatelessWidget {
  /// Cria um cartão com barras de progresso de macros e nutrientes.
  const MacroSectionCard({
    super.key,
    required this.kcalUsed,
    required this.kcalTarget,
    required this.proteinG,
    required this.proteinTargetG,
    required this.carbG,
    required this.carbTargetG,
    required this.fatG,
    required this.fatTargetG,
    required this.sugarsG,
    required this.fiberG,
    required this.saltG,

    // Metas / limites recomendados (podem vir a null)
    this.sugarsTargetG,
    this.fiberTargetG,
    this.saltTargetG,
  });

  // ==================== Calorias ====================

  /// Calorias consumidas no dia.
  final int kcalUsed;

  /// Meta diária de calorias.
  final int kcalTarget;

  // ==================== Macros principais ====================

  /// Proteína consumida (g).
  final double proteinG;

  /// Meta de proteína (g).
  final double proteinTargetG;

  /// Hidratos de carbono consumidos (g).
  final double carbG;

  /// Meta de hidratos (g).
  final double carbTargetG;

  /// Gordura consumida (g).
  final double fatG;

  /// Meta de gordura (g).
  final double fatTargetG;

  // ==================== Nutrientes extra ====================

  /// Açúcares totais consumidos (g).
  final double sugarsG;

  /// Fibra consumida (g).
  final double fiberG;

  /// Sal consumido (g).
  final double saltG;

  // Recomendações (podem ser null)

  /// Limite/objetivo recomendado para açúcares (g).
  final double? sugarsTargetG;

  /// Objetivo recomendado para fibra (g).
  final double? fiberTargetG;

  /// Limite/objetivo recomendado para sal (g).
  final double? saltTargetG;

  /// Garante que o **alvo da barra não é zero**, para manter a visualização estável.
  ///
  /// Lógica:
  /// - Se [target] > 0 → devolve [target];
  /// - Caso contrário, se [used] > 0 → devolve [used] (barra cheia);
  /// - Se ambos forem 0 → devolve 1 (barra mínima).
  ///
  /// Isto evita a situação de `0/0` e assegura feedback visual.
  num _nonZeroTarget(num? target, double used) {
    final t = (target ?? 0).toDouble();
    if (t > 0) return t;
    return used > 0 ? used : 1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Cores neutras para nutrientes adicionais.
    final neutralFill = cs.outlineVariant;
    final neutralTrack = cs.surfaceContainerHighest;

    // Alvos seguros (evitam 0/0)
    final sugarsT = _nonZeroTarget(sugarsTargetG, sugarsG);
    final fiberT  = _nonZeroTarget(fiberTargetG,  fiberG);
    final saltT   = _nonZeroTarget(saltTargetG,   saltG);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, 4),
            color: Color.fromRGBO(0, 0, 0, 0.05),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // -------------------- Cabeçalho --------------------
          Row(
            children: [
              Text('Calorias', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.surfaceContainerHighest),
                ),
                child: Text(
                  '$kcalUsed / $kcalTarget kcal',
                  style: tt.labelLarge?.copyWith(color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: cs.surfaceContainerHighest, height: 1),

          // -------------------- Macros principais --------------------
          MacroProgressBar(
            label: 'Proteína',
            unit: ' g',
            used: proteinG,
            target: _nonZeroTarget(proteinTargetG, proteinG),
            color: cs.primary, // Fresh Green
            backgroundColor: cs.surfaceContainerHighest,
            duration: const Duration(milliseconds: 1800),
            delay: const Duration(milliseconds: 80),
          ),
          MacroProgressBar(
            label: 'Hidratos',
            unit: ' g',
            used: carbG,
            target: _nonZeroTarget(carbTargetG, carbG),
            color: cs.secondary, // Warm Tangerine
            backgroundColor: cs.surfaceContainerHighest,
            duration: const Duration(milliseconds: 1800),
            delay: const Duration(milliseconds: 160),
          ),
          MacroProgressBar(
            label: 'Gordura',
            unit: ' g',
            used: fatG,
            target: _nonZeroTarget(fatTargetG, fatG),
            color: cs.error, // Ripe Red
            backgroundColor: cs.surfaceContainerHighest,
            duration: const Duration(milliseconds: 1800),
            delay: const Duration(milliseconds: 240),
          ),

          const SizedBox(height: 8),
          Divider(color: cs.surfaceContainerHighest, height: 1),

          // -------------------- Nutrientes extra --------------------
          MacroProgressBar(
            label: 'Açúcar',
            unit: ' g',
            used: sugarsG,
            target: sugarsT,
            color: neutralFill,
            backgroundColor: neutralTrack,
            duration: const Duration(milliseconds: 1600),
            delay: const Duration(milliseconds: 320),
          ),
          MacroProgressBar(
            label: 'Fibra',
            unit: ' g',
            used: fiberG,
            target: fiberT,
            color: neutralFill,
            backgroundColor: neutralTrack,
            duration: const Duration(milliseconds: 1600),
            delay: const Duration(milliseconds: 400),
          ),
          MacroProgressBar(
            label: 'Sal',
            unit: ' g',
            used: saltG,
            target: saltT,
            color: neutralFill,
            backgroundColor: neutralTrack,
            duration: const Duration(milliseconds: 2200),
            delay: const Duration(milliseconds: 480),
          ),
        ],
      ),
    );
  }
}
