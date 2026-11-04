// sync_service.dart
// Sincronización GLOBAL "todo o nada".
//
// Arma UN solo lote con todo lo pendiente (conteos locales terminados,
// detalles, hallazgos y cierres) y lo envía a /sync/batch, que lo aplica
// dentro de una única transacción SQL. Si algo falla, el servidor hace
// ROLLBACK y aquí NO se marca nada: los ítems quedan "no_transferido" y se
// reintentan luego. Solo cuando el servidor confirma y la VERIFICACIÓN por
// conteo de filas coincide exactamente, se marcan como "transferido"
// (se conservan como historial; no se borran).

import 'dart:convert';
import 'api_client.dart' as http;
import 'config.dart';
import 'conectividad_service.dart';
import 'conteo_service.dart';
import 'local_store.dart';

class SyncService {
  static bool _sincronizando = false;

  Future<List<dynamic>> _leer(String clave) async {
    final d = await LocalStore.leer(clave);
    return (d is List) ? List<dynamic>.from(d) : <dynamic>[];
  }

  // ¿Un ítem sigue pendiente (no transferido)?
  bool _pend(dynamic x) =>
      !(x is Map && x["estado"] == "transferido");

  // Cuántos ítems están LISTOS para subir (indicador de la UI).
  Future<int> pendientes() async {
    final lote = await _construirLote();
    return lote["total"] as int;
  }

  // Construye el lote a enviar a partir de las colas locales.
  // Devuelve las listas ya con el formato del endpoint + conjuntos de
  // ClienteRef para poder marcar "transferido" después.
  Future<Map<String, dynamic>> _construirLote() async {
    final conteos = await _leer(ConteoService.kConteosLocal);
    final detalles = await _leer(ConteoService.kDetallesLocal);
    final encontrados = await _leer(ConteoService.kEncontradosLocal);
    final terminar = await _leer(ConteoService.kTerminarLocal);

    // Conteos LOCALES terminados y aún no transferidos (se crean + cierran).
    final localTerm = conteos
        .where((c) => c["terminado"] == true && _pend(c))
        .toList();
    final idsLocalTerm = localTerm.map((c) => c["localId"]).toSet();

    final loteConteos = localTerm
        .map<Map<String, dynamic>>((c) => {
              "localId": c["localId"],
              "clienteRef": c["clienteRef"],
              "numeroConteo": c["numeroConteo"],
              "fechaInicio": c["fechaInicio"],
              "conteoPadreId": c["conteoPadreId"],
              "finalizar": true,
            })
        .toList();

    // Detalles: de conteos del servidor (refId>0) o de locales terminados.
    final loteDetalles = <Map<String, dynamic>>[];
    for (final d in detalles) {
      if (!_pend(d)) continue;
      final refId = d["refId"];
      final esServer = refId is int && refId > 0;
      final esLocalTerm = idsLocalTerm.contains(refId);
      if (!esServer && !esLocalTerm) continue; // conteo local en curso: aún no
      loteDetalles.add({
        "clienteRef": d["clienteRef"],
        "refLocalId": esServer ? null : refId,
        "conteoServerId": esServer ? refId : null,
        "numeroConteo": d["numeroConteo"],
        "productoId": d["productoId"],
        "cantidadFisica": d["cantidadFisica"],
        "usuarioId": d["usuarioId"],
        "dispositivo": d["dispositivo"],
      });
    }

    // Hallazgos: misma lógica que los detalles.
    final loteEnc = <Map<String, dynamic>>[];
    for (final e in encontrados) {
      if (!_pend(e)) continue;
      final refId = e["refId"];
      final esServer = refId is int && refId > 0;
      final esLocalTerm = idsLocalTerm.contains(refId);
      if (!esServer && !esLocalTerm) continue;
      loteEnc.add({
        "clienteRef": e["clienteRef"],
        "refLocalId": esServer ? null : refId,
        "conteoServerId": esServer ? refId : null,
        "productoId": e["productoId"],
        "cantidad": e["cantidad"],
        "usuarioId": e["usuarioId"],
        "dispositivo": e["dispositivo"],
      });
    }

    // Cierres de conteos del servidor (compatibilidad: int u objeto).
    final cierres = <int>[];
    for (final t in terminar) {
      if (t is int) {
        cierres.add(t);
      } else if (t is Map && _pend(t)) {
        cierres.add(t["conteoId"] as int);
      }
    }

    final total = loteConteos.length +
        loteDetalles.length +
        loteEnc.length +
        cierres.length;

    return {
      "conteos": loteConteos,
      "detalles": loteDetalles,
      "encontrados": loteEnc,
      "cierresServidor": cierres,
      "total": total,
    };
  }

