// lib/features/nutrition/add_food_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart' as di;
import '../../domain/models.dart';
import '../../core/meal_type.dart'; // <- fonte única do enum + extensions (labelPt, dbValue)

/// NutriScore — AddFoodScreen (ligado ao SQLite)

class AddFoodScreen extends StatefulWidget {
  final MealType? initialMeal; // Pequeno-almoço / Almoço / Lanche / Jantar
  final DateTime? selectedDate;
  const AddFoodScreen({super.key, this.initialMeal, this.selectedDate});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

// --- Tabs do AddFood ---
enum _AddTab { history, favorites, results }

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  late MealType _selectedMeal;

  // Alterna título Histórico/Pesquisa
  bool _showPesquisa = false;

  // Loading states
  bool _loading = false;
  bool _loadingHistory = false;
  bool _loadingFavs = false;

  // Data (reais)
  List<ProductModel> _results = const [];
  List<HistoryEntry> _history = const [];
  List<ProductModel> _favorites = const [];

  _AddTab _tab = _AddTab.history;

  @override
  void initState() {
    super.initState();
    _selectedMeal = widget.initialMeal ?? MealType.breakfast;

    // carregar histórico + favoritos iniciais
    _loadHistoryAndFavorites();

    // sugestões rápidas: procura real com debouncing
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      setState(() {
        _showPesquisa = q.isNotEmpty;
        _tab = q.isNotEmpty ? _AddTab.results : _tab;
      });
      _debounce?.cancel();
      if (q.isEmpty) {
        setState(() => _results = const []);
        return;
      }
      _debounce = Timer(const Duration(milliseconds: 220), () async {
        final list = await di.di.productsRepo.searchByName(q, limit: 8);
        if (!mounted) return;
        // só mostra se continuas a escrever o mesmo
        if (_searchCtrl.text.trim() == q) {
          setState(() => _results = list);
        }
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /* ----------------- Helpers ----------------- */

  String get _selectedDateYmd {
    final d = widget.selectedDate ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /* ----------------- Loads ----------------- */

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

  Future<void> _onSearchSubmitted(String q) async {
    final query = q.trim();
    setState(() {
      _showPesquisa = query.isNotEmpty;
      _loading = query.isNotEmpty;
      _tab = _AddTab.results;
    });
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }

    final resp = await di.di.productsRepo.searchByName(query, limit: 20);
    if (!mounted) return;
    setState(() {
      _results = resp;
      _loading = false;
    });
  }

  /* ----------------- NAVIGAÇÃO ----------------- */

  // 1) Scanner -> /scan; se devolver um barcode (String), preenche pesquisa e procura
  Future<void> _openScanner() async {
    final res = await context.push<String>('/scan');
    if (!mounted)
      return; // boa prática para o lint "use_build_context_synchronously"
    if (res is String && res.trim().isNotEmpty) {
      _searchCtrl.text = res.trim();
      await _onSearchSubmitted(_searchCtrl.text);
    }
  }

  // Abre detalhe preferindo dados do model quando existirem
  void _openDetailByBarcode(String barcode, {ProductModel? p}) {
    if (barcode.isEmpty) return;
    context.pushNamed(
      'productDetail',
      extra: {
        'barcode': barcode,
        'name': p?.name,
        'baseQuantityLabel': '100 g',
        'kcalPerBase': p?.energyKcal100g,
        'proteinGPerBase': p?.protein100g,
        'carbsGPerBase': p?.carb100g,
        'fatGPerBase': p?.fat100g,
        'sugarsGPerBase': p?.sugars100g,
        'fiberGPerBase': p?.fiber100g,
        'saltGPerBase': p?.salt100g,
        'readOnly': false,
        'meal': _selectedMeal, // passa o enum
        'dateYmd': _selectedDateYmd, // YYYY-MM-DD
        'selectedMealDb': _selectedMeal.dbValue, // BREAKFAST/LUNCH/...
        'selectedDateYmd': _selectedDateYmd,
      },
    );
  }

  /* ----------------- UI ----------------- */

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
            // ===================== HERO VERDE =====================
            Container(
              padding: EdgeInsets.only(top: topInset),
              decoration: BoxDecoration(color: cs.primary),
              child: Column(
                children: [
                  // Back + combo (chip verde blendado)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: "Voltar",
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

                  // Search pill (frosted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: _SearchBarHero(
                      controller: _searchCtrl,
                      hintText: "Pesquisar alimento…",
                      textColor: cs.onPrimary,
                      onSubmitted: _onSearchSubmitted,
                    ),
                  ),
                ],
              ),
            ),

            // Curva separadora
            ClipPath(
              clipper: _TopCurveClipper(),
              child: Container(height: 16, color: cs.surface),
            ),

            // ===================== SCAN =====================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ScanCardSurfaceGreen(onTap: _openScanner),
            ),

