
import 'package:flutter/material.dart';

import '../services/conteo_service.dart';
import '../services/sync_service.dart';
import '../utils/transiciones.dart';
import '../widgets/app_bar_personalizado.dart';
import '../screens/nuevo_conteo_screen.dart';
import '../screens/escaneo_screen.dart';

class InicioScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;

  const InicioScreen({
    super.key,
    required this.usuario,
  });

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  static const Color verdePrincipal = Color(0xFF245C3A);
  static const Color verdeSecundario = Color(0xFF34754A);
  static const Color verdeClaro = Color(0xFFE7F1E8);
  static const Color fondoPantalla = Color(0xFFF5F7F5);
  static const Color textoPrincipal = Color(0xFF203B2A);
  static const Color textoSecundario = Color(0xFF66756A);
  static const Color borde = Color(0xFFD7E2D9);

  final _conteoService = ConteoService();
  final _sync = SyncService();

  List<dynamic> _activos = [];

  bool _cargando = true;
  bool _sincronizando = false;
  bool _errorCarga = false;
  bool _actualizandoCatalogo = false;

  int _pendientes = 0;
  DateTime? _ultimaActualizacion;

  String get _nombreUsuario {
    final nombre = widget.usuario['nombre']?.toString().trim();

    if (nombre == null || nombre.isEmpty) {
      return 'Almacenista';
    }

    return nombre;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _sincronizarEnFondo();
    _cargarFechaCatalogo();
  }

  Future<void> _cargarFechaCatalogo() async {
    try {
      final fecha = await _conteoService.ultimaActualizacionCatalogos();
      if (!mounted) return;
      setState(() => _ultimaActualizacion = fecha);
    } catch (_) {}
  }

  // ---- Reglas del catálogo ----
  Duration? get _edadCatalogo {
    final f = _ultimaActualizacion;
    return f == null ? null : DateTime.now().difference(f);
  }

  // Desactualizado: nunca registrado o más viejo que el máximo permitido.
  bool get _desactualizado {
    final e = _edadCatalogo;
    return e == null ||
        e > const Duration(hours: ConteoService.horasMaxCatalogo);
  }

  // Con un conteo en curso no se puede actualizar el catálogo.
  bool get _hayConteoEnCurso => _activos.isNotEmpty;

  String _textoEdad() {
    final e = _edadCatalogo;
    if (e == null) return 'tiempo indeterminado';
    if (e.inHours < 1) return 'menos de 1 hora';
    if (e.inHours < 48) {
      return '${e.inHours} hora${e.inHours == 1 ? '' : 's'}';
    }
    return '${e.inDays} días';
  }

  Future<bool?> _confirmar(
    String titulo,
    String mensaje,
    String textoConfirmar,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: verdePrincipal,
              foregroundColor: Colors.white,
            ),
            child: Text(textoConfirmar),
          ),
        ],
      ),
    );
  }

  // Se llama antes de iniciar un conteo. Devuelve true si se puede seguir.
  // - Catálogo al día: sigue.
  // - Desactualizado: obliga a actualizar primero.
  // - Si no se puede actualizar (conteo en curso o sin conexión) y ya hay
  //   un catálogo en el teléfono, deja continuar solo con confirmación.
  // - Si no hay catálogo en el teléfono, no deja continuar.
  Future<bool> _asegurarCatalogoActual() async {
    await _cargarFechaCatalogo();
    if (!mounted) return false;
    if (!_desactualizado) return true;

    final vacio = await _conteoService.catalogoLocalVacio();
    if (!mounted) return false;

    final primeraVez = _ultimaActualizacion == null;

    // Solo informa el tiempo transcurrido (sin recomendaciones).
    final antiguedad = primeraVez
        ? 'Es la primera vez que se inicia un conteo en este dispositivo, '
            'por eso se debe actualizar el inventario.'
        : 'Tu inventario lleva ${_textoEdad()} sin actualizarse.';

    final titulo =
        primeraVez ? 'Primera actualización' : 'Inventario desactualizado';

    if (_hayConteoEnCurso && !vacio) {
      final seguir = await _confirmar(
        titulo,
        '$antiguedad\n\nHay un conteo en curso, por lo que no se puede '
            'actualizar ahora.',
        'Continuar',
      );
      return seguir ?? false;
    }

    final actualizar = await _confirmar(
      titulo,
      antiguedad,
      'Actualizar ahora',
    );
    if (actualizar != true || !mounted) return false;

    final r = await _ejecutarActualizacion();
    if (!mounted) return false;
    if (r['ok'] == true) return true;

    final motivo = r['mensaje']?.toString() ?? 'No se pudo actualizar.';

    if (vacio) {
      _mostrarAviso(motivo, correcto: false);
      return false;
    }

    final seguir = await _confirmar(
      'No se pudo actualizar',
      '$motivo\n\n$antiguedad',
      'Continuar',
    );
    return seguir ?? false;
  }

  void _mostrarAviso(String mensaje, {required bool correcto}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor:
              correcto ? verdePrincipal : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  String _textoActualizacion() {
    final f = _ultimaActualizacion;
    if (f == null) return 'Sin registro de actualización';

    String dos(int n) => n.toString().padLeft(2, '0');
    final hora = '${dos(f.hour)}:${dos(f.minute)}';
    final ahora = DateTime.now();
    final esHoy = f.year == ahora.year &&
        f.month == ahora.month &&
        f.day == ahora.day;

    final base = esHoy
        ? 'Actualizado hoy a las $hora'
        : 'Actualizado el ${dos(f.day)}/${dos(f.month)} a las $hora';

    return _desactualizado ? '$base · desactualizado' : base;
  }

  // Ejecuta la actualización (el servicio valida el candado de conteos).
  Future<Map<String, dynamic>> _ejecutarActualizacion() async {
    if (_actualizandoCatalogo) {
      return {'ok': false, 'mensaje': 'Ya se está actualizando.'};
    }

    setState(() => _actualizandoCatalogo = true);

    Map<String, dynamic> resultado;

    try {
      resultado = await _conteoService.actualizarCatalogos();
    } catch (_) {
      resultado = {
        'ok': false,
        'mensaje': 'No fue posible actualizar el inventario. '
            'Se mantiene la copia anterior.',
      };
    }

    if (mounted) {
      setState(() => _actualizandoCatalogo = false);
      await _cargarFechaCatalogo();
    }

    return resultado;
  }

  Future<void> _actualizarCatalogo() async {
    final resultado = await _ejecutarActualizacion();

    if (!mounted) return;

    final correcto = resultado['ok'] == true;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(resultado['mensaje']?.toString() ??
              (correcto
                  ? 'Inventario actualizado.'
                  : 'No se pudo actualizar el inventario.')),
          backgroundColor:
              correcto ? verdePrincipal : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _errorCarga = false;
      });
    }

    try {
      final activos =
          await _conteoService.obtenerConteosActivos();

      final pendientes = await _sync.pendientes();

      if (!mounted) return;

      setState(() {
        _activos = activos;
        _pendientes = pendientes;
        _cargando = false;
        _errorCarga = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _errorCarga = true;
      });
    }
  }

  Future<void> _sincronizarEnFondo() async {
    try {
      final resultado = await _sync.sincronizar();

      if (!mounted) return;

      if (resultado['ok'] == true &&
          (resultado['subidos'] ?? 0) > 0) {
        await _cargar();
      } else {
        final pendientes = await _sync.pendientes();

        if (!mounted) return;

        setState(() {
          _pendientes = pendientes;
        });
      }
    } catch (_) {
      try {
        final pendientes = await _sync.pendientes();

        if (!mounted) return;

        setState(() {
          _pendientes = pendientes;
        });
      } catch (_) {
        // Se conserva el estado actual si no es posible consultar
        // la cantidad de cambios pendientes.
      }
    }
  }

  Future<void> _sincronizarManual() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    Map<String, dynamic> resultado;

    try {
      resultado = Map<String, dynamic>.from(
        await _sync.sincronizar(),
      );
    } catch (_) {
      resultado = {
        'ok': false,
        'mensaje': 'No fue posible sincronizar. '
            'Verifica la conexión de la empresa.',
      };
    }

    if (!mounted) return;

    setState(() => _sincronizando = false);

    await _cargar();

    if (!mounted) return;

    final correcto = resultado['ok'] == true;

    final mensaje = resultado['mensaje']?.toString() ??
        (correcto
            ? 'Sincronización completada.'
            : 'No se pudo sincronizar. Los cambios pendientes '
                'se conservarán para intentarlo nuevamente.');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor:
              correcto ? verdePrincipal : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _crearNuevo() async {
    // Antes de iniciar un conteo, el inventario debe estar al día.
    if (!await _asegurarCatalogoActual()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      rutaFade(
        NuevoConteoScreen(usuario: widget.usuario),
      ),
    );

    if (mounted) {
      await _cargar();
    }
  }

  Future<void> _unirse(Map<String, dynamic> conteo) async {
    await Navigator.push(
      context,
      rutaFade(
        EscaneoScreen(
          conteoId: conteo['ConteoID'],
          numeroConteo: conteo['NumeroConteo'],
          usuario: widget.usuario,
          conteoPadreId: conteo['ConteoPadreID'],
        ),
      ),
    );

    if (mounted) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoPantalla,
      appBar: AppBarPersonalizado(
        titulo: 'Inventario',
        usuario: widget.usuario,
      ),
      body: RefreshIndicator(
        color: verdePrincipal,
        onRefresh: _cargar,
        child: _cargando
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 220),
                  Center(
                    child: CircularProgressIndicator(
                      color: verdePrincipal,
                    ),
                  ),
                  SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Cargando inventario...',
                      style: TextStyle(
                        color: textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
                children: [
                  _construirBienvenida(),
                  const SizedBox(height: 22),

                  if (_pendientes > 0) ...[
                    _bannerPendientes(),
                    const SizedBox(height: 20),
                  ],

                  _botonCrear(),
                  const SizedBox(height: 14),

                  _tarjetaCatalogo(),
                  const SizedBox(height: 22),

                  _construirResumen(),
                  const SizedBox(height: 27),

                  _construirEncabezadoConteos(),
                  const SizedBox(height: 14),

                  if (_errorCarga)
                    _construirErrorCarga()
                  else if (_activos.isEmpty)
                    _estadoVacio()
                  else
                    ..._activos.map(
                      (conteo) => _tarjetaConteo(
                        Map<String, dynamic>.from(conteo as Map),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _construirBienvenida() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PANEL DE CONTROL',
          style: TextStyle(
            color: verdeSecundario,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 9),
        const SizedBox(height: 8),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: verdeSecundario,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Control de inventario',
                style: TextStyle(
                  color: textoSecundario,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.inventory_2_outlined,
              color: verdePrincipal,
              size: 19,
            ),
          ],
        ),
      ],
    );
  }

  Widget _botonCrear() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(23),
      child: InkWell(
        onTap: _crearNuevo,
        borderRadius: BorderRadius.circular(23),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                verdePrincipal,
                verdeSecundario,
              ],
            ),
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: verdePrincipal.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.18),
                  ),
                ),
                child: const Icon(
                  Icons.add_box_outlined,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nuevo conteo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Inicia una jornada de inventario',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Comenzar ahora',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 7),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCatalogo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: borde),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: verdeClaro,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: verdePrincipal,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catálogo de productos',
                  style: TextStyle(
                    color: textoPrincipal,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _hayConteoEnCurso
                      ? '${_textoActualizacion()}\n'
                          'Bloqueado: hay un conteo en curso'
                      : _textoActualizacion(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _desactualizado
                        ? const Color(0xFF9A5A0A)
                        : textoSecundario,
                    fontSize: 11,
                    fontWeight: _desactualizado
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: (_actualizandoCatalogo || _hayConteoEnCurso)
                  ? null
                  : _actualizarCatalogo,
              style: OutlinedButton.styleFrom(
                foregroundColor: verdePrincipal,
                side: const BorderSide(color: verdePrincipal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: _actualizandoCatalogo
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: verdePrincipal,
                      ),
                    )
                  : Icon(
                      _hayConteoEnCurso
                          ? Icons.lock_outline_rounded
                          : Icons.refresh_rounded,
                      size: 17,
                    ),
              label: Text(
                _actualizandoCatalogo
                    ? 'Actualizando...'
                    : (_hayConteoEnCurso ? 'Bloqueado' : 'Actualizar'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirResumen() {
    final cantidadActivos = _activos.length;

    return Row(
      children: [
        Expanded(
          child: _tarjetaResumen(
            icono: Icons.play_circle_outline_rounded,
            titulo: 'En proceso',
            valor: '$cantidadActivos',
            color: verdePrincipal,
            fondo: verdeClaro,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tarjetaResumen(
            icono: _pendientes > 0
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined,
            titulo: 'Por sincronizar',
            valor: '$_pendientes',
            color: _pendientes > 0
                ? const Color(0xFF9A5A0A)
                : verdePrincipal,
            fondo: _pendientes > 0
                ? const Color(0xFFFFF2D9)
                : verdeClaro,
          ),
        ),
      ],
    );
  }

  Widget _tarjetaResumen({
    required IconData icono,
    required String titulo,
    required String valor,
    required Color color,
    required Color fondo,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icono,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            valor,
            style: const TextStyle(
              color: textoPrincipal,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textoSecundario,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirEncabezadoConteos() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Conteos en curso',
                style: TextStyle(
                  color: textoPrincipal,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _activos.isEmpty
                    ? 'No tienes jornadas activas'
                    : 'Selecciona un conteo para continuar',
                style: const TextStyle(
                  color: textoSecundario,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (_activos.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: verdeClaro,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_activos.length} activo${_activos.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: verdePrincipal,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bannerPendientes() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF0D6A8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE7BD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.cloud_upload_outlined,
              color: Color(0xFF925500),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cambios pendientes',
                  style: TextStyle(
                    color: Color(0xFF704400),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Tienes $_pendientes cambio(s) por sincronizar '
                  'con el servidor.',
                  style: const TextStyle(
                    color: Color(0xFF805E2C),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: _sincronizando
                        ? null
                        : _sincronizarManual,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF805000),
                      side: const BorderSide(
                        color: Color(0xFFD7B675),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                    icon: _sincronizando
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            size: 17,
                          ),
                    label: Text(
                      _sincronizando
                          ? 'Sincronizando...'
                          : 'Sincronizar ahora',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaConteo(Map<String, dynamic> conteo) {
    final esReconteo = conteo['ConteoPadreID'] != null;
    final esLocal = conteo['_local'] == true;
    final esCache = conteo['_cache'] == true;

    final numero = conteo['NumeroConteo'] ?? '—';
    final contados = conteo['Contados'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borde),
        boxShadow: [
          BoxShadow(
            color: verdePrincipal.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _unirse(conteo),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 60,
                  decoration: BoxDecoration(
                    color: verdeClaro,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: verdePrincipal,
                        size: 19,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '#$numero',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: verdePrincipal,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        esReconteo
                            ? 'Reconteo #$numero'
                            : 'Conteo #$numero',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textoPrincipal,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _etiquetaEstado(
                            texto: 'En proceso',
                            color: verdePrincipal,
                            fondo: verdeClaro,
                            icono: Icons.play_circle_outline,
                          ),
                          if (esLocal)
                            _etiquetaEstado(
                              texto: 'Local',
                              color: const Color(0xFF925500),
                              fondo: const Color(0xFFFFF0D5),
                              icono: Icons.cloud_off_outlined,
                            ),
                          if (!esLocal && esCache)
                            _etiquetaEstado(
                              texto: 'En caché',
                              color: const Color(0xFF52616B),
                              fondo: const Color(0xFFEAF0F3),
                              icono: Icons.offline_bolt_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.inventory_outlined,
                            color: textoSecundario,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$contados productos contados',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: fondoPantalla,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: verdePrincipal,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _etiquetaEstado({
    required String texto,
    required Color color,
    required Color fondo,
    required IconData icono,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icono,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 32,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borde),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: verdeClaro,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: verdePrincipal,
              size: 36,
            ),
          ),
          const SizedBox(height: 19),
          const Text(
            'Todo listo para comenzar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textoPrincipal,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No hay conteos en curso. Crea una nueva jornada '
            'para empezar a registrar el inventario.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textoSecundario,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _crearNuevo,
            style: OutlinedButton.styleFrom(
              foregroundColor: verdePrincipal,
              side: const BorderSide(color: verdePrincipal),
              padding: const EdgeInsets.symmetric(
                horizontal: 17,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Crear primer conteo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirErrorCarga() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borde),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: textoSecundario,
            size: 38,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudo actualizar la información',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textoPrincipal,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Comprueba la conexión e inténtalo de nuevo. '
            'Desliza hacia abajo para actualizar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textoSecundario,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: verdePrincipal,
              side: const BorderSide(color: borde),
            ),
          ),
        ],
      ),
    );
  }
}

// Indicador animado del estado "En proceso".
class _LedVerde extends StatefulWidget {
  const _LedVerde();

  @override
  State<_LedVerde> createState() => _LedVerdeState();
}

class _LedVerdeState extends State<_LedVerde>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.3,
        end: 1,
      ).animate(_controller),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: _InicioScreenState.verdeSecundario,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _InicioScreenState.verdeSecundario.withOpacity(0.35),
              blurRadius: 5,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
