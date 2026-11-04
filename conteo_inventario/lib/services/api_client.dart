// api_client.dart
// Sesión con token y cliente HTTP que lo envía en cada petición.
//
// Uso: en los servicios, en vez de
//     import 'package:http/http.dart' as http;
// se importa
//     import 'api_client.dart' as http;
// y las llamadas (http.get, http.post, http.put, http.patch, http.delete)
// quedan igual: ahora agregan solas "Authorization: Bearer <token>".
//
// - El token se guarda SOLO en memoria (se pierde al cerrar la app, que de
//   todos modos pide iniciar sesión de nuevo).
// - Si el servidor responde 401 (token vencido o inválido), se vuelve a
//   iniciar sesión en silencio con las credenciales de esta sesión y se
//   repite la petición una vez. Esto también cubre a quien entró SIN
//   conexión: apenas hay red consigue su token.
// - Si el servidor rechaza esas credenciales (clave cambiada o usuario
//   desactivado) se cierra la sesión y se vuelve al login.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

// Para que los servicios puedan seguir escribiendo `http.Response`.
export 'package:http/http.dart' show Response;

class Sesion {
  Sesion._();

  /// Token de la sesión actual (null si entró sin conexión y aún no lo obtuvo).
  static String? token;

  /// Datos del usuario logueado: { id, nombre, rolId, rol }.
  static Map<String, dynamic>? usuario;

  static String? _nombre;
  static String? _contrasena;

  /// Llaves globales para poder volver al login desde cualquier parte.
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// La define main.dart: qué hacer cuando la sesión deja de ser válida.
  static void Function()? alExpirar;

  static bool _expirando = false;
  static Future<bool>? _renovando;

  static void iniciar({
    required String nombre,
    required String contrasena,
    required Map<String, dynamic> usuario,
    String? token,
  }) {
    Sesion.token = token;
    Sesion.usuario = usuario;
    _nombre = nombre;
    _contrasena = contrasena;
    _expirando = false;
  }

  /// Cierra la sesión: borra token y credenciales de la memoria.
  static void cerrar() {
    token = null;
    usuario = null;
    _nombre = null;
    _contrasena = null;
  }

  static bool get hayCredenciales => _nombre != null && _contrasena != null;

  static Map<String, String> get cabecera =>
      token == null ? {} : {"Authorization": "Bearer $token"};

  /// Pide un token nuevo. true = lo obtuvo. Si varias peticiones lo piden a la
  /// vez, comparten una sola solicitud.
  static Future<bool> renovar() {
    return _renovando ??= _renovar().whenComplete(() => _renovando = null);
  }

  static Future<bool> _renovar() async {
    if (!hayCredenciales) return false;
    try {
      final r = await http
          .post(
            Uri.parse("${Config.baseUrl}/login"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"nombre": _nombre, "contrasena": _contrasena}),
          )
          .timeout(const Duration(seconds: 6));

      if (r.statusCode == 200) {
        final nuevo = jsonDecode(r.body)["token"];
        if (nuevo is String && nuevo.isNotEmpty) {
          token = nuevo;
          return true;
        }
        return false;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        // El servidor ya no acepta estas credenciales.
        sesionInvalida();
      }
      return false;
    } catch (_) {
      return false; // sin red: se reintentará en la próxima petición
    }
  }

  /// Cierra la sesión y avisa a la app para volver al login (una sola vez).
  static void sesionInvalida() {
    if (_expirando) return;
    _expirando = true;
    cerrar();
    alExpirar?.call();
  }
}

// ---------------------------------------------------------------------------
// Funciones con la misma forma que las de package:http, pero con token.
// ---------------------------------------------------------------------------

Future<http.Response> _enviar(
  Future<http.Response> Function(Map<String, String> cabeceras) llamada,
  Map<String, String>? headers,
) async {
  Map<String, String> cabeceras() => {...?headers, ...Sesion.cabecera};

  // Entró sin conexión y aún no tiene token: intenta conseguirlo.
  if (Sesion.token == null && Sesion.hayCredenciales) {
    await Sesion.renovar();
  }

  var r = await llamada(cabeceras());

  if (r.statusCode == 401) {
    if (Sesion.hayCredenciales) {
      if (await Sesion.renovar()) r = await llamada(cabeceras());
    } else {
      // Sin credenciales para renovar: la sesión no se puede recuperar.
      Sesion.sesionInvalida();
    }
  }
  return r;
}

Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
    _enviar((h) => http.get(url, headers: h), headers);

Future<http.Response> post(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar((h) => http.post(url, headers: h, body: body, encoding: encoding),
        headers);

Future<http.Response> put(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar((h) => http.put(url, headers: h, body: body, encoding: encoding),
        headers);

Future<http.Response> patch(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar((h) => http.patch(url, headers: h, body: body, encoding: encoding),
        headers);

Future<http.Response> delete(Uri url,
        {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _enviar((h) => http.delete(url, headers: h, body: body, encoding: encoding),
        headers);