            // ===================== HISTÓRICO / PESQUISA =====================
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: (() {
                  if (showingResults || _tab == _AddTab.results) {
                    return (_results.isEmpty ? 1 : _results.length + 1);
                  }
                  if (_tab == _AddTab.favorites) {
                    return (_favorites.isEmpty ? 1 : _favorites.length + 1);
                  }
                  return (_history.isEmpty ? 1 : _history.length + 1);
                })(),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Row(
                        children: [
                          // ====== CENTRADO ======
                          Expanded(
                            child: Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                runAlignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  _HeaderTabChip(
                                    label: 'Histórico',
                                    selected:
                                        _tab == _AddTab.history &&
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
                                    selected:
                                        _tab == _AddTab.favorites &&
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

                          // Refresh
                          if (!showingResults)
                            IconButton(
                              tooltip: _tab == _AddTab.favorites
                                  ? "Atualizar favoritos"
                                  : "Atualizar histórico",
                              icon: const Icon(Icons.refresh_rounded),
                              onPressed: () async {
                                if (_tab == _AddTab.favorites) {
                                  await _reloadFavorites();
                                } else {
                                  await _reloadHistory();
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Atualizado.')),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  }

                  // RESULTADOS
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
                          "Sem resultados.",
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

                  // FAVORITOS
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
                          "Ainda não tens favoritos.",
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

                  // HISTÓRICO
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
                        "Ainda não tens histórico.",
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final h = _history[i - 1];
                  final scanned = _tryParseIso(h.scannedAtIso);

                  // título principal
                  final title = (h.name != null && h.name!.trim().isNotEmpty)
                      ? h.name!.trim()
                      : (h.barcode ?? 'Produto');

                  // subtítulo: marca • código • data
                  final subtitleParts = <String>[];
                  if ((h.brand ?? '').trim().isNotEmpty)
                    subtitleParts.add(h.brand!.trim());
                  if ((h.barcode ?? '').trim().isNotEmpty)
                    subtitleParts.add(h.barcode!.trim());
                  if (scanned != null) subtitleParts.add(_fmtDate(scanned));

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

  DateTime? _tryParseIso(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(d.day)}/${two(d.month)}/${d.year}";
  }
}

/* ============================ WIDGETS HERO ============================ */

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
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textColor),
                  onPressed: () {
                    controller.clear();
                    onSubmitted?.call(''); // limpa para voltar a "Histórico"
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
                        "Scan código de barras",
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Usa a câmara para adicionar rapidamente um produto.",
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

class _ResultTile extends StatelessWidget {
  final String name;
  final String barcode;
  final String? brand; // <- NOVO
  final int? kcal100;
  final VoidCallback? onTap;
  const _ResultTile({
    required this.name,
    required this.barcode,
    this.brand, // <- NOVO
    this.kcal100,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

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
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (kcal100 != null)
                      _ChipMetric(label: "por 100g", value: "$kcal100 kcal"),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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

class _FavoriteTile extends StatelessWidget {
  final String name;
  final String barcode;
  final int? kcal100;
  final VoidCallback? onTap;
  final String? brand; // opcional se já tiveres no model

  const _FavoriteTile({
    required this.name,
    required this.barcode,
    this.kcal100,
    this.onTap,
    this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return _ResultTile(
      name: name,
      barcode: barcode,
      brand: brand, // se ainda não tens, deixa null
      kcal100: kcal100,
      onTap: onTap,
    );
  }
}

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    if (kcal100 != null)
                      _ChipMetric(label: "por 100g", value: "$kcal100 kcal"),
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

class _ChipMetric extends StatelessWidget {
  final String label;
  final String value;
  const _ChipMetric({required this.label, required this.value});

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
