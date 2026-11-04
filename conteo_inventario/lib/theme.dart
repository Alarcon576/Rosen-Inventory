// theme.dart
// Paleta de colores VERDE BOSQUE/NATURAL para Rosen Tantau.
// Tonos de hoja, musgo y tierra — natural, acorde a una finca.

import 'package:flutter/material.dart';
import 'services/local_store.dart';

class AppColors {
  static const Color verdeBosque = Color(0xFF2E5D34);   // verde principal (hoja oscura)
  static const Color verdeMedio = Color(0xFF4A7C50);    // verde medio
  static const Color verdeClaro = Color(0xFF7FA982);    // verde suave
  static const Color verdeSuave = Color(0xFFDCE8DC);    // fondo verde muy claro
  static const Color crema = Color(0xFFF7FAF5);          // fondo crema verdoso
  static const Color tierra = Color(0xFF8B6F47);         // acento tierra (tallo/tronco)
  static const Color textoOscuro = Color(0xFF2A322A);

  // Alias para compatibilidad con el código existente
  // (así no hay que renombrar en todas las pantallas).
  static const Color vino = verdeBosque;
  static const Color rosaProfundo = verdeMedio;
  static const Color rosaMedio = verdeClaro;
  static const Color rosaSuave = verdeSuave;
  static const Color verdeHoja = verdeMedio;

  // --- Superficies del MODO OSCURO ---
  static const Color fondoOscuro = Color(0xFF14181A);    // fondo general
  static const Color superficieOscura = Color(0xFF1E2427); // tarjetas/campos
}

// ============================================================
// TEMA CLARO (el de siempre)
// ============================================================
final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.crema,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.verdeBosque,
    primary: AppColors.verdeBosque,
    secondary: AppColors.verdeMedio,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.verdeBosque,
    foregroundColor: Colors.white,
    centerTitle: true,
    elevation: 0,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.verdeBosque,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
);

// ============================================================
// TEMA OSCURO
// Deriva de la misma semilla verde; el AppBar mantiene el verde
// de marca (el degradado del AppBar se pinta aparte en el widget).
// ============================================================
final ThemeData appThemeDark = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.fondoOscuro,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.verdeBosque,
    brightness: Brightness.dark,
    primary: AppColors.verdeClaro,
    secondary: AppColors.verdeMedio,
    surface: AppColors.superficieOscura,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.verdeBosque,
    foregroundColor: Colors.white,
    centerTitle: true,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    color: AppColors.superficieOscura,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: AppColors.superficieOscura,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.superficieOscura,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.verdeMedio,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
);

// ============================================================
// CONTROLADOR DE TEMA
// Guarda la preferencia (claro/oscuro) en el almacenamiento local
// y notifica a la app para reconstruir con el tema elegido.
// Uso:
//   ThemeController.instance.modo   -> ValueNotifier<ThemeMode>
//   ThemeController.instance.cargar()   (al arrancar)
//   ThemeController.instance.alternar() (desde el menú)
// ============================================================
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _clave = "tema_oscuro"; // bool en LocalStore

  final ValueNotifier<ThemeMode> modo = ValueNotifier<ThemeMode>(ThemeMode.light);

  bool get esOscuro => modo.value == ThemeMode.dark;

  // Lee la preferencia guardada (si existe) al iniciar la app.
  Future<void> cargar() async {
    try {
      final v = await LocalStore.leer(_clave);
      modo.value = (v == true) ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      modo.value = ThemeMode.light;
    }
  }

  // Cambia entre claro/oscuro y persiste la elección.
  Future<void> alternar() async {
    final oscuro = modo.value != ThemeMode.dark;
    modo.value = oscuro ? ThemeMode.dark : ThemeMode.light;
    try {
      await LocalStore.guardar(_clave, oscuro);
    } catch (_) {}
  }
}