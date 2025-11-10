// lib/features/nutrition/add_food_screen.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/online/products_repo_hybrid.dart';
import '../../app/di.dart' as di;
import '../../domain/models.dart';
import '../../core/meal_type.dart'; // <- fonte única do enum + extensions (labelPt, dbValue)

/// NutriScore — Adicionar Alimento (AddFoodScreen)
///
/// Ecrã dedicado a **procurar e adicionar alimentos** ao diário alimentar,
/// associado a:
/// - uma **refeição** (Pequeno-almoço / Almoço / Lanche / Jantar);
/// - uma **data específica** (dia selecionado no diário).
///
/// Fontes de dados:
/// - **Pesquisa local** (base de dados interna do NutriScore);
/// - **Pesquisa online** (Open Food Facts ou fonte semelhante), através de
///   [`ProductsRepoHybrid`] quando a pesquisa local não devolve resultados;
/// - **Histórico** de produtos usados recentemente pelo utilizador;
/// - **Favoritos** guardados pelo utilizador.
///
/// Principais funcionalidades:
/// - Selecionar refeição via *chip dropdown* no topo (sempre visível);
/// - Pesquisar por nome/código de barras com:
///   - *debounce* enquanto o utilizador escreve (sugestões rápidas);
///   - *submit* explícito (enter) com fallback para pesquisa online;
/// - Navegar para o ecrã de **detalhe do produto** (`productDetail`) já
///   parametrizado para a refeição e data selecionadas;
/// - Aceder ao **scanner de código de barras** para preencher a pesquisa.
///
class AddFoodScreen extends StatefulWidget {
  /// Refeição inicialmente selecionada ao abrir o ecrã.
  ///
  /// Se for `null`, assume o valor por omissão `MealType.breakfast`.
  final MealType? initialMeal;

  /// Data selecionada no diário (dia ao qual o alimento será associado).
  ///
  /// Se for `null`, é assumida a data atual (`DateTime.now()`).
  final DateTime? selectedDate;

  const AddFoodScreen({
    super.key,
    this.initialMeal,
    this.selectedDate,
  });

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

/// Tabs lógicas do ecrã de adicionar alimento.
///
/// Não corresponde a `TabBar` clássico, mas a três "modos" de listagem:
/// - [history]: histórico de produtos utilizados recentemente;
/// - [favorites]: lista de produtos marcados como favoritos;
/// - [results]: resultados da pesquisa atual.
enum _AddTab {
  /// Lista de histórico (produtos usados recentemente).
  history,

  /// Lista de favoritos do utilizador.
  favorites,

  /// Resultados da pesquisa atual.
  results,
}

/// Estado do ecrã de adicionar alimento.
///
/// Responsável por:
/// - gerir o texto de pesquisa e o *debounce* da pesquisa rápida;
/// - carregar histórico e favoritos quando o ecrã é aberto e em *refresh*;
/// - executar pesquisas locais e online de produtos;
/// - controlar qual a tab ativa (Histórico, Favoritos ou Resultados);
/// - navegar para o scanner e para o detalhe de produto.
class _AddFoodScreenState extends State<AddFoodScreen> {
  // ---------------------------------------------------------------------------
  // Estado de pesquisa
  // ---------------------------------------------------------------------------

  /// Controlador do campo de pesquisa de alimento.
  ///
  /// O listener associado executa uma pesquisa "rápida" com *debounce*
  /// sempre que o utilizador escreve.
  final TextEditingController _searchCtrl = TextEditingController();

  /// Timer usado para implementar *debounce* da pesquisa rápida.
  ///
  /// Cada vez que o utilizador digita algo, o timer é reiniciado. A pesquisa
  /// só é executada após um pequeno intervalo (220ms) sem novas teclas.
  Timer? _debounce;

  /// Refeição atualmente selecionada no *chip* do header.
  ///
  /// Os alimentos adicionados a partir deste ecrã serão associados a esta refeição.
  late MealType _selectedMeal;

  /// Indica se estamos a mostrar uma pesquisa ativa (true) ou as tabs de
  /// histórico/favoritos (false).
  ///
  /// - `true`: o conteúdo principal mostra `_results`;
  /// - `false`: o conteúdo mostra histórico ou favoritos conforme `_tab`.
  bool _showPesquisa = false;

  // ---------------------------------------------------------------------------
  // Estados de loading
  // ---------------------------------------------------------------------------

  /// Indica se uma pesquisa de resultados está em curso.
  bool _loading = false;

