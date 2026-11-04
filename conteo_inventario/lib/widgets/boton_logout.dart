import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
class BotonLogout extends StatelessWidget {
  const BotonLogout({super.key});

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cerrar sesión"),
        content: const Text("¿Seguro que quieres cerrar sesión?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Cerrar sesión"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!context.mounted) return;

    
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _cerrarSesion(context),
      icon: const Icon(Icons.logout),
      tooltip: "Cerrar sesión",
    );
  }
}