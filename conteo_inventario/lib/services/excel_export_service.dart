// excel_export_service.dart
// Genera un informe Excel de los conteos de una fecha, con estilo:
//   - Hoja "Resumen": una fila por conteo (pérdidas, sobrantes, neto).
//   - Una hoja por conteo con el detalle de productos descuadrados.
//   - Hoja "Hallazgos": productos fuera de inventario.
//
// Requiere en pubspec.yaml:
//   excel: ^4.0.0
//   path_provider: ^2.1.0   (solo móvil)
//   share_plus: ^7.2.0      (solo móvil)

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

// Importación condicional: en web usa dart:html (descarga), en móvil
// usa path_provider + share_plus (compartir). El stub nunca corre.
import 'excel/guardar_stub.dart'
    if (dart.library.html) 'excel/guardar_web.dart'
    if (dart.library.io) 'excel/guardar_io.dart';

class ExcelExportService {
  // --- Colores de marca (verde Rosen Tantau) ---
  static final _verde = ExcelColor.fromHexString("FF2E5D34");
  static final _rojo = ExcelColor.fromHexString("FFB00020");

  num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _fecha(dynamic valor, String formato) {
    if (valor == null) return "";
    final f = DateTime.tryParse(valor.toString());
    if (f == null) return valor.toString();
    return DateFormat(formato).format(f);
  }

  // Deja un nombre de hoja válido: máx 31 chars y sin caracteres raros.
  String _nombreHoja(String base) {
    var n = base.replaceAll(RegExp(r'[\[\]\*\/\\\?:]'), "-");
    if (n.length > 31) n = n.substring(0, 31);
    return n;
  }

