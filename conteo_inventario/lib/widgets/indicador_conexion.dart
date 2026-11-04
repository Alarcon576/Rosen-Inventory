// indicador_conexion.dart
// Puntito de color que muestra si hay conexión con el servidor.
// Verde = conectado, rojo = sin conexión. Se revisa cada 5 segundos.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/estado_service.dart';

class IndicadorConexion extends StatefulWidget {
  const IndicadorConexion({super.key});

  @override
  State<IndicadorConexion> createState() => _IndicadorConexionState();
}

class _IndicadorConexionState extends State<IndicadorConexion> {
  bool? _conectado;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _verificar();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _verificar(),
    );
  }

  Future<void> _verificar() async {
    final ok = await EstadoService.servidorDisponible();
    if (!mounted) return;
    setState(() => _conectado = ok);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color color;
    String texto;

    if (_conectado == null) {
      color = Colors.grey;
      texto = "...";
    } else if (_conectado!) {
      color = Colors.greenAccent.shade400;
      texto = "En línea";
    } else {
      color = Colors.red.shade400;
      texto = "Sin conexión";
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}