// usuarios.controller.js
// Gestión de usuarios (panel de admin) y listado de roles.

const bcrypt = require("bcrypt");
const { poolPromise, sql } = require("../db");

exports.listar = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool.request().query(`
      SELECT u.UsuarioID, u.Nombre, u.RolID, r.Nombre AS Rol, u.Activo
      FROM Usuarios u
      JOIN Roles r ON r.RolID = u.RolID
      ORDER BY u.Nombre
    `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error listando usuarios" });
  }
};

exports.crear = async (req, res) => {
  try {
    const { nombre, contrasena, rolId } = req.body;

    if (!nombre || !contrasena || !rolId) {
      return res.status(400).json({ ok: false, mensaje: "Faltan datos" });
    }

    const pool = await poolPromise;

    const existe = await pool
      .request()
      .input("nombre", sql.VarChar, nombre)
      .query("SELECT UsuarioID FROM Usuarios WHERE Nombre = @nombre");

    if (existe.recordset.length > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: "Ya existe un usuario con ese nombre",
      });
    }

    const hash = await bcrypt.hash(contrasena, 10);

    await pool
      .request()
      .input("nombre", sql.VarChar, nombre)
      .input("contrasena", sql.VarChar, hash)
      .input("rolId", sql.Int, rolId)
      .query(`
        INSERT INTO Usuarios (Nombre, Contrasena, RolID, Activo)
        VALUES (@nombre, @contrasena, @rolId, 1)
      `);

    res.status(201).json({ ok: true, mensaje: "Usuario creado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error creando usuario" });
  }
};

exports.editar = async (req, res) => {
  try {
    const { id } = req.params;
    const { nombre, rolId, contrasena } = req.body;

    const pool = await poolPromise;

    if (contrasena && contrasena.trim() !== "") {
      const hash = await bcrypt.hash(contrasena, 10);
      await pool
        .request()
        .input("id", sql.Int, id)
        .input("nombre", sql.VarChar, nombre)
        .input("rolId", sql.Int, rolId)
        .input("contrasena", sql.VarChar, hash)
        .query(`
          UPDATE Usuarios
          SET Nombre = @nombre, RolID = @rolId, Contrasena = @contrasena
          WHERE UsuarioID = @id
        `);
    } else {
      await pool
        .request()
        .input("id", sql.Int, id)
        .input("nombre", sql.VarChar, nombre)
        .input("rolId", sql.Int, rolId)
        .query(`
          UPDATE Usuarios
          SET Nombre = @nombre, RolID = @rolId
          WHERE UsuarioID = @id
        `);
    }

    res.json({ ok: true, mensaje: "Usuario actualizado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error actualizando usuario" });
  }
};

exports.cambiarEstado = async (req, res) => {
  try {
    const { id } = req.params;
    const { activo } = req.body;

    const pool = await poolPromise;

    // Regla: no se puede INACTIVAR a un administrador (ni a otro admin
    // ni a uno mismo). Se valida por el NOMBRE del rol para no quemar
    // el ID del rol en el código. Reactivar (activo = true) sí se permite.
    if (!activo) {
      const objetivo = await pool
        .request()
        .input("id", sql.Int, id)
        .query(`
          SELECT r.Nombre AS Rol
          FROM Usuarios u
          JOIN Roles r ON r.RolID = u.RolID
          WHERE u.UsuarioID = @id
        `);

      if (objetivo.recordset.length === 0) {
        return res.status(404).json({ ok: false, mensaje: "Usuario no encontrado" });
      }

      if (objetivo.recordset[0].Rol === "Admin") {
        return res.status(403).json({
          ok: false,
          mensaje: "No se puede inactivar a un administrador",
        });
      }
    }

    await pool
      .request()
      .input("id", sql.Int, id)
      .input("activo", sql.Bit, activo ? 1 : 0)
      .query("UPDATE Usuarios SET Activo = @activo WHERE UsuarioID = @id");

    res.json({ ok: true, mensaje: "Estado actualizado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error cambiando estado" });
  }
};

exports.listarRoles = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .query("SELECT RolID, Nombre FROM Roles ORDER BY RolID");
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error listando roles" });
  }
};