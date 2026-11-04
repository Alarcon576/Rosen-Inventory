// reporte_service.dart
// Reportes para el panel de admin.

import 'dart:convert';
import 'api_client.dart' as http;
import 'config.dart';

class ReporteService {
  // Total del inventario en plata (según el sistema).
  Future<Map<String, dynamic>?> totalInventario() async {
    try {
      final r = await http.get(
        Uri.parse("${Config.baseUrl}/reportes/total-inventario"),
      );
      if (r.statusCode == 200) return jsonDecode(r.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  // Conteos finalizados (para elegir cuál analizar).
  Future<List<dynamic>> conteosFinalizados() async {
    try {
      final r = await http.get(
        Uri.parse("${Config.baseUrl}/reportes/conteos-finalizados"),
      );
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  // Análisis de plata de un conteo (pérdidas y sobrantes).
  Future<Map<String, dynamic>?> analisisPlata(int conteoId) async {
    try {
      final r = await http.get(
        Uri.parse("${Config.baseUrl}/reportes/conteo/$conteoId/plata"),
      );
      if (r.statusCode == 200) return jsonDecode(r.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  // Distribución del valor del inventario por grupo (para la torta).
  Future<List<dynamic>> valorPorGrupo() async {
    try {
      final r = await http.get(
        Uri.parse("${Config.baseUrl}/reportes/valor-por-grupo"),
      );
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (e) {
      return [];
    }
  }
  

  // Tendencia del descuadre neto entre conteos finalizados (para la línea).
  Future<List<dynamic>> tendenciaDescuadre() async {
    try {
      final r = await http.get(
        Uri.parse("${Config.baseUrl}/reportes/tendencia-descuadre"),
      );
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (e) {
      return [];
    }
  }
}