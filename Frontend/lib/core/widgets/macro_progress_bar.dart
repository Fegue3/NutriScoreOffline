import 'package:flutter/material.dart';

/// NutriScore — Barra de Progresso de Macronutrientes
///
/// Widget para mostrar o progresso de um nutriente (ex.: **Proteína**, **Carboidratos**, **Gordura**, **Calorias**)
/// com animação ao montar (on-mount). Exibe:
/// - **Etiqueta** (label) à esquerda;
/// - **Valor usado** e, opcionalmente, **alvo** + **unidade** à direita (ex.: `34g / 60g`);
/// - **Barra de progresso** com animação (curva e duração configuráveis);
/// - **Mensagem auxiliar** (helper) opcional por baixo.
///
/// Regras:
/// - Se [target] for `null` ou `<= 0`, **não** renderiza a barra, apenas o valor.
/// - Se `used > target`, o texto de valor fica com a cor de **erro** do tema.
///
/// ### Exemplo
/// ```dart
/// MacroProgressBar(
///   label: 'Proteína',
///   unit: 'g',
///   used: 42,
///   target: 100,
///   helper: 'Objetivo diário: 100g',
///   color: Theme.of(context).colorScheme.primary,
///   delay: const Duration(milliseconds: 150), // para efeito em cascata (stagger)
/// )
/// ```
///
/// ### Acessibilidade
/// - Apresenta **texto explícito** com valores e unidade (não depende apenas de cor).
/// - Animações usam `Curves.easeOutCubic` por omissão para transições suaves.
///
/// ### Performance
/// - Usa `TweenAnimationBuilder` para animar apenas a largura da barra.
/// - Reanima quando `used` ou `target` mudam significativamente.
class MacroProgressBar extends StatefulWidget {
  /// Texto do nutriente (ex.: `"Proteína"`).
  final String label;     // "Proteína"

  /// Unidade do valor (ex.: `"g"` | `"kcal"`).
  final String unit;      // "g" | "kcal"

  /// Valor consumido/atingido.
  final num used;         // valor consumido

  /// Alvo opcional. Se `null` ou `<= 0`, não mostra a barra.
  final num? target;      // null -> sem alvo/barra

  /// Texto auxiliar por baixo (opcional).
  final String? helper;   // texto extra abaixo (opcional)

  /// Espaçamento interno vertical do componente (por padrão, `EdgeInsets.symmetric(vertical: 10)`).
  final EdgeInsets padding;

  /// Se `true`, usa uma barra mais baixa (8px em vez de 10px).
  final bool dense;

  /// Cor principal da barra (fallback: `primary` ou `error` se excedido).
  final Color? color;           // cor da barra (ex.: primary/secondary/error)

  /// Cor de fundo da barra (fallback: `surfaceContainerHighest`).
  final Color? backgroundColor; // fundo da barra

  /// Duração da animação da barra.
  final Duration duration;      // duração da animação

  /// Curva da animação.
  final Curve curve;            // curva da animação

  /// Atraso inicial para permitir **stagger** quando existem múltiplas barras.
  final Duration? delay;        // atraso inicial (para stagger)

  /// Cria uma barra de progresso para macronutrientes/calorias.
  const MacroProgressBar({
    super.key,
    required this.label,
    required this.unit,
    required this.used,
    this.target,
    this.helper,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
    this.dense = false,
    this.color,
    this.backgroundColor,
    this.duration = const Duration(milliseconds: 750),
    this.curve = Curves.easeOutCubic,
    this.delay,
  });

  @override
  State<MacroProgressBar> createState() => _MacroProgressBarState();
}

class _MacroProgressBarState extends State<MacroProgressBar>
    with SingleTickerProviderStateMixin {
  /// *Trigger* interno (0..1) para coordenar o atraso ([delay]) com a animação do tween.
  double _t = 0; // 0..1 para animar widthFactor

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MacroProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reanima se o alvo/valor mudarem significativamente
    if (oldWidget.used != widget.used || oldWidget.target != widget.target) {
      _t = 0;
      _start();
    }
  }

  /// Inicia a animação, respeitando um eventual [delay] configurado.
  Future<void> _start() async {
    if (widget.delay != null) {
      await Future.delayed(widget.delay!);
    }
    if (!mounted) return;
    setState(() => _t = 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final hasTarget = widget.target != null && widget.target! > 0;
    final pct = hasTarget ? (widget.used / widget.target!).clamp(0, 2).toDouble() : null;
    final over = hasTarget && widget.used > widget.target!;
    final barColor = widget.color ?? (over ? cs.error : cs.primary);
    final bg = widget.backgroundColor ?? cs.surfaceContainerHighest;
    final onBg = cs.onSurface;

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título + valores
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: onBg,
                  ),
                ),
              ),
              Text(
                hasTarget
                    ? '${_fmt(widget.used)}${widget.unit} / ${_fmt(widget.target!)}${widget.unit}'
                    : '${_fmt(widget.used)}${widget.unit}',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: over ? cs.error : onBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Barra com animação do widthFactor
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: widget.dense ? 8 : 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // fundo
                  ColoredBox(color: bg),
                  if (pct != null)
                    TweenAnimationBuilder<double>(
                      key: ValueKey('${widget.label}-${widget.used}-${widget.target}'),
                      tween: Tween<double>(begin: 0, end: pct.clamp(0, 1)),
                      duration: widget.duration,
                      curve: widget.curve,
                      builder: (ctx, value, child) {
                        // aplica também o "gatilho" manual _t para suportar delay
                        final width = value * _t;
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: width,
                          child: child,
                        );
                      },
                      child: ColoredBox(color: barColor),
                    ),
                ],
              ),
            ),
          ),
          if (widget.helper != null && widget.helper!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.helper!,
              style: tt.bodySmall?.copyWith(
                color: onBg.withValues(alpha: .7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Formata números em **PT-PT**:
  /// - 0 casas decimais para inteiros;
  /// - 1 casa decimal para fracionários;
  /// - **vírgula** como separador decimal.
  String _fmt(num n) {
    final s = n.toStringAsFixed(n % 1 == 0 ? 0 : 1);
    return s.replaceAll('.', ',');
  }
}
