// conteos.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/conteos.controller");
const sync = require("../controllers/sync.controller");

router.post("/conteo", ctrl.crear);
router.post("/detalle", ctrl.guardarDetalle);
router.get("/conteo/:conteoId/faltantes", ctrl.faltantes);
router.get("/conteo/:conteoId/pendientes-reconteo", ctrl.pendientesReconteo);
router.get("/reconteo/pendientes-actual", ctrl.pendientesReconteoActual);
router.get("/conteo/:conteoId/conflictos", ctrl.conflictos);
router.post("/conteo/:conteoId/producto/:productoId/resolver", ctrl.resolverConflicto);
router.post("/conteo/:conteoId/terminar", ctrl.terminar);
router.get("/conteo/:conteoId/resumen", ctrl.resumen);
router.get("/conteo/:conteoId/contados", ctrl.contados);
router.get("/conteos/activos", ctrl.activos);
router.post("/conteo/:conteoId/encontrado", ctrl.guardarEncontrado);
router.get("/conteo/:conteoId/encontrados", ctrl.encontrados);

// --- Pausa / reanudar / gestión de conteos (admin) ---
router.get("/conteos/en-curso", ctrl.enCurso);              // en proceso (1) + en pausa (3)
router.post("/conteo/:conteoId/pausar", ctrl.pausar);       // 1 -> 3
router.post("/conteo/:conteoId/reactivar", ctrl.reactivar); // 3 -> 1
router.delete("/conteo/:conteoId", ctrl.eliminar);          // borrar conteo activo/pausado

// Sincronización global "todo o nada" (transacción única).
router.post("/sync/batch", sync.batch);

module.exports = router;