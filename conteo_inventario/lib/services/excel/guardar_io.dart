// guardar_io.dart
// En móvil (Android/iOS) guarda el archivo en una carpeta temporal
// y abre el diálogo de compartir para que el usuario lo mande por
// correo, WhatsApp, lo guarde en Drive, etc.

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> guardarArchivo(List<int> bytes, String nombre) async {
  final dir = await getTemporaryDirectory();
  final ruta = "${dir.path}/$nombre";
  final archivo = File(ruta);
  await archivo.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(ruta)],
    subject: nombre,
    text: "Informe de conteo de inventario",
  );
}