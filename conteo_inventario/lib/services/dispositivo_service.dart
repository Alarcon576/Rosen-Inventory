
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DispositivoService {
 
  static Future<String> obtenerNombre() async {
    final info = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        
        return "${android.brand} ${android.model}";
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.name; 
      }
    } catch (_) {
  
    }

    return "Desconocido";
  }
}