  Future<Map<String, dynamic>> sincronizar() async {
    if (_sincronizando) return {"ok": false, "mensaje": "Ya está sincronizando"};
    if (!await ConectividadService.hayBackend()) {
      return {"ok": false, "mensaje": "Sin conexión"};
    }

    _sincronizando = true;
    try {
      final lote = await _construirLote();
      if ((lote["total"] as int) == 0) {
        return {"ok": true, "subidos": 0, "mensaje": "Nada pendiente por sincronizar"};
      }

      final conteos = lote["conteos"] as List;
      final detalles = lote["detalles"] as List;
      final encontrados = lote["encontrados"] as List;
      final cierres = lote["cierresServidor"] as List;

      // --- Envío en UN solo lote (transacción en el servidor) ---
      http.Response resp;
      try {
        resp = await http
            .post(
              Uri.parse("${Config.baseUrl}/sync/batch"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "conteos": conteos,
                "detalles": detalles,
                "encontrados": encontrados,
                "cierresServidor": cierres,
              }),
            )
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        // Corte de conexión a mitad: el servidor revierte; no marcamos nada.
        return {
          "ok": false,
          "mensaje": "Se interrumpió la conexión. No se guardó nada; se reintentará.",
        };
      }

      Map<String, dynamic> datos;
      try {
        datos = Map<String, dynamic>.from(jsonDecode(resp.body));
      } catch (_) {
        datos = {};
      }

      if (resp.statusCode != 200 || datos["ok"] != true) {
        return {
          "ok": false,
          "mensaje": datos["mensaje"] ?? "No se pudo sincronizar (rollback)",
        };
      }

      // --- Verificación EXACTA por conteo de filas ---
      final v = (datos["verificacion"] is Map)
          ? Map<String, dynamic>.from(datos["verificacion"])
          : <String, dynamic>{};
      final exacto = (v["conteosOk"] == conteos.length) &&
          (v["detallesOk"] == detalles.length) &&
          (v["encontradosOk"] == encontrados.length);

      if (!exacto) {
        return {
          "ok": false,
          "mensaje": "La verificación no coincidió; no se marcó nada (se reintentará).",
        };
      }

      // --- Todo exacto: marcar "transferido" (se conservan) ---
      final mapa = (datos["mapa"] is Map)
          ? Map<String, dynamic>.from(datos["mapa"])
          : <String, dynamic>{};
      final refsConteos =
          conteos.map((c) => c["clienteRef"]).whereType<String>().toSet();
      final refsDet =
          detalles.map((d) => d["clienteRef"]).whereType<String>().toSet();
      final refsEnc =
          encontrados.map((e) => e["clienteRef"]).whereType<String>().toSet();
      final cierresSet = cierres.map((e) => e as int).toSet();

      await LocalStore.actualizar(ConteoService.kConteosLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        for (final c in l) {
          if (refsConteos.contains(c["clienteRef"])) {
            c["estado"] = "transferido";
            final sid = mapa["${c["localId"]}"];
            if (sid != null) c["serverId"] = sid;
          }
        }
        return l;
      });

      await LocalStore.actualizar(ConteoService.kDetallesLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        for (final d in l) {
          if (refsDet.contains(d["clienteRef"])) d["estado"] = "transferido";
        }
        return l;
      });

      await LocalStore.actualizar(ConteoService.kEncontradosLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        for (final e in l) {
          if (refsEnc.contains(e["clienteRef"])) e["estado"] = "transferido";
        }
        return l;
      });

      await LocalStore.actualizar(ConteoService.kTerminarLocal, (actual) {
        final l = (actual is List) ? List<dynamic>.from(actual) : <dynamic>[];
        return l.map((t) {
          final id = (t is int) ? t : (t is Map ? t["conteoId"] : null);
          if (id != null && cierresSet.contains(id)) {
            return {"conteoId": id, "estado": "transferido"};
          }
          return t;
        }).toList();
      });

      final partes = <String>[];
      if (conteos.isNotEmpty) partes.add("${conteos.length} conteo(s)");
      if (detalles.isNotEmpty) partes.add("${detalles.length} detalle(s)");
      if (encontrados.isNotEmpty) partes.add("${encontrados.length} hallazgo(s)");
      if (cierres.isNotEmpty) partes.add("${cierres.length} cierre(s)");

      return {
        "ok": true,
        "subidos": lote["total"],
        "mensaje": "Sincronizado (todo o nada): ${partes.join(", ")}",
      };
    } finally {
      _sincronizando = false;
    }
  }

  // Limpia del almacenamiento local los ítems YA transferidos (historial).
  // Útil para depurar la cola cuando ya no se necesitan.
  Future<void> purgarTransferidos() async {
    bool transferido(dynamic x) => (x is Map && x["estado"] == "transferido");

    await LocalStore.actualizar(ConteoService.kConteosLocal, (a) {
      final l = (a is List) ? List<dynamic>.from(a) : <dynamic>[];
      return l.where((c) => !transferido(c)).toList();
    });
    await LocalStore.actualizar(ConteoService.kDetallesLocal, (a) {
      final l = (a is List) ? List<dynamic>.from(a) : <dynamic>[];
      return l.where((d) => !transferido(d)).toList();
    });
    await LocalStore.actualizar(ConteoService.kEncontradosLocal, (a) {
      final l = (a is List) ? List<dynamic>.from(a) : <dynamic>[];
      return l.where((e) => !transferido(e)).toList();
    });
    await LocalStore.actualizar(ConteoService.kTerminarLocal, (a) {
      final l = (a is List) ? List<dynamic>.from(a) : <dynamic>[];
      return l.where((t) => !transferido(t)).toList();
    });
  }
}