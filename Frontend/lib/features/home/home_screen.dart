// lib/features/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/theme.dart' show AppColors;
import '../../core/widgets/weight_trend_chart.dart'; // WeightTrendCard + WeightPoint

/// NutriScore — Ecrã Inicial / Dashboard
///
/// Este ecrã é o **ponto de entrada principal** da experiência NutriScore
/// depois de o utilizador concluir o onboarding e autenticação.
///
/// Aqui o utilizador consegue, de forma rápida:
/// - ver o progresso **calórico diário** (objetivo vs. consumido vs. restante);
/// - acompanhar a **evolução do peso** dos últimos dias num mini-gráfico;
/// - ver o estado dos **macronutrientes** (proteína, hidratos, gordura);
/// - ver um resumo de calorias por **refeição** (pequeno-almoço, almoço,
///   lanche, jantar).
///
/// O ecrã:
/// - lê dados dos vários repositórios (`userRepo`, `goalsRepo`, `statsRepo`,
///   `weightRepo`, `mealsRepo`) através de `di`;
/// - recalcula/resgata estatísticas sempre que:
///   - o ecrã é aberto;
///   - o utilizador puxa para atualizar (`RefreshIndicator`);
///   - a app volta do background (`AppLifecycleState.resumed`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Estado do `HomeScreen`.
///
/// Implementa:
/// - `WidgetsBindingObserver` para reagir a mudanças de ciclo de vida da app
///   (por ex. voltar do background);
/// - carregamento assíncrono de dados de utilizador, objetivos, macros,
///   peso e refeições;
/// - construção do UI reativo com base no estado `_loading` e nos campos
///   calculados (_goalKcal, _consumedKcal, etc.).
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // Campos de utilizador / metas
  // ---------------------------------------------------------------------------

  /// Nome do utilizador atual (para saudação).
  ///
  /// Pode ser `null` ou string vazia, caso ainda não tenha sido definido.
  String? _username;

  /// Objetivo diário de calorias (kcal) definido nos objetivos do utilizador.
  int _goalKcal = 0;

  /// Total de calorias consumidas hoje (kcal).
  int _consumedKcal = 0;

  // ---------------------------------------------------------------------------
  // Distribuição de calorias por refeição
  // ---------------------------------------------------------------------------

  /// Calorias consumidas no pequeno-almoço (kcal).
  double _kBreakfast = 0;

  /// Calorias consumidas no almoço (kcal).
  double _kLunch = 0;

  /// Calorias consumidas no lanche (kcal).
  double _kSnack = 0;

  /// Calorias consumidas no jantar (kcal).
  double _kDinner = 0;

  // ---------------------------------------------------------------------------
  // Macros atuais e metas de macros (em gramas)
  // ---------------------------------------------------------------------------

  /// Proteína consumida hoje (g).
  double _proteinG = 0;

  /// Hidratos de carbono consumidos hoje (g).
  double _carbG = 0;

  /// Gordura consumida hoje (g).
  double _fatG = 0;

  /// Objetivo diário de proteína (g), calculado a partir de `_goalKcal`
  /// e da percentagem de proteína.
  double _targetProteinG = 0;

  /// Objetivo diário de hidratos de carbono (g), calculado a partir de
  /// `_goalKcal` e da percentagem de hidratos.
  double _targetCarbG = 0;

  /// Objetivo diário de gordura (g), calculado a partir de `_goalKcal`
  /// e da percentagem de gordura.
  double _targetFatG = 0;

  // ---------------------------------------------------------------------------
  // Estado de carregamento e dados de peso
  // ---------------------------------------------------------------------------

  /// Indica se o dashboard está a carregar dados (mostra spinner).
  bool _loading = true;

  /// Pontos de peso (últimos ~30 dias) para alimentar o mini-gráfico.
  ///
  /// Cada [WeightPoint] contém:
  /// - data (`date`);
  /// - peso em kg (`weightKg`).
  List<WeightPoint> _weightPoints = const [];

  // ---------------------------------------------------------------------------
  // Ciclo de vida do State
  // ---------------------------------------------------------------------------

  /// Regista o `WidgetsBindingObserver` e inicia o primeiro carregamento
  /// de dados quando o ecrã é criado.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  /// Remove o `WidgetsBindingObserver` ao destruir o ecrã.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Reage a alterações no estado da aplicação (foreground/background, etc.).
  ///
  /// Caso a app seja retomada (`AppLifecycleState.resumed`), volta a chamar
  /// `_load()` para refrescar dados que possam ter mudado entretanto,
  /// como calorias registadas, peso, etc.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  // ---------------------------------------------------------------------------
  // Carregamento de dados do dashboard
  // ---------------------------------------------------------------------------

  /// Carrega e agrupa todos os dados necessários para o dashboard.
  ///
  /// Este método é o “coração” da lógica do ecrã. Ele:
  /// 1. Marca `_loading = true` para mostrar o indicador de carregamento;
  /// 2. Obtém o utilizador atual a partir de `di.userRepo.currentUser()`:
  ///    - se não existir utilizador (ex.: sessão expirada), pára por aqui;
  /// 3. Carrega objetivos de utilizador (`goalsRepo.getByUser`);
  /// 4. Determina as calorias alvo (`dailyCalories`);
  /// 5. Carrega estatísticas do dia:
  ///    - tenta ler de cache via `statsRepo.getCached`;
  ///    - caso não exista ou não seja suficiente, chama `statsRepo.computeDaily`;
  /// 6. Preenche campos de calorias e macros (`_consumedKcal`, `_proteinG`,
  ///    `_carbG`, `_fatG`);
  /// 7. Carrega os registos de peso dos últimos 30 dias (`weightRepo.getRange`);
  /// 8. Calcula objetivos de macros em gramas com base nas percentagens
  ///    configuradas (carb/protein/fat) e em `_goalKcal`;
  /// 9. Carrega as refeições do dia (`mealsRepo.getMealsForDay`) e agrega
  ///    calorias por tipo de refeição (`BREAKFAST`, `LUNCH`, etc.);
  /// 10. No final, garante que `_loading` volta a false se o widget ainda
  ///     estiver montado.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) Utilizador atual
      final u = await di.userRepo.currentUser();
      if (u == null) {
        // Se não houver utilizador, não conseguimos mostrar dados.
        setState(() => _loading = false);
        return;
      }

      // Nome para saudação (pode vir vazio ou null).
      _username = u.name ?? '';

      // 2) Objetivos do utilizador (metas diárias)
      final goals = await di.goalsRepo.getByUser(u.id);
      _goalKcal = goals?.dailyCalories ?? 0;

      // 3) Estatísticas de hoje (kcal + macros)
      final now = DateTime.now().toUtc();

      // Tenta obter estatísticas em cache, senão calcula de raiz.
      final cached = await di.statsRepo.getCached(u.id, now);
      final stats = cached ?? await di.statsRepo.computeDaily(u.id, now);

      _consumedKcal = stats.kcal;
      _proteinG = stats.protein;
      _carbG = stats.carb;
      _fatG = stats.fat;

      // 4) Peso: últimos 30 dias para o mini-gráfico do Home
      try {
        // Consideramos o intervalo [hoje - 30 dias, hoje].
        final today = DateTime.utc(now.year, now.month, now.day);
        final from = today.subtract(const Duration(days: 30));
        final logs = await di.weightRepo.getRange(u.id, from, today);

        _weightPoints = logs
            .map(
              (e) => WeightPoint(
                date: DateTime.parse('${e.dayIso}T00:00:00Z'),
                weightKg: e.kg,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
      } catch (_) {
        // Em caso de erro ao carregar peso, apenas mostramos o estado vazio.
        _weightPoints = const [];
      }

      // 5) Metas de macros (em g), calculadas a partir de `goalKcal` e %
      if (_goalKcal > 0) {
        // Valores default caso `goals` não especifique percentagens.
        final carbPct = goals?.carbPercent ?? 50;
        final protPct = goals?.proteinPercent ?? 20;
        final fatPct = goals?.fatPercent ?? 30;

        // Conversão kcal → g:
        // - proteína / hidratos: 4 kcal/g;
        // - gordura: 9 kcal/g.
        _targetCarbG = (_goalKcal * carbPct / 100.0) / 4.0;
        _targetProteinG = (_goalKcal * protPct / 100.0) / 4.0;
        _targetFatG = (_goalKcal * fatPct / 100.0) / 9.0;
      }

      // 6) Calorias por refeição (para o card "Refeições")
      final meals = await di.mealsRepo.getMealsForDay(u.id, now);
      double b = 0, l = 0, s = 0, d = 0;

      // Agrega calorias por tipo de refeição (string vinda da DB/enum).
      for (final m in meals) {
        switch (m.type) {
          case 'BREAKFAST':
            b += m.totalKcal;
            break;
          case 'LUNCH':
            l += m.totalKcal;
            break;
          case 'SNACK':
            s += m.totalKcal;
            break;
          case 'DINNER':
            d += m.totalKcal;
            break;
        }
      }

      _kBreakfast = b;
      _kLunch = l;
      _kSnack = s;
      _kDinner = d;
    } finally {
      // Garante que `_loading` volta a false, desde que o widget ainda exista.
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Construção do UI (Scaffold, AppBar, cards)
  // ---------------------------------------------------------------------------

  /// Constrói o layout visual do dashboard.
  ///
  /// Elementos principais:
  /// - `AppBar` verde (Fresh Green) com título "Dashboard";
  /// - Corpo que mostra:
  ///   - spinner central enquanto `_loading == true`;
  ///   - caso contrário, um `ListView` com `RefreshIndicator`:
  ///     - saudação com o nome do utilizador;
  ///     - card de calorias diárias (anel + progresso);
  ///     - card de evolução do peso (mini-gráfico ou mensagem "Sem registos");
  ///     - card de macros (três círculos com progresso);
  ///     - card de refeições com barras de progresso.
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Calorias restantes = max(0, objetivo - consumidas).
    final int remaining = (_goalKcal - _consumedKcal).clamp(0, 1 << 31);

    // Percentagem de objetivo cumprido (0.0 a 1.0).
    final double pct =
        _goalKcal <= 0 ? 0.0 : (_consumedKcal / _goalKcal).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.freshGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Dashboard',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          // Enquanto `_loading` for true, mostramos apenas um indicador
          // de carregamento centrado.
          ? const Center(child: CircularProgressIndicator())
          // Depois de carregar, o conteúdo fica dentro de um `RefreshIndicator`
          // para permitir "pull-to-refresh".
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  // ===== Saudação =====
                  Text(
                    (_username == null || _username!.trim().isEmpty)
                        ? 'Olá 👋'
                        : 'Olá, ${_username!.trim()} 👋',
                    style: tt.titleLarge,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 16),

                  // ===== Card: Calorias de hoje =====
                  _Card(
                    child: Row(
                      children: [
                        // Anel de progresso de calorias (consumidas vs objetivo).
                        _CaloriesRing(
                          consumed: _consumedKcal,
                          goal: _goalKcal,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Calorias de hoje', style: tt.titleMedium),
                              const SizedBox(height: 8),
                              _kv('Objetivo', '$_goalKcal kcal', tt),
                              _kv('Consumidas', '$_consumedKcal kcal', tt),
                              _kv(
                                'Restantes',
                                '$remaining kcal',
                                tt,
                                emphasize: true,
                                color: cs.primary,
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Card: Evolução do peso =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Evolução do peso', style: tt.titleMedium),
                            const Spacer(),
                            if (_weightPoints.isNotEmpty)
                              Text(
                                // Mostra o último peso registado ao lado do título.
                                '${_weightPoints.last.weightKg.toStringAsFixed(1)} kg',
                                style: tt.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.charcoal,
                                  fontFamily: 'RobotoMono',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          // Ao tocar no gráfico, abre o ecrã detalhado de peso.
                          onTap: () async {
                            await GoRouter.of(context).push('/weight');
                            if (mounted) _load(); // recarrega ao voltar
                          },
                          child: _weightPoints.isEmpty
                              ? Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Sem registos ainda',
                                    style: tt.labelLarge?.copyWith(
                                      color: Colors.black54,
                                    ),
                                  ),
                                )
                              : WeightTrendCard(
                                  points: _weightPoints,
                                  height: 160,
                                  // `collapseSameDay = false` significa que
                                  // se houver mais do que um registo no mesmo
                                  // dia, todos serão mostrados no gráfico.
                                  collapseSameDay: false,
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Card: Macros =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Macros', style: tt.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Proteína
                            Expanded(
                              child: _MacroCircle(
                                key: const ValueKey('macro_protein'),
                                label: 'Proteína',
                                value: _proteinG,
                                target: _targetProteinG,
                                unit: 'g',
                                color: AppColors.leafyGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Hidratos de carbono
                            Expanded(
                              child: _MacroCircle(
                                key: const ValueKey('macro_carb'),
                                label: 'Hidratos',
                                value: _carbG,
                                target: _targetCarbG,
                                unit: 'g',
                                color: AppColors.warmTangerine,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Gordura
                            Expanded(
                              child: _MacroCircle(
                                key: const ValueKey('macro_fat'),
                                label: 'Gordura',
                                value: _fatG,
                                target: _targetFatG,
                                unit: 'g',
                                color: AppColors.goldenAmber,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Card: Refeições =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Refeições', style: tt.titleMedium),
                        const SizedBox(height: 12),
                        _MealRow(
                          icon: Icons.free_breakfast,
                          label: 'Pequeno-almoço',
                          kcal: _kBreakfast,
                        ),
                        const SizedBox(height: 12),
                        _MealRow(
                          icon: Icons.lunch_dining,
                          label: 'Almoço',
                          kcal: _kLunch,
                        ),
                        const SizedBox(height: 12),
                        _MealRow(
                          icon: Icons.cookie_outlined,
                          label: 'Lanche',
                          kcal: _kSnack,
                        ),
                        const SizedBox(height: 12),
                        _MealRow(
                          icon: Icons.dinner_dining,
                          label: 'Jantar',
                          kcal: _kDinner,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper para linhas "chave: valor" (kcal, objetivos, etc.)
  // ---------------------------------------------------------------------------

  /// Helper para desenhar uma linha de texto no formato:
  /// `chave .......................... valor`.
  ///
  /// Parâmetros:
  /// - [k]: etiqueta (ex.: "Objetivo");
  /// - [v]: valor formatado (ex.: "1800 kcal");
  /// - [tt]: `TextTheme` atual (para estilos base);
  /// - [emphasize]: se `true`, aplica estilo mais forte ao valor;
  /// - [color]: cor personalizada para o valor enfatizado.
  Widget _kv(
    String k,
    String v,
    TextTheme tt, {
    bool emphasize = false,
    Color? color,
  }) {
    final style = emphasize
        ? tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'RobotoMono',
          )
        : tt.bodyMedium;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: tt.bodyMedium),
        Text(v, style: style),
      ],
    );
  }
}

// ============================================================================
// UI building blocks (cards, círculos, linhas de refeição)
// ============================================================================

/// Container base para cartões do dashboard.
///
/// Aplica:
/// - cor de fundo baseada em `surfaceContainerHighest`;
/// - cantos arredondados;
/// - sombra suave;
/// - padding interno consistente.
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 4),
            color: Color(0x14000000),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Anel de progresso de calorias (consumidas vs objetivo).
///
/// - Mostra um `CircularProgressIndicator` com `value = percentagem`
///   e um texto central com a percentagem e rótulo `"kcal"`.
/// - Se `goal <= 0`, considera o progresso como 0%.
class _CaloriesRing extends StatelessWidget {
  final int consumed;
  final int goal;

  const _CaloriesRing({required this.consumed, required this.goal});

  @override
  Widget build(BuildContext context) {
    // Percentagem do objetivo atingida (0.0 a 1.0).
    final double pct = goal <= 0 ? 0.0 : (consumed / goal).clamp(0.0, 1.0);

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Trilha do anel (fundo).
          SizedBox(
            width: 92,
            height: 92,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          // Conteúdo central: percentagem e rótulo "kcal".
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(pct * 100).round()}%',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'RobotoMono',
                ),
              ),
              const SizedBox(height: 2),
              Text('kcal', style: tt.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Círculo de progresso para um macronutriente (proteína, hidratos, gordura).
///
/// Mostra:
/// - um anel de fundo totalmente preenchido com cor neutra;
/// - um anel superior proporcional ao progresso (0–100% do alvo);
/// - no centro, o valor atual em gramas e indicação do alvo (ou "sem alvo").
///
/// Exemplo de apresentação:
/// - "80 g" no centro; "Alvo 120" logo abaixo; rótulo "Proteína" fora do círculo.
class _MacroCircle extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final String unit;
  final Color color;

  const _MacroCircle({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final bool hasTarget = target > 0;
    final double pct = hasTarget ? (value / target).clamp(0.0, 1.0) : 0.0;

    // Anel duplo: fundo neutro + progresso colorido.
    final circle = SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anel de fundo (100% preenchido, cor neutra).
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              // Cor NEUTRA para a trilha, para não "roubar" o destaque ao anel colorido.
              color: cs.surfaceContainerHighest,
              backgroundColor: Colors.transparent,
            ),
          ),
          // Anel de progresso (0–100%, cor específica do macro).
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              backgroundColor: Colors.transparent,
            ),
          ),
          // Texto central: valor atual + alvo/sem alvo.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(0)} $unit',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'RobotoMono',
                ),
              ),
              Text(
                hasTarget ? 'Alvo ${target.toStringAsFixed(0)}' : 'sem alvo',
                style: tt.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 8),
        Text(label, style: tt.bodyMedium),
      ],
    );
  }
}

/// Linha de resumo de uma refeição com barra de progresso de calorias.
///
/// Estrutura:
/// - Ícone (ex.: pequeno-almoço, almoço, etc.);
/// - Nome da refeição;
/// - Barra horizontal que representa aproximadamente a carga calórica
///   (normalizada para um máximo arbitrário, aqui 800 kcal);
/// - Valor numérico das kcal à direita.
///
/// Exemplo: `🍳 Pequeno-almoço  [██████----]   320 kcal`
class _MealRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double kcal;

  const _MealRow({
    required this.icon,
    required this.label,
    required this.kcal,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // Percentagem da barra: consideramos 800 kcal como “cheio”.
    final double barPct = kcal <= 0 ? 0.0 : (kcal / 800).clamp(0.0, 1.0);

    final row = Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: tt.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: barPct,
                  minHeight: 10,
                  color: AppColors.warmTangerine,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${kcal.round()} kcal',
          style: tt.titleSmall?.copyWith(fontFamily: 'RobotoMono'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: row,
    );
  }
}
