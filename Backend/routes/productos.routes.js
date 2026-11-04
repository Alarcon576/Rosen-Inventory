// productos.routes.js
// Ya llegan con token válido (Server.js). Aquí se limita por rol.
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/productos.controller");
const { requireRol } = require("../middleware/auth.middleware");

const conteo = requireRol("Lector", "Admin");

router.get("/productos", conteo, ctrl.todos); // inventario/productos (para offline)
router.get("/catalogo", conteo, ctrl.catalogoTodos); // catálogo general completo (offline)
router.get("/catalogo/buscar", conteo, ctrl.buscarCatalogo); // buscar en catálogo general
router.get("/producto/:id", conteo, ctrl.buscarPorId);
router.get("/productos/buscar", conteo, ctrl.buscarPorNombre);

module.exports = router;
