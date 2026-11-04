// salud.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/salud.controller");
const { verificarToken, requireRol } = require("../middleware/auth.middleware");

router.get("/", ctrl.raiz);
router.get("/ping-db", verificarToken, requireRol("Admin"), ctrl.pingDb);

module.exports = router;