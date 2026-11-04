
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/app_bar_personalizado.dart';
import 'usuarios_screen.dart';
import 'reportes_screen.dart';
import 'gestion_conteos_screen.dart';

class AdminScreen extends StatelessWidget {
  final Map<String, dynamic> usuario;

  const AdminScreen({
    super.key,
    required this.usuario,
  });

  static const Color verde = Color(0xFF245C3A);
  static const Color verdeClaro = Color(0xFFEAF2EC);
  static const Color fondo = Color(0xFFF7F9F7);
  static const Color texto = Color(0xFF202A23);
  static const Color textoSecundario = Color(0xFF778078);
  static const Color borde = Color(0xFFE1E7E2);

  @override
  Widget build(BuildContext context) {
    final nombre = (usuario['nombre'] ?? 'Administrador').toString();

    return Scaffold(
      backgroundColor: fondo,
      appBar: AppBarPersonalizado(
        titulo: 'Administración',
        usuario: usuario,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Encabezado de bienvenida.
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: verde,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'PANEL ADMINISTRATIVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Hola, $nombre',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Administra los usuarios, controla los conteos '
                    'y consulta los reportes del inventario.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Icon(
                        Icons.eco_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Rosen Tantau · Control de Inventario',
                          style: TextStyle(
                            color: Colors.white,
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

            const SizedBox(height: 30),

            const Text(
              'Módulos de administración',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: texto,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Selecciona el módulo al que deseas ingresar.',
              style: TextStyle(
                fontSize: 13,
                color: textoSecundario,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 20),

            _opcion(
              context,
              icono: Icons.people_alt_outlined,
              titulo: 'Usuarios',
              descripcion: 'Crear, editar y desactivar usuarios.',
              detalle: 'GESTIÓN DE ACCESOS',
              destino: const UsuariosScreen(),
            ),

            _opcion(
              context,
              icono: Icons.fact_check_outlined,
              titulo: 'Conteos',
              descripcion: 'Gestionar, pausar o reanudar los conteos.',
              detalle: 'CONTROL DE INVENTARIO',
              destino: GestionConteosScreen(usuario: usuario),
            ),

            _opcion(
              context,
              icono: Icons.insert_chart_outlined_rounded,
              titulo: 'Reportes',
              descripcion: 'Consultar valores, pérdidas y sobrantes.',
              detalle: 'ANÁLISIS DE RESULTADOS',
              destino: const ReportesScreen(),
            ),

            const SizedBox(height: 18),

            // Identidad visual de la empresa.
            Center(
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: verdeClaro,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ROSEN TANTAU',
                    style: TextStyle(
                      color: verde,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Sistema de control de inventario',
                    style: TextStyle(
                      color: textoSecundario,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _opcion(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String descripcion,
    required String detalle,
    required Widget destino,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borde),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => destino,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: verdeClaro,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icono,
                    color: verde,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: texto,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        descripcion,
                        style: const TextStyle(
                          color: textoSecundario,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        detalle,
                        style: const TextStyle(
                          color: verde,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: verde,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
