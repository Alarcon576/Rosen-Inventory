// productos.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/productos.controller");

router.get("/productos", ctrl.todos); // inventario/productos (para offline)
router.get("/catalogo", ctrl.catalogoTodos); // catálogo general completo (offline)
router.get("/catalogo/buscar", ctrl.buscarCatalogo); // buscar en catálogo general
router.get("/producto/:id", ctrl.buscarPorId);
router.get("/productos/buscar", ctrl.buscarPorNombre);

module.exports = router;