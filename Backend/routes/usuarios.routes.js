// usuarios.routes.js
// Ya llegan con token válido (Server.js). Todo el módulo es solo para Admin.
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/usuarios.controller");
const { requireRol } = require("../middleware/auth.middleware");

router.use(["/usuarios", "/roles"], requireRol("Admin"));

router.get("/usuarios", ctrl.listar);
router.post("/usuarios", ctrl.crear);
router.put("/usuarios/:id", ctrl.editar);
router.patch("/usuarios/:id/estado", ctrl.cambiarEstado);
router.get("/roles", ctrl.listarRoles);

module.exports = router;
