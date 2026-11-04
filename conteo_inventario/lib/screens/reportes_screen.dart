// reportes_screen.dart
// Reportes del admin: total del inventario, y análisis de plata
// (pérdidas y sobrantes) por conteo finalizado.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/reporte_service.dart';
import '../services/conteo_service.dart';
import '../services/excel_export_service.dart';
import '../theme.dart';
import '../widgets/app_bar_personalizado.dart';

class ReportesScreen extends StatefulWidget {
  // Si viene un usuario, la pantalla actúa como PANEL PRINCIPAL (para el
  // rol "Reportes"): muestra el AppBar con saludo/salir y unos KPIs.
  // Sin usuario (abierta desde el panel del admin), es una sub-pantalla
  // con AppBar simple y botón de atrás.
  final Map<String, dynamic>? usuario;

  const ReportesScreen({super.key, this.usuario});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  final _service = ReporteService();
  final _conteoService = ConteoService();
  final _excel = ExcelExportService();
  final _formatoPlata = NumberFormat.currency(
    locale: "es_CO",
    symbol: "\$",
    decimalDigits: 0,
  );

  Map<String, dynamic>? _total;
  List<dynamic> _conteos = [];
  List<dynamic> _valorGrupo = [];   // valor del inventario por grupo (torta)
  Map<String, dynamic>? _analisis;
  int? _conteoSeleccionado;
  bool _cargando = true;

  String? _mesFiltro; // filtro por mes en formato "yyyy-MM" (null = todos)
  bool _exportando = false;

  // Clave de mes ("yyyy-MM") de una fecha. Sirve para agrupar por mes.
  String? _claveMes(dynamic valor) {
    final f = DateTime.tryParse((valor ?? "").toString());
    if (f == null) return null;
    return "${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}";
  }

  // Meses que SÍ tienen conteos, más recientes primero. Cada elemento
  // es {"clave": "2026-08", "etiqueta": "Agosto 2026"}.
  List<Map<String, String>> get _mesesDisponibles {
    final claves = <String>{};
    for (final c in _conteos) {
      final k = _claveMes(c["FechaInicio"]);
      if (k != null) claves.add(k);
    }
    final lista = claves.toList()..sort((a, b) => b.compareTo(a)); // desc
    return lista.map((k) {
      final partes = k.split("-");
      final fecha = DateTime(int.parse(partes[0]), int.parse(partes[1]));
      final mes = DateFormat("MMMM", "es").format(fecha);
      final etiqueta =
          "${mes[0].toUpperCase()}${mes.substring(1)} ${partes[0]}";
      return {"clave": k, "etiqueta": etiqueta};
    }).toList();
  }

  // Conteos visibles según el mes elegido (si hay uno).
  List<dynamic> get _conteosFiltrados {
    if (_mesFiltro == null) return _conteos;
    return _conteos.where((c) => _claveMes(c["FechaInicio"]) == _mesFiltro).toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final total = await _service.totalInventario();
    final conteos = await _service.conteosFinalizados();
    final valorGrupo = await _service.valorPorGrupo();
    if (!mounted) return;
    setState(() {
      _total = total;
      _conteos = conteos;
      _valorGrupo = valorGrupo;
      _cargando = false;
    });
  }

  Future<void> _analizar(int conteoId) async {
    setState(() {
      _conteoSeleccionado = conteoId;
      _analisis = null;
    });
    final analisis = await _service.analisisPlata(conteoId);
    if (!mounted) return;
    setState(() => _analisis = analisis);
  }

  // Cambia el mes filtrado. Si el conteo elegido ya no pertenece al
  // mes, se limpia la selección.
  void _cambiarMes(String? clave) {
    setState(() {
      _mesFiltro = clave;
      if (!_conteosFiltrados.any((c) => c["ConteoID"] == _conteoSeleccionado)) {
        _conteoSeleccionado = null;
        _analisis = null;
      }
    });
  }

  // Fecha representativa del mes filtrado (para nombrar el Excel).
  DateTime _fechaDelMesFiltro() {
    if (_mesFiltro == null) return DateTime.now();
    final p = _mesFiltro!.split("-");
    return DateTime(int.parse(p[0]), int.parse(p[1]));
  }

