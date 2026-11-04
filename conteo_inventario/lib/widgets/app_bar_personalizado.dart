import 'package:flutter/material.dart';
import '../theme.dart';
import '../screens/login_screen.dart';
import 'indicador_conexion.dart';

class AppBarPersonalizado extends StatelessWidget
    implements PreferredSizeWidget {
  final String titulo;
  final Map<String, dynamic>? usuario;
  final List<Widget> accionesExtra;
  final bool mostrarAtras;

  const AppBarPersonalizado({
    super.key,
    required this.titulo,
    this.usuario,
    this.accionesExtra = const [],
    this.mostrarAtras = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String get _nombreUsuario {
    final valor = usuario?['nombre']?.toString().trim();
    return valor == null || valor.isEmpty ? 'Usuario' : valor;
  }

  String get _rolUsuario {
    final valor = usuario?['rol']?.toString().trim();
    return valor == null || valor.isEmpty ? 'Sin rol' : valor;
  }

  String get _inicialUsuario {
    final nombre = _nombreUsuario.trim();
    return nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.logout,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text('Cerrar sesión'),
            ),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas cerrar tu sesión actual?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true || !context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  void _verPerfil(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Mi perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.vino.withValues(alpha: 0.1),
              child: Text(
                _inicialUsuario,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.vino,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _nombreUsuario,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _rolUsuario,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _construirMenu(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    return [
      PopupMenuItem<String>(
        enabled: false,
        height: 72,
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.vino.withValues(alpha: 0.1),
              child: Text(
                _inicialUsuario,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.vino,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _nombreUsuario,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _rolUsuario,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      const PopupMenuItem<String>(
        value: 'perfil',
        child: Row(
          children: [
            Icon(Icons.person_outline, size: 22),
            SizedBox(width: 12),
            Text('Ver perfil completo'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'tema',
        child: Row(
          children: [
            Icon(
              esOscuro
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              size: 22,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Modo oscuro'),
            ),
            Icon(
              esOscuro ? Icons.toggle_on : Icons.toggle_off,
              color: esOscuro
                  ? AppColors.verdeMedio
                  : Colors.grey.shade400,
              size: 24,
            ),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'salir',
        child: Row(
          children: [
            Icon(
              Icons.logout,
              size: 22,
              color: Colors.redAccent,
            ),
            SizedBox(width: 12),
            Text(
              'Cerrar sesión',
              style: TextStyle(
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: mostrarAtras,
      titleSpacing: 0,
      elevation: 2,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.vino,
              AppColors.rosaProfundo,
            ],
          ),
        ),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          // Si el espacio es poco (muchas acciones + "Sin conexión"),
          // se oculta el logo para que el título nunca desborde.
          final mostrarLogo = constraints.maxWidth >= 120;
          return Row(
            children: [
              if (mostrarLogo) ...[
                Container(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/rosen_tantau.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) => const Icon(
                        Icons.eco,
                        color: AppColors.vino,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Center(
            child: IndicadorConexion(),
          ),
        ),
        ...accionesExtra,
        if (usuario != null) ...[
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            tooltip: 'Opciones de usuario',
            icon: const Icon(
              Icons.more_vert,
              color: Colors.white,
            ),
            offset: const Offset(0, kToolbarHeight),
            onSelected: (valor) {
              if (!context.mounted) return;

              switch (valor) {
                case 'perfil':
                  _verPerfil(context);
                  break;
                case 'tema':
                  ThemeController.instance.alternar();
                  break;
                case 'salir':
                  _cerrarSesion(context);
                  break;
              }
            },
            itemBuilder: _construirMenu,
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}