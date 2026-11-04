// reportes.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/reportes.controller");

router.get("/reportes/total-inventario", ctrl.totalInventario);
router.get("/reportes/conteos-finalizados", ctrl.conteosFinalizados);
router.get("/reportes/conteo/:conteoId/plata", ctrl.analisisPlata);
router.get("/reportes/valor-por-grupo", ctrl.valorPorGrupo);
router.get("/reportes/tendencia-descuadre", ctrl.tendenciaDescuadre);

module.exports = router;