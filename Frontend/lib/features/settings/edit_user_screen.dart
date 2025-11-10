// lib/features/settings/edit_user_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';

/// ---------------------------------------------------------------------------
/// NutriScore — Ecrã de Edição de Utilizador (Perfil + Metas / Goals)
/// ---------------------------------------------------------------------------
/// Este ecrã permite ao utilizador rever e atualizar:
///   - Nome (perfil básico);
///   - Sexo;
///   - Altura, peso atual e peso alvo;
///   - Datas (nascimento + objetivo);
///   - Nível de atividade diária;
///
/// Do ponto de vista de domínio:
///   - Lê o utilizador atual via `userRepo.currentUser()`;
///   - Lê / guarda metas de utilizador (`UserGoalsModel`) via `goalsRepo`;
///   - Não recalcula aqui as kcal diárias → deixa `dailyCalories` a `null`
///     para que o repositório (ou lógica de negócio) recalcule com base
///     nos dados inseridos/atualizados.
///
/// UX:
///   - Mostra loader inicial enquanto carrega dados;
///   - Usa um `Form` com validação mínima (campos obrigatórios);
///   - Botão "Guardar" tipo pill sticky na parte inferior;
///   - SnackBar de sucesso e fallback de navegação para /settings.
/// ---------------------------------------------------------------------------

class EditUserScreen extends StatefulWidget {
  const EditUserScreen({super.key});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

/// Estado do [EditUserScreen].
///
/// Responsabilidades principais:
///  - Gerir controladores de texto para dados de perfil/metas;
///  - Carregar dados iniciais (perfil + metas) do backend via DI;
///  - Validar e construir um [UserGoalsModel] para guardar;
///  - Navegação de retorno para o ecrã de definições.
class _EditUserScreenState extends State<EditUserScreen> {
  /// Chave do `Form` para validação global (_form.currentState!.validate()).
  final _form = GlobalKey<FormState>();

  // ---------------------------------------------------------------------------
  // Campos de perfil (User)
  // ---------------------------------------------------------------------------

  /// Nome visível do utilizador (não é obrigatório, mas recomendado).
  final _nameCtrl = TextEditingController();

  // ---------------------------------------------------------------------------
  // Campos de metas / biometrias (UserGoals)
  // ---------------------------------------------------------------------------

  /// Altura em centímetros (ex.: "175").
  final _heightCtrl = TextEditingController(); // cm

  /// Peso atual em quilogramas (ex.: "72.5").
  final _weightCtrl = TextEditingController(); // kg

  /// Peso objetivo em quilogramas (ex.: "68.0").
  final _targetWeightCtrl = TextEditingController(); // kg

  /// Data de nascimento (UI em "dd/mm/aaaa", armazenada também em `_dobIso`).
  final _dobCtrl = TextEditingController(); // dd/mm/aaaa

  /// Data objetivo (UI em "dd/mm/aaaa", armazenada também em `_targetDateIso`).
  final _targetDateCtrl = TextEditingController(); // dd/mm/aaaa

  /// Sexo do utilizador: 'MALE' | 'FEMALE' | 'OTHER'.
  String? _sex;

  /// Nível de atividade diária:
  /// 'sedentary'|'light'|'moderate'|'active'|'very_active'
  String? _activity;

  /// Data de nascimento em formato ISO (DateTime → armazenado em `UserGoalsModel`).
  DateTime? _dobIso;

  /// Data objetivo em formato ISO.
  DateTime? _targetDateIso;

  /// Indica se o ecrã está a carregar os dados iniciais.
  bool _loading = true;

  /// Indica se está a ocorrer uma operação de guardar (_save()).
  bool _saving = false;

  // ---- activity items (alinhados com o onboarding) ----
  static const List<(String value, String label)> _activityItems = [
    ('sedentary', 'Sedentário'),
    ('light', 'Pouca atividade'),
    ('moderate', 'Moderada'),
    ('active', 'Ativo'),
    ('very_active', 'Muito ativo'),
  ];

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _targetWeightCtrl.dispose();
    _dobCtrl.dispose();
    _targetDateCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HELPERS DE DATA
  // ---------------------------------------------------------------------------

  /// Converte um [DateTime] para string no formato **dd/mm/aaaa**.
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Abre um `showDatePicker` centralizado e devolve a data escolhida (ou null).
  ///
  /// Permite configurar:
  ///  - [initial]: data inicialmente selecionada;
  ///  - [first]: data mínima;
  ///  - [last]: data máxima.
  Future<DateTime?> _pickDate({
    DateTime? initial,
    DateTime? first,
    DateTime? last,
  }) async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: first ?? DateTime(1900),
      lastDate: last ?? DateTime(now.year + 10),
      helpText: 'Selecionar data',
      confirmText: 'OK',
      cancelText: 'Cancelar',
      builder: (ctx, child) {
        final cs = Theme.of(ctx).colorScheme;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: cs.copyWith(primary: cs.primary),
          ),
          child: child!,
        );
      },
    );
    return res;
  }

  // ---------------------------------------------------------------------------
  // LOAD: ler dados atuais do utilizador + metas
  // ---------------------------------------------------------------------------

  /// Carrega:
  ///  - Utilizador atual (`userRepo.currentUser()`);
  ///  - Goals (`goalsRepo.getByUser(user.id)`).
  ///
  /// Preenche os controladores de texto e variáveis locais:
  ///  - Nome, sexo, activityLevel;
  ///  - Altura, peso atual, peso alvo;
  ///  - datas (nascimento + objetivo) em `_dobIso` / `_targetDateIso`
  ///    e respetivos campos de texto formatados.
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final u = await di.userRepo.currentUser();
      if (u == null) {
        // Se não houver sessão, apenas pára o loading.
        setState(() {
          _loading = false;
        });
        return;
      }

      // Lê goals existentes (se houver).
      final g = await di.goalsRepo.getByUser(u.id);

      setState(() {
        _nameCtrl.text = u.name ?? '';

        if (g != null) {
          _sex = g.sex;
          _activity = g.activityLevel;

          _heightCtrl.text = g.heightCm > 0 ? g.heightCm.toString() : '';

          _weightCtrl.text = g.currentWeightKg > 0
              ? g.currentWeightKg.toStringAsFixed(1)
              : '';

          _targetWeightCtrl.text = g.targetWeightKg > 0
              ? g.targetWeightKg.toStringAsFixed(1)
              : '';

          _dobIso = g.dateOfBirth;
          _dobCtrl.text =
              g.dateOfBirth == null ? '' : _fmtDate(g.dateOfBirth!);

          _targetDateIso = g.targetDate;
          _targetDateCtrl.text =
              g.targetDate == null ? '' : _fmtDate(g.targetDate!);
        } else {
          // Sem goals ainda → limpa campos para estado inicial.
          _sex = null;
          _activity = null;
          _heightCtrl.text = '';
          _weightCtrl.text = '';
          _targetWeightCtrl.text = '';
          _dobIso = null;
          _dobCtrl.text = '';
          _targetDateIso = null;
          _targetDateCtrl.text = '';
        }

        _loading = false;
      });
    } catch (_) {
      // Em caso de erro, apenas garante que o loading termina.
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE: construir UserGoalsModel e persistir
  // ---------------------------------------------------------------------------

  /// Valida o formulário, constrói um [UserGoalsModel] e chama `goalsRepo.upsert`.
  ///
  /// Comportamento:
  ///  - Não guarda o nome do utilizador neste método (mas podes ativar a
  ///    atualização no repositório de utilizador se tiveres suporte a isso);
  ///  - Deixa `dailyCalories` e percentagens de macros a `null` para serem
  ///    calculados noutro nível da app (por exemplo no repositório);
  ///  - Mostra `SnackBar` de sucesso e navega de volta para settings.
  Future<void> _save() async {
    if (_saving) return; // evita duplo clique
    if (!_form.currentState!.validate()) return; // form inválido → sai

    setState(() => _saving = true);

    try {
      final u = await di.userRepo.currentUser();
      if (u == null) throw Exception('Sem sessão');

      // helpers locais para parse
      int? toInt(String s) => int.tryParse(s.trim());
      double? toDouble(String s) =>
          double.tryParse(s.trim().replaceAll(',', '.'));

      final heightCm = toInt(_heightCtrl.text) ?? 0;
      final weightKg = toDouble(_weightCtrl.text) ?? 0.0;
      final targetKg = toDouble(_targetWeightCtrl.text) ?? 0.0;

      final goals = UserGoalsModel(
        userId: u.id,
        sex: _sex ?? 'OTHER',
        dateOfBirth: _dobIso,
        heightCm: heightCm,
        currentWeightKg: weightKg,
        targetWeightKg: targetKg,
        targetDate: _targetDateIso,
        activityLevel: _activity ?? 'sedentary',

        // Deixar a null para o backend ou repo recalcular:
        dailyCalories: null,
        carbPercent: null,
        proteinPercent: null,
        fatPercent: null,
      );

      // Persiste/metas no repositório.
      await di.goalsRepo.upsert(goals);

      // (opcional) atualizar nome do utilizador se quiseres:
      // Ex.: await di.userRepo.updateName(u.id, _nameCtrl.text);

      if (!mounted) return;
      _showSuccessToast();
      _goBackToSettings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha a guardar. Tenta novamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS DE UI (decorators / validações / navegação)
  // ---------------------------------------------------------------------------

  /// Decoração base usada na maioria dos campos de texto deste ecrã.
  InputDecoration _dec({
    required String label,
    String? hint,
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      suffixText: suffix,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.coolGray, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.coolGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.freshGreen, width: 2),
      ),
    );
  }

  /// Validação simples para campos numéricos obrigatórios (não vazios).
  String? _reqNum(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  /// Navega de volta ao ecrã de definições:
  ///  - Se houver algo na stack, faz pop;
  ///  - Caso contrário, faz `go('/settings')` como fallback.
  void _goBackToSettings() {
    if (Navigator.canPop(context)) {
      context.pop();
    } else {
      GoRouter.of(context).go('/settings'); // fallback
    }
  }

  /// Mostra uma snack de sucesso, com ícone **check** e cor principal do tema.
  void _showSuccessToast() {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.primary,
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'Dados guardados',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.softOffWhite,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _goBackToSettings,
        ),
        title: Text(
          'Editar informações',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),

      // Corpo principal: loader ou formulário com secções
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ===================== SECÇÃO UTILIZADOR =====================
                  const _Section('Utilizador'),
                  _ElevatedCard(
                    child: TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _dec(
                        label: 'Nome',
                        hint: 'ex.: João Silva',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ================== SECÇÃO BIOMETRIA & METAS =================
                  const _Section('Biometria & Metas'),
                  _ElevatedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ---------- Sexo ----------
                        Text(
                          'Sexo',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ChoiceChip(
                              label: 'Masculino',
                              selected: _sex == 'MALE',
                              onTap: () =>
                                  setState(() => _sex = 'MALE'),
                            ),
                            _ChoiceChip(
                              label: 'Feminino',
                              selected: _sex == 'FEMALE',
                              onTap: () =>
                                  setState(() => _sex = 'FEMALE'),
                            ),
                            _ChoiceChip(
                              label: 'Outro',
                              selected: _sex == 'OTHER',
                              onTap: () =>
                                  setState(() => _sex = 'OTHER'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ---------- Altura & Peso atual ----------
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _heightCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter
                                      .digitsOnly,
                                ],
                                decoration: _dec(
                                  label: 'Altura',
                                  suffix: 'cm',
                                ),
                                validator: _reqNum,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _weightCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d,\.]'),
                                  ),
                                ],
                                decoration: _dec(
                                  label: 'Peso atual',
                                  suffix: 'kg',
                                ),
                                validator: _reqNum,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ---------- Peso alvo & Data objetivo ----------
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _targetWeightCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d,\.]'),
                                  ),
                                ],
                                decoration: _dec(
                                  label: 'Peso alvo',
                                  suffix: 'kg',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _targetDateCtrl,
                                readOnly: true,
                                decoration: _dec(
                                  label: 'Data objetivo',
                                  hint: 'dd/mm/aaaa',
                                ),
                                onTap: () async {
                                  final picked = await _pickDate(
                                    initial: _targetDateIso ??
                                        DateTime.now().add(
                                          const Duration(days: 60),
                                        ),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _targetDateIso = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                      );
                                      _targetDateCtrl.text =
                                          _fmtDate(_targetDateIso!);
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ---------- Data de nascimento ----------
                        TextFormField(
                          controller: _dobCtrl,
                          readOnly: true,
                          decoration: _dec(
                            label: 'Data de nascimento',
                            hint: 'dd/mm/aaaa',
                          ),
                          onTap: () async {
                            final initial =
                                _dobIso ?? DateTime(2000, 1, 1);
                            final picked = await _pickDate(
                              initial: initial,
                              first: DateTime(1900),
                              last: DateTime(
                                DateTime.now().year,
                                12,
                                31,
                              ),
                            );
                            if (picked != null) {
                              setState(() {
                                _dobIso = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                                _dobCtrl.text = _fmtDate(_dobIso!);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // ---------- Nível de atividade ----------
                        Text(
                          'Nível de atividade',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        _ActivityDropdown(
                          value: _activity,
                          onChanged: (v) =>
                              setState(() => _activity = v),
                          items: _activityItems,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

      // -----------------------------------------------------------------------
      // Botão sticky (pill) para guardar alterações
      // -----------------------------------------------------------------------
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
              textStyle: tt.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Guardar'),
          ),
        ),
      ),
    );
  }
}

/* ================== helpers UI (widgets reutilizáveis) ================== */

/// Cabeçalho de secção grande (ex.: "Utilizador", "Biometria & Metas").
class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
      ),
    );
  }
}

/// Card com elevação suave usado para agrupar campos de edição.
class _ElevatedCard extends StatelessWidget {
  final Widget child;
  const _ElevatedCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSage,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 6),
            color: Color(0x14000000),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Chip “toggle” customizado para escolhas de sexo (Masculino/Feminino/Outro).
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    color: cs.primary.withValues(alpha: .25),
                  ),
                ]
              : const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, 4),
                    color: Color(0x11000000),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Dropdown para selecionar o nível de atividade diária.
class _ActivityDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final List<(String value, String label)> items;

  const _ActivityDropdown({
    required this.value,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          borderRadius: BorderRadius.circular(14),
          isExpanded: true,
          hint: const Text('Seleciona…'),
          items: [
            for (final (v, label) in items)
              DropdownMenuItem(value: v, child: Text(label)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