  // Exporta a Excel los conteos visibles (del mes elegido, o todos).
  Future<void> _exportarExcel() async {
    final visibles = _conteosFiltrados;
    if (visibles.isEmpty) {
      _aviso("No hay conteos para exportar en ese mes.");
      return;
    }

    setState(() => _exportando = true);
    try {
      final datos = <Map<String, dynamic>>[];
      for (final c in visibles) {
        final analisis = await _service.analisisPlata(c["ConteoID"]);
        // Hallazgos (productos fuera de inventario) para la hoja "Hallazgos".
        final hallazgos =
            await _conteoService.obtenerEncontrados(c["ConteoID"]);
        datos.add({
          "meta": c,
          "analisis": analisis ?? {},
          "hallazgos": hallazgos,
        });
      }

      await _excel.exportarConteosDeFecha(
        fecha: _fechaDelMesFiltro(),
        conteos: datos,
      );
      if (mounted) _aviso("Informe generado (${visibles.length} conteo(s)).");
    } catch (e) {
      if (mounted) _aviso("No se pudo generar el Excel.");
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  // ¿Actúa como panel principal (rol Reportes)?
  bool get _esPanel => widget.usuario != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _esPanel
          ? AppBarPersonalizado(titulo: "Reportes", usuario: widget.usuario)
          : AppBar(title: const Text("Reportes")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Saludo + KPIs (solo cuando es el panel principal).
                if (_esPanel) ...[
                  Text(
                    "Hola, ${widget.usuario!["nombre"]}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.vino,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Panel de reportes",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _kpis(),
                  const SizedBox(height: 16),
                ],

                // Total del inventario (tarjeta destacada con degradado).
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.verdeBosque, AppColors.verdeMedio],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.verdeBosque.withOpacity(0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.inventory_2,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Valor total del inventario",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _total == null
                                  ? "-"
                                  : _formatoPlata
                                      .format(_total!["ValorTotal"] ?? 0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${_total?["TotalProductos"] ?? 0} productos",
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // --- Distribución del valor del inventario por grupo ---
                _tituloSeccion(
                  Icons.pie_chart_outline,
                  "Valor del inventario por grupo",
                  subtitulo: "Distribución por grupo (excluye Activos).",
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: _graficaValorPorGrupo(),
                  ),
                ),

                const SizedBox(height: 24),

                _tituloSeccion(Icons.assessment_outlined, "Análisis por conteo"),
                const SizedBox(height: 12),

                // Filtro por MES (solo aparecen los meses con conteos).
                DropdownButtonFormField<String?>(
                  value: _mesFiltro,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Mes",
                    prefixIcon: Icon(Icons.calendar_month),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text("Todos los meses"),
                    ),
                    ..._mesesDisponibles.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m["clave"],
                        child: Text(m["etiqueta"]!),
                      ),
                    ),
                  ],
                  onChanged: _cambiarMes,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportando ? null : _exportarExcel,
                    icon: _exportando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download),
                    label: Text(
                      _exportando
                          ? "Generando..."
                          : _mesFiltro == null
                              ? "Exportar todos a Excel"
                              : "Exportar este mes a Excel",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.verdeHoja,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_conteos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "No hay conteos aún.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else if (_conteosFiltrados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "No hay conteos en el mes elegido.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  // Selector de conteo
                  DropdownButtonFormField<int>(
                    value: _conteoSeleccionado,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Elige un conteo",
                      border: OutlineInputBorder(),
                    ),
                    items: _conteosFiltrados.map<DropdownMenuItem<int>>((c) {
                      final estado = (c["Estado"] ?? "").toString();
                      final enProceso = estado == "En proceso";
                      return DropdownMenuItem<int>(
                        value: c["ConteoID"],
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Conteo #${c["NumeroConteo"]} · ${_fecha(c["FechaInicio"])} · ${_mes(c["FechaInicio"])}",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: enProceso
                                    ? Colors.orange.shade100
                                    : AppColors.verdeHoja.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                estado,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: enProceso
                                      ? Colors.orange.shade900
                                      : AppColors.verdeHoja,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) _analizar(v);
                    },
                  ),

                const SizedBox(height: 16),

                // Resultado del análisis
                if (_conteoSeleccionado != null)
                  _analisis == null
                      ? const Center(child: CircularProgressIndicator())
                      : _resultadoAnalisis(),
              ],
            ),
    );
  }

  Widget _resultadoAnalisis() {
    final perdidas = _analisis!["totalPerdidas"] ?? 0;
    final sobrantes = _analisis!["totalSobrantes"] ?? 0;
    final neto = _analisis!["descuadreNeto"] ?? 0;
    final detalle = _analisis!["detalle"] as List<dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjetas de pérdidas / sobrantes / neto
        Row(
          children: [
            _tarjetaPlata(
                "Pérdidas", perdidas, Colors.red.shade700, Icons.trending_down),
            const SizedBox(width: 10),
            _tarjetaPlata("Sobrantes", sobrantes, AppColors.verdeHoja,
                Icons.trending_up),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          color: neto < 0 ? Colors.red.shade50 : Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Descuadre neto",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  _formatoPlata.format(neto),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: neto < 0 ? Colors.red.shade700 : AppColors.verdeHoja,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        Text(
          "Productos descuadrados (${detalle.length})",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        ...detalle.map((d) {
          final valorDif = Number(d["ValorDiferencia"]);
          final esPerdida = valorDif < 0;
          return Card(
            child: ListTile(
              leading: Icon(
                esPerdida ? Icons.arrow_downward : Icons.arrow_upward,
                color: esPerdida ? Colors.red.shade700 : AppColors.verdeHoja,
              ),
              title: Text(d["Nombre"]),
              subtitle: Text(
                "Físico: ${d["CantidadFisica"]} · Sistema: ${d["CantidadSistema"]}",
              ),
              trailing: Text(
                _formatoPlata.format(valorDif),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: esPerdida ? Colors.red.shade700 : AppColors.verdeHoja,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _tarjetaPlata(String titulo, dynamic valor, Color color, IconData icono) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icono, color: color),
              const SizedBox(height: 6),
              Text(
                _formatoPlata.format(valor),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(titulo, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // Paleta para las porciones de la torta (amplia: cada grupo su color).
  static const List<Color> _paleta = [
    AppColors.verdeBosque,
    AppColors.verdeMedio,
    AppColors.verdeClaro,
    AppColors.tierra,
    Color(0xFF6A7FDB), // azul suave
    Colors.teal,
    Colors.orange,
    Color(0xFFB4654A), // terracota
    Color(0xFF8E7CC3), // lila
    Color(0xFF3D9970), // esmeralda
    Color(0xFFC98BB9), // rosa polvo
    Colors.brown,
    Color(0xFF5B8DEF), // azul
    Color(0xFFE0A458), // mostaza
  ];

  Widget _sinDatos(String texto) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(texto, style: const TextStyle(color: Colors.grey)),
      );

  // Encabezado de sección con acento e ícono (look más profesional).
  Widget _tituloSeccion(IconData icono, String texto, {String? subtitulo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.vino,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icono, size: 18, color: AppColors.vino),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        if (subtitulo != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              subtitulo,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  // ---- Torta: valor del inventario por grupo ----
  Widget _graficaValorPorGrupo() {
    if (_valorGrupo.isEmpty) return _sinDatos("Sin datos de inventario.");

    // Se muestran TODOS los grupos con valor, cada uno su porción,
    // EXCEPTO el grupo "Activos" (no se incluye ni se agrupa en "Otros").
    final visibles = <Map<String, dynamic>>[];
    for (final g in _valorGrupo) {
      final nombre = (g["Grupo"] ?? "Sin grupo").toString();
      if (nombre.trim().toLowerCase() == "activos") continue; // se excluye
      final valor = Number(g["Valor"]);
      if (valor <= 0) continue;
      visibles.add({"Grupo": nombre, "Valor": valor});
    }

    if (visibles.isEmpty) {
      return _sinDatos("Sin datos de inventario (fuera de Activos).");
    }

    // El total es sobre los grupos mostrados, para que los % sumen 100.
    final total = visibles.fold<num>(0, (s, g) => s + Number(g["Valor"]));
    if (total <= 0) return _sinDatos("Sin datos de inventario.");

    final secciones = <PieChartSectionData>[];
    for (var i = 0; i < visibles.length; i++) {
      final valor = Number(visibles[i]["Valor"]);
      final pct = valor / total * 100;
      secciones.add(PieChartSectionData(
        value: valor.toDouble(),
        color: _paleta[i % _paleta.length],
        radius: 60,
        title: pct >= 6 ? "${pct.toStringAsFixed(0)}%" : "",
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ));
    }

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PieChart(
            PieChartData(
              sections: secciones,
              sectionsSpace: 2,
              centerSpaceRadius: 38,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Leyenda: grupo · valor · porcentaje.
        Column(
          children: [
            for (var i = 0; i < visibles.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _paleta[i % _paleta.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        visibles[i]["Grupo"] ?? "Sin grupo",
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      "${_formatoPlata.format(Number(visibles[i]["Valor"]))}  ·  ${(Number(visibles[i]["Valor"]) / total * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Fila de KPIs informativos (solo en el panel principal).
  Widget _kpis() {
    final finalizados =
        _conteos.where((c) => (c["Estado"] ?? "") == "Finalizado").length;
    final enProceso =
        _conteos.where((c) => (c["Estado"] ?? "") == "En proceso").length;
    final meses = _mesesDisponibles.length;

    return Row(
      children: [
        _kpi("Finalizados", "$finalizados", Icons.check_circle,
            AppColors.verdeHoja),
        const SizedBox(width: 10),
        _kpi("En proceso", "$enProceso", Icons.hourglass_bottom,
            Colors.orange.shade800),
        const SizedBox(width: 10),
        _kpi("Meses", "$meses", Icons.calendar_month, AppColors.vino),
      ],
    );
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icono, color: color),
              const SizedBox(height: 6),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(titulo,
                  style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // Helper: formatea la fecha del conteo (dd/MM/yyyy). Sirve para
  // distinguir dos conteos con el mismo número pero de fechas distintas
  // (por ejemplo un "Conteo 1" de agosto y otro de diciembre).
  String _fecha(dynamic valor) {
    if (valor == null) return "sin fecha";
    final fecha = DateTime.tryParse(valor.toString());
    if (fecha == null) return valor.toString();
    return DateFormat("dd/MM/yyyy").format(fecha);
  }

  // Helper: nombre del mes de la fecha, en español (ej: "agosto").
  // Se muestra al lado del conteo, con la primera letra en mayúscula.
  String _mes(dynamic valor) {
    if (valor == null) return "";
    final fecha = DateTime.tryParse(valor.toString());
    if (fecha == null) return "";
    final mes = DateFormat("MMMM", "es").format(fecha);
    return mes.isEmpty ? mes : "${mes[0].toUpperCase()}${mes.substring(1)}";
  }

  // Helper: convierte a número de forma segura (puede venir como String).
  num Number(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }
}