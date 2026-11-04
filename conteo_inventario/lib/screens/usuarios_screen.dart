// usuarios_screen.dart
// Gestión de usuarios (panel de admin): listar, crear, editar,
// activar/desactivar.
//
// Los usuarios con rol "Admin" NO se muestran en la lista (se gestionan
// aparte). La pantalla incluye resumen, buscador y filtro por estado.

import 'package:flutter/material.dart';
import '../services/usuario_service.dart';
import '../theme.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  final _service = UsuarioService();
  List<dynamic> _usuarios = [];
  List<dynamic> _roles = [];
  bool _cargando = true;

  // Filtros de la lista.
  String _busqueda = "";
  String _filtroEstado = "todos"; // todos | activos | inactivos

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final usuarios = await _service.listar();
    final roles = await _service.listarRoles();
    if (!mounted) return;
    setState(() {
      _usuarios = usuarios;
      _roles = roles;
      _cargando = false;
    });
  }

  // CORREGIDO: Se especifica el tipo Map<String, dynamic> para evitar errores de tipo
  bool _activo(Map<String, dynamic> u) => u["Activo"] == true || u["Activo"] == 1;

  // Usuarios visibles: se excluyen los administradores.
  List<dynamic> get _visibles =>
      _usuarios.where((u) => u["Rol"] != "Admin").toList();

  // Aplica búsqueda + filtro de estado sobre los visibles.
  List<dynamic> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    return _visibles.where((u) {
      final act = _activo(u);
      if (_filtroEstado == "activos" && !act) return false;
      if (_filtroEstado == "inactivos" && act) return false;
      if (q.isEmpty) return true;
      return (u["Nombre"] ?? "").toString().toLowerCase().contains(q);
    }).toList();
  }

  // Color/ícono distintivo por rol.
  Color _colorRol(String rol) {
    switch (rol) {
      case "Reportes":
        return AppColors.tierra;
      case "Lector":
      default:
        return AppColors.verdeMedio;
    }
  }

  IconData _iconoRol(String rol) {
    switch (rol) {
      case "Reportes":
        return Icons.bar_chart;
      case "Lector":
      default:
        return Icons.inventory_2;
    }
  }

  // Abre el formulario para crear o editar.
  Future<void> _abrirFormulario({Map<String, dynamic>? usuario}) async {
    final esEdicion = usuario != null;
    final nombreCtrl =
        TextEditingController(text: esEdicion ? usuario["Nombre"] : "");
    final contrasenaCtrl = TextEditingController();
    // Solo se ofrecen roles distintos de Admin (no se crean admins aquí).
    final rolesForm =
        _roles.where((r) => r["Nombre"] != "Admin").toList();
    int rolSeleccionado = esEdicion
        ? usuario["RolID"]
        : (rolesForm.isNotEmpty ? rolesForm[0]["RolID"] : 1);

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(esEdicion ? Icons.edit : Icons.person_add,
                      color: AppColors.vino),
                  const SizedBox(width: 10),
                  Text(esEdicion ? "Editar usuario" : "Nuevo usuario"),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nombre",
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contrasenaCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: esEdicion
                            ? "Nueva contraseña (vacío = no cambiar)"
                            : "Contraseña",
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: rolSeleccionado,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Rol",
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: rolesForm.map<DropdownMenuItem<int>>((r) {
                        return DropdownMenuItem<int>(
                          value: r["RolID"],
                          child: Text(r["Nombre"]),
                        );
                      }).toList(),
                      onChanged: (v) => setLocal(() => rolSeleccionado = v!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final nombre = nombreCtrl.text.trim();
                    final contrasena = contrasenaCtrl.text;

                    if (nombre.isEmpty) return;
                    if (!esEdicion && contrasena.isEmpty) return;

                    Map<String, dynamic> res;
                    if (esEdicion) {
                      res = await _service.editar(
                        usuario["UsuarioID"],
                        nombre,
                        rolSeleccionado,
                        contrasena,
                      );
                    } else {
                      res = await _service.crear(
                        nombre,
                        contrasena,
                        rolSeleccionado,
                      );
                    }

                    if (context.mounted) {
                      Navigator.pop(context, res["ok"] == true);
                      if (res["ok"] != true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res["mensaje"] ?? "Error")),
                        );
                      }
                    }
                  },
                  child: const Text("Guardar"),
                ),
              ],
            );
          },
        );
      },
    );

    if (guardado == true) _cargar();
  }

  Future<void> _cambiarEstado(Map<String, dynamic> u) async {
    final activoActual = _activo(u);

    // Un administrador no se puede inactivar (defensa extra; no se listan).
    if (activoActual && u["Rol"] == "Admin") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se puede inactivar a un administrador")),
      );
      return;
    }

    final ok = await _service.cambiarEstado(u["UsuarioID"], !activoActual);
    if (ok) _cargar();
  }

  // --- Tira de resumen (total / activos / inactivos) ---
  Widget _resumen() {
    final total = _visibles.length;
    final activos = _visibles.where((u) => _activo(u)).length;
    final inactivos = total - activos;

    Widget tarjeta(String etiqueta, int valor, IconData icono, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                "$valor",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(etiqueta,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tarjeta("Usuarios", total, Icons.groups, AppColors.vino),
        const SizedBox(width: 10),
        tarjeta("Activos", activos, Icons.check_circle, AppColors.verdeMedio),
        const SizedBox(width: 10),
        tarjeta("Inactivos", inactivos, Icons.pause_circle, Colors.grey),
      ],
    );
  }

  // --- Chips de filtro por estado ---
  Widget _filtros() {
    Widget chip(String valor, String texto) {
      final sel = _filtroEstado == valor;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(texto),
          selected: sel,
          selectedColor: AppColors.vino,
          labelStyle: TextStyle(
            color: sel ? Colors.white : null,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _filtroEstado = valor),
        ),
      );
    }

    return Row(
      children: [
        chip("todos", "Todos"),
        chip("activos", "Activos"),
        chip("inactivos", "Inactivos"),
      ],
    );
  }

  Widget _tarjetaUsuario(Map<String, dynamic> u) {
    final activo = _activo(u);
    final rol = (u["Rol"] ?? "").toString();
    final color = _colorRol(rol);
    final nombre = (u["Nombre"] ?? "?").toString();
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : "?";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: (activo ? color : Colors.grey).withOpacity(0.85),
              child: Text(
                inicial,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
            const SizedBox(width: 12),
            // Nombre + rol + estado.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration:
                          activo ? null : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Distintivo de rol.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconoRol(rol), size: 13, color: color),
                            const SizedBox(width: 4),
                            Text(rol,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: color,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      // Estado.
                      Text(
                        activo ? "Activo" : "Inactivo",
                        style: TextStyle(
                          fontSize: 11,
                          color: activo
                              ? AppColors.verdeMedio
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Acciones.
            IconButton(
              tooltip: "Editar",
              onPressed: () => _abrirFormulario(usuario: u),
              icon: const Icon(Icons.edit, size: 20),
            ),
            Switch(
              value: activo,
              activeColor: AppColors.verdeHoja,
              onChanged: (_) => _cambiarEstado(u),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;

    return Scaffold(
      appBar: AppBar(title: const Text("Usuarios")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add),
        label: const Text("Nuevo"),
        backgroundColor: AppColors.vino,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: _resumen(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _busqueda = v),
                    decoration: InputDecoration(
                      hintText: "Buscar por nombre",
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: _filtros(),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _cargar,
                    child: lista.isEmpty
                        ? ListView(
                            // ListView para que el RefreshIndicator funcione.
                            children: const [
                              SizedBox(height: 80),
                              Icon(Icons.people_outline,
                                  size: 56, color: Colors.grey),
                              SizedBox(height: 12),
                              Center(
                                child: Text(
                                  "No hay usuarios que coincidan",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: lista.length,
                            itemBuilder: (_, i) =>
                                _tarjetaUsuario(lista[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}