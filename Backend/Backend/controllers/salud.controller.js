// salud.controller.js
// Endpoints de prueba para verificar que el servidor y la base responden.

const { poolPromise } = require("../db");

exports.raiz = (req, res) => {
  res.json({ ok: true, mensaje: "Servidor activo" });
};

exports.pingDb = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .query("SELECT COUNT(*) AS totalProductos FROM Productos");

    res.json({
      ok: true,
      mensaje: "Conexión a la base OK",
      totalProductos: resultado.recordset[0].totalProductos,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error consultando la base" });
  }
};