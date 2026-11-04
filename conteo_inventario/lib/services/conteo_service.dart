// conteo_service.dart
// Comunicación con el backend para los conteos, con soporte OFFLINE.
//
// Idea general:
//  - Si hay backend, se trabaja online como siempre.
//  - Si NO hay backend, los conteos y detalles se guardan en una COLA
//    local (archivos JSON) y se suben luego con SyncService.
//
// Un conteo creado offline usa un "localId" NEGATIVO (basado en la hora)
// hasta que el servidor le asigne su ConteoID real al sincronizar.

import 'dart:convert';
import 'dart:math';
import 'api_client.dart' as http;
import 'config.dart';
import 'local_store.dart';

class ConteoService {
  // Genera una "huella" única de cliente para idempotencia (anti-duplicados).
  static String nuevoClienteRef() {
    final r = Random();
    return "${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 31)}";
  }

  static const _claveCatalogo = "catalogo";
  static const _claveCatalogoGeneral = "catalogo_general"; // catálogo grande
  static const _claveReconteo = "reconteo_pendientes"; // descuadrados cacheados
  static const _claveActivos = "activos_cache";        // conteos en marcha
  static const _claveContados = "contados_cache";       // ya contados por conteo
  // Claves de la cola offline (compartidas con SyncService).
  static const kConteosLocal = "conteos_local";
  static const kDetallesLocal = "detalles_local";
  static const kTerminarLocal = "terminar_local";
  static const kEncontradosLocal = "encontrados_local"; // hallazgos por subir

  // ---------- Helpers ----------
  Future<List<dynamic>> _leerLista(String clave) async {
    final d = await LocalStore.leer(clave);
    return (d is List) ? List<dynamic>.from(d) : <dynamic>[];
  }

  // Convierte a número de forma segura (puede venir como String).
  num Number(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  // ---------- Catálogo (offline) ----------
  // ¿Hay un conteo en curso según lo que se sabe LOCALMENTE (sin red)?
  // Cuenta los conteos locales sin terminar y la caché de activos del
  // servidor (se refresca cada vez que se abre la pantalla de inicio).
  Future<bool> _hayConteoEnCursoLocal() async {
    final locales = await _leerLista(kConteosLocal);
    if (locales.any((c) => c["terminado"] != true)) return true;
    final activos = await LocalStore.leer(_claveActivos);
    return activos is List && activos.isNotEmpty;
  }

  // El catálogo local no se puede reemplazar si ya hay uno guardado y hay
  // un conteo en curso (evita que cambie a mitad de un conteo).
  Future<bool> _catalogoProtegido(List<dynamic> local) async =>
      local.isNotEmpty && await _hayConteoEnCursoLocal();

  // ¿No hay catálogo guardado en el teléfono todavía?
  Future<bool> catalogoLocalVacio() async => (await _catalogoLocal()).isEmpty;

  Future<void> descargarCatalogo() async {
    if (await _catalogoProtegido(await _catalogoLocal())) return;
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/productos"))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final lista = jsonDecode(r.body);
        if (lista is List) {
          await LocalStore.guardar(_claveCatalogo, lista);
          await _marcarActualizado();
        }
      }
    } catch (_) {}
  }

  // Fecha de la última vez que se refrescó el catálogo local.
  static const _claveCatalogoMeta = "catalogo_meta";

  Future<void> _marcarActualizado() => LocalStore.guardar(
        _claveCatalogoMeta,
        {"actualizado": DateTime.now().toIso8601String()},
      );

  // Horas máximas que puede tener el catálogo para permitir iniciar un
  // conteo. Si pasa más tiempo (o nunca se actualizó), hay que actualizar.
  static const int horasMaxCatalogo = 360;

  // Devuelve null si nunca se ha registrado una actualización.
  Future<DateTime?> ultimaActualizacionCatalogos() async {
    final d = await LocalStore.leer(_claveCatalogoMeta);
    if (d is Map && d["actualizado"] is String) {
      return DateTime.tryParse(d["actualizado"] as String);
    }
    return null;
  }

  // Descarga una lista del servidor SIN guardarla. Devuelve null si falla
  // la red, el servidor responde mal o la lista viene vacía.
  Future<List<dynamic>?> _bajarLista(String ruta, int segundos) async {
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}$ruta"))
          .timeout(Duration(seconds: segundos));
      if (r.statusCode != 200) return null;
      final lista = jsonDecode(r.body);
      if (lista is List && lista.isNotEmpty) return lista;
      return null;
    } catch (_) {
      return null;
    }
  }

  // Botón "Actualizar inventario": refresca los DOS catálogos locales.
  // Primero baja todo a memoria; solo si ambos llegaron completos
  // reemplaza las copias locales. Si algo falla, queda la copia anterior.
  // No toca las colas de conteos/detalles/hallazgos/cierres pendientes.
  //
  // REGLA: NO se puede actualizar mientras haya un conteo en curso (del
  // servidor, en caché o local sin terminar), porque cambiar los
  // productos a mitad de una jornada generaría inconsistencias. Esta
  // validación vive aquí para que ninguna pantalla pueda saltársela.
  Future<Map<String, dynamic>> actualizarCatalogos() async {
    try {
      final activos = await obtenerConteosActivos();
      if (activos.isNotEmpty) {
        final n = activos.length;
        return {
          "ok": false,
          "bloqueado": true,
          "mensaje": n == 1
              ? "Hay 1 conteo en curso. Finalízalo antes de actualizar el inventario."
              : "Hay $n conteos en curso. Finalízalos antes de actualizar el inventario.",
        };
      }
    } catch (_) {
      return {
        "ok": false,
        "bloqueado": true,
        "mensaje": "No se pudo verificar si hay conteos en curso. Inténtalo de nuevo.",
      };
    }

    final productos = await _bajarLista("/productos", 60);
    if (productos == null) {
      return {
        "ok": false,
        "mensaje": "No se pudo descargar el inventario. Se mantiene la copia anterior.",
      };
    }
    final catalogo = await _bajarLista("/catalogo", 60);
    if (catalogo == null) {
      return {
        "ok": false,
        "mensaje": "No se pudo descargar el catálogo general. Se mantiene la copia anterior.",
      };
    }

    final okProd = await LocalStore.guardarVerificado(_claveCatalogo, productos);
    final okCat =
        await LocalStore.guardarVerificado(_claveCatalogoGeneral, catalogo);
    if (!okProd || !okCat) {
      return {
        "ok": false,
        "mensaje": "No se pudo guardar en el teléfono (¿poco espacio?).",
      };
    }

    await _marcarActualizado();

    return {
      "ok": true,
      "productos": productos.length,
      "catalogo": catalogo.length,
      "mensaje":
          "Inventario actualizado: ${productos.length} productos, ${catalogo.length} en catálogo general.",
    };
  }

  Future<List<dynamic>> _catalogoLocal() async {
    final data = await LocalStore.leer(_claveCatalogo);
    return (data is List) ? data : [];
  }

  // Todos los productos del inventario (para listar/filtrar por grupo en
  // el primer conteo). Online los baja y cachea; offline usa la caché.
  Future<List<dynamic>> obtenerProductos() async {
    // Con un conteo en curso no se reemplaza el catálogo: se usa el local.
    final local = await _catalogoLocal();
    if (await _catalogoProtegido(local)) return local;
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/productos"))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final lista = jsonDecode(r.body);
        if (lista is List) {
          await LocalStore.guardar(_claveCatalogo, lista);
          await _marcarActualizado();
          return lista;
        }
      }
    } catch (_) {}
    return await _catalogoLocal();
  }

  // ---------- Catálogo GENERAL (hallazgos fuera de inventario) ----------
  Future<void> descargarCatalogoGeneral() async {
    if (await _catalogoProtegido(await _catalogoGeneralLocal())) return;
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/catalogo"))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final lista = jsonDecode(r.body);
        if (lista is List) await LocalStore.guardar(_claveCatalogoGeneral, lista);
      }
    } catch (_) {}
  }

  Future<List<dynamic>> _catalogoGeneralLocal() async {
    final data = await LocalStore.leer(_claveCatalogoGeneral);
    return (data is List) ? data : [];
  }

  // Buscar en el catálogo general (por nombre o ID), con respaldo offline.
  // Si se pasa conteoId, el servidor excluye los productos ya hallados en la
  // cadena de ese conteo (evita duplicar hallazgos en reconteos).
  Future<List<dynamic>> buscarCatalogo(String texto, {int? conteoId}) async {
    try {
      final extra =
          (conteoId != null && conteoId > 0) ? "&conteoId=$conteoId" : "";
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/catalogo/buscar?q=$texto$extra"))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (_) {
      final catalogo = await _catalogoGeneralLocal();
      final q = texto.trim().toLowerCase();
      if (q.isEmpty) return [];
      // Offline: excluye los ya hallados localmente para este conteo.
      final Set<int> yaHallados = {};
      if (conteoId != null) {
        final data = await LocalStore.leer(kEncontradosLocal);
        if (data is List) {
          for (final e in data) {
            if (e["refId"] == conteoId) yaHallados.add(e["productoId"] as int);
          }
        }
      }
      final res = catalogo.where((p) {
        if (yaHallados.contains(p["ProductoID"])) return false;
        final nombre = (p["Nombre"] ?? "").toString().toLowerCase();
        final id = (p["ProductoID"] ?? "").toString();
        return nombre.contains(q) || id.contains(q);
      }).toList();
      res.sort((a, b) {
        final ia = (a["ProductoID"] ?? "").toString();
        final ib = (b["ProductoID"] ?? "").toString();
        int rank(String id) => id == texto ? 0 : (id.startsWith(texto) ? 1 : 2);
        final r = rank(ia).compareTo(rank(ib));
        if (r != 0) return r;
        return (a["Nombre"] ?? "").toString().compareTo((b["Nombre"] ?? "").toString());
      });
      return res.take(10).toList();
    }
  }

  // Registrar un HALLAZGO (producto fuera de inventario). Online lo sube;
  // offline (o conteo local) lo encola. Se guarda Nombre/Unidad para el Excel.
  Future<Map<String, dynamic>> guardarEncontrado({
    required int conteoId,
    required int productoId,
    required double cantidad,
    required int usuarioId,
    required String nombre,
    required String unidadMedida,
    String? dispositivo,
  }) async {
    final clienteRef = nuevoClienteRef();

    // Conteo local (negativo): siempre a la cola.
    if (conteoId < 0) {
      return _encontradoLocal(conteoId, productoId, cantidad, usuarioId,
          nombre, unidadMedida, dispositivo, clienteRef);
    }
    try {
      final r = await http
          .post(
            Uri.parse("${Config.baseUrl}/conteo/$conteoId/encontrado"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "productoId": productoId,
              "cantidad": cantidad,
              "usuarioId": usuarioId,
              "dispositivo": dispositivo,
              "clienteRef": clienteRef,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 201) return {"ok": true, "offline": false};
      final datos = jsonDecode(r.body);
      return {"ok": false, "mensaje": datos["mensaje"] ?? "No se pudo guardar"};
    } catch (_) {
      return _encontradoLocal(conteoId, productoId, cantidad, usuarioId,
          nombre, unidadMedida, dispositivo, clienteRef);
    }
  }

  Future<Map<String, dynamic>> _encontradoLocal(
    int refId, int productoId, double cantidad, int usuarioId,
    String nombre, String unidadMedida, String? dispositivo, String clienteRef,
  ) async {
    await LocalStore.actualizar(kEncontradosLocal, (actual) {
      final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
      l.add({
        "refId": refId,
        "productoId": productoId,
        "cantidad": cantidad,
        "usuarioId": usuarioId,
        "nombre": nombre,
        "unidadMedida": unidadMedida,
        "dispositivo": dispositivo,
        "clienteRef": clienteRef,
        "estado": "no_transferido",
      });
      return l;
    });
    return {"ok": true, "offline": true};
  }

  // Hallazgos de un conteo (servidor + cola local) para el Excel.
  Future<List<dynamic>> obtenerEncontrados(int conteoId) async {
    final List<dynamic> resultado = [];
    if (conteoId > 0) {
      try {
        final r = await http
            .get(Uri.parse("${Config.baseUrl}/conteo/$conteoId/encontrados"))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) resultado.addAll(jsonDecode(r.body));
      } catch (_) {}
    }
    // Suma los que están en la cola local para este conteo.
    final data = await LocalStore.leer(kEncontradosLocal);
    if (data is List) {
      for (final e in data) {
        if (e["refId"] == conteoId) {
          resultado.add({
            "ProductoID": e["productoId"],
            "Nombre": e["nombre"],
            "UnidadMedida": e["unidadMedida"],
            "Cantidad": e["cantidad"],
          });
        }
      }
    }
    return resultado;
  }

  // Descarga y cachea los descuadrados del último conteo finalizado,
  // para poder hacer el RECONTEO sin internet restringido a ellos.
  Future<void> descargarReconteoPendientes() async {
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/reconteo/pendientes-actual"))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        await LocalStore.guardar(_claveReconteo, data);
      }
    } catch (_) {}
  }

  // Lee el cache de descuadrados. Forma: {padreId, numeroPadre, pendientes:[...]}
  Future<Map<String, dynamic>?> _reconteoCache() async {
    final d = await LocalStore.leer(_claveReconteo);
    return (d is Map) ? Map<String, dynamic>.from(d) : null;
  }

  // ---------- Crear conteo ----------
  Future<Map<String, dynamic>> crearConteo(
    int numeroConteo,
    String fechaInicio,
  ) async {
    // La MISMA huella se usa online y offline: si el POST se ejecutó pero
    // hubo timeout, al reintentar/sincronizar el servidor la reconoce.
    final clienteRef = nuevoClienteRef();
    try {
      final respuesta = await http
          .post(
            Uri.parse("${Config.baseUrl}/conteo"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "numeroConteo": numeroConteo,
              "fechaInicio": fechaInicio,
              "clienteRef": clienteRef,
            }),
          )
          .timeout(const Duration(seconds: 6));

      final datos = jsonDecode(respuesta.body);
      if (respuesta.statusCode == 201) {
        return {
          "ok": true,
          "conteoId": datos["conteoId"],
          "conteoPadreId": datos["conteoPadreId"],
          "esReconteo": datos["esReconteo"] == true,
          "offline": false,
        };
      }
      // Online pero rechazado (ej. número repetido): error real.
      return {
        "ok": false,
        "mensaje": datos["mensaje"] ?? "No se pudo crear el conteo",
      };
    } catch (e) {
      // Sin conexión: se crea LOCAL (id negativo) y se encola.
      return await _crearConteoLocal(numeroConteo, fechaInicio, clienteRef);
    }
  }

  Future<Map<String, dynamic>> _crearConteoLocal(
    int numeroConteo,
    String fechaInicio,
    String clienteRef,
  ) async {
    // ¿Es reconteo? Si el número es > 1 y hay descuadrados cacheados,
    // se trata como reconteo restringido a esos productos (igual que
    // online). El "padre" es el último conteo finalizado cacheado.
    int? padreId;
    final cache = await _reconteoCache();
    if (numeroConteo > 1 &&
        cache != null &&
        cache["padreId"] != null &&
        (cache["pendientes"] is List) &&
        (cache["pendientes"] as List).isNotEmpty) {
      padreId = cache["padreId"];
    }

    final localId = -DateTime.now().millisecondsSinceEpoch;
    await LocalStore.actualizar(kConteosLocal, (actual) {
      final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
      l.add({
        "localId": localId,
        "numeroConteo": numeroConteo,
        "fechaInicio": fechaInicio,
        "terminado": false,
        "serverId": null,
        "conteoPadreId": padreId, // null = conteo completo
        "clienteRef": clienteRef,
        "estado": "no_transferido", // transferido cuando el servidor confirma
      });
      return l;
    });
    return {
      "ok": true,
      "conteoId": localId,
      "conteoPadreId": padreId,
      "esReconteo": padreId != null,
      "offline": true,
    };
  }

  // ---------- Conteos activos (online + cache offline + locales) ----------
  Future<List<dynamic>> obtenerConteosActivos() async {
    List<dynamic> servidor = [];
    bool online = false;
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/conteos/activos"))
          .timeout(const Duration(seconds: 5));
      if (respuesta.statusCode == 200) {
        servidor = jsonDecode(respuesta.body);
        online = true;
      }
    } catch (_) {}

    if (online) {
      await LocalStore.guardar(_claveActivos,servidor);
      await _limpiarContadosInactivos(servidor);

      _cachearContados(servidor);
    } else {
      // Offline: usa la lista cacheada (marcada con _cache).
      final cache = await LocalStore.leer(_claveActivos);
      if (cache is List) {
        servidor = cache.map((c) {
          final m = Map<String, dynamic>.from(c);
          m["_cache"] = true;
          return m;
        }).toList();
      }
    }

    // Conteos locales aún no terminados (se ven junto a los del servidor).
    final locales = await _leerLista(kConteosLocal);
    final detalles = await _leerLista(kDetallesLocal);
    final localesActivos = locales.where((c) => c["terminado"] != true).map((c) {
      final contados = detalles
          .where((d) => d["refId"] == c["localId"])
          .map((d) => d["productoId"])
          .toSet()
          .length;
      return {
        "ConteoID": c["localId"],
        "NumeroConteo": c["numeroConteo"],
        "FechaInicio": c["fechaInicio"],
        "ConteoPadreID": c["conteoPadreId"], // reconteo local si != null
        "Contados": contados,
        "_local": true, // marca para la UI (sin sincronizar)
      };
    }).toList();

    return [...localesActivos, ...servidor];
  }

  // Elimina de contados_cache los conteos que ya no están activos.
// Solo se ejecuta cuando el servidor respondió correctamente.
Future<void> _limpiarContadosInactivos(
    List<dynamic> servidor) async {
  try {
    final idsActivos = servidor
        .map((c) => int.tryParse(
            (c["ConteoID"] ?? "").toString()))
        .whereType<int>()
        .where((id) => id > 0)
        .map((id) => id.toString())
        .toSet();

    await LocalStore.actualizar(_claveContados, (actual) {
      final mapa = actual is Map
          ? Map<String, dynamic>.from(actual)
          : <String, dynamic>{};

      // Conserva únicamente los conteos que siguen activos.
      mapa.removeWhere(
          (conteoId, productos) => !idsActivos.contains(conteoId));

      return mapa;
    });
  } catch (_) {
    // Si falla la limpieza, conserva los datos existentes.
  }
}

  // Cachea, en segundo plano, los productos ya contados de cada conteo
  // activo del servidor (para que al unirse offline se sepa qué ya está).
 Future<void> _cachearContados(List<dynamic> servidor) async {
  try {
    final idsActivos = servidor
        .map((c) => int.tryParse(
            (c["ConteoID"] ?? "").toString()))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();

    final nuevosContados = <String, dynamic>{};

    // Consulta los productos contados de cada conteo activo.
    for (final id in idsActivos) {
      try {
        final r = await http
            .get(Uri.parse(
                "${Config.baseUrl}/conteo/$id/contados"))
            .timeout(const Duration(seconds: 5));

        if (r.statusCode == 200) {
          final datos = jsonDecode(r.body);

          if (datos is List) {
            nuevosContados["$id"] = datos;
          }
        }
      } catch (_) {
        // Si falla una consulta, conserva la caché anterior
        // de ese conteo, siempre que siga activo.
      }
    }

    // Actualización atómica: no recupera entradas antiguas.
    await LocalStore.actualizar(_claveContados, (actual) {
      final mapa = actual is Map
          ? Map<String, dynamic>.from(actual)
          : <String, dynamic>{};

      // Elimina conteos que ya no están activos.
      mapa.removeWhere(
          (conteoId, productos) =>
              !idsActivos.contains(int.tryParse(conteoId)));

      // Actualiza los conteos consultados correctamente.
      mapa.addAll(nuevosContados);

      return mapa;
    });
  } catch (_) {}
}

  // ---------- Búsqueda / escaneo (con respaldo offline) ----------
  Future<List<dynamic>> buscarProductos(String texto) async {
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/productos/buscar?q=$texto"))
          .timeout(const Duration(seconds: 5));
      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      return [];
    } catch (e) {
      return _buscarLocal(texto);
    }
  }

  Future<List<dynamic>> _buscarLocal(String texto) async {
    final catalogo = await _catalogoLocal();
    final q = texto.trim().toLowerCase();
    if (q.isEmpty) return [];
    final res = catalogo.where((p) {
      final nombre = (p["Nombre"] ?? "").toString().toLowerCase();
      final id = (p["ProductoID"] ?? "").toString();
      return nombre.contains(q) || id.contains(q);
    }).toList();
    res.sort((a, b) {
      final ia = (a["ProductoID"] ?? "").toString();
      final ib = (b["ProductoID"] ?? "").toString();
      int rank(String id) => id == texto ? 0 : (id.startsWith(texto) ? 1 : 2);
      final r = rank(ia).compareTo(rank(ib));
      if (r != 0) return r;
      return (a["Nombre"] ?? "").toString().compareTo((b["Nombre"] ?? "").toString());
    });
    return res.take(10).toList();
  }

  Future<Map<String, dynamic>?> buscarPorId(int id) async {
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/producto/$id"))
          .timeout(const Duration(seconds: 5));
      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      return null;
    } catch (e) {
      final catalogo = await _catalogoLocal();
      for (final p in catalogo) {
        if ((p["ProductoID"]).toString() == id.toString()) {
          return Map<String, dynamic>.from(p);
        }
      }
      return null;
    }
  }

  // ---------- Guardar detalle ----------
  Future<Map<String, dynamic>> guardarDetalle({
    required int conteoId,
    required int numeroConteo,
    required int productoId,
    required double cantidadFisica,
    required int usuarioId,
    String? dispositivo,
  }) async {
    final clienteRef = nuevoClienteRef();

    // Conteo LOCAL (id negativo): siempre a la cola.
    if (conteoId < 0) {
      return _guardarDetalleLocal(conteoId, numeroConteo, productoId,
          cantidadFisica, usuarioId, dispositivo, clienteRef);
    }

    // Conteo del servidor: intenta online; si falla, encola con la misma huella.
    try {
      final respuesta = await http
          .post(
            Uri.parse("${Config.baseUrl}/detalle"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "conteoId": conteoId,
              "numeroConteo": numeroConteo,
              "productoId": productoId,
              "cantidadFisica": cantidadFisica,
              "usuarioId": usuarioId,
              "dispositivo": dispositivo,
              "clienteRef": clienteRef,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (respuesta.statusCode == 201) return {"ok": true, "offline": false};
      final datos = jsonDecode(respuesta.body);
      return {
        "ok": false,
        "mensaje": datos["mensaje"] ?? "No se pudo guardar el detalle",
      };
    } catch (e) {
      return _guardarDetalleLocal(conteoId, numeroConteo, productoId,
          cantidadFisica, usuarioId, dispositivo, clienteRef);
    }
  }

  Future<Map<String, dynamic>> _guardarDetalleLocal(
    int refId,
    int numeroConteo,
    int productoId,
    double cantidadFisica,
    int usuarioId,
    String? dispositivo,
    String clienteRef,
  ) async {
    await LocalStore.actualizar(kDetallesLocal, (actual) {
      final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
      // Si ya hay un detalle de ese producto en este conteo, lo reemplaza
      // (última cantidad gana), igual que un reconteo de la misma ronda.
      l.removeWhere((d) => d["refId"] == refId && d["productoId"] == productoId);
      l.add({
        "refId": refId,
        "numeroConteo": numeroConteo,
        "productoId": productoId,
        "cantidadFisica": cantidadFisica,
        "usuarioId": usuarioId,
        "dispositivo": dispositivo,
        "clienteRef": clienteRef,
        "estado": "no_transferido",
      });
      return l;
    });
    return {"ok": true, "offline": true};
  }

  // ---------- Faltantes ----------
  Future<List<dynamic>> obtenerFaltantes(int conteoId) async {
    // Conteo del servidor y online: pregunta al backend.
    if (conteoId > 0) {
      try {
        final respuesta = await http
            .get(Uri.parse("${Config.baseUrl}/conteo/$conteoId/faltantes"))
            .timeout(const Duration(seconds: 5));
        if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      } catch (_) {}
    }
    // Offline o conteo local: faltantes = catálogo − ya contados localmente.
    final catalogo = await _catalogoLocal();
    final contados = await obtenerContados(conteoId);
    return catalogo.where((p) => !contados.contains(p["ProductoID"])).toList();
  }

  Future<List<dynamic>> obtenerPendientesReconteo(int conteoPadreId) async {
    try {
      final respuesta = await http
          .get(Uri.parse(
              "${Config.baseUrl}/conteo/$conteoPadreId/pendientes-reconteo"))
          .timeout(const Duration(seconds: 5));
      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
    } catch (_) {}
    // Offline: usa los descuadrados cacheados.
    final cache = await _reconteoCache();
    if (cache != null && cache["pendientes"] is List) {
      return List<dynamic>.from(cache["pendientes"]);
    }
    return [];
  }

  // ---------- Conflictos (dos dispositivos, mismo producto) ----------
  // Solo aplica a conteos del servidor; requiere conexión.
  Future<List<dynamic>> obtenerConflictos(int conteoId) async {
    if (conteoId < 0) return [];
    try {
      final r = await http
          .get(Uri.parse("${Config.baseUrl}/conteo/$conteoId/conflictos"))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) return jsonDecode(r.body);
      return [];
    } catch (_) {
      return [];
    }
  }

  // Resuelve un conflicto con el recuento definitivo. Requiere conexión.
  Future<Map<String, dynamic>> resolverConflicto({
    required int conteoId,
    required int productoId,
    required double cantidadFisica,
    required int usuarioId,
    required int numeroConteo,
    String? dispositivo,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse(
                "${Config.baseUrl}/conteo/$conteoId/producto/$productoId/resolver"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "cantidadFisica": cantidadFisica,
              "usuarioId": usuarioId,
              "numeroConteo": numeroConteo,
              "dispositivo": dispositivo,
              "clienteRef": nuevoClienteRef(),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) return {"ok": true};
      final datos = jsonDecode(r.body);
      return {"ok": false, "mensaje": datos["mensaje"] ?? "No se pudo resolver"};
    } catch (e) {
      return {"ok": false, "mensaje": "Necesitas conexión para resolver conflictos"};
    }
  }

  // ---------- Terminar ----------
  Future<Map<String, dynamic>> terminarConteo(int conteoId) async {
    // Conteo LOCAL: se marca terminado; se subirá al sincronizar.
    if (conteoId < 0) {
      await LocalStore.actualizar(kConteosLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        for (final c in l) {
          if (c["localId"] == conteoId) c["terminado"] = true;
        }
        return l;
      });
      return {"ok": true, "offline": true, "mensaje": "Conteo guardado"};
    }

    // Conteo del servidor: intenta online; si falla, encola el "terminar".
    try {
      final respuesta = await http
          .post(Uri.parse("${Config.baseUrl}/conteo/$conteoId/terminar"))
          .timeout(const Duration(seconds: 6));
      final datos = jsonDecode(respuesta.body);
      return {
        "ok": respuesta.statusCode == 200,
        "mensaje": datos["mensaje"] ?? "",
        "offline": false,
      };
    } catch (e) {
      await LocalStore.actualizar(kTerminarLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        // Compatibilidad: entradas viejas eran enteros; ahora son objetos
        // {conteoId, estado}. Evita duplicar el mismo conteo.
        final yaEsta = l.any((e) =>
            (e is int && e == conteoId) ||
            (e is Map && e["conteoId"] == conteoId));
        if (!yaEsta) {
          l.add({"conteoId": conteoId, "estado": "no_transferido"});
        }
        return l;
      });
      return {"ok": true, "offline": true, "mensaje": "Se cerrará al sincronizar"};
    }
  }

  // ---------- Contados (online + local) ----------
  Future<Set<int>> obtenerContados(int conteoId) async {
    final Set<int> locales = {};
    final detalles = await _leerLista(kDetallesLocal);
    for (final d in detalles) {
      if (d["refId"] == conteoId) locales.add(d["productoId"] as int);
    }

    // Conteo local: solo lo local.
    if (conteoId < 0) return locales;

    // Conteo del servidor: intenta traer los del servidor y los une.
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/conteo/$conteoId/contados"))
          .timeout(const Duration(seconds: 5));
      if (respuesta.statusCode == 200) {
        final List<dynamic> ids = jsonDecode(respuesta.body);
        locales.addAll(ids.map((e) => e as int));
        // Actualiza el cache para uso offline.
        final actual = await LocalStore.leer(_claveContados);
        final mapa = (actual is Map)
            ? Map<String, dynamic>.from(actual)
            : <String, dynamic>{};
        mapa["$conteoId"] = ids;
        await LocalStore.guardar(_claveContados, mapa);
        return locales;
      }
    } catch (_) {}

    // Offline: suma lo ya contado cacheado de ese conteo.
    final cache = await LocalStore.leer(_claveContados);
    if (cache is Map && cache["$conteoId"] is List) {
      locales.addAll((cache["$conteoId"] as List).map((e) => e as int));
    }
    return locales;
  }

  // ---------- Resumen (solo online, admin) ----------
  Future<Map<String, dynamic>?> obtenerResumen(int conteoId) async {
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/conteo/$conteoId/resumen"))
          .timeout(const Duration(seconds: 6));
      if (respuesta.statusCode == 200) return jsonDecode(respuesta.body);
      return null;
    } catch (e) {
      return null;
    }
  }
}