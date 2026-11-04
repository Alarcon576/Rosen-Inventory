// conteos.routes.js
// Ya llegan con token válido (Server.js). Aquí se limita por rol:
//  - Lector / Admin: contar (crear, guardar, faltantes, conflictos, terminar...).
//  - Reportes además puede ver los hallazgos (para el Excel).
//  - Solo Admin: pausar, reanudar, borrar y ver los conteos en curso.
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/conteos.controller");
const sync = require("../controllers/sync.controller");
const { requireRol } = require("../middleware/auth.middleware");

const contar = requireRol("Lector", "Admin");
const soloAdmin = requireRol("Admin");
const verHallazgos = requireRol("Lector", "Admin", "Reportes");

router.post("/conteo", contar, ctrl.crear);
router.post("/detalle", contar, ctrl.guardarDetalle);
router.get("/conteo/:conteoId/faltantes", contar, ctrl.faltantes);
router.get("/conteo/:conteoId/pendientes-reconteo", contar, ctrl.pendientesReconteo);
router.get("/reconteo/pendientes-actual", contar, ctrl.pendientesReconteoActual);
router.get("/conteo/:conteoId/conflictos", contar, ctrl.conflictos);
router.post("/conteo/:conteoId/producto/:productoId/resolver", contar, ctrl.resolverConflicto);
router.post("/conteo/:conteoId/terminar", contar, ctrl.terminar);
router.get("/conteo/:conteoId/resumen", contar, ctrl.resumen);
router.get("/conteo/:conteoId/contados", contar, ctrl.contados);
router.get("/conteos/activos", contar, ctrl.activos);
router.post("/conteo/:conteoId/encontrado", contar, ctrl.guardarEncontrado);
router.get("/conteo/:conteoId/encontrados", verHallazgos, ctrl.encontrados);

// --- Pausa / reanudar / gestión de conteos (solo admin) ---
router.get("/conteos/en-curso", soloAdmin, ctrl.enCurso);              // en proceso (1) + en pausa (3)
router.post("/conteo/:conteoId/pausar", soloAdmin, ctrl.pausar);       // 1 -> 3
router.post("/conteo/:conteoId/reactivar", soloAdmin, ctrl.reactivar); // 3 -> 1
router.delete("/conteo/:conteoId", soloAdmin, ctrl.eliminar);          // borrar conteo activo/pausado

// Sincronización global "todo o nada" (transacción única).
router.post("/sync/batch", contar, sync.batch);

module.exports = router;
