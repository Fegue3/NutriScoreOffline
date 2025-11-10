// lib/features/scanner/scanner_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import '../../app/di.dart';
import '../../domain/models.dart';

/// Ecrã de **scanner de códigos de barras** (câmara traseira).
///
/// Fluxo principal:
/// 1) Captura um código de barras (EAN, etc.) via `mobile_scanner`;
/// 2) Faz lookup local/online (via `di.productsRepo.getByBarcode`);
/// 3) Regista entrada no histórico (`di.historyRepo.addIfNotDuplicate`);
/// 4) Navega para o detalhe do produto, já com base nutricional (100 g).
///
/// Notas de UX/robustez:
/// - Utiliza *debounce/cooldown* para evitar leituras repetidas (`_last` + `_cooldown`);
/// - Feedback háptico no momento da leitura (`HapticFeedback.mediumImpact`);
/// - Mostra *SnackBar* se o produto não for encontrado;
/// - Botões de *Flash* e *Inverter câmara* em *pills* no rodapé.
///
/// Parâmetros de navegação (opcionais):
/// - [initialMealLabelPt]  — rótulo PT da refeição para pré-seleção (p.ex. "Almoço");
/// - [isoDate]             — data ISO para registo (se ausente, usa `DateTime.now()`).
class ScannerScreen extends StatefulWidget {
  final String? initialMealLabelPt; // ex: "Almoço"
  final String? isoDate; // ex: "2025-10-11T00:00:00.000"
  const ScannerScreen({super.key, this.initialMealLabelPt, this.isoDate});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  /// Controlador do `mobile_scanner` (câmara, velocidade, face).
  final MobileScannerController _c = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  /// Evita *re-entrância* durante a resolução de um código.
  bool _busy = false;

  /// Guarda o último código lido para evitar duplicados consecutivos.
  String? _last;

  /// Janela de *cooldown* curta após cada leitura (evita toques repetidos).
  Timer? _cooldown;

  /// Data efetiva utilizada no registo/encaminhamento (ISO fornecida ou agora).
  DateTime get _date =>
      (widget.isoDate != null ? DateTime.tryParse(widget.isoDate!) : null) ??
      DateTime.now();

  /// Rótulo PT da refeição inicial (se fornecido externamente).
  String? get _mealLabelPt => widget.initialMealLabelPt;

  @override
  void dispose() {
    _c.dispose();
    _cooldown?.cancel();
    super.dispose();
  }

  /// Handler de deteção de código de barras.
  ///
  /// Passos:
  /// - Ignora se estiver ocupado (`_busy`) ou se o código for vazio/igual ao último;
  /// - Vibra (feedback háptico);
  /// - Obtém produto por *barcode* (repo híbrido: local → OFF);
  /// - Acrescenta ao histórico (se existir *user*);
  /// - Faz `pushNamed('productDetail', extra: {...})` com dados do produto;
  /// - Abre janela de *cooldown* para permitir nova leitura segura.
  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    final code = cap.barcodes.first.rawValue;
    if (code == null || code.isEmpty || code == _last) return;

    _busy = true;
    _last = code;

    try {
      HapticFeedback.mediumImpact();

      // 1) buscar produto (offline-first; o híbrido tenta local e pode ir à OFF API)
      final p = await di.productsRepo.getByBarcode(code);
      if (p == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produto não encontrado offline.')),
        );
        return;
      }

      // 2) registar no histórico (usa kcal/macros do modelo)
      final user = await di.userRepo.currentUser();
      if (user != null) {
        await di.historyRepo.addIfNotDuplicate(
          user.id,
          HistorySnapshot(
            barcode: p.barcode,
            name: p.name,
            brand: p.brand,
            calories: p.energyKcal100g,
            proteins: p.protein100g,
            carbs: p.carb100g,
            fat: p.fat100g,
          ),
        );
      }

      // 3) navegar para o detalhe com dados reais (base = 100 g)
      if (!mounted) return; // garante que o State ainda existe
      await context.pushNamed(
        'productDetail',
        extra: {
          'barcode': p.barcode,
          'initialMeal': _mealLabelPt,
          'date': _date,
          'name': p.name,
          'brand': p.brand,
          'baseQuantityLabel': '100 g',
          'kcalPerBase': p.energyKcal100g,
          'proteinGPerBase': p.protein100g,
          'carbsGPerBase': p.carb100g,
          'fatGPerBase': p.fat100g,
          'sugarsGPerBase': p.sugars100g,
          'fiberGPerBase': p.fiber100g,
          'saltGPerBase': p.salt100g,
        },
      );
    } finally {
      _busy = false;
      _cooldown?.cancel();
      _cooldown = Timer(const Duration(milliseconds: 400), () {
        _last = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Scanner'), backgroundColor: cs.surface),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // *Preview* da câmara + deteção em tempo real
          MobileScanner(controller: _c, onDetect: _onDetect),

          // Moldura visual (área de foco) — meramente decorativa
          Align(
            alignment: const Alignment(0, -0.1),
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.primary, width: 3),
              ),
            ),
          ),

          // Ações rápidas: Flash e inverter câmara
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pill('Flash', Icons.flash_on, _c.toggleTorch, cs),
                _pill('Inverter', Icons.cameraswitch, _c.switchCamera, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Botão em formato *pill* usado na barra de ações do scanner.
  Widget _pill(
    String label,
    IconData icon,
    VoidCallback onTap,
    ColorScheme cs,
  ) {
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: cs.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
