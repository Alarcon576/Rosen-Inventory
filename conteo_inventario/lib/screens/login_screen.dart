// login_screen.dart
// Pantalla de inicio de sesión con identidad Rosen Tantau.

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/conteo_service.dart';
import '../theme.dart';
import '../utils/transiciones.dart';
import '../widgets/indicador_conexion.dart';
import 'inicio_screen.dart';
import 'admin_screen.dart';
import 'reportes_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _authService = AuthService();

  bool _cargando = false;
  String? _error;

  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await _authService.login(
      _nombreController.text.trim(),
      _contrasenaController.text,
    );

    if (!mounted) return;
    setState(() => _cargando = false);

    if (resultado == null) {
      setState(() => _error = "Usuario o contraseña incorrectos");
      return;
    }

    final usuario = Map<String, dynamic>.from(resultado["usuario"]);
    final offline = resultado["offline"] == true;

    // Con conexión: descarga el catálogo de productos en segundo plano
    // para poder trabajar luego sin internet. Sin conexión: avisa.
    if (offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Entraste sin conexión. Se usarán los datos guardados."),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      // No se espera (fire-and-forget) para no demorar el ingreso.
      final cs = ConteoService();
      cs.descargarCatalogo();
      cs.descargarReconteoPendientes(); // para reconteo offline
      cs.descargarCatalogoGeneral();    // para hallazgos offline
    }

    if (usuario["rol"] == "Lector") {
      Navigator.pushReplacement(
        context,
        rutaFade(InicioScreen(usuario: usuario)),
      );
    } else if (usuario["rol"] == "Admin") {
      Navigator.pushReplacement(
        context,
        rutaFade(AdminScreen(usuario: usuario)),
      );
    } else if (usuario["rol"] == "Reportes") {
      // Rol solo-reportes: su panel principal es la pantalla de reportes.
      Navigator.pushReplacement(
        context,
        rutaFade(ReportesScreen(usuario: usuario)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Bienvenido ${usuario["nombre"]} (rol: ${usuario["rol"]}). "
            "Pantalla de este rol pendiente.",
          ),
          backgroundColor: AppColors.verdeHoja,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo con degradado y formulario centrado.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.crema, AppColors.rosaSuave],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Emblema circular con el logo de Rosen Tantau
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.vino.withOpacity(0.20),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: "logoRosen",
                          child: ClipOval(
                            child: Image.asset(
                              "assets/rosen_tantau.png",
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        "Rosen Tantau",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.vino,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Control de Inventario",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textoOscuro.withOpacity(0.6),
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Tarjeta blanca con el formulario
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.vino.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nombreController,
                              decoration: InputDecoration(
                                labelText: "Usuario",
                                prefixIcon: const Icon(Icons.person_outline,
                                    color: AppColors.rosaProfundo),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: AppColors.vino, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            TextField(
                              controller: _contrasenaController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: "Contraseña",
                                prefixIcon: const Icon(Icons.lock_outline,
                                    color: AppColors.rosaProfundo),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: AppColors.vino, width: 2),
                                ),
                              ),
                            ),

                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.red, size: 18),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style:
                                            const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _cargando ? null : _iniciarSesion,
                                child: _cargando
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text("Ingresar"),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        "Rosas premium desde 1906",
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textoOscuro.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Indicador de conexión arriba a la derecha.
          Positioned(
            top: 44,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.vino,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const IndicadorConexion(),
            ),
          ),
        ],
      ),
    );
  }
}