// salud.routes.js
const express = require("express");
const router = express.Router();
const ctrl = require("../controllers/salud.controller");

router.get("/", ctrl.raiz);
router.get("/ping-db", ctrl.pingDb);

module.exports = router;