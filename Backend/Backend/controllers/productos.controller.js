// productos.controller.js
// Búsqueda de productos (por ID para escaneo, por nombre para autocompletado).

const { poolPromise, sql } = require("../db");

// Catálogo COMPLETO de productos (para descargar y usar sin internet).
exports.todos = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .query("SELECT * FROM vista_productos ORDER BY Nombre");
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo el catálogo" });
  }
};

// Catálogo GENERAL completo (Productos) para cache offline.
exports.catalogoTodos = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .query("SELECT ProductoID, Nombre, Grupo, UnidadMedida FROM Productos ORDER BY Nombre");
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo el catálogo general" });
  }
};

// Buscar en el CATÁLOGO GENERAL (para productos que no están en inventario).
// Si se pasa conteoId, se EXCLUYEN los productos ya registrados como hallazgo
// en ese conteo o en cualquiera de su cadena de reconteos (padres), para no
// duplicar (un producto hallado en el conteo 1 no vuelve a hallarse en el
// reconteo 2, etc.). Busca en faltantes activos y en el espejo.
exports.buscarCatalogo = async (req, res) => {
  try {
    const texto = req.query.q || "";
    const conteoId = parseInt(req.query.conteoId, 10);

    const pool = await poolPromise;
    const request = pool
      .request()
      .input("texto", sql.VarChar, `%${texto}%`)
      .input("idContiene", sql.VarChar, `%${texto}%`)
      .input("idEmpieza", sql.VarChar, `${texto}%`)
      .input("idExacto", sql.VarChar, `${texto}`);

    const usarFiltro = Number.isInteger(conteoId) && conteoId > 0;
    let query;

    if (usarFiltro) {
      request.input("conteoId", sql.Int, conteoId);
      // CTE al inicio: la cadena del conteo (el actual + sus padres/reconteos).
      // Se excluyen los productos ya hallados en cualquiera de esa cadena,
      // tanto en la tabla activa como en el espejo.
      query = `
        WITH cadena AS (
          SELECT ConteoID, ConteoPadreID FROM Conteo WHERE ConteoID = @conteoId
          UNION ALL
          SELECT e.ConteoID, e.ConteoPadreID
          FROM Conteo_Espejo e
          JOIN cadena c ON e.ConteoID = c.ConteoPadreID
        )
        SELECT TOP 10 ProductoID, Nombre, Grupo, UnidadMedida
        FROM Productos
        WHERE (Nombre LIKE @texto
               OR CAST(ProductoID AS VARCHAR(20)) LIKE @idContiene)
          AND ProductoID NOT IN (
            SELECT f.ProductoID FROM DetalleInventario_Faltante f
            WHERE f.ConteoID IN (SELECT ConteoID FROM cadena)
            UNION
            SELECT fe.ProductoID FROM DetalleInventario_Faltante_Espejo fe
            WHERE fe.ConteoID IN (SELECT ConteoID FROM cadena)
          )
        ORDER BY
          CASE
            WHEN CAST(ProductoID AS VARCHAR(20)) = @idExacto  THEN 0
            WHEN CAST(ProductoID AS VARCHAR(20)) LIKE @idEmpieza THEN 1
            ELSE 2
          END,
          Nombre`;
    } else {
      query = `
        SELECT TOP 10 ProductoID, Nombre, Grupo, UnidadMedida
        FROM Productos
        WHERE Nombre LIKE @texto
           OR CAST(ProductoID AS VARCHAR(20)) LIKE @idContiene
        ORDER BY
          CASE
            WHEN CAST(ProductoID AS VARCHAR(20)) = @idExacto  THEN 0
            WHEN CAST(ProductoID AS VARCHAR(20)) LIKE @idEmpieza THEN 1
            ELSE 2
          END,
          Nombre`;
    }

    const resultado = await request.query(query);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error buscando en el catálogo" });
  }
};

exports.buscarPorId = async (req, res) => {
  try {
    const { id } = req.params;

    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("id", sql.Int, id)
      .query("SELECT * FROM vista_productos WHERE ProductoID = @id");

    if (resultado.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "Producto no encontrado" });
    }

    res.json(resultado.recordset[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error buscando el producto" });
  }
};

exports.buscarPorNombre = async (req, res) => {
  try {
    const texto = req.query.q || "";

    const pool = await poolPromise;
    // Busca por NOMBRE o por ID (código). Si el texto es un número, el
    // producto con ese ID exacto sale primero, luego los que empiezan
    // por ese número, luego el resto.
    const resultado = await pool
      .request()
      .input("texto", sql.VarChar, `%${texto}%`)      // nombre contiene
      .input("idContiene", sql.VarChar, `%${texto}%`) // id contiene
      .input("idEmpieza", sql.VarChar, `${texto}%`)   // id empieza por
      .input("idExacto", sql.VarChar, `${texto}`)     // id exacto
      .query(`
        SELECT TOP 10 * FROM vista_productos
        WHERE Nombre LIKE @texto
           OR CAST(ProductoID AS VARCHAR(20)) LIKE @idContiene
        ORDER BY
          CASE
            WHEN CAST(ProductoID AS VARCHAR(20)) = @idExacto  THEN 0
            WHEN CAST(ProductoID AS VARCHAR(20)) LIKE @idEmpieza THEN 1
            ELSE 2
          END,
          Nombre
      `);

    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error buscando productos" });
  }
};