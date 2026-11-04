// reportes.routes.js
// Ya llegan con token válido (Server.js). Solo Admin y Reportes.
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/reportes.controller");
const { requireRol } = require("../middleware/auth.middleware");

router.use("/reportes", requireRol("Admin", "Reportes"));

router.get("/reportes/total-inventario", ctrl.totalInventario);
router.get("/reportes/conteos-finalizados", ctrl.conteosFinalizados);
router.get("/reportes/conteo/:conteoId/plata", ctrl.analisisPlata);
router.get("/reportes/valor-por-grupo", ctrl.valorPorGrupo);
router.get("/reportes/tendencia-descuadre", ctrl.tendenciaDescuadre);

module.exports = router;
