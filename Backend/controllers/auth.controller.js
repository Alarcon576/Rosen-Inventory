// auth.controller.js
// Autenticación: login con verificación de contraseña hasheada.

const bcrypt = require("bcrypt");
const { generarToken } = require("../middleware/auth.middleware");
const { poolPromise, sql } = require("../db");

exports.login = async (req, res) => {
  try {
    const { nombre, contrasena } = req.body;

    if (!nombre || !contrasena) {
      return res.status(400).json({
        ok: false,
        mensaje: "Faltan nombre o contraseña",
      });
    }

    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("nombre", sql.VarChar, nombre)
      .query(`
        SELECT u.UsuarioID, u.Nombre, u.Contrasena, u.RolID, r.Nombre AS Rol, u.Activo
        FROM Usuarios u
        JOIN Roles r ON r.RolID = u.RolID
        WHERE u.Nombre = @nombre
      `);

    if (resultado.recordset.length === 0) {
      return res.status(401).json({
        ok: false,
        mensaje: "Usuario o contraseña incorrectos",
      });
    }

    const usuario = resultado.recordset[0];

    if (usuario.Activo === false || usuario.Activo === 0) {
      return res.status(403).json({
        ok: false,
        mensaje: "Usuario desactivado. Contacta al administrador.",
      });
    }

    const coincide = await bcrypt.compare(contrasena, usuario.Contrasena);

    if (!coincide) {
      return res.status(401).json({
        ok: false,
        mensaje: "Usuario o contraseña incorrectos",
      });
    }

    res.json({
      ok: true,
      token: generarToken(usuario),
      usuario: {
        id: usuario.UsuarioID,
        nombre: usuario.Nombre,
        rolId: usuario.RolID,
        rol: usuario.Rol,
      },
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error en el login" });
  }
};