  // ---- Estilos reutilizables ----
  CellStyle get _estTitulo => CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: _verde,
      );

  CellStyle get _estSubtitulo => CellStyle(
        italic: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString("FF6B6B6B"),
      );

  CellStyle get _estEncabezado => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: _verde,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  // Escribe una fila de encabezado con estilo (fondo verde, texto blanco).
  void _encabezado(Sheet hoja, List<String> titulos) {
    final r = hoja.maxRows;
    hoja.appendRow(titulos.map<CellValue?>((t) => TextCellValue(t)).toList());
    for (var c = 0; c < titulos.length; c++) {
      hoja
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .cellStyle = _estEncabezado;
    }
  }

  // Escribe un título grande y lo combina a lo ancho de [cols] columnas.
  void _tituloHoja(Sheet hoja, String texto, int cols, {String? subtitulo}) {
    var r = hoja.maxRows;
    hoja.appendRow([TextCellValue(texto)]);
    hoja
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = _estTitulo;
    if (cols > 1) {
      hoja.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: cols - 1, rowIndex: r),
      );
    }
    if (subtitulo != null) {
      r = hoja.maxRows;
      hoja.appendRow([TextCellValue(subtitulo)]);
      hoja
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .cellStyle = _estSubtitulo;
    }
    hoja.appendRow([]); // línea en blanco
  }

  // conteos: lista de mapas { "meta": ..., "analisis": ..., "hallazgos": ... }
  Future<void> exportarConteosDeFecha({
    required DateTime fecha,
    required List<Map<String, dynamic>> conteos,
  }) async {
    final excel = Excel.createExcel();

    // ================= Hoja Resumen =================
    final resumen = excel["Resumen"];
    excel.delete("Sheet1"); // hoja por defecto del paquete

    _tituloHoja(resumen, "Informe de conteos", 7,
        subtitulo: "Fecha: ${DateFormat("dd/MM/yyyy").format(fecha)}");

    _encabezado(resumen, [
      "Conteo",
      "Fecha inicio",
      "Estado",
      "Perdidas",
      "Sobrantes",
      "Neto",
      "Descuadrados",
    ]);

    for (final c in conteos) {
      final meta = c["meta"] as Map<String, dynamic>;
      final a = (c["analisis"] as Map<String, dynamic>?) ?? {};
      final perdidas = _num(a["totalPerdidas"]);
      final sobrantes = _num(a["totalSobrantes"]);
      final neto = _num(a["descuadreNeto"]);
      final detalle = (a["detalle"] as List<dynamic>?) ?? [];

      final r = resumen.maxRows;
      resumen.appendRow([
        TextCellValue("Conteo #${meta["NumeroConteo"]}"),
        TextCellValue(_fecha(meta["FechaInicio"], "dd/MM/yyyy HH:mm")),
        TextCellValue((meta["Estado"] ?? "").toString()),
        DoubleCellValue(perdidas.toDouble()),
        DoubleCellValue(sobrantes.toDouble()),
        DoubleCellValue(neto.toDouble()),
        IntCellValue(detalle.length),
      ]);
      // El neto en rojo si es negativo.
      if (neto < 0) {
        resumen
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r))
            .cellStyle = CellStyle(bold: true, fontColorHex: _rojo);
      }
    }

    _anchos(resumen, [16, 20, 14, 14, 14, 14, 14]);

    // ============ Una hoja por conteo (detalle) ============
    for (final c in conteos) {
      final meta = c["meta"] as Map<String, dynamic>;
      final a = (c["analisis"] as Map<String, dynamic>?) ?? {};
      final detalle = (a["detalle"] as List<dynamic>?) ?? [];

      final nombre = _nombreHoja(
        "Conteo ${meta["NumeroConteo"]} - ${_fecha(meta["FechaInicio"], "dd-MM")}",
      );
      final hoja = excel[nombre];

      _tituloHoja(hoja, "Conteo #${meta["NumeroConteo"]}", 5,
          subtitulo:
              "${_fecha(meta["FechaInicio"], "dd/MM/yyyy")} · ${(meta["Estado"] ?? "").toString()}");

      _encabezado(hoja, [
        "Producto",
        "Fisico",
        "Sistema",
        "Diferencia",
        "Valor diferencia",
      ]);

      for (final d in detalle) {
        final r = hoja.maxRows;
        final dif = _num(d["Diferencia"]).toDouble();
        hoja.appendRow([
          TextCellValue((d["Nombre"] ?? "").toString()),
          DoubleCellValue(_num(d["CantidadFisica"]).toDouble()),
          DoubleCellValue(_num(d["CantidadSistema"]).toDouble()),
          DoubleCellValue(dif),
          DoubleCellValue(_num(d["ValorDiferencia"]).toDouble()),
        ]);
        // Resalta en rojo las diferencias/valores negativos (pérdidas).
        if (dif < 0) {
          for (final col in [3, 4]) {
            hoja
                .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r))
                .cellStyle = CellStyle(fontColorHex: _rojo);
          }
        }
      }

      if (detalle.isEmpty) {
        hoja.appendRow([TextCellValue("Sin descuadres")]);
      }

      _anchos(hoja, [40, 12, 12, 12, 16]);
    }

    // ================= Hoja "Hallazgos" =================
    final hallazgos = <Map<String, dynamic>>[];
    for (final c in conteos) {
      final meta = (c["meta"] as Map<String, dynamic>?) ?? {};
      final numero = meta["NumeroConteo"];
      final lista = (c["hallazgos"] as List<dynamic>?) ?? [];
      for (final h in lista) {
        final m = Map<String, dynamic>.from(h as Map);
        m["_Conteo"] = numero; // en qué conteo se halló
        hallazgos.add(m);
      }
    }
    if (hallazgos.isNotEmpty) {
      final hoja = excel["Hallazgos"];
      _tituloHoja(hoja, "Hallazgos (fuera de inventario)", 4);
      _encabezado(hoja, ["Conteo", "Producto", "Unidad de medida", "Cantidad"]);
      for (final h in hallazgos) {
        hoja.appendRow([
          TextCellValue(
              h["_Conteo"] == null ? "" : "Conteo #${h["_Conteo"]}"),
          TextCellValue((h["Nombre"] ?? "").toString()),
          TextCellValue((h["UnidadMedida"] ?? "").toString()),
          DoubleCellValue(_num(h["Cantidad"]).toDouble()),
        ]);
      }
      _anchos(hoja, [14, 40, 18, 12]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final nombreArchivo =
        "informe_conteos_${DateFormat("yyyy-MM-dd").format(fecha)}.xlsx";
    await guardarArchivo(bytes, nombreArchivo);
  }

  // Ajusta el ancho de las columnas de una hoja.
  void _anchos(Sheet hoja, List<double> anchos) {
    for (var i = 0; i < anchos.length; i++) {
      hoja.setColumnWidth(i, anchos[i]);
    }
  }
}