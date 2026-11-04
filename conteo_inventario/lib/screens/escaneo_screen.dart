// escaneo_screen.dart
// Pantalla donde el almacenista busca productos, ve su info y
// registra la cantidad física de cada uno.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/conteo_service.dart';
import '../services/dispositivo_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/transiciones.dart';
import '../widgets/app_bar_personalizado.dart';
import 'conteo_terminado_screen.dart';
import 'scanner_screen.dart';

class EscaneoScreen extends StatefulWidget {
  final int conteoId;
  final int numeroConteo;
  final Map<String, dynamic> usuario;

  // Si viene con padre, este conteo es un RECONTEO: solo se pueden
  // contar los productos que quedaron descuadrados en el conteo padre.
  final int? conteoPadreId;

  const EscaneoScreen({
    super.key,
    required this.conteoId,
    required this.numeroConteo,
    required this.usuario,
    this.conteoPadreId,
  });

  @override
  State<EscaneoScreen> createState() => _EscaneoScreenState();
}

class _EscaneoScreenState extends State<EscaneoScreen> {
  final _buscarController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _conteoService = ConteoService();

  List<dynamic> _sugerencias = [];
  Map<String, dynamic>? _productoSeleccionado;
  bool _guardando = false;

  // MEJORA 3: guardamos los IDs de los productos ya contados en esta
  // ronda, para marcarlos visualmente en las sugerencias.
  // Ahora incluye lo que cuentan TODOS los dispositivos (polling).
  Set<int> _yaContados = {};

  // Timer que consulta al servidor cada 5s qué se ha contado.
  Timer? _pollingTimer;

  // Nombre del dispositivo (se carga una vez al abrir la pantalla).
  String _dispositivo = "";

  // --- Reconteo ---
  // Es reconteo si el conteo tiene padre.
  bool get _esReconteo => widget.conteoPadreId != null;
  // IDs de los productos que SÍ se pueden contar (los descuadrados
  // del conteo padre). En un conteo completo queda vacío = sin límite.
  final Set<int> _permitidos = {};
  // Lista completa de esos productos descuadrados (para mostrarlos).
  List<dynamic> _pendientes = [];
  bool _cargandoPendientes = false;
  // Filtro por grupo en la lista del reconteo (null = todos).
  String? _grupoReconteoFiltro;

  // Productos EN CONFLICTO (dos dispositivos, cantidades distintas).
  List<dynamic> _conflictos = [];

  // Modo "buscar en catálogo general" para registrar productos físicos
  // que no están en el inventario (hallazgos).
  bool _modoCatalogo = false;
  int _hallazgosRegistrados = 0;

  void _alternarModoCatalogo() {
    setState(() {
      _modoCatalogo = !_modoCatalogo;
      _sugerencias = [];
      _buscarController.clear();
      _textoBuscado = "";
      _productoSeleccionado = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _sincronizarContados(); // carga inicial
    _cargarDispositivo();
    _cargarConflictos();
    if (_esReconteo) _cargarPendientes();
    // Polling: cada 5 segundos actualiza los ya contados por todos.
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _sincronizarContados();
        _cargarConflictos();
      },
    );
  }

  // Trae los productos en conflicto (solo aplica a conteos del servidor).
  Future<void> _cargarConflictos() async {
    final lista = await _conteoService.obtenerConflictos(widget.conteoId);
    if (!mounted) return;
    setState(() => _conflictos = lista);
  }

  // Carga los productos descuadrados del conteo padre (los únicos
  // que se pueden recontar).
  Future<void> _cargarPendientes() async {
    setState(() => _cargandoPendientes = true);
    final lista =
        await _conteoService.obtenerPendientesReconteo(widget.conteoPadreId!);
    if (!mounted) return;
    setState(() {
      _pendientes = lista;
      _permitidos
        ..clear()
        ..addAll(lista.map<int>((p) => p["ProductoID"] as int));
      _cargandoPendientes = false;
    });
  }

  // Carga el nombre del dispositivo una sola vez.
  Future<void> _cargarDispositivo() async {
    final nombre = await DispositivoService.obtenerNombre();
    if (!mounted) return;
    setState(() => _dispositivo = nombre);
  }

  // Trae del servidor los productos ya contados por CUALQUIER
  // dispositivo en este conteo, y actualiza la marca visual.
  Future<void> _sincronizarContados() async {
    final contados = await _conteoService.obtenerContados(widget.conteoId);
    if (!mounted) return;
    setState(() => _yaContados = contados);
  }

  // Guarda el texto que se buscó, para resaltarlo (MEJORA 2).
  String _textoBuscado = "";

  // Abre el escáner, lee un código y busca ese producto por ID.
  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
      context,
      rutaFade<String>(const ScannerScreen()),
    );

    if (codigo == null || !mounted) return;

    // El código de barras ES el ProductoID. Lo convertimos a número.
    final id = int.tryParse(codigo.trim());
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El código leído no es válido")),
      );
      return;
    }

    final producto = await _conteoService.buscarPorId(id);
    if (!mounted) return;

    if (producto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se encontró el producto #$id")),
      );
      return;
    }

    // Selecciona el producto (reusa la validación de "ya contado").
    _seleccionarProducto(producto);
  }

  Future<void> _onBuscarCambio(String texto) async {
    _textoBuscado = texto.trim();

    if (_textoBuscado.isEmpty) {
      setState(() => _sugerencias = []);
      return;
    }

    // Modo hallazgos: se busca en el catálogo general (más amplio) para
    // registrar productos físicos que no están en el inventario.
    if (_modoCatalogo) {
      final resultados = await _conteoService.buscarCatalogo(
        _textoBuscado,
        conteoId: widget.conteoId,
      );
      if (!mounted) return;
      setState(() => _sugerencias = resultados);
      return;
    }

    final resultados = await _conteoService.buscarProductos(_textoBuscado);
    if (!mounted) return;

    // En un reconteo, solo se muestran los productos descuadrados.
    final filtrados = _esReconteo
        ? resultados
            .where((p) => _permitidos.contains(p["ProductoID"]))
            .toList()
        : resultados;

    setState(() => _sugerencias = filtrados);
  }

  // Registra un hallazgo: un producto del catálogo general encontrado
  // físicamente pero que no está en el inventario del conteo. Pide la
  // cantidad y lo guarda (online u offline, según haya conexión).
  Future<void> _registrarHallazgo(Map<String, dynamic> producto) async {
    final ctrl = TextEditingController();
    final cantidad = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Registrar hallazgo: ${producto["Nombre"]}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Unidad: ${producto["UnidadMedida"] ?? ""} · Grupo: ${producto["Grupo"] ?? ""}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Cantidad encontrada",
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
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(",", "."));
              Navigator.pop(context, v);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );

    if (cantidad == null || cantidad < 0) return;

    final res = await _conteoService.guardarEncontrado(
      conteoId: widget.conteoId,
      productoId: producto["ProductoID"],
      cantidad: cantidad,
      usuarioId: widget.usuario["id"],
      nombre: producto["Nombre"],
      unidadMedida: producto["UnidadMedida"],
      dispositivo: _dispositivo,
    );
    if (!mounted) return;

    if (res["ok"] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["mensaje"] ?? "No se pudo registrar el hallazgo"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Hallazgo registrado: ${producto["Nombre"]}"),
        backgroundColor: AppColors.verdeHoja,
      ),
    );

    setState(() {
      _hallazgosRegistrados++;
      _sugerencias = [];
      _buscarController.clear();
      _textoBuscado = "";
    });
  }

  void _seleccionarProducto(Map<String, dynamic> producto) {
    // En un reconteo, solo se permiten los productos descuadrados.
    if (_esReconteo && !_permitidos.contains(producto["ProductoID"])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este producto no forma parte del reconteo"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Si ya se contó, avisamos y no dejamos seleccionarlo.
    if (_yaContados.contains(producto["ProductoID"])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Este producto ya fue contado en esta ronda"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _productoSeleccionado = producto;
      _sugerencias = [];
      _buscarController.clear();
      _textoBuscado = "";
      _cantidadController.clear();
    });
  }

  Future<void> _guardar() async {
    final cantidad = double.tryParse(
      _cantidadController.text.trim().replaceAll(",", "."),
    );

    if (cantidad == null || cantidad < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingresa una cantidad válida")),
      );
      return;
    }

    setState(() => _guardando = true);

    final resultado = await _conteoService.guardarDetalle(
      conteoId: widget.conteoId,
      numeroConteo: widget.numeroConteo,
      productoId: _productoSeleccionado!["ProductoID"],
      cantidadFisica: cantidad,
      usuarioId: widget.usuario["id"],
      dispositivo: _dispositivo,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    if (resultado["ok"] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado["mensaje"] ?? "No se pudo guardar"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${_productoSeleccionado!["Nombre"]} contado"),
        backgroundColor: AppColors.verdeHoja,
      ),
    );

    setState(() {
      // Marcamos localmente al instante (el polling lo confirmará).
      _yaContados.add(_productoSeleccionado!["ProductoID"]);
      _productoSeleccionado = null;
      _cantidadController.clear();
    });

    // Refresca de inmediato la lista compartida (no espera los 5s).
    _sincronizarContados();
    _cargarConflictos();
  }

  // Termina el conteo (si no quedan faltantes) y va al resumen.
  Future<void> _terminarConteo() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Terminar conteo"),
        content: const Text(
          "¿Seguro que quieres terminar este conteo? "
          "Solo se puede si ya contaste todos los productos.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Terminar"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    // Validación de faltantes ANTES de cerrar (también offline), para no
    // marcar como terminado un conteo incompleto que luego el servidor
    // rechazaría al sincronizar.
    int faltan;
    if (_esReconteo) {
      faltan = _pendientes
          .where((p) => !_yaContados.contains(p["ProductoID"]))
          .length;
    } else {
      final f = await _conteoService.obtenerFaltantes(widget.conteoId);
      faltan = f.length;
    }
    if (!mounted) return;
    if (faltan > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Aún faltan $faltan productos por contar."),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final resultado = await _conteoService.terminarConteo(widget.conteoId);
    if (!mounted) return;

    if (resultado["ok"] != true) {
      // Ej: "Aún faltan N productos por contar".
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado["mensaje"] ?? "No se pudo terminar"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Intenta subir lo pendiente (si hay conexión). No se espera para no
    // demorar; si no hay internet, quedará en la cola.
    SyncService().sincronizar();

    // Terminado: pantalla simple de confirmación con botón para volver
    // a la lista de conteos (ya no se muestra el resumen al lector).
    Navigator.pushReplacement(
      context,
      rutaFade(ConteoTerminadoScreen(
        numeroConteo: widget.numeroConteo,
        esReconteo: _esReconteo,
      )),
    );
  }

  // Hoja con los productos en conflicto y opción de recontar para resolver.
  Future<void> _verConflictos() async {
    await _cargarConflictos();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _conflictos.isEmpty
                        ? "No hay conflictos 🎉"
                        : "${_conflictos.length} producto(s) en conflicto",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.vino,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _conflictos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _conflictos[i];
                      final lecturas = (c["lecturas"] as List<dynamic>?) ?? [];
                      // Cantidades distintas reportadas.
                      final valores = lecturas
                          .map((l) => l["CantidadFisica"].toString())
                          .toSet()
                          .join("  vs  ");
                      return ListTile(
                        leading: Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade800),
                        title: Text(c["Nombre"] ?? ""),
                        subtitle: Text(
                          "Lecturas: $valores\n${c["UnidadMedida"] ?? ""} · ${c["Grupo"] ?? ""}",
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () => _resolverConflicto(c),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.vino,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Recontar"),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Pide la cantidad definitiva y resuelve el conflicto del producto.
  Future<void> _resolverConflicto(Map<String, dynamic> c) async {
    final ctrl = TextEditingController();
    final cantidad = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Recontar: ${c["Nombre"]}"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Cantidad física correcta",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(",", "."));
              Navigator.pop(context, v);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );

    if (cantidad == null || cantidad < 0) return;

    final res = await _conteoService.resolverConflicto(
      conteoId: widget.conteoId,
      productoId: c["ProductoID"],
      cantidadFisica: cantidad,
      usuarioId: widget.usuario["id"],
      numeroConteo: widget.numeroConteo,
      dispositivo: _dispositivo,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res["ok"] == true
            ? "Conflicto resuelto"
            : (res["mensaje"] ?? "No se pudo resolver")),
        backgroundColor:
            res["ok"] == true ? AppColors.verdeHoja : Colors.red.shade700,
      ),
    );

    if (res["ok"] == true) {
      Navigator.of(context).pop(); // cierra la hoja
      await _cargarConflictos();
      _sincronizarContados();
    }
  }

  Future<void> _verFaltantes() async {
    // En un reconteo, lo que "falta" son los descuadrados del padre que
    // todavía no se han recontado (se calcula aquí, sin pedir todos los
    // productos). En un conteo completo se pregunta al backend.
    final List<dynamic> faltantes = _esReconteo
        ? _pendientes
            .where((p) => !_yaContados.contains(p["ProductoID"]))
            .toList()
        : await _conteoService.obtenerFaltantes(widget.conteoId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    faltantes.isEmpty
                        ? "¡No falta nada por contar! 🌹"
                        : "Faltan ${faltantes.length} productos por contar",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.vino,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: faltantes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = faltantes[i];
                      return ListTile(
                        leading: const Icon(Icons.local_florist,
                            color: AppColors.rosaMedio),
                        title: Text(p["Nombre"]),
                        subtitle: Text("${p["UnidadMedida"]} · ${p["Grupo"]}"),
                        trailing: Text("#${p["ProductoID"]}"),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Lista de productos descuadrados por recontar (estado inicial del
  // reconteo). Los ya recontados se marcan; los pendientes son tocables.
  Widget _listaPendientesReconteo() {
    if (_cargandoPendientes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pendientes.isEmpty) {
      return const Center(
        child: Text(
          "No hay productos descuadrados para recontar.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final pendientesPorContar =
        _pendientes.where((p) => !_yaContados.contains(p["ProductoID"])).length;

    // Agrupa los pendientes por GRUPO para un mejor orden de lectura.
    final Map<String, List<dynamic>> porGrupo = {};
    for (final p in _pendientes) {
      final g = (p["Grupo"] ?? "Sin grupo").toString();
      porGrupo.putIfAbsent(g, () => []).add(p);
    }
    final todosLosGrupos = porGrupo.keys.toList()..sort();

    // Si hay filtro, solo se muestra ese grupo.
    final grupos = _grupoReconteoFiltro == null
        ? todosLosGrupos
        : todosLosGrupos.where((g) => g == _grupoReconteoFiltro).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "Faltan $pendientesPorContar de ${_pendientes.length} por recontar",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.vino,
            ),
          ),
        ),
        // Filtro desplegable por grupo.
        DropdownButtonFormField<String?>(
          value: _grupoReconteoFiltro,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "Filtrar por grupo",
            prefixIcon: Icon(Icons.filter_list),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text("Todos los grupos"),
            ),
            ...todosLosGrupos.map(
              (g) => DropdownMenuItem<String?>(
                value: g,
                child: Text("$g (${porGrupo[g]!.length})",
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _grupoReconteoFiltro = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: grupos.length,
            itemBuilder: (_, gi) {
              final grupo = grupos[gi];
              final items = porGrupo[grupo]!;
              final faltanGrupo =
                  items.where((p) => !_yaContados.contains(p["ProductoID"])).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Encabezado del grupo.
                  Container(
                    color: AppColors.rosaSuave.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.category,
                            size: 16, color: AppColors.vino),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            grupo,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.vino,
                            ),
                          ),
                        ),
                        Text(
                          "$faltanGrupo/${items.length}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.vino,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Productos del grupo.
                  ...items.map((p) {
                    final yaContado = _yaContados.contains(p["ProductoID"]);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: yaContado
                            ? AppColors.verdeHoja
                            : Colors.orange.shade700,
                        child: Icon(
                          yaContado ? Icons.check : Icons.priority_high,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(p["Nombre"]),
                      subtitle: Text("${p["UnidadMedida"]}"),
                      trailing: yaContado
                          ? const Text("Recontado",
                              style: TextStyle(
                                  color: AppColors.verdeHoja, fontSize: 12))
                          : const Icon(Icons.chevron_right),
                      onTap: yaContado ? null : () => _seleccionarProducto(p),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }


  // MEJORA 2: construye el nombre resaltando la parte que coincide
  // con lo buscado (en rosa vino y negrita).
  Widget _nombreResaltado(String nombre) {
    if (_textoBuscado.isEmpty) {
      return Text(nombre);
    }

    final nombreLower = nombre.toLowerCase();
    final buscarLower = _textoBuscado.toLowerCase();
    final indice = nombreLower.indexOf(buscarLower);

    // Si no se encuentra la coincidencia en el nombre (ej. se buscó
    // por ID), lo mostramos normal.
    if (indice < 0) {
      return Text(nombre);
    }

    final antes = nombre.substring(0, indice);
    final coincide = nombre.substring(indice, indice + _textoBuscado.length);
    final despues = nombre.substring(indice + _textoBuscado.length);

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 15),
        children: [
          TextSpan(text: antes),
          TextSpan(
            text: coincide,
            style: const TextStyle(
              color: AppColors.vino,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xFFF3D9E1),
            ),
          ),
          TextSpan(text: despues),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _buscarController.dispose();
    _cantidadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarPersonalizado(
        titulo: _esReconteo
            ? "Reconteo #${widget.numeroConteo}"
            : "Conteo #${widget.numeroConteo}",
        usuario: widget.usuario,
        mostrarAtras: true,
        accionesExtra: [
          // Botón de conflictos (con contador) — solo si hay.
          if (_conflictos.isNotEmpty)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  onPressed: _verConflictos,
                  icon: const Icon(Icons.warning_amber_rounded,
                      color: Colors.white),
                  tooltip: "Conflictos",
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      "${_conflictos.length}",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          // Modo hallazgos: buscar en el catálogo general productos que
          // no están en el inventario (disponible en conteo y reconteo).
          IconButton(
            onPressed: _alternarModoCatalogo,
            icon: Icon(
              _modoCatalogo ? Icons.inventory_2 : Icons.travel_explore,
              color: _modoCatalogo ? Colors.amberAccent : Colors.white,
            ),
            tooltip: _modoCatalogo
                ? "Volver al inventario"
                : "Buscar en catálogo (hallazgos)",
          ),
          IconButton(
            onPressed: _verFaltantes,
            icon: const Icon(Icons.checklist, color: Colors.white),
            tooltip: "Falta por contar",
          ),
          IconButton(
            onPressed: _terminarConteo,
            icon: const Icon(Icons.flag, color: Colors.white),
            tooltip: "Terminar conteo",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _buscarController,
              onChanged: _onBuscarCambio,
              decoration: InputDecoration(
                labelText: _modoCatalogo
                    ? "Buscar en catálogo (hallazgo)"
                    : "Buscar por nombre o ID",
                prefixIcon: const Icon(Icons.search),
                // Botón de cámara para escanear.
                suffixIcon: IconButton(
                  onPressed: _escanear,
                  icon: const Icon(Icons.qr_code_scanner,
                      color: AppColors.vino),
                  tooltip: "Escanear código",
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            // Aviso de modo hallazgos: se busca en el catálogo general.
            if (_modoCatalogo)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.rosaSuave.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.rosaMedio),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.travel_explore,
                        size: 18, color: AppColors.vino),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Modo hallazgos: registra productos del catálogo que "
                        "no están en el inventario. Registrados: $_hallazgosRegistrados.",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.vino,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Aviso de reconteo: se explica que solo se cuentan los
            // productos que quedaron descuadrados.
            if (_esReconteo)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Reconteo: solo se cuentan los ${_permitidos.length} productos descuadrados del conteo anterior.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_sugerencias.isNotEmpty)
              // Flexible + scroll: ocupa el espacio disponible y NUNCA se
              // desborda (antes tenía alto fijo y con el teclado desbordaba).
              Flexible(
                child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.rosaSuave),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  itemCount: _sugerencias.length,
                  itemBuilder: (_, i) {
                    final p = _sugerencias[i];
                    // En modo hallazgos no aplica "ya contado".
                    final yaContado = !_modoCatalogo &&
                        _yaContados.contains(p["ProductoID"]);

                    return Container(
                      // MEJORA 3: fondo distinto si ya se contó.
                      color: yaContado
                          ? AppColors.rosaSuave.withOpacity(0.5)
                          : null,
                      child: ListTile(
                        dense: true,
                        leading: Text("#${p["ProductoID"]}"),
                        // MEJORA 2: nombre con la parte buscada resaltada.
                        title: _nombreResaltado(p["Nombre"]),
                        subtitle: Text("${p["UnidadMedida"]} · ${p["Grupo"]}"),
                        // En modo hallazgos: icono de "agregar"; si no,
                        // etiqueta "Ya contado" cuando corresponde.
                        trailing: _modoCatalogo
                            ? const Icon(Icons.add_circle_outline,
                                color: AppColors.vino)
                            : yaContado
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.verdeHoja,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      "Ya contado",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                        onTap: () => _modoCatalogo
                            ? _registrarHallazgo(p)
                            : _seleccionarProducto(p),
                      ),
                    );
                  },
                ),
              ),
            ),

            if (_sugerencias.isEmpty) const SizedBox(height: 16),

            if (_productoSeleccionado != null)
              // Expanded + SingleChildScrollView: al subir el teclado la
              // tarjeta se desplaza en vez de desbordarse (antes overflow 26px).
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  // Aparición suave (fade + leve subida) al elegir un producto.
                  // Es una animación de una sola vez (TweenAnimationBuilder),
                  // no consume recursos de forma continua.
                  child: TweenAnimationBuilder<double>(
                key: ValueKey(_productoSeleccionado!["ProductoID"]),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (_, valor, child) => Opacity(
                  opacity: valor,
                  child: Transform.translate(
                    offset: Offset(0, (1 - valor) * 12),
                    child: child,
                  ),
                ),
                child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _productoSeleccionado!["Nombre"],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.vino,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.straighten,
                              size: 18, color: AppColors.rosaProfundo),
                          const SizedBox(width: 6),
                          Text("Unidad: ${_productoSeleccionado!["UnidadMedida"]}"),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.category,
                              size: 18, color: AppColors.rosaProfundo),
                          const SizedBox(width: 6),
                          Text("Grupo: ${_productoSeleccionado!["Grupo"]}"),
                        ],
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _cantidadController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: "Cantidad física",
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _guardando ? null : _guardar,
                          child: _guardando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text("Guardar conteo"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ), // cierre del TweenAnimationBuilder
                ), // cierre del SingleChildScrollView
              ) // cierre del Expanded
            else if (_esReconteo && !_modoCatalogo && _sugerencias.isEmpty)
              // En reconteo mostramos directamente los descuadrados
              // pendientes (los que aún no se han recontado), tocables.
              Expanded(child: _listaPendientesReconteo())
            else if (_sugerencias.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _modoCatalogo
                            ? "Busca en el catálogo el producto que encontraste"
                            : "Busca un producto para empezar a contar",
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (_yaContados.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "${_yaContados.length} productos contados en esta ronda",
                          style: const TextStyle(
                            color: AppColors.verdeHoja,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}