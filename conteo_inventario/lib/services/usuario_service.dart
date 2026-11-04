// usuario_service.dart
// Gestión de usuarios (para el panel de admin).

import 'dart:convert';
import 'api_client.dart' as http;
import 'config.dart';

class UsuarioService {
  Future<List<dynamic>> listar() async {
    try {
      final r = await http.get(Uri.parse("${Config.baseUrl}/usuarios"));
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> listarRoles() async {
    try {
      final r = await http.get(Uri.parse("${Config.baseUrl}/roles"));
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> crear(
    String nombre,
    String contrasena,
    int rolId,
  ) async {
    try {
      final r = await http.post(
        Uri.parse("${Config.baseUrl}/usuarios"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "nombre": nombre,
          "contrasena": contrasena,
          "rolId": rolId,
        }),
      );
      final datos = jsonDecode(r.body);
      return {"ok": r.statusCode == 201, "mensaje": datos["mensaje"] ?? ""};
    } catch (e) {
      return {"ok": false, "mensaje": "Error de conexión"};
    }
  }

  Future<Map<String, dynamic>> editar(
    int id,
    String nombre,
    int rolId,
    String? contrasena,
  ) async {
    try {
      final r = await http.put(
        Uri.parse("${Config.baseUrl}/usuarios/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "nombre": nombre,
          "rolId": rolId,
          "contrasena": contrasena ?? "",
        }),
      );
      final datos = jsonDecode(r.body);
      return {"ok": r.statusCode == 200, "mensaje": datos["mensaje"] ?? ""};
    } catch (e) {
      return {"ok": false, "mensaje": "Error de conexión"};
    }
  }

  Future<bool> cambiarEstado(int id, bool activo) async {
    try {
      final r = await http.patch(
        Uri.parse("${Config.baseUrl}/usuarios/$id/estado"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"activo": activo}),
      );
      return r.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}