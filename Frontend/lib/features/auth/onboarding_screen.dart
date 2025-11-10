// lib/features/auth/onboarding_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/di.dart';
import '../../domain/models.dart';

/// NutriScore — Onboarding do Utilizador
///
/// Este ecrã implementa o fluxo de **onboarding guiado** do NutriScore.
/// A ideia é que, logo após o registo, o utilizador preencha um pequeno
/// questionário com os dados mínimos necessários para:
///
/// - compreender o seu contexto físico atual (idade, peso, altura);
/// - perceber qual é o objetivo (peso alvo e, opcionalmente, data alvo);
/// - estimar o nível de atividade física;
/// - configurar os primeiros objetivos diários (através de `UserGoalsModel`).
///
/// Características principais:
/// - Fluxo em formato *wizard*, dividido em passos sequenciais;
/// - Navegação controlada via `PageView` **sem scroll manual** (passos são
///   avançados apenas pelos botões/ações do ecrã);
/// - Validação simples em cada passo, com feedback imediato via `SnackBar`;
/// - Persistência dos dados no repositório de objetivos (`goalsRepo`);
/// - Redireção automática para o dashboard (`/dashboard`) no final.
///
/// Este ecrã assume que:
/// - Apenas é apresentado enquanto o utilizador ainda não completou o
///   onboarding (regra garantida pelo router/guardas);
/// - A marcação de “onboarding concluído” é tratada externamente (por ex.
///   na tabela de utilizadores em `drift`), depois de o fluxo ser concluído.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Enumeração interna que representa cada passo do fluxo.
///
/// A principal função desta enum é:
/// - simplificar a navegação (avançar/recuar) sem depender de índices mágicos;
/// - permitir saber rapidamente qual é o conteúdo que deve ser apresentado;
/// - servir de base para o indicador de progresso segmentado.
enum _Step {
  /// Passo 0 — seleção de género.
  gender,

  /// Passo 1 — seleção da data de nascimento.
  birthdate,

  /// Passo 2 — introdução do peso atual.
  weight,

  /// Passo 3 — introdução do peso alvo.
  targetWeight,

  /// Passo 4 — introdução da data alvo (opcional).
  targetDate,

  /// Passo 5 — introdução da altura.
  height,

  /// Passo 6 — seleção do nível de atividade física.
  activity,

  /// Passo 7 — passo final (mensagem "Tudo pronto" / estado de submissão).
  done,
}

/// Estado do ecrã de onboarding.
///
/// Responsável por:
/// - gerir o `PageController` do `PageView` que apresenta os passos;
/// - manter os valores escolhidos pelo utilizador em memória;
/// - aplicar regras de validação específicas em cada passo;
/// - orquestrar a submissão final e navegação para o dashboard.
///
/// Nota: as variáveis privadas seguem a convenção `_nome`, pois não são
/// usadas fora deste ecrã.
class _OnboardingScreenState extends State<OnboardingScreen> {
  // ---------------------------------------------------------------------------
  // Controladores e estado de navegação
  // ---------------------------------------------------------------------------

  /// Controla a página atual do fluxo de onboarding.
  ///
  /// - É partilhado com o `PageView`;
  /// - Nunca permite scroll manual (a navegação é bloqueada ao utilizador);
  /// - É atualizado por `_goNext()` e `_goBack()`.
  final PageController _page = PageController();

  /// Passo atual do fluxo de onboarding.
  ///
  /// Este valor é:
  /// - utilizado para decidir que ecrã mostrar na `PageView`;
  /// - usado no indicador de progresso segmentado (`_SegmentedProgress`);
  /// - atualizado sempre que o utilizador avança ou recua no fluxo.
  _Step _current = _Step.gender;

  // ---------------------------------------------------------------------------
  // Campos de perfil: género, data de nascimento
  // ---------------------------------------------------------------------------

  /// Género selecionado pelo utilizador.
  ///
  /// Valores esperados (compatíveis com o modelo e/ou backend):
  /// - `"MALE"`
  /// - `"FEMALE"`
  /// - `"OTHER"`
  ///
  /// No UI, isto é apresentado como *chips* amigáveis (Masculino, Feminino,
  /// Outro), mas internamente guardamos só o código.
  String? _gender;

