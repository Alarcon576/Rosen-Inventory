// gestion_conteos_screen.dart
// Panel del admin para gestionar el conteo EN CURSO:
//  - Pausar   (En proceso -> En pausa)
//  - Reanudar (En pausa   -> En proceso)
//  - Borrar   (elimina el conteo activo/pausado)
//
// Regla: solo puede haber UN conteo vivo a la vez (en proceso o en pausa).
// Mientras haya uno en pausa, no se pueden crear otros hasta reanudarlo
// (y finalizarlo) o borrarlo.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart' as http;
import '../services/config.dart';
import '../theme.dart';
import '../widgets/app_bar_personalizado.dart';

class GestionConteosScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  const GestionConteosScreen({super.key, required this.usuario});

  @override
  State<GestionConteosScreen> createState() => _GestionConteosScreenState();
}

class _GestionConteosScreenState extends State<GestionConteosScreen> {
  List<dynamic> _conteos = [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resp = await http
          .get(Uri.parse("${Config.baseUrl}/conteos/en-curso"))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _conteos = jsonDecode(resp.body) as List<dynamic>);
      } else {
        setState(() => _conteos = []);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _conteos = []);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Llama a un endpoint de acción y refresca. Devuelve el mensaje del server.
    // Llama a un endpoint de acción y refresca. Devuelve el mensaje del server.
  Future<void> _accion(String url, String method,
      {String metodoHttp = "POST", Map<String, dynamic>? body}) async {
    setState(() => _procesando = true);
    try {
      final uri = Uri.parse(url);
      final headers = {"Content-Type": "application/json"};
      final cuerpo = body != null ? jsonEncode(body) : null;
      
      final resp = metodoHttp == "DELETE"
          ? await http
              .delete(uri, headers: headers, body: cuerpo)
              .timeout(const Duration(seconds: 10))
          : await http
              .post(uri, headers: headers, body: cuerpo)
              .timeout(const Duration(seconds: 10));
              
      if (!mounted) return;

      // ✅ CORREGIDO: Nombre de variable cambiado a 'responseData'
      Map<String, dynamic> responseData = {};
      try {
        responseData = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {}

      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // ✅ CORREGIDO: Uso de 'responseData' en lugar de 'body'
          content: Text(responseData["mensaje"] ?? (ok ? "Listo" : "No se pudo")),
          backgroundColor: ok ? AppColors.verdeHoja : Colors.red.shade700,
        ),
      );
      await _cargar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error de conexión")),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }
  Future<void> _pausar(int conteoId) =>
      _accion("${Config.baseUrl}/conteo/$conteoId/pausar", "pausar");

  Future<void> _reanudar(int conteoId) =>
      _accion("${Config.baseUrl}/conteo/$conteoId/reactivar", "reactivar");

  Future<void> _borrar(int conteoId, int numero) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Borrar conteo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Vas a BORRAR el conteo #$numero. Se archivará en el historial "
              "de borrados (no se pierde la data). Indica el motivo:",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Motivo del borrado",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final m = ctrl.text.trim();
              if (m.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Escribe un motivo para borrar")),
                );
                return;
              }
              Navigator.pop(context, m);
            },
            child: const Text("Borrar"),
          ),
        ],
      ),
    );
    if (motivo == null) return;
    await _accion(
      "${Config.baseUrl}/conteo/$conteoId",
      "borrar",
      metodoHttp: "DELETE",
      body: {"usuarioId": widget.usuario["id"], "motivo": motivo},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarPersonalizado(
        titulo: "Gestión de conteos",
        usuario: widget.usuario,
        mostrarAtras: true,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _conteos.isEmpty
                ? ListView(
                    // ListView para que RefreshIndicator funcione aun vacío.
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            "No hay conteos en curso.\n"
                            "Puedes crear uno nuevo desde la pantalla de conteos.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conteos.length,
                    itemBuilder: (_, i) => _tarjeta(_conteos[i]),
                  ),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final estadoId = c["EstadoProcesoID"] as int;
    final enPausa = estadoId == 3;
    final numero = c["NumeroConteo"] as int;
    final contados = c["Contados"] ?? 0;
    final esReconteo = c["ConteoPadreID"] != null;

    final colorEstado = enPausa ? Colors.orange.shade700 : AppColors.verdeHoja;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enPausa ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: colorEstado,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${esReconteo ? "Reconteo" : "Conteo"} #$numero",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.vino,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorEstado.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c["Estado"] ?? "",
                    style: TextStyle(
                      color: colorEstado,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Productos contados: $contados",
                style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 12),
            // Botones de acción.
            Row(
              children: [
                if (!enPausa)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _procesando
                          ? null
                          : () => _pausar(c["ConteoID"] as int),
                      icon: const Icon(Icons.pause),
                      label: const Text("Pausar"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade800,
                      ),
                    ),
                  ),
                if (enPausa)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _procesando
                          ? null
                          : () => _reanudar(c["ConteoID"] as int),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Reanudar"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.verdeHoja,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _procesando
                        ? null
                        : () => _borrar(c["ConteoID"] as int, numero),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Borrar"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}