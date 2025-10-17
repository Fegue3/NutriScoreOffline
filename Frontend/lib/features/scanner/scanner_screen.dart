// lib/features/scanner/scanner_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import '../../app/di.dart';
import '../../domain/models.dart';

class ScannerScreen extends StatefulWidget {
  final String? initialMealLabelPt; // ex: "Almoço"
  final String? isoDate; // ex: "2025-10-11T00:00:00.000"
  const ScannerScreen({super.key, this.initialMealLabelPt, this.isoDate});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _c = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _busy = false;
  String? _last;
  Timer? _cooldown;

  DateTime get _date =>
      (widget.isoDate != null ? DateTime.tryParse(widget.isoDate!) : null) ??
      DateTime.now();

  String? get _mealLabelPt => widget.initialMealLabelPt;

  @override
  void dispose() {
    _c.dispose();
    _cooldown?.cancel();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    final code = cap.barcodes.first.rawValue;
    if (code == null || code.isEmpty || code == _last) return;

    _busy = true;
    _last = code;

    try {
      HapticFeedback.mediumImpact();

      // 1) buscar produto
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
            calories: p.energyKcal100g,
            proteins: p.protein100g,
            carbs: p.carb100g,
            fat: p.fat100g,
          ),
        );
      }

      // 3) navegar para o detalhe com dados reais (base = 100 g)
      await context.pushNamed(
        'productDetail',
        extra: {
          'barcode': p.barcode,
          'initialMeal': _mealLabelPt,
          'date': _date,
          'name': p.name,
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
          MobileScanner(controller: _c, onDetect: _onDetect),

          // moldura simples
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

          // ações
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
