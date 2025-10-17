// lib/features/settings/edit_user_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/di.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';

class EditUserScreen extends StatefulWidget {
  const EditUserScreen({super.key});
  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _form = GlobalKey<FormState>();

  // Perfil
  final _nameCtrl = TextEditingController();

  // UserGoals (onboarding-like)
  final _heightCtrl = TextEditingController();        // cm
  final _weightCtrl = TextEditingController();        // kg
  final _targetWeightCtrl = TextEditingController();  // kg
  final _dobCtrl = TextEditingController();           // dd/mm/aaaa (UI)
  final _targetDateCtrl = TextEditingController();    // dd/mm/aaaa (UI)

  String? _sex;      // 'MALE' | 'FEMALE' | 'OTHER'
  String? _activity; // 'sedentary'|'light'|'moderate'|'active'|'very_active'

  DateTime? _dobIso;
  DateTime? _targetDateIso;

  bool _loading = true;
  bool _saving = false;

  // ---- activity items (alinhados com o onboarding) ----
  static const List<(String value, String label)> _activityItems = [
    ('sedentary',  'Sedentário'),
    ('light',      'Pouca atividade'),
    ('moderate',   'Moderada'),
    ('active',     'Ativo'),
    ('very_active','Muito ativo'),
  ];

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

  // ------- helpers -------

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  Future<void> _loadData() async {
  setState(() => _loading = true);
  try {
    final u = await di.userRepo.currentUser();
    if (u == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    // ler goals
    final g = await di.goalsRepo.getByUser(u.id);

    setState(() {
      _nameCtrl.text = u.name ?? '';

      if (g != null) {
        _sex = g.sex;
        _activity = g.activityLevel;

        _heightCtrl.text =
            g.heightCm > 0 ? g.heightCm.toString() : '';

        _weightCtrl.text =
            g.currentWeightKg > 0 ? g.currentWeightKg.toStringAsFixed(1) : '';

        _targetWeightCtrl.text =
            g.targetWeightKg > 0 ? g.targetWeightKg.toStringAsFixed(1) : '';

        _dobIso = g.dateOfBirth;
        _dobCtrl.text = g.dateOfBirth == null ? '' : _fmtDate(g.dateOfBirth!);

        _targetDateIso = g.targetDate;
        _targetDateCtrl.text =
            g.targetDate == null ? '' : _fmtDate(g.targetDate!);
      } else {
        // vazio por omissão
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
    setState(() => _loading = false);
  }
}

Future<void> _save() async {
  if (_saving) return;
  if (!_form.currentState!.validate()) return;

  setState(() => _saving = true);

  try {
    final u = await di.userRepo.currentUser();
    if (u == null) throw Exception('Sem sessão');

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
      // deixa null para forçar cálculo no repo (ou calcula já aqui se preferires)
      dailyCalories: null,
      carbPercent: null,
      proteinPercent: null,
      fatPercent: null,
    );

    await di.goalsRepo.upsert(goals);

    // (opcional) atualizar nome do utilizador se quiseres (tens repo p/ isso?)
    // Ex.: await di.userRepo.updateName(u.id, _nameCtrl.text);

    if (!mounted) return;
    _showSuccessToast();
    _goBackToSettings();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Falha a guardar. Tenta novamente.')),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}


  // ---------- UI bits ----------
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.coolGray, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.coolGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.freshGreen, width: 2),
      ),
    );
  }

  String? _reqNum(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  void _goBackToSettings() {
    if (Navigator.canPop(context)) {
      context.pop();
    } else {
      GoRouter.of(context).go('/settings'); // fallback
    }
  }

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
            Text('Dados guardados', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }


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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ===== Utilizador =====
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

                  // ===== Biometria & Metas =====
                  const _Section('Biometria & Metas'),
                  _ElevatedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sexo
                        Text('Sexo', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ChoiceChip(
                              label: 'Masculino',
                              selected: _sex == 'MALE',
                              onTap: () => setState(() => _sex = 'MALE'),
                            ),
                            _ChoiceChip(
                              label: 'Feminino',
                              selected: _sex == 'FEMALE',
                              onTap: () => setState(() => _sex = 'FEMALE'),
                            ),
                            _ChoiceChip(
                              label: 'Outro',
                              selected: _sex == 'OTHER',
                              onTap: () => setState(() => _sex = 'OTHER'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Altura & Peso atual
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _heightCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: _dec(label: 'Altura', suffix: 'cm'),
                                validator: _reqNum,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _weightCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]')),
                                ],
                                decoration: _dec(label: 'Peso atual', suffix: 'kg'),
                                validator: _reqNum,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Peso alvo & Data alvo
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _targetWeightCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]')),
                                ],
                                decoration: _dec(label: 'Peso alvo', suffix: 'kg'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _targetDateCtrl,
                                readOnly: true,
                                decoration: _dec(label: 'Data objetivo', hint: 'dd/mm/aaaa'),
                                onTap: () async {
                                  final picked = await _pickDate(
                                    initial: _targetDateIso ?? DateTime.now().add(const Duration(days: 60)),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _targetDateIso = DateTime(picked.year, picked.month, picked.day);
                                      _targetDateCtrl.text = _fmtDate(_targetDateIso!);
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Data de nascimento
                        TextFormField(
                          controller: _dobCtrl,
                          readOnly: true,
                          decoration: _dec(label: 'Data de nascimento', hint: 'dd/mm/aaaa'),
                          onTap: () async {
                            final initial = _dobIso ?? DateTime(2000, 1, 1);
                            final picked = await _pickDate(
                              initial: initial,
                              first: DateTime(1900),
                              last: DateTime(DateTime.now().year, 12, 31),
                            );
                            if (picked != null) {
                              setState(() {
                                _dobIso = DateTime(picked.year, picked.month, picked.day);
                                _dobCtrl.text = _fmtDate(_dobIso!);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Nível de atividade
                        Text('Nível de atividade', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        _ActivityDropdown(
                          value: _activity,
                          onChanged: (v) => setState(() => _activity = v),
                          items: _activityItems,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      // Botão sticky (pill)
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
              textStyle: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar'),
          ),
        ),
      ),
    );
  }
}

/* ================== helpers UI ================== */

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

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ChoiceChip({required this.label, required this.selected, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          boxShadow: selected
              ? [BoxShadow(blurRadius: 10, offset: const Offset(0, 4), color: cs.primary.withValues(alpha: .25))]
              : const [BoxShadow(blurRadius: 8, offset: Offset(0, 4), color: Color(0x11000000))],
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

class _ActivityDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final List<(String value, String label)> items;
  const _ActivityDropdown({required this.value, required this.onChanged, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
