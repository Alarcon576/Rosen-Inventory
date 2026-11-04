// usuarios.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/usuarios.controller");

router.get("/usuarios", ctrl.listar);
router.post("/usuarios", ctrl.crear);
router.put("/usuarios/:id", ctrl.editar);
router.patch("/usuarios/:id/estado", ctrl.cambiarEstado);
router.get("/roles", ctrl.listarRoles);

module.exports = router;