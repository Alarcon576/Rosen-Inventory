// reportes.controller.js
// Reportes del panel de admin: total del inventario, conteos
// finalizados y análisis de plata (pérdidas/sobrantes).

const { poolPromise, sql } = require("../db");

exports.totalInventario = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .query("SELECT * FROM vista_total_inventario");
    res.json(resultado.recordset[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo total" });
  }
};

exports.conteosFinalizados = async (req, res) => {
  try {
    const pool = await poolPromise;
    // Combina: los FINALIZADOS viven en el espejo, los EN CURSO en
    // la tabla activa. Se unen con UNION ALL para mostrarlos juntos,
    // cada uno con su estado.
    const resultado = await pool.request().query(`
      SELECT
        ConteoID, NumeroConteo, FechaInicio, FechaFin, ConteoPadreID,
        'Finalizado' AS Estado
      FROM Conteo_Espejo

      UNION ALL

      SELECT
        ConteoID, NumeroConteo, FechaInicio, FechaFin, ConteoPadreID,
        'En proceso' AS Estado
      FROM Conteo
      WHERE EstadoProcesoID = 1

      ORDER BY FechaInicio DESC, NumeroConteo DESC
    `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error listando conteos" });
  }
};

exports.analisisPlata = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;

    const detalle = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT * FROM vista_plata_conteo
        WHERE ConteoID = @conteoId
        ORDER BY ValorDiferencia
      `);

    const totales = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT * FROM vista_totales_plata WHERE ConteoID = @conteoId");

    const t = totales.recordset[0] || {
      TotalPerdidas: 0,
      TotalSobrantes: 0,
      CantidadDescuadres: 0,
    };

    res.json({
      totalPerdidas: t.TotalPerdidas,
      totalSobrantes: t.TotalSobrantes,
      descuadreNeto: t.TotalSobrantes - t.TotalPerdidas,
      cantidadDescuadres: t.CantidadDescuadres,
      detalle: detalle.recordset,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error analizando plata" });
  }
};

// Distribución del VALOR del inventario por grupo (para la torta).
// Valor de cada producto = Valor * Cantidad (según el sistema).
// Lee de INVENTARIO (la tabla del inventario contado). OJO: tras el
// renombrado, "Productos" es el catálogo (sin Valor/Cantidad).
exports.valorPorGrupo = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool.request().query(`
      SELECT
        ISNULL(Grupo, 'Sin grupo') AS Grupo,
        SUM(Valor * Cantidad) AS Valor,
        COUNT(*) AS Productos
      FROM Inventario
      GROUP BY ISNULL(Grupo, 'Sin grupo')
      HAVING SUM(Valor * Cantidad) > 0
      ORDER BY Valor DESC
    `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo valor por grupo" });
  }
};

// Tendencia del descuadre neto entre conteos FINALIZADOS (para la línea).
// Neto = sobrantes - pérdidas. Un conteo sin descuadres aporta 0.
// Se ordena por fecha para ver si el inventario mejora o empeora.
exports.tendenciaDescuadre = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool.request().query(`
      SELECT
        e.ConteoID,
        e.NumeroConteo,
        e.FechaInicio,
        COALESCE(t.TotalPerdidas, 0)  AS Perdidas,
        COALESCE(t.TotalSobrantes, 0) AS Sobrantes,
        COALESCE(t.TotalSobrantes, 0) - COALESCE(t.TotalPerdidas, 0) AS DescuadreNeto
      FROM Conteo_Espejo e
      LEFT JOIN vista_totales_plata t ON t.ConteoID = e.ConteoID
      ORDER BY e.FechaInicio, e.ConteoID
    `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo tendencia" });
  }
};