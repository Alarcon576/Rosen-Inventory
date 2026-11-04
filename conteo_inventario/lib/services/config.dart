import 'dart:io';
import 'api_client.dart' as http;

class Config {
  static const String baseUrl = "http://10.81.0.97:3000";

  /// Llama a esta función cuando una petición falle.
  /// Fuerza al sistema a buscar el nombre de nuevo, como si hubieras apagado/prendido el Wi-Fi.
  static Future<bool> forzarReconexion() async {
    print("🔄 Forzando nueva resolución de DNS para: $baseUrl");
    try {
      final uri = Uri.parse(baseUrl);
      
      // Socket.connect es más "crudo" y obliga al OS a preguntar al router de nuevo
      final socket = await Socket.connect(
        uri.host, 
        uri.port, 
        timeout: const Duration(seconds: 3)
      );
      socket.destroy(); // Cerramos inmediatamente, solo queríamos probar la ruta
      
      print("✅ ¡DNS actualizado! Ruta encontrada correctamente.");
      return true;
    } catch (e) {
      print("❌ Sigue sin encontrar el servidor: $e");
      return false;
    }
  }

  /// Función segura para hacer peticiones, con reintento automático
  static Future<http.Response?> getSeguro(String endpoint) async {
    final url = "$baseUrl$endpoint";
    try {
      // Primer intento
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) return response;
      
      // Si falla (ej. 500, 404, o timeout), intentamos forzar la reconexión
      throw Exception("Código de estado: ${response.statusCode}");
    } catch (e) {
      print("⚠️ Primer intento falló. Intentando forzar reconexión de red...");
      
      final reconectado = await forzarReconexion();
      if (reconectado) {
        // Segundo y último intento con la ruta "fresca"
        try {
          final response2 = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
          return response2;
        } catch (e2) {
          print("❌ Fallo definitivo después de reconectar: $e2");
          return null;
        }
      }
      return null;
    }
  }
}