// main.dart
// Punto de entrada de la app.

import 'package:conteo_inventario/services/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http; 

import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_client.dart' show Sesion;
import 'utils/transiciones.dart';
import 'theme.dart';
import 'services/conteo_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Carga los nombres de meses/días en español para DateFormat.
  await initializeDateFormatting('es', null);
  
  // Carga la preferencia de tema (claro/oscuro) guardada.
  await ThemeController.instance.cargar();


  // Si el servidor deja de aceptar la sesión (token vencido, usuario
  // desactivado o clave cambiada), se vuelve al login con un aviso.
  Sesion.alExpirar = () {
    final nav = Sesion.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(rutaFade(const LoginScreen()), (_) => false);
    Sesion.messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text("Tu sesión expiró. Inicia sesión de nuevo."),
        backgroundColor: Colors.orange,
      ),
    );
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.modo,
      builder: (_, modo, __) {
        return MaterialApp(
          navigatorKey: Sesion.navigatorKey,
          scaffoldMessengerKey: Sesion.messengerKey,
          title: 'Rosen Tantau - Inventario',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          darkTheme: appThemeDark,
          themeMode: modo,

          locale: const Locale('es'),
          supportedLocales: const [
            Locale('es'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          home: const SplashScreen(),
        );
      },
    );
  }
}