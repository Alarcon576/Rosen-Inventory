// estado_service.dart
// Verifica si el backend está accesible.

import 'package:http/http.dart' as http;
import 'config.dart';

class EstadoService {
  static Future<bool> servidorDisponible() async {
    try {
      final respuesta = await http
          .get(Uri.parse("${Config.baseUrl}/"))
          .timeout(const Duration(seconds: 3));
      return respuesta.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}