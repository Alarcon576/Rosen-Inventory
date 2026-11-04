// conteo_terminado_screen.dart
// Pantalla simple que ve el LECTOR al terminar un conteo: un mensaje
// de confirmación y un botón para volver a la pantalla de conteos.
// (Reemplaza el resumen/dashboard que se mostraba antes al cerrar.)

import 'package:flutter/material.dart';
import '../theme.dart';

class ConteoTerminadoScreen extends StatelessWidget {
  final int numeroConteo;
  final bool esReconteo;

  const ConteoTerminadoScreen({
    super.key,
    required this.numeroConteo,
    this.esReconteo = false,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = esReconteo ? "Reconteo #$numeroConteo" : "Conteo #$numeroConteo";

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.verdeBosque, AppColors.verdeMedio],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle,
                    color: Colors.white, size: 90),
                const SizedBox(height: 20),
                Text(
                  "$titulo terminado",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "El conteo se guardó correctamente. "
                  "Puedes volver a la lista de conteos.",
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Vuelve a la pantalla base (lista de conteos).
                      Navigator.of(context)
                          .popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.list_alt),
                    label: const Text("Volver a conteos"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.verdeBosque,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}