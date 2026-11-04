// local_store.dart
// Guarda y lee datos en archivos JSON dentro del almacenamiento de la
// app (funciona sin internet). Es la base del modo offline.
//
// IMPORTANTE (anti pérdida de datos): todas las operaciones pasan por un
// CANDADO en cadena, así nunca se solapan dos escrituras. Además existe
// `actualizar()`, que hace leer-modificar-escribir de forma ATÓMICA:
// si mientras se sincroniza el usuario guarda un detalle, no se pisan.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalStore {
  // Candado: cada operación se encadena a la anterior.
  static Future<void> _cadena = Future.value();

  static Future<T> _bloqueo<T>(Future<T> Function() accion) {
    final completer = Completer<T>();
    _cadena = _cadena.then((_) async {
      try {
        completer.complete(await accion());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  static Future<File> _archivo(String nombre) async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/rt_$nombre.json");
  }

  // Escritura ATÓMICA: escribe en un archivo temporal y, solo si terminó
  // bien, lo renombra sobre el definitivo. Si la app se cierra a mitad,
  // el archivo anterior queda intacto (nunca un JSON cortado).
  // Devuelve true si se guardó, false si falló.
  static Future<bool> _guardarRawOk(String nombre, dynamic data) async {
    try {
      final f = await _archivo(nombre);
      final tmp = File("${f.path}.tmp");
      await tmp.writeAsString(jsonEncode(data), flush: true);
      try {
        await tmp.rename(f.path);
      } catch (_) {
        // Algunos sistemas no reemplazan al renombrar: borra y reintenta.
        if (await f.exists()) await f.delete();
        await tmp.rename(f.path);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _guardarRaw(String nombre, dynamic data) async {
    await _guardarRawOk(nombre, data);
  }

  static Future<dynamic> _leerRaw(String nombre) async {
    try {
      final f = await _archivo(nombre);
      if (!await f.exists()) return null;
      final texto = await f.readAsString();
      if (texto.trim().isEmpty) return null;
      return jsonDecode(texto);
    } catch (_) {
      return null;
    }
  }

  // Guarda cualquier estructura (Map o List) como JSON.
  static Future<void> guardar(String nombre, dynamic data) =>
      _bloqueo(() => _guardarRaw(nombre, data));

  // Igual que guardar(), pero avisa si falló (true = guardado).
  static Future<bool> guardarVerificado(String nombre, dynamic data) =>
      _bloqueo(() => _guardarRawOk(nombre, data));

  // Lee y decodifica; devuelve null si no existe o hay error.
  static Future<dynamic> leer(String nombre) => _bloqueo(() => _leerRaw(nombre));

  // Leer-modificar-escribir ATÓMICO: transforma el contenido actual y lo
  // vuelve a guardar sin que otra operación se meta en medio.
  static Future<T> actualizar<T>(
    String nombre,
    T Function(dynamic actual) transform,
  ) {
    return _bloqueo(() async {
      final actual = await _leerRaw(nombre);
      final nuevo = transform(actual);
      await _guardarRaw(nombre, nuevo);
      return nuevo;
    });
  }

  static Future<void> borrar(String nombre) => _bloqueo(() async {
        try {
          final f = await _archivo(nombre);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      });
}