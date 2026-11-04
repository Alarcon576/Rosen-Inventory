// auth_service.dart
// Login con soporte OFFLINE.
//
// - Con internet: valida contra el backend (bcrypt del lado servidor) y,
//   si acierta, guarda localmente la credencial (nombre + hash) para
//   poder entrar después sin conexión.
// - Sin internet: valida contra las credenciales guardadas de quienes ya
//   iniciaron sesión antes en este dispositivo.
//
// El hash local es SHA-256 de "nombre::contraseña". No es tan fuerte
// como bcrypt, pero solo sirve como respaldo offline en el dispositivo;
// la validación "de verdad" sigue siendo la del servidor.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart' show Sesion;
import 'config.dart';
import 'conectividad_service.dart';
import 'local_store.dart';

class AuthService {
  static const _claveCredenciales = "credenciales";

  String _hash(String nombre, String contrasena) {
    return sha256.convert(utf8.encode("$nombre::$contrasena")).toString();
  }

  // Resultado del login: incluye el usuario y si fue offline.
  Future<Map<String, dynamic>?> login(
    String nombre,
    String contrasena,
  ) async {
    final online = await ConectividadService.hayBackend();

    if (online) {
      try {
        final respuesta = await http
            .post(
              Uri.parse("${Config.baseUrl}/login"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"nombre": nombre, "contrasena": contrasena}),
            )
            .timeout(const Duration(seconds: 6));

        if (respuesta.statusCode == 200) {
          final datos = jsonDecode(respuesta.body);
          final usuario = datos["usuario"]; // { id, nombre, rolId, rol }
          // Guarda/actualiza la credencial local para uso offline.
          await _guardarCredencial(nombre, contrasena, usuario);
          // Sesión con token: se envía en todas las peticiones siguientes.
          Sesion.iniciar(
            nombre: nombre,
            contrasena: contrasena,
            usuario: Map<String, dynamic>.from(usuario),
            token: datos["token"] as String?,
          );
          return {"usuario": usuario, "offline": false};
        }

        // 401 u otro: credenciales incorrectas ESTANDO online.
        return null;
      } catch (_) {
        // Falló la red a mitad de camino: intenta offline.
        return await _loginOffline(nombre, contrasena);
      }
    }

    // Sin backend: login offline.
    return await _loginOffline(nombre, contrasena);
  }

  Future<Map<String, dynamic>?> _loginOffline(
    String nombre,
    String contrasena,
  ) async {
    final data = await LocalStore.leer(_claveCredenciales);
    if (data is! List) return null;

    final hash = _hash(nombre, contrasena);
    for (final c in data) {
      if (c is Map &&
          c["nombre"] == nombre &&
          c["hash"] == hash &&
          c["usuario"] != null) {
        final usuario = Map<String, dynamic>.from(c["usuario"]);
        // Sin token todavía: se consigue solo apenas haya conexión.
        Sesion.iniciar(nombre: nombre, contrasena: contrasena, usuario: usuario);
        return {
          "usuario": usuario,
          "offline": true,
        };
      }
    }
    return null;
  }

  Future<void> _guardarCredencial(
    String nombre,
    String contrasena,
    Map<String, dynamic> usuario,
  ) async {
    final data = await LocalStore.leer(_claveCredenciales);
    final lista = (data is List) ? List<dynamic>.from(data) : <dynamic>[];

    // Quita cualquier credencial previa del mismo usuario.
    lista.removeWhere((c) => c is Map && c["nombre"] == nombre);

    lista.add({
      "nombre": nombre,
      "hash": _hash(nombre, contrasena),
      "usuario": usuario,
    });

    await LocalStore.guardar(_claveCredenciales, lista);
  }
}