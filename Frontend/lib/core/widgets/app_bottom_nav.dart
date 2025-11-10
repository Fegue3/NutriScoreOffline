import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

/// NutriScore — Barra de Navegação Inferior (AppBottomNav)
///
/// Componente de navegação com 3 itens (Dashboard, Diário, Definições) que:
/// - Usa um **indicador "pill"** com *slide* + *fade-out* para realçar o tab ativo;
/// - Mantém **ícones a 32px** e **labels a 12px** (fixos, sem zoom);
/// - Permite **configurar fundo** semi-transparente e **divisor** superior.
///
/// ### Diretrizes de design (NutriScore)
/// - Cores: usa `AppColors.freshGreen` para o estado **ativo**; `AppColors.coolGray`
///   para **inativo**; fundo por omissão `Color(0xEEFFFFFF)` (semelhante ao DS);
/// - Tipografia: label com `AppText.bodyFamily`, **12px** (Caption/Labels);
/// - Acessibilidade: ícone + label (não depende só da cor).
///
/// ### Exemplo de utilização
/// ```dart
/// AppBottomNav(
///   currentIndex: 0,
///   onChanged: (i) {
///     // navegar para /dashboard, /diary ou /settings
///   },
/// )
/// ```
class AppBottomNav extends StatefulWidget {
  /// Índice do tab atualmente selecionado.
  ///
  /// - `0` → Dashboard
  /// - `1` → Diário
  /// - `2` → Definições
  final int currentIndex;

  /// Callback disparado quando o utilizador toca noutro tab.
  ///
  /// Recebe o índice do item escolhido (`0..2`).
  final ValueChanged<int> onChanged;

  // Destaque/estilo

  /// Cor de fundo da barra (por omissão `0xEEFFFFFF`, branco com opacidade).
  ///
  /// Sugestão: manter contraste adequado com o conteúdo (WCAG AA).
  final Color backgroundColor; // destaca vs app bg (#FAFAF7)

  /// Mostra uma linha divisória (1px) no topo da barra.
  final bool showTopDivider;   // linha 1px no topo

  /// Se `true`, mantém a "pill" visível mesmo quando parada (sem animação recente).
  final bool showIndicatorWhenIdle; // se true, mantém a pill visível parado

  /// Cria a barra de navegação inferior do NutriScore.
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.backgroundColor = const Color(0xEEFFFFFF),
    this.showTopDivider = true,
    this.showIndicatorWhenIdle = false,
  });

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  // Layout / animações

  /// Altura total da barra (um pouco maior para conforto táctil).
  static const double _barHeight = 88.0;   // barra um pouco maior

  /// Duração (ms) do slide do indicador.
  static const int _animMs = 280;          // velocidade do slide

  /// Altura da "pill" (indicador visual).
  static const double _pillH = 60.0;       // altura do "pill" (sombra)

  /// Padding horizontal interno na célula ao calcular a largura da "pill".
  static const double _pillHPad = 21.0;    // padding lateral dentro da célula

  /// Largura mínima/máxima da "pill" para estabilidade visual.
  static const double _pillMinW = 86.0;    // limites para estabilidade
  static const double _pillMaxW = 164.0;

  /// Especificação fixa dos 3 itens da *Bottom Nav*.
  ///
  /// - `Painel` (Dashboard)
  /// - `Diário`
  /// - `Mais` (Definições)
  static const _items = <_NavSpec>[
    _NavSpec('Painel', Icons.dashboard_outlined, Icons.dashboard_rounded),
    _NavSpec('Diário', Icons.book_outlined, Icons.book_rounded),
    _NavSpec('Mais', Icons.settings_outlined, Icons.settings_rounded),
  ];

  /// Opacidade atual do indicador "pill" (0..1).
  double _indicatorOpacity = 0.0;

  /// Temporizador para fazer *fade-out* depois da animação de slide terminar.
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _indicatorOpacity = widget.showIndicatorWhenIdle ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(covariant AppBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      // mostra a sombra enquanto desliza, depois desvanece (se configurado)
      _fadeTimer?.cancel();
      setState(() => _indicatorOpacity = 1.0);
      if (!widget.showIndicatorWhenIdle) {
        _fadeTimer = Timer(Duration(milliseconds: _animMs + 120), () {
          if (mounted) setState(() => _indicatorOpacity = 0.0);
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, c) {
            final cellW = c.maxWidth / _items.length;

            // dimensões da "pill" dinâmica
            final pillW = (cellW - _pillHPad * 2)
                .clamp(_pillMinW, _pillMaxW)
                .toDouble();
            final pillTop = (_barHeight - _pillH) / 2;
            final pillLeft =
                cellW * widget.currentIndex + (cellW - pillW) / 2;

            return Stack(
              children: [
                // fundo destacado
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.backgroundColor),
                  ),
                ),
                if (widget.showTopDivider)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: 1,
                      color: Colors.black.withValues(alpha: 0.07),
                    ),
                  ),

                // pill a deslizar + fade
                AnimatedPositioned(
                  duration: const Duration(milliseconds: _animMs),
                  curve: Curves.easeOutCubic,
                  top: pillTop,
                  left: pillLeft,
                  width: pillW,
                  height: _pillH,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: _indicatorOpacity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.freshGreen.withAlpha(31), // ~12%
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),

                // items
                Row(
                  children: List.generate(_items.length, (i) {
                    final spec = _items[i];
                    final selected = widget.currentIndex == i;
                    return Expanded(
                      child: _NavButton(
                        label: spec.label,
                        icon: spec.icon,
                        selectedIcon: spec.selectedIcon,
                        selected: selected,
                        onTap: () => widget.onChanged(i),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Especificação interna de um item de navegação (label + ícones).
class _NavSpec {
  /// Texto apresentado por baixo do ícone.
  final String label;

  /// Ícone a usar quando o item **não** está selecionado.
  final IconData icon;

  /// Ícone a usar quando o item está **selecionado**.
  final IconData selectedIcon;

  /// Cria uma especificação de item de navegação.
  const _NavSpec(this.label, this.icon, this.selectedIcon);
}

/// Botão individual de item de *Bottom Nav* (ícone + label).
///
/// Responsável apenas pela apresentação e *tap*; o estado de seleção é
/// passado via [selected].
class _NavButton extends StatelessWidget {
  /// Label exibido sob o ícone.
  final String label;

  /// Ícone normal (inativo).
  final IconData icon;

  /// Ícone para o estado selecionado (ativo).
  final IconData selectedIcon;

  /// Indica se este item está selecionado.
  final bool selected;

  /// Callback invocado ao tocar no item.
  final VoidCallback onTap;

  /// Cria um item de navegação com ícone e texto.
  const _NavButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.freshGreen : AppColors.coolGray;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 32, // FIXO
                color: color,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 12, // FIXO
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