  /// Indica se o histórico está a ser recarregado.
  bool _loadingHistory = false;

  /// Indica se os favoritos estão a ser recarregados.
  bool _loadingFavs = false;

  // ---------------------------------------------------------------------------
  // Dados de resultados, histórico e favoritos
  // ---------------------------------------------------------------------------

  /// Lista de produtos encontrados na pesquisa atual.
  List<ProductModel> _results = const [];

  /// Lista de entradas de histórico (produtos utilizados recentemente).
  List<HistoryEntry> _history = const [];

  /// Lista de produtos marcados como favoritos.
  List<ProductModel> _favorites = const [];

  /// Tab/mode atual (Histórico / Favoritos / Resultados).
  _AddTab _tab = _AddTab.history;

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Inicializa o estado:
  /// - define a refeição selecionada a partir de [widget.initialMeal];
  /// - carrega histórico & favoritos iniciais;
  /// - regista listener no campo de pesquisa para suportar sugestões com
  ///   *debounce*.
  @override
  void initState() {
    super.initState();

    // Refeição inicial (ou pequeno-almoço por omissão).
    _selectedMeal = widget.initialMeal ?? MealType.breakfast;

    // Carrega histórico e favoritos logo ao entrar.
    _loadHistoryAndFavorites();

    // Liga a pesquisa rápida com debounce ao campo de pesquisa.
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();

      // Se existe texto, ativamos "modo pesquisa" e vamos para tab de resultados.
      setState(() {
        _showPesquisa = q.isNotEmpty;
        _tab = q.isNotEmpty ? _AddTab.results : _tab;
      });

      // Cancelamos qualquer debounce anterior.
      _debounce?.cancel();

      // Se o utilizador apagou o texto todo, limpamos resultados.
      if (q.isEmpty) {
        setState(() => _results = const []);
        return;
      }

      // Após pequeno atraso, executa pesquisa local limitada (sugestões rápidas).
      _debounce = Timer(const Duration(milliseconds: 220), () async {
        final list = await di.di.productsRepo.searchByName(q, limit: 8);
        if (!mounted) return;

        // Garante que o texto não mudou entretanto antes de aplicar resultados.
        if (_searchCtrl.text.trim() == q) {
          setState(() => _results = list);
        }
      });
    });
  }

  /// Liberta recursos:
  /// - cancela o timer de *debounce* se ainda existir;
  /// - liberta o controlador de texto da pesquisa.
  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers de data/refeição
  // ---------------------------------------------------------------------------

  /// Data selecionada no formato `YYYY-MM-DD`, usada para passar ao detalhe.
  ///
  /// Se [widget.selectedDate] for `null`, usa a data atual (`DateTime.now()`).
  String get _selectedDateYmd {
    final d = widget.selectedDate ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // ---------------------------------------------------------------------------
  // Carregamento de histórico e favoritos
  // ---------------------------------------------------------------------------

  /// Carrega, em paralelo, o histórico e a lista de favoritos do utilizador.
  ///
  /// Fluxo:
  /// 1. Obtém o utilizador atual de `userRepo.currentUser()`;
  /// 2. Se não existir utilizador, retorna sem fazer nada;
  /// 3. Marca `_loadingHistory` e `_loadingFavs` como `true`;
  /// 4. Faz `historyRepo.list` e `favoritesRepo.list` (página 1, 20 items);
  /// 5. Atualiza `_history`, `_favorites` e flags de loading.
  Future<void> _loadHistoryAndFavorites() async {
    final user = await di.di.userRepo.currentUser();
    if (user == null) return;

    setState(() {
      _loadingHistory = true;
      _loadingFavs = true;
    });

    final h = await di.di.historyRepo.list(user.id, page: 1, pageSize: 20);
    final f = await di.di.favoritesRepo.list(user.id, page: 1, pageSize: 20);

    if (!mounted) return;
    setState(() {
      _history = h;
      _favorites = f;
      _loadingHistory = false;
      _loadingFavs = false;
    });
  }

  /// Recarrega apenas o histórico do utilizador.
  ///
  /// Usado quando o utilizador carrega em "Atualizar histórico".
  Future<void> _reloadHistory() async {
    final user = await di.di.userRepo.currentUser();
    if (user == null) return;

    setState(() => _loadingHistory = true);
    final h = await di.di.historyRepo.list(user.id, page: 1, pageSize: 20);

    if (!mounted) return;
    setState(() {
      _history = h;
      _loadingHistory = false;
    });
  }

  /// Recarrega apenas a lista de favoritos do utilizador.
  ///
  /// Usado quando o utilizador carrega em "Atualizar favoritos".
  Future<void> _reloadFavorites() async {
    final user = await di.di.userRepo.currentUser();
    if (user == null) return;

    setState(() => _loadingFavs = true);
    final f = await di.di.favoritesRepo.list(user.id, page: 1, pageSize: 20);

    if (!mounted) return;
    setState(() {
      _favorites = f;
      _loadingFavs = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Pesquisa submetida (enter / botão de teclado)
  // ---------------------------------------------------------------------------

  /// Executa uma pesquisa completa quando o utilizador submete (enter/teclado).
  ///
  /// Etapas:
  /// 1. Normaliza e limpa o texto da pesquisa (`trim`);
  /// 2. Se estiver vazio:
  ///    - limpa resultados e desliga `_loading`;
  /// 3. Se tiver texto:
  ///    - ativa `_showPesquisa` e `_tab = results`;
  ///    - ativa `_loading = true`;
  ///    - tenta primeiro pesquisa **local** em `productsRepo.searchByName`;
  ///    - se local estiver vazia **e** o repo for `ProductsRepoHybrid`,
  ///      tenta `fetchOnlineAndCache` para buscar online + guardar local;
  ///    - atualiza `_results` com a lista final;
  ///    - se continuar vazia, mostra *SnackBar* "Sem resultados.";
  ///    - em caso de erro, mostra *SnackBar* com mensagem de erro;
  ///    - no fim, garante `_loading = false`.
  Future<void> _onSearchSubmitted(String q) async {
    final query = q.trim();

    setState(() {
      _showPesquisa = query.isNotEmpty;
      _loading = query.isNotEmpty;
      _tab = _AddTab.results;
    });

    // Se a pesquisa for vazia, desliga e limpa resultados.
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }

    try {
      // 1) Tentar LOCAL primeiro
      var items = await di.di.productsRepo.searchByName(query, limit: 20);

      // 2) Se nada local ⇒ tenta FETCH ONLINE (apenas quando repo suporta).
      if (items.isEmpty && di.di.productsRepo is ProductsRepoHybrid) {
        items = await (di.di.productsRepo as ProductsRepoHybrid)
            .fetchOnlineAndCache(query, limit: 20);
      }

      if (!mounted) return;
      setState(() {
        _results = items;
      });

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sem resultados.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na pesquisa: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Navegação (scanner + detalhe)
  // ---------------------------------------------------------------------------

  /// Abre o ecrã de **scanner de código de barras** (`/scan`).
  ///
  /// Fluxo:
  /// - navega para `'/scan'` e aguarda um `String?` de retorno (barcode);
  /// - se o resultado for uma `String` não vazia:
  ///   - preenche o campo de pesquisa com o código;
  ///   - chama `_onSearchSubmitted` para procurar diretamente esse código.
  Future<void> _openScanner() async {
    final res = await context.push<String>('/scan');
    if (!mounted) {
      return;
    }

    // (Boa prática) Verificação manual do tipo + branco.
    if (res is String && res.trim().isNotEmpty) {
      _searchCtrl.text = res.trim();
      await _onSearchSubmitted(_searchCtrl.text);
    }
  }

  /// Abre o ecrã de **detalhe de produto**, passando o código de barras
  /// obrigatório e, opcionalmente, o [ProductModel] com dados já carregados.
  ///
  /// Esta função prepara um `extra` robusto para a rota `'productDetail'`,
  /// com:
  /// - `barcode`, `name`, `brand`;
  /// - valores nutricionais por 100 g (kcal, macros, sal, fibra, etc.);
  /// - flags de contexto:
  ///   - `readOnly: false` (é um fluxo de adição/edição);
  ///   - `meal` (enum `MealType`) e `selectedMealDb` (string DB 'BREAKFAST'…);
  ///   - `dateYmd` e `selectedDateYmd` (ISO `YYYY-MM-DD`).
  ///
  /// Desta forma, o ecrã de detalhe sabe:
  /// - para que refeição estamos a adicionar;
  /// - para que dia;
  /// - e já dispõe de nutrição base por 100 g.
  void _openDetailByBarcode(
    String barcode, {
    ProductModel? p,
  }) {
    if (barcode.isEmpty) return;

    context.pushNamed(
      'productDetail',
      extra: {
        'barcode': barcode,
        'name': p?.name,
        'brand': p?.brand,
        'baseQuantityLabel': '100 g',
        'kcalPerBase': p?.energyKcal100g,
        'proteinGPerBase': p?.protein100g,
        'carbsGPerBase': p?.carb100g,
        'fatGPerBase': p?.fat100g,
        'sugarsGPerBase': p?.sugars100g,
        'fiberGPerBase': p?.fiber100g,
        'saltGPerBase': p?.salt100g,
        'readOnly': false,
        'meal': _selectedMeal, // passa o enum diretamente
        'dateYmd': _selectedDateYmd, // YYYY-MM-DD
        'selectedMealDb': _selectedMeal.dbValue, // BREAKFAST/LUNCH/...
        'selectedDateYmd': _selectedDateYmd,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI principal (Scaffold, header hero, tabs, listas)
  // ---------------------------------------------------------------------------

  /// Constrói toda a estrutura visual do ecrã:
  ///
  /// - Cabeçalho "hero" com:
  ///   - botão de voltar;
  ///   - chip central para escolher a refeição;
  ///   - barra de pesquisa com efeito "frosted glass";
  /// - Card de "Scan código de barras" logo abaixo;
  /// - Lista principal com:
  ///   - tabs (Histórico / Favoritos) + botão de refresh;
  ///   - conteúdo variável (resultados, favoritos ou histórico) dependendo
  ///     de `_showPesquisa` e `_tab`.
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topInset = MediaQuery.of(context).padding.top;

    final showingResults = _showPesquisa;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // ===================== HERO VERDE (header) =====================
            Container(
              padding: EdgeInsets.only(top: topInset),
              decoration: BoxDecoration(color: cs.primary),
              child: Column(
                children: [
                  // Linha do topo: botão voltar + combo de refeição centrado
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Voltar',
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: cs.onPrimary,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _MealComboChipCentered(
                              value: _selectedMeal,
                              onChanged: (v) =>
                                  setState(() => _selectedMeal = v),
                              chipColor: cs.primary,
                              textColor: cs.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  // Barra de pesquisa com efeito vidro fosco
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: _SearchBarHero(
                      controller: _searchCtrl,
                      hintText: 'Pesquisar alimento…',
                      textColor: cs.onPrimary,
                      onSubmitted: _onSearchSubmitted,
                    ),
                  ),
                ],
              ),
            ),

            // Curva separadora entre header verde e conteúdo em superfície
            ClipPath(
              clipper: _TopCurveClipper(),
              child: Container(height: 16, color: cs.surface),
            ),

            // ===================== CARTÃO DE SCAN =====================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ScanCardSurfaceGreen(onTap: _openScanner),
            ),

            // ===================== LISTA PRINCIPAL =====================
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: (() {
                  // Determina o número de linhas a renderizar.
                  // A linha 0 é sempre o cabeçalho de tabs.
                  if (showingResults || _tab == _AddTab.results) {
                    // Resultados: se não houver, mostramos uma linha "Sem resultados".
                    return (_results.isEmpty ? 1 : _results.length + 1);
                  }
                  if (_tab == _AddTab.favorites) {
                    return (_favorites.isEmpty ? 1 : _favorites.length + 1);
                  }
                  // Histórico
                  return (_history.isEmpty ? 1 : _history.length + 1);
                })(),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  // Linha 0: cabeçalho com tabs + botão de refresh
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Row(
                        children: [
                          // Tabs centradas (Histórico / Favoritos)
                          Expanded(
                            child: Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                runAlignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  _HeaderTabChip(
                                    label: 'Histórico',
                                    selected: _tab == _AddTab.history &&
                                        !showingResults,
                                    onTap: () {
                                      setState(() {
                                        _tab = _AddTab.history;
                                        _showPesquisa = false;
                                      });
                                    },
                                  ),
                                  _HeaderTabChip(
                                    label: 'Favoritos',
                                    selected: _tab == _AddTab.favorites &&
                                        !showingResults,
                                    onTap: () {
                                      setState(() {
                                        _tab = _AddTab.favorites;
                                        _showPesquisa = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Botão de refresh (só quando não em modo resultados)
                          if (!showingResults)
                            IconButton(
                              tooltip: _tab == _AddTab.favorites
                                  ? 'Atualizar favoritos'
                                  : 'Atualizar histórico',
                              icon: const Icon(Icons.refresh_rounded),
                              onPressed: () async {
                                // Captura síncrona para evitar warnings de lint
                                final messenger = ScaffoldMessenger.of(context);

                                if (_tab == _AddTab.favorites) {
                                  await _reloadFavorites();
                                } else {
                                  await _reloadHistory();
                                }

                                // Mostra feedback de atualização
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Atualizado.')),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  }

                  // ===================== MODO RESULTADOS =====================
                  if (showingResults) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_results.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Sem resultados.',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final it = _results[i - 1];
                    return _ResultTile(
                      name: it.name,
                      barcode: it.barcode,
                      brand: it.brand,
                      kcal100: it.energyKcal100g,
                      onTap: () => _openDetailByBarcode(it.barcode, p: it),
                    );
                  }

                  // ===================== MODO FAVORITOS =====================
                  if (_tab == _AddTab.favorites) {
                    if (_loadingFavs && _favorites.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_favorites.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Ainda não tens favoritos.',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final f = _favorites[i - 1];
                    return _FavoriteTile(
                      name: f.name,
                      barcode: f.barcode,
                      kcal100: f.energyKcal100g,
                      onTap: () => _openDetailByBarcode(f.barcode, p: f),
                    );
                  }

                  // ===================== MODO HISTÓRICO =====================
                  if (_loadingHistory && _history.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (_history.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Ainda não tens histórico.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final h = _history[i - 1];
                  final scanned = _tryParseIso(h.scannedAtIso);

                  // Título principal do item (nome ou barcode).
                  final title = (h.name != null && h.name!.trim().isNotEmpty)
                      ? h.name!.trim()
                      : (h.barcode ?? 'Produto');

                  // Subtítulo: marca • código • data
                  final subtitleParts = <String>[];
                  if ((h.brand ?? '').trim().isNotEmpty) {
                    subtitleParts.add(h.brand!.trim());
                  }
                  if ((h.barcode ?? '').trim().isNotEmpty) {
                    subtitleParts.add(h.barcode!.trim());
                  }
                  if (scanned != null) {
                    subtitleParts.add(_fmtDate(scanned));
                  }

                  return _HistoryTile(
                    title: title,
                    subtitle: subtitleParts.join(' • '),
                    kcal100: h.calories,
                    onTap: () => _openDetailByBarcode(h.barcode ?? ''),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pequenos helpers de data
  // ---------------------------------------------------------------------------

  /// Tenta fazer `DateTime.parse` a partir de uma string ISO.
  ///
  /// Em caso de falha, devolve `null` sem lançar exceção.
  DateTime? _tryParseIso(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Formata uma data no formato `DD/MM/AAAA`.
  ///
  /// Exemplo:
  /// - `2025-11-10` → `"10/11/2025"`.
  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/* ============================ WIDGETS HERO ============================ */

/// Chip central para seleção de refeição no header.
///
/// Mostra um `DropdownButton<MealType>` estilizado como *chip*:
/// - texto da refeição em PT (via `MealType.labelPt`);
/// - ícone de "expand more";
/// - lista de todas as refeições possíveis.
class _MealComboChipCentered extends StatelessWidget {
  final MealType value;
  final ValueChanged<MealType> onChanged;
  final Color chipColor;
  final Color textColor;

  const _MealComboChipCentered({
    required this.value,
    required this.onChanged,
    required this.chipColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const ShapeDecoration(
        color: Colors.transparent,
        shape: StadiumBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MealType>(
          value: value,
          isExpanded: true,
          icon: const SizedBox.shrink(),
          alignment: Alignment.center,
          dropdownColor: chipColor,
          borderRadius: BorderRadius.circular(12),

          // Construtor customizado para o item selecionado:
          // texto + ícone, centrados.
          selectedItemBuilder: (_) => MealType.values.map((m) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.labelPt, // <- getter do core
                    style: tt.titleMedium?.copyWith(
                      fontSize: 20,
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.expand_more_rounded, color: textColor),
                ],
              ),
            );
          }).toList(),

          // Lista de opções do dropdown.
          items: MealType.values.map((m) {
            return DropdownMenuItem<MealType>(
              value: m,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    m.labelPt, // <- getter do core
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),

          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Barra de pesquisa com efeito "frosted glass" no header.
///
/// Características:
/// - fundo semi-transparente com blur (`BackdropFilter`);
/// - ícone de lupa à esquerda;
/// - campo de texto que dispara [onSubmitted] ao pressionar "search";
/// - botão de limpar (X) quando existe texto.
class _SearchBarHero extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final Color textColor;
  final ValueChanged<String>? onSubmitted;

  const _SearchBarHero({
    required this.controller,
    required this.hintText,
    required this.textColor,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 10,
                offset: Offset(0, 4),
                color: Color(0x22000000),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: textColor,
                  onSubmitted: onSubmitted,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: textColor.withValues(alpha: .9),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isCollapsed: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textColor),
                  onPressed: () {
                    controller.clear();
                    // Force o modo histórico ao limpar totalmente a pesquisa.
                    onSubmitted?.call('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ============================ SCAN CARD ============================ */

/// Card de destaque para acesso rápido ao scanner de código de barras.
///
/// Visual:
/// - fundo na cor primária;
/// - ícone de QR à esquerda;
/// - título e subtítulo explicativo;
/// - seta à direita.
class _ScanCardSurfaceGreen extends StatelessWidget {
  final VoidCallback? onTap;

  const _ScanCardSurfaceGreen({this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 6),
              color: Color(0x1A000000),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: .30),
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: cs.onPrimary,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan código de barras',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Usa a câmara para adicionar rapidamente um produto.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onPrimary.withValues(alpha: .96),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onPrimary.withValues(alpha: .96),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================ LIST ITEMS SIMPLIFICADOS ============================ */

/// Item de lista para um resultado de pesquisa.
///
/// Mostra:
/// - nome do produto;
/// - marca + código de barras em subtítulo;
/// - chip com kcal/100g (se conhecido);
/// - botão circular com seta para abrir o detalhe.
class _ResultTile extends StatelessWidget {
  final String name;
  final String barcode;
  final String? brand;
  final int? kcal100;
  final VoidCallback? onTap;

  const _ResultTile({
    required this.name,
    required this.barcode,
    this.brand,
    this.kcal100,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Subtítulo: "Marca • código"
    final subtitle = [
      if ((brand ?? '').trim().isNotEmpty) brand!.trim(),
      barcode,
    ].join(' • ');

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Texto principal (nome, subtítulo, métrica kcal).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: tt.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (kcal100 != null)
                      _ChipMetric(
                        label: 'por 100g',
                        value: '$kcal100 kcal',
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Botão circular para abrir detalhe.
              Material(
                color: cs.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Item de lista para um produto favorito.
///
/// Reutiliza internamente [_ResultTile] para manter consistência visual.
class _FavoriteTile extends StatelessWidget {
  final String name;
  final String barcode;
  final int? kcal100;
  final VoidCallback? onTap;
  final String? brand; // opcional se já existir no modelo

  const _FavoriteTile({
    required this.name,
    required this.barcode,
    this.kcal100,
    this.onTap,
    // ignore: unused_element_parameter
    this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return _ResultTile(
      name: name,
      barcode: barcode,
      brand: brand, // se não tiveres marca, pode ir null
      kcal100: kcal100,
      onTap: onTap,
    );
  }
}

/// Chip de cabeçalho para seleção de tab (Histórico / Favoritos).
///
/// Mostra:
/// - fundo primário quando `selected == true`;
/// - fundo neutro quando `selected == false`.
class _HeaderTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HeaderTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected
          ? cs.primary
          : cs.surfaceContainerHighest.withValues(alpha: .35),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: tt.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Item de lista para entradas de histórico.
///
/// Mostra:
/// - título (nome do produto ou barcode);
/// - subtítulo com marca / código / data;
/// - chip de kcal/100g se disponível;
/// - botão circular com ícone "+" para voltar a adicionar o produto.
class _HistoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int? kcal100;
  final VoidCallback? onTap;

  const _HistoryTile({
    required this.title,
    required this.subtitle,
    this.kcal100,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Conteúdo principal.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título + botão circular "+" à direita.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: tt.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Material(
                          color: cs.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onTap,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.add,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (kcal100 != null)
                      _ChipMetric(
                        label: 'por 100g',
                        value: '$kcal100 kcal',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pequeno chip usado para destacar métricas, como "por 100g 120 kcal".
class _ChipMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ChipMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/* ============================ UTIL PARTILHADO ============================ */

/// Clipper que desenha uma curva suave no topo, usada como separador
/// entre o header verde e a área de conteúdo em `surface`.
class _TopCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path();
    p.lineTo(0, 0);
    p.lineTo(0, size.height);
    p.quadraticBezierTo(
      size.width * 0.5,
      -size.height,
      size.width,
      size.height,
    );
    p.lineTo(size.width, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
