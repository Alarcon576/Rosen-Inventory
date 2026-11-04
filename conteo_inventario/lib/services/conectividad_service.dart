// conectividad_service.dart
// Versión "Nuclear" para forzar la actualización de red sin apagar el Wi-Fi.

import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';

class ConectividadService {
  
  static Future<bool> hayBackend() async {
    // 1. TRUCO: Añadimos un timestamp para evitar caché de red/proxy
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urlConCacheBuster = "${Config.baseUrl}/?_=$timestamp";

    // --- INTENTO 1: Normal ---
    if (await _probarConexion(urlConCacheBuster)) {
      return true;
    }

    print("⚠️ Fallo inicial. Ejecutando protocolo de forzamiento de red...");

    // --- PROTOCOLO DE FORZAMIENTO ---
    try {
      final uri = Uri.parse(Config.baseUrl);
      
      // 2. TRUCO: Forzamos una búsqueda de DNS explícita a nivel de Dart
      print("🔄 Buscando dirección IP para: ${uri.host}");
      final addresses = await InternetAddress.lookup(uri.host);
      print("✅ DNS Resuelto exitosamente a: ${addresses.first.address}");
      
    } catch (e) {
      // 3. TRUCO: Si falla, el sistema operativo aún tiene el caché negativo.
      // Esperamos 1.5 segundos. A veces, el demonio mDNS de Android actualiza 
      // la tabla en segundo plano justo en este lapso.
      print("⏳ DNS en caché negativo. Esperando 1.5s a que el sistema actualice...");
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    // 4. TRUCO: Usamos un Cliente HTTP TOTALMENTE NUEVO.
    // El cliente por defecto de Dart puede mantener sockets o caché interno.
    // Al crear uno nuevo y destruirlo, limpiamos ese estado.
    final clienteFresco = http.Client();
    
    try {
      print("🔄 Reintentando con cliente de red fresco...");
      final r = await clienteFresco
          .get(Uri.parse(urlConCacheBuster))
          .timeout(const Duration(seconds: 4));
      
      clienteFresco.close(); // Destruimos el cliente para liberar recursos
      return r.statusCode == 200;
      
    } catch (e) {
      clienteFresco.close();
      print("❌ El backend sigue inaccesible incluso tras el forzamiento: $e");
      return false;
    }
  }

  // Función auxiliar para el primer intento rápido
  static Future<bool> _probarConexion(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}