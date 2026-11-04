// guardar_web.dart
// En web (Chrome) dispara la descarga del archivo con un Blob.

import 'dart:html' as html;

Future<void> guardarArchivo(List<int> bytes, String nombre) async {
  final blob = html.Blob([
    bytes,
  ], "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", nombre)
    ..click();
  html.Url.revokeObjectUrl(url);
}