  /// Data de nascimento selecionada.
  ///
  /// Representa apenas a componente de data (ano/mês/dia), sem preocupação
  /// com horas/minutos/segundos. É usada para estimar idade e, por exemplo,
  /// apoiar o cálculo de metabolismo basal.
  DateTime? _dob;

  /// Controlador de texto associado ao campo de data de nascimento.
  ///
  /// Este campo:
  /// - não é editável diretamente (é apenas para mostrar a data formatada);
  /// - é atualizado quando o utilizador escolhe uma data via `_pickBirthdate()`.
  final _dobCtrl = TextEditingController();

  // ---------------------------------------------------------------------------
  // Campos de peso, altura, alvo e data alvo
  // ---------------------------------------------------------------------------

  /// Campo de texto que guarda o peso atual do utilizador, em quilogramas.
  ///
  /// O valor é mantido como `String` até ao momento da validação/conversão
  /// (onde usamos `double.parse` ou `double.tryParse`).
  final _weight = TextEditingController();

  /// Campo de texto para o peso alvo do utilizador, em quilogramas.
  ///
  /// Ajuda a definir o objetivo de perda/ganho de peso.
  final _targetWeight = TextEditingController();

  /// Campo de texto para a altura do utilizador, em centímetros.
  ///
  /// Exemplo: `"178"`.
  final _height = TextEditingController();

  /// Data alvo para alcançar o peso pretendido (opcional).
  ///
  /// - Se for `null`, o utilizador não quis definir um prazo específico;
  /// - Se tiver valor, é usada na lógica de planeamento (fora deste ficheiro).
  DateTime? _targetDate;

  /// Controlador de texto para exibir a data alvo formatada no campo.
  final _targetDateCtrl = TextEditingController();

  // ---------------------------------------------------------------------------
  // Atividade física e estado de submissão
  // ---------------------------------------------------------------------------

  /// Nível de atividade física do utilizador.
  ///
  /// Valores possíveis (códigos técnicos):
  /// - `"sedentary"`
  /// - `"light"`
  /// - `"moderate"`
  /// - `"active"`
  /// - `"very_active"`
  ///
  /// Estes códigos são tipicamente usados em fórmulas de gasto calórico.
  String? _activity;

  /// Flag que indica se estamos a fazer a submissão final do onboarding.
  ///
  /// Enquanto `_submitting` for `true`:
  /// - a navegação (tanto back como cancel) é bloqueada;
  /// - o passo final mostra uma animação/texto de "A preparar o teu dashboard".
  bool _submitting = false;

  /// Lista estática de opções de atividade física.
  ///
  /// Cada entrada é um par:
  /// - valor interno (para lógica/armazenamento);
  /// - etiqueta legível em PT-PT para mostrar no `DropdownButtonFormField`.
  static const _activities = <(String, String)>[
    ('sedentary', 'Sedentário (pouco/no exercício)'),
    ('light', 'Leve (1–3x/semana)'),
    ('moderate', 'Moderado (3–5x/semana)'),
    ('active', 'Ativo (6–7x/semana)'),
    ('very_active', 'Muito ativo (treino intenso)'),
  ];

  // ---------------------------------------------------------------------------
  // Ciclo de vida do State
  // ---------------------------------------------------------------------------

  /// Liberta recursos associados a controladores (PageController, TextEditing).
  ///
  /// Este método é chamado automaticamente quando o widget é removido da
  /// árvore de widgets do Flutter. Evita fugas de memória e avisos de debug.
  @override
  void dispose() {
    _page.dispose();
    _dobCtrl.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    _height.dispose();
    _targetDateCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Fluxo de cancelamento no 1º passo (apenas navegação UI)
  // ---------------------------------------------------------------------------

  /// Cancela o onboarding e volta ao Hub (`'/'`).
  ///
  /// Fluxo esperado:
  /// 1. Se `_submitting` for `true`, não faz nada (não queremos interromper);
  /// 2. Tenta apagar a conta local ou terminar sessão via `di.userRepo`;
  /// 3. Ignora qualquer erro nessa operação (para não bloquear a saída);
  /// 4. Se o widget ainda estiver montado, chama `context.go('/')`.
  ///
  /// É usado, por exemplo, quando o utilizador está no primeiro passo e
  /// pressiona "voltar" ou o botão de cancelar.
  Future<void> _cancelAndExit() async {
    if (_submitting) return;
    try {
      await di.userRepo.deleteAccount(); // ou: await di.userRepo.signOut();
    } catch (_) {
      // Erros aqui são silenciosos de propósito: prioridade é sair.
    }
    if (!mounted) return;
    context.go('/'); // volta ao Hub (AuthHubScreen)
  }

  // ---------------------------------------------------------------------------
  // Navegação entre passos (lógica de wizard)
  // ---------------------------------------------------------------------------

  /// Índice numérico correspondente ao passo atual.
  ///
  /// Baseado na ordem definida em `_Step.values`.
  int get _index => _current.index;

  /// Número total de segmentos usados pelo indicador de progresso.
  ///
  /// Repare que usamos `index` de `_Step.done` como "comprimento" do wizard,
  /// porque o passo `done` é o estado terminal (não conta como segmento extra).
  int get _total => _Step.done.index;

  /// Avança para o próximo passo do onboarding.
  ///
  /// - Primeiro valida o passo atual usando `_validateStep()`;
  /// - Se a validação falhar, não avança e mostra um `SnackBar`;
  /// - Se o passo atual for o de atividade (`_Step.activity`):
  ///   - atualiza o estado para `_Step.done`;
  ///   - avança a página com uma animação mais longa;
  ///   - chama `_finishAndGo()` para gravar dados e ir para o dashboard;
  /// - Nos restantes casos:
  ///   - apenas incrementa o passo na enum e avança uma página no `PageView`.
  void _goNext() async {
    // Não deixamos avançar se o passo atual estiver inválido.
    if (!_validateStep()) return;

    // Se estamos no passo de atividade, o próximo é o fim do fluxo.
    if (_current == _Step.activity) {
      setState(() => _current = _Step.done);

      // Animação um pouco mais suave/demorada para a transição final.
      _page.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );

      // Inicia submissão e navegação final.
      await _finishAndGo();
      return;
    }

    // Caso geral: avança para o passo seguinte na enum.
    setState(() => _current = _Step.values[_index + 1]);

    // Animação padrão para a transição de página entre passos intermédios.
    _page.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// Volta ao passo anterior ou cancela o onboarding, conforme o contexto.
  ///
  /// Casos tratados:
  /// - Se o passo atual é `gender` (primeiro passo):
  ///   - Em vez de recuar (não há passo anterior), chama `_cancelAndExit()`;
  /// - Se o passo atual é `done`:
  ///   - Se `_submitting` for `true`, não faz nada (evita inconsistências);
  ///   - Caso contrário, volta ao passo `activity` e recua uma página;
  /// - Em qualquer outro passo:
  ///   - decrementa o índice na enum e recua uma página no `PageView`.
  void _goBack() {
    // Primeiro passo: não há onde recuar, por isso cancelamos o onboarding.
    if (_current == _Step.gender) {
      _cancelAndExit();
      return;
    }

    // Passo final: podemos voltar ao passo de atividade, se não estivermos a submeter.
    if (_current == _Step.done) {
      if (_submitting) return;
      setState(() => _current = _Step.activity);
      _page.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Caso geral: recua um passo na enumeração e no PageView.
    setState(() => _current = _Step.values[_index - 1]);
    _page.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------------------------------------------------------------------------
  // Validação dos passos
  // ---------------------------------------------------------------------------

  /// Valida o conteúdo do passo atual e mostra mensagens de erro via `SnackBar`.
  ///
  /// Este método centraliza toda a validação do wizard, passo a passo:
  ///
  /// - Género:
  ///   - tem de estar selecionado;
  /// - Data de nascimento:
  ///   - tem de estar preenchida;
  ///   - idade resultante tem de estar entre 10 e 120 anos;
  /// - Peso atual:
  ///   - tem de ser um número entre 25 e 400 kg;
  /// - Peso alvo:
  ///   - tem de ser um número entre 25 e 400 kg;
  /// - Data alvo:
  ///   - pode ser vazia;
  ///   - se existir, tem de ser entre amanhã e 2 anos no futuro;
  /// - Altura:
  ///   - tem de ser um inteiro entre 90 e 250 cm;
  /// - Atividade:
  ///   - tem de estar selecionada;
  /// - Passo `done`:
  ///   - é sempre considerado válido.
  ///
  /// Retorna:
  /// - `true` se o passo atual passar nas validações;
  /// - `false` se falhar (e nesse caso o fluxo não avança).
  bool _validateStep() {
    final snack = ScaffoldMessenger.of(context);

    switch (_current) {
      // ---------------- GÉNERO ----------------
      case _Step.gender:
        if (_gender == null) {
          snack.showSnackBar(
            const SnackBar(content: Text('Escolhe o teu género.')),
          );
          return false;
        }
        return true;

      // ---------------- DATA DE NASCIMENTO ----------------
      case _Step.birthdate:
        if (_dob == null) {
          snack.showSnackBar(
            const SnackBar(content: Text('Escolhe a tua data de nascimento.')),
          );
          return false;
        }

        // Calcula limites aceitáveis de idade (entre 10 e 120 anos).
        final now = DateTime.now();
        final minDate = DateTime(now.year - 120, now.month, now.day);
        final maxDate = DateTime(now.year - 10, now.month, now.day);

        // Se a data de nascimento estiver fora deste intervalo, é inválida.
        if (_dob!.isBefore(minDate) || _dob!.isAfter(maxDate)) {
          snack.showSnackBar(
            const SnackBar(
              content: Text('Indica uma data de nascimento válida.'),
            ),
          );
          return false;
        }
        return true;

      // ---------------- PESO ATUAL ----------------
      case _Step.weight:
        // Troca vírgulas por pontos para aceitar ambos os formatos.
        final w = double.tryParse(_weight.text.replaceAll(',', '.'));

        // Validação de range (25–400 kg) para evitar valores absurdos.
        if (w == null || w < 25 || w > 400) {
          snack.showSnackBar(
            const SnackBar(content: Text('Indica um peso válido (kg).')),
          );
          return false;
        }
        return true;

      // ---------------- PESO ALVO ----------------
      case _Step.targetWeight:
        final tw = double.tryParse(_targetWeight.text.replaceAll(',', '.'));
        if (tw == null || tw < 25 || tw > 400) {
          snack.showSnackBar(
            const SnackBar(content: Text('Define um peso alvo válido (kg).')),
          );
          return false;
        }
        return true;

      // ---------------- DATA ALVO (OPCIONAL) ----------------
      case _Step.targetDate:
        // Se o utilizador não definiu nenhuma data, não bloqueamos o fluxo.
        if (_targetDate == null) return true;

        final now = DateTime.now();

        // A data alvo tem de ser no mínimo amanhã.
        final earliest = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1)); // amanhã

        // E no máximo 2 anos à frente, para evitar objetivos muito longos.
        final latest = DateTime(now.year + 2, now.month, now.day); // até 2 anos

        // Se a data estiver fora do intervalo permitido, consideramos inválido.
        if (_targetDate!.isBefore(earliest) || _targetDate!.isAfter(latest)) {
          snack.showSnackBar(
            const SnackBar(
              content: Text('Escolhe uma data futura (até 2 anos).'),
            ),
          );
          return false;
        }
        return true;

      // ---------------- ALTURA ----------------
      case _Step.height:
        final h = int.tryParse(_height.text);

        // Validamos apenas alturas numéricas plausíveis para um adulto.
        if (h == null || h < 90 || h > 250) {
          snack.showSnackBar(
            const SnackBar(content: Text('Indica uma altura válida (cm).')),
          );
          return false;
        }
        return true;

      // ---------------- ATIVIDADE FÍSICA ----------------
      case _Step.activity:
        if (_activity == null) {
          snack.showSnackBar(
            const SnackBar(
              content: Text('Seleciona o teu nível de atividade.'),
            ),
          );
          return false;
        }
        return true;

      // ---------------- PASSO FINAL ----------------
      case _Step.done:
        // Passo de confirmação/submissão: já não há validação aqui.
        return true;
    }
  }

  // ---------------------------------------------------------------------------
  // Submissão final e navegação para o dashboard
  // ---------------------------------------------------------------------------

  /// Conclui o onboarding, grava os objetivos e entra no dashboard.
  ///
  /// Este método é chamado automaticamente quando o utilizador chega ao
  /// passo `done` a partir do passo de atividade.
  ///
  /// Fluxo de alto nível:
  /// 1. Garante que não está já a submeter (evita duplicações);
  /// 2. Lê o utilizador atual via `di.userRepo.currentUser()`;
  /// 3. Se existir utilizador:
  ///    - normaliza todos os campos do formulário;
  ///    - constrói um `UserGoalsModel` com esses dados;
  ///    - grava/atualiza os objetivos via `di.goalsRepo.upsert(goals)`;
  /// 4. Ignora erros silenciosamente (não impede a entrada no dashboard);
  /// 5. Espera um pequeno *delay* apenas para que o UI mostre o estado de
  ///    "a preparar o dashboard";
  /// 6. Navega para `/dashboard`, se o widget ainda estiver montado.
  Future<void> _finishAndGo() async {
    // Se já estiver em submissão, não voltamos a fazer nada.
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      // Obtém o utilizador atual a partir do repositório.
      final u = await di.userRepo.currentUser();

      if (u != null) {
        // Normaliza campos vindos do UI
        // (é aqui que convertemos Strings em números/enum-like).
        final sex = _gender ?? 'OTHER';
        final dob = _dob; // já é DateTime (apenas data)
        final heightCm = int.parse(_height.text);
        final currentKg = double.parse(_weight.text.replaceAll(',', '.'));
        final targetKg = double.parse(_targetWeight.text.replaceAll(',', '.'));
        final targetDate = _targetDate;
        final activity = _activity ?? 'sedentary';

        // (Opcional) Poderíamos calcular calorias/macros aqui com base
        // nos dados acima e preencher `dailyCalories`, `carbPercent`, etc.
        final goals = UserGoalsModel(
          userId: u.id,
          sex: sex,
          dateOfBirth: dob,
          heightCm: heightCm,
          currentWeightKg: currentKg,
          targetWeightKg: targetKg,
          targetDate: targetDate,
          activityLevel: activity,
          dailyCalories: null, // se quiseres calcular, mete valor
          carbPercent: null,
          proteinPercent: null,
          fatPercent: null,
        );

        // Grava ou atualiza os objetivos do utilizador.
        await di.goalsRepo.upsert(goals);
      }
    } catch (_) {
      // Se der erro, seguimos para o dashboard na mesma, para não bloquear
      // a experiência do utilizador. Logs podem ser feitos noutro nível.
    }

    // Pequeno atraso para o utilizador ver o estado de "a preparar dashboard".
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    // Entra no dashboard principal do NutriScore.
    context.go('/dashboard');
  }

  // ---------------------------------------------------------------------------
  // Construção do UI principal (Scaffold, AppBar, PageView, ações)
  // ---------------------------------------------------------------------------

  /// Constrói todo o layout do ecrã de onboarding.
  ///
  /// Elementos principais:
  /// - `PopScope` para sobrepor o comportamento de "back" do sistema;
  /// - `AppBar` sem botão de back padrão (usa ação customizada para cancelar);
  /// - indicador de progresso segmentado na parte superior;
  /// - cartão central com sombras e cantos arredondados que contém o wizard;
  /// - `PageView` com os diferentes passos (sem scroll por gesto);
  /// - barra inferior com botões "Voltar" e "Continuar/Concluir".
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Impede o pop automático do sistema. O fluxo de saída é controlado
      // manualmente por `_cancelAndExit` ou pela lógica aqui no callback.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        // Se o sistema já tratou o pop, não fazemos mais nada.
        if (didPop) return;

        // Se não estamos a submeter, podemos enviar o utilizador de volta ao Hub.
        if (!_submitting) {
          final router = GoRouter.of(context); // captura síncrona, evita lint
          router.go('/'); // vai para o Hub (ecrã inicial de auth)
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Completar perfil'),
          automaticallyImplyLeading: false, // removemos o botão de back padrão
          backgroundColor: cs.surface,
          surfaceTintColor: cs.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            // Este botão atua como um "cancelar onboarding".
            onPressed: _submitting
                ? null
                : () async {
                    final ctx = context; // captura síncrona do contexto
                    await di.userRepo.deleteAccount();

                    // Certifica-te que ainda estamos montados antes de navegar.
                    if (!ctx.mounted) return;
                    ctx.go('/'); // go_router extension
                  },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Indicador de progresso em segmentos (topo do cartão).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _SegmentedProgress(currentIndex: _index, total: _total),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    // Limitamos a largura máxima para melhor legibilidade
                    // em ecrãs largos (ex.: tablet).
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 10,
                              offset: Offset(0, 4),
                              color: Color(0x14000000),
                            ),
                          ],
                          border: Border.all(
                            color: cs.outline.withValues(alpha: .25),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Conteúdo principal: cada passo do onboarding.
                              Expanded(
                                child: PageView(
                                  controller: _page,
                                  // Não permitimos scroll horizontal pelo dedo
                                  // para garantir que a navegação obedece às
                                  // validações.
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: [
                                    _buildGenderStep(context),
                                    _buildBirthdateStep(context),
                                    _buildWeightStep(context),
                                    _buildTargetWeightStep(context),
                                    _buildTargetDateStep(context),
                                    _buildHeightStep(context),
                                    _buildActivityStep(context),
                                    _buildDoneStep(context),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Zona de ações (botão Voltar e Continuar/Concluir).
                              Row(
                                children: [
                                  // Botão "Voltar" só é mostrado em passos intermédios.
                                  if (_current != _Step.gender &&
                                      _current != _Step.done)
                                    OutlinedButton(
                                      onPressed: _goBack,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: cs.primary,
                                        side: BorderSide(color: cs.primary),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('Voltar'),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  const Spacer(),
                                  // Botão "Continuar" ou "Concluir" (não aparece no passo final).
                                  if (_current != _Step.done)
                                    FilledButton(
                                      onPressed: _goNext,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: cs.primary,
                                        foregroundColor: cs.onPrimary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 14,
                                        ),
                                      ),
                                      child: Text(
                                        _current == _Step.activity
                                            ? 'Concluir'
                                            : 'Continuar',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers de datas e pickers
  // ---------------------------------------------------------------------------

  /// Formata uma instância de `DateTime` para a string `DD/MM/AAAA`.
  ///
  /// - Usa `padLeft(2, '0')` para garantir sempre dois dígitos no dia e mês;
  /// - Ignora componentes de hora/minutos/segundos.
  String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  }

  /// Abre o `showDatePicker` para o utilizador escolher a data de nascimento.
  ///
  /// Comportamento:
  /// - O intervalo de datas permitidas é entre 10 e 120 anos atrás;
  /// - A data inicial sugerida é:
  ///   - a data já selecionada (`_dob`), se existir;
  ///   - ou 25 anos atrás, como "default" razoável;
  /// - Se o utilizador confirmar uma data:
  ///   - atualizamos `_dob` com a data escolhida (só ano/mês/dia);
  ///   - atualizamos `_dobCtrl.text` com a data formatada.
  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 120, now.month, now.day);
    final last = DateTime(now.year - 10, now.month, now.day);

    // Data inicial que vamos sugerir ao picker:
    // se já houver `_dob`, usamos essa; caso contrário, 25 anos atrás.
    final initial = _dob != null
        ? _dob!
        : DateTime(now.year - 25, now.month, now.day); // default ~25 anos

    final picked = await showDatePicker(
      context: context,
      // Se a data inicial estiver fora dos limites, forçamos para o limite
      // mais próximo (ex.: se for demasiado antiga, usamos `last`).
      initialDate: initial.isBefore(first) || initial.isAfter(last)
          ? last
          : initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Seleciona a tua data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );

    // Se o utilizador cancelar, não fazemos mais nada.
    if (picked != null) {
      setState(() {
        // Guardamos só ano/mês/dia (sem horas).
        _dob = DateTime(picked.year, picked.month, picked.day);
        _dobCtrl.text = _formatDate(_dob!);
      });
    }
  }

  /// Abre o `showDatePicker` para escolher a data alvo (opcional).
  ///
  /// Regras:
  /// - mínimo: amanhã (não faz sentido uma data passada);
  /// - máximo: 2 anos a partir de hoje;
  /// - data inicial sugerida:
  ///   - se já existir `_targetDate`, usamos essa;
  ///   - caso contrário, sugerimos daqui a ~90 dias (~3 meses).
  ///
  /// Se o utilizador escolher uma data:
  /// - guardamos em `_targetDate` (só ano/mês/dia);
  /// - atualizamos `_targetDateCtrl.text`.
  ///
  /// Se cancelar (null), mantemos o valor anterior.
  Future<void> _pickTargetDate() async {
    final now = DateTime.now();

    // Primeiro dia permitido: amanhã.
    final first = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));

    // Último dia permitido: daqui a 2 anos.
    final last = DateTime(now.year + 2, now.month, now.day);

    // Sugestão inicial:
    // - se já houver `_targetDate`, usamos essa;
    // - caso contrário, +90 dias (3 meses).
    final initial = _targetDate != null
        ? _targetDate!
        : DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 90)); // sugestão: ~3 meses

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) || initial.isAfter(last)
          ? first
          : initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Quando queres atingir o teu peso alvo? (opcional)',
      cancelText: 'Limpar',
      confirmText: 'OK',
    );

    // Se o utilizador clicou em "Limpar" ou cancelou, não alteramos nada.
    if (picked == null) {
      return;
    }

    setState(() {
      _targetDate = DateTime(picked.year, picked.month, picked.day);
      _targetDateCtrl.text = _formatDate(_targetDate!);
    });
  }

  // ---------------------------------------------------------------------------
  // Construção de cada passo do wizard (UI)
  // ---------------------------------------------------------------------------

  /// Passo 1 — Seleção de género.
  ///
  /// Mostra três chips:
  /// - Masculino;
  /// - Feminino;
  /// - Outro.
  ///
  /// A seleção é guardada em `_gender` como código `"MALE"`, `"FEMALE"` ou
  /// `"OTHER"`. Abaixo das opções, é apresentada uma pequena explicação
  /// de utilização dos dados.
  Widget _buildGenderStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Lista local de opções (código, label, ícone).
    final chips = [
      ('MALE', 'Masculino', Icons.male_rounded),
      ('FEMALE', 'Feminino', Icons.female_rounded),
      ('OTHER', 'Outro', Icons.transgender_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é o teu género?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in chips)
              _SelectableChip(
                selected: _gender == c.$1,
                label: c.$2,
                icon: c.$3,
                onTap: () => setState(() => _gender = c.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Usamos isto apenas para calcular necessidades energéticas.',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 2 — Data de nascimento.
  ///
  /// Mostra:
  /// - título explicativo;
  /// - um campo de texto não editável, com ícone de calendário;
  /// - ao clicar no campo, abre `_pickBirthdate()` com o `showDatePicker`.
  ///
  /// A data selecionada é mostrada em formato `DD/MM/AAAA`.
  Widget _buildBirthdateStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é a tua data de nascimento?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dobCtrl,
          readOnly: true,
          onTap: _pickBirthdate,
          decoration: InputDecoration(
            labelText: 'Data de nascimento',
            hintText: 'DD/MM/AAAA',
            suffixIcon: const Icon(Icons.calendar_today_rounded),
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Isto ajuda a estimar o teu metabolismo basal.',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 3 — Peso atual.
  ///
  /// Campo de texto numérico com:
  /// - teclado numérico com suporte a decimais;
  /// - `inputFormatters` que aceitam dígitos, vírgula e ponto;
  /// - sufixo "kg" para deixar claro a unidade;
  /// - pequena ajuda textual com exemplo.
  Widget _buildWeightStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é o teu peso?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
          ],
          decoration: InputDecoration(
            labelText: 'Peso (kg)',
            suffixText: 'kg',
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Apenas números. Ex.: 72.5',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 4 — Peso alvo.
  ///
  /// Estrutura idêntica ao passo de peso atual, mas com label "Peso alvo".
  /// Ajuda o utilizador a definir um objetivo concreto de peso.
  Widget _buildTargetWeightStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é o teu peso alvo?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _targetWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]')),
          ],
          decoration: InputDecoration(
            labelText: 'Peso alvo (kg)',
            suffixText: 'kg',
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Define um objetivo realista. Ex.: 68.0',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 5 — Data alvo (opcional).
  ///
  /// Permite ao utilizador definir um prazo para atingir o peso objetivo.
  /// O campo é apenas de leitura e abre o `showDatePicker` ao toque.
  Widget _buildTargetDateStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quando queres atingir esse peso? (opcional)',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _targetDateCtrl,
          readOnly: true,
          onTap: _pickTargetDate,
          decoration: InputDecoration(
            labelText: 'Data alvo',
            hintText: 'DD/MM/AAAA',
            suffixIcon: const Icon(Icons.event_rounded),
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Se não escolheres, usamos só o peso alvo (podes definir a data mais tarde).',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 6 — Altura.
  ///
  /// Campo numérico simples para a altura, em centímetros.
  /// Exemplo de input válido: `178`.
  Widget _buildHeightStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é a tua altura?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _height,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Altura (cm)',
            suffixText: 'cm',
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ex.: 178',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 7 — Nível de atividade física.
  ///
  /// Apresenta um `DropdownButtonFormField` com as opções de `_activities`,
  /// permitindo ao utilizador escolher aquela que melhor reflete a sua
  /// rotina semanal típica.
  Widget _buildActivityStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qual é o teu nível de atividade?',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _activity,
          items: _activities
              .map(
                (a) => DropdownMenuItem<String>(
                  value: a.$1,
                  child: Text(a.$2),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _activity = v),
          decoration: InputDecoration(
            labelText: 'Seleciona uma opção',
            filled: true,
            fillColor: cs.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: .50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Isto ajuda a estimar as calorias diárias recomendadas.',
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }

  /// Passo 8 — Ecrã final.
  ///
  /// Mostra:
  /// - enquanto `_submitting` for `false`: mensagem "Tudo pronto!";
  /// - enquanto `_submitting` for `true`: mensagem "Obrigado por te registares"
  ///   e "A preparar o teu dashboard…".
  ///
  /// Usa `AnimatedSwitcher` para uma transição suave entre os dois estados.
  Widget _buildDoneStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _submitting
            ? Column(
                key: const ValueKey('submitting'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Obrigado por te registares! 🎉',
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A preparar o teu dashboard…',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              )
            : Column(
                key: const ValueKey('ready'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    size: 64,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tudo pronto! 🎯',
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vamos configurar o teu plano diário…',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ============================================================================
// Widgets de UI auxiliares
// ============================================================================

/// Indicador de progresso segmentado para o fluxo de onboarding.
///
/// Em vez de usar uma barra de progresso contínua, este widget mostra vários
/// segmentos horizontais. Cada segmento representa um passo do fluxo.
///
/// - Os segmentos até ao índice atual (inclusive) aparecem preenchidos com
///   a cor principal da interface (`colorScheme.primary`);
/// - Os restantes aparecem com uma cor neutra/atenuada;
/// - Quando um segmento se torna ativo, é aplicada uma sombra leve para dar
///   feedback visual adicional (efeito de "brilho").
class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({
    required this.currentIndex,
    required this.total,
  });

  /// Índice do passo atual (segmento ativo).
  ///
  /// Valor esperado: entre `0` e `total - 1`.
  final int currentIndex;

  /// Número total de segmentos exibidos (normalmente igual ao número
  /// de passos "úteis", excluindo o passo `done`).
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;

        // Calcula a largura de cada segmento de forma a ocupar toda a
        // largura disponível, descontando o espaço entre eles.
        final segWidth = (c.maxWidth - gap * (total - 1)) / total;

        return Row(
          children: List.generate(total, (i) {
            // Consideramos um segmento ativo se o seu índice for menor ou
            // igual ao índice atual. O passo `done` não entra aqui, porque
            // `total` costuma ser `_Step.done.index`.
            final active = i <= currentIndex && currentIndex < total;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: segWidth,
              height: 10,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : gap),
              decoration: BoxDecoration(
                color: active
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: .35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Chip selecionável genérico com estado visual.
///
/// Este widget é usado, por exemplo, no passo de género, mas é suficientemente
/// genérico para ser reutilizado noutros contextos.
///
/// Características:
/// - Tem um estado visual "ativo" (selecionado) e "inativo";
/// - Quando está selecionado:
///   - o fundo e a borda usam a cor principal (`primary`);
///   - o texto e o ícone usam `onPrimary`;
///   - recebe uma sombra suave para destacar;
/// - Quando não está selecionado:
///   - fundo baseado em `surface`;
///   - borda com cor de `outline` atenuada;
/// - O toque é tratado via `InkWell` para dar feedback tátil/visual.
class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  /// Indica se o chip está atualmente selecionado.
  final bool selected;

  /// Texto apresentado no chip.
  final String label;

  /// Ícone associado ao chip (ex.: ícone de género).
  final IconData icon;

  /// Callback chamado quando o utilizador toca no chip.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: .45),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: .28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: tt.bodyMedium?.copyWith(
                color: selected ? cs.onPrimary : cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
