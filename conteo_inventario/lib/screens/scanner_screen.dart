// scanner_screen.dart
// Pantalla que abre la cámara y lee un código de barras.
// Devuelve el código leído a la pantalla anterior.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  // Evita leer el mismo código muchas veces seguidas.
  bool _yaLeido = false;

  void _onDetectar(BarcodeCapture captura) {
    if (_yaLeido) return;

    final codigos = captura.barcodes;
    if (codigos.isEmpty) return;

    final valor = codigos.first.rawValue;
    if (valor == null || valor.isEmpty) return;

    _yaLeido = true;

    // Devolvemos el código leído a la pantalla anterior.
    Navigator.pop(context, valor);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escanear código"),
        actions: [
          // Botón para prender/apagar la linterna.
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
            tooltip: "Linterna",
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetectar,
          ),

          // Marco visual en el centro para guiar el escaneo.
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.vino, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Texto de ayuda abajo.
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Apunta al código de barras",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}