// guardar_stub.dart
// Fallback: nunca se usa en la práctica (siempre entra web o io),
// pero Dart lo necesita para resolver la importación condicional.

Future<void> guardarArchivo(List<int> bytes, String nombre) async {
  throw UnsupportedError("Plataforma no soportada para exportar Excel");
}