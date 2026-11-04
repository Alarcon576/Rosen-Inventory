
import 'package:flutter/material.dart';

import '../services/conteo_service.dart';
import '../utils/transiciones.dart';
import '../widgets/indicador_conexion.dart';
import 'escaneo_screen.dart';

class NuevoConteoScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;

  const NuevoConteoScreen({
    super.key,
    required this.usuario,
  });

  @override
  State<NuevoConteoScreen> createState() => _NuevoConteoScreenState();
}

class _NuevoConteoScreenState extends State<NuevoConteoScreen> {
  static const Color verdePrincipal = Color(0xFF245C3A);
  static const Color verdeSecundario = Color(0xFF34754A);
  static const Color verdeClaro = Color(0xFFE7F1E8);
  static const Color fondoPantalla = Color(0xFFF5F7F5);
  static const Color textoPrincipal = Color(0xFF203B2A);
  static const Color textoSecundario = Color(0xFF66756A);
  static const Color borde = Color(0xFFD7E2D9);

  final _numeroController = TextEditingController();
  final _numeroFocus = FocusNode();
  final _conteoService = ConteoService();
  final _formKey = GlobalKey<FormState>();

  DateTime? _fechaInicio;
  bool _cargando = false;

  DateTime get _hoy {
    final fecha = DateTime.now();
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  String get _nombreUsuario {
    final nombre = widget.usuario['nombre']?.toString().trim();

    return nombre == null || nombre.isEmpty
        ? 'Almacenista'
        : nombre;
  }

  String get _fechaFormateada {
    if (_fechaInicio == null) return 'Seleccionar fecha';

    final fecha = _fechaInicio!;
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  String get _fechaParaBackend {
    final fecha = _fechaInicio!;

    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _numeroFocus.dispose();
    super.dispose();
  }

  void _mostrarMensaje(
    String mensaje, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              error ? Colors.red.shade700 : verdePrincipal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Icon(
                error
                    ? Icons.error_outline
                    : Icons.info_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(mensaje),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _elegirFecha() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaInicio ?? _hoy,
      firstDate: _hoy,
      lastDate: DateTime(2100),
      helpText: 'FECHA DEL CONTEO',
      cancelText: 'Cancelar',
      confirmText: 'Seleccionar',
      builder: (context, child) {
        final tema = Theme.of(context);

        return Theme(
          data: tema.copyWith(
            colorScheme: tema.colorScheme.copyWith(
              primary: verdePrincipal,
              secondary: verdeSecundario,
              surface: Colors.white,
            ),
            datePickerTheme: DatePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (fecha == null || !mounted) return;

    setState(() {
      _fechaInicio = fecha;
    });
  }

  Future<void> _generarConteo() async {
    if (_cargando) return;

    FocusScope.of(context).unfocus();

    if (_fechaInicio == null) {
      _mostrarMensaje('Selecciona la fecha del conteo.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final numero = int.tryParse(
      _numeroController.text.trim(),
    );

    if (numero == null || numero <= 0) {
      _mostrarMensaje(
        'Ingresa un número de conteo válido.',
        error: true,
      );
      return;
    }

    final fecha = _fechaInicio!;
    final soloFecha = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    );

    if (soloFecha.isBefore(_hoy)) {
      _mostrarMensaje(
        'No se permiten fechas anteriores a hoy.',
        error: true,
      );
      return;
    }

    setState(() => _cargando = true);

    try {
      final activos =
          await _conteoService.obtenerConteosActivos();

      if (!mounted) return;

      if (activos.isNotEmpty) {
        final numeroActivo = activos.first['NumeroConteo'];

        _mostrarMensaje(
          'Ya existe un conteo en proceso (#$numeroActivo). '
          'Finalízalo antes de crear otro.',
          error: true,
        );
        return;
      }

      final resultado = await _conteoService.crearConteo(
        numero,
        _fechaParaBackend,
      );

      if (!mounted) return;

      if (resultado['ok'] != true) {
        _mostrarMensaje(
          resultado['mensaje']?.toString() ??
              'No se pudo crear el conteo.',
          error: true,
        );
        return;
      }

      final conteoId = resultado['conteoId'];
      final conteoPadreId = resultado['conteoPadreId'];

      Navigator.pushReplacement(
        context,
        rutaFade(
          EscaneoScreen(
            conteoId: conteoId,
            numeroConteo: numero,
            usuario: widget.usuario,
            conteoPadreId: conteoPadreId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _mostrarMensaje(
        'No fue posible crear el conteo. '
        'Verifica la conexión e inténtalo nuevamente.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoPantalla,
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        backgroundColor: verdePrincipal,
        foregroundColor: Colors.white,
        title: const Text(
          'Nuevo conteo',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 19,
            letterSpacing: 0.2,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: IndicadorConexion(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _construirBienvenida(),
                  const SizedBox(height: 24),
                  _construirFormulario(),
                  const SizedBox(height: 18),
                  _construirConsejo(),
                  const SizedBox(height: 20),
                  _construirBoton(),
                  const SizedBox(height: 18),
                  const Text(
                    'ROSEN TANTAU · CONTROL DE INVENTARIO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textoSecundario,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirBienvenida() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: verdeClaro,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: verdePrincipal,
            size: 29,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '¡Hola!',
          style: TextStyle(
            color: textoPrincipal,
            fontSize: 29,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _nombreUsuario,
          style: const TextStyle(
            color: verdePrincipal,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'completando los siguientes datos.',
          style: TextStyle(
            color: textoSecundario,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _construirFormulario() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borde),
        boxShadow: [
          BoxShadow(
            color: verdePrincipal.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: verdeClaro,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    color: verdePrincipal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Datos del conteo',
                        style: TextStyle(
                          color: textoPrincipal,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Completa la información requerida',
                        style: TextStyle(
                          color: textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 27),
            _construirEtiqueta(
              'Fecha de inicio',
              requerida: true,
            ),
            const SizedBox(height: 9),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _elegirFecha,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _fechaInicio == null
                          ? borde
                          : verdePrincipal.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: verdePrincipal,
                        size: 23,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fechaFormateada,
                              style: TextStyle(
                                color: _fechaInicio == null
                                    ? textoSecundario
                                    : textoPrincipal,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Selecciona el día del inventario',
                              style: TextStyle(
                                color: textoSecundario,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: verdePrincipal,
                        size: 25,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 23),
            _construirEtiqueta(
              'Número de conteo',
              requerida: true,
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: _numeroController,
              focusNode: _numeroFocus,
              enabled: !_cargando,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _generarConteo(),
              style: const TextStyle(
                color: textoPrincipal,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Ej. 1, 2, 3...',
                hintStyle: const TextStyle(
                  color: textoSecundario,
                  fontWeight: FontWeight.normal,
                ),
                prefixIcon: const Icon(
                  Icons.tag_rounded,
                  color: verdePrincipal,
                  size: 23,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 17,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borde),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borde),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: verdePrincipal,
                    width: 1.6,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
              ),
              validator: (valor) {
                final numero = int.tryParse(
                  valor?.trim() ?? '',
                );

                if (numero == null || numero <= 0) {
                  return 'Ingresa un número entero mayor que cero';
                }

                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirEtiqueta(
    String texto, {
    bool requerida = false,
  }) {
    return Row(
      children: [
        Text(
          texto,
          style: const TextStyle(
            color: textoPrincipal,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (requerida)
          const Text(
            ' *',
            style: TextStyle(
              color: verdeSecundario,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _construirConsejo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: verdeClaro,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: borde),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: verdePrincipal,
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Antes de comenzar',
                  style: TextStyle(
                    color: verdePrincipal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Verifica la fecha y el número. Solo puede '
                  'haber un conteo en proceso a la vez. '
                  'Si hay uno activo, debes finalizarlo primero.',
                  style: TextStyle(
                    color: textoSecundario,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirBoton() {
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              verdePrincipal,
              verdeSecundario,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: verdePrincipal.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _cargando ? null : _generarConteo,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _cargando
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Preparando conteo...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 23,
                    ),
                    SizedBox(width: 11),
                    Text(
                      'Generar conteo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(width: 9),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
