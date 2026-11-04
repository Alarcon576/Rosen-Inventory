// sync.controller.js
// Sincronización GLOBAL "todo o nada" de lo acumulado offline.
//
// Recibe en UN solo lote: conteos locales a crear (y finalizar), detalles,
// hallazgos y cierres de conteos del servidor. Todo se aplica dentro de UNA
// transacción SQL: si algo falla (corte de conexión a mitad, error de datos,
// faltantes/conflictos al cerrar), se hace ROLLBACK y NO queda nada a medias.
//
// Idempotencia: cada fila lleva ClienteRef; si ya existe, no se duplica.
// Verificación: al final se cuentan las filas efectivamente presentes por
// ClienteRef y se devuelven, para que el cliente confirme que quedó "exacto"
// antes de marcar los ítems como "transferido".

const { poolPromise, sql } = require("../db");

exports.batch = async (req, res) => {
  const conteos = Array.isArray(req.body.conteos) ? req.body.conteos : [];
  const detalles = Array.isArray(req.body.detalles) ? req.body.detalles : [];
  const encontrados = Array.isArray(req.body.encontrados) ? req.body.encontrados : [];
  const cierresServidor = Array.isArray(req.body.cierresServidor) ? req.body.cierresServidor : [];

  const pool = await poolPromise;
  const tx = new sql.Transaction(pool);

  try {
    await tx.begin();

    // localId (negativo del cliente) -> ConteoID real del servidor.
    const mapa = {};
    // Conteos que hay que finalizar al final (serverId).
    const aFinalizar = new Set();

    // ---------- 1) Conteos locales: crear (idempotente) ----------
    for (const c of conteos) {
      let serverId = null;

      // ¿Ya existe (mismo ClienteRef)? Entonces se reutiliza.
      if (c.clienteRef) {
        const ya = await new sql.Request(tx)
          .input("cr", sql.VarChar, c.clienteRef)
          .query("SELECT ConteoID FROM Conteo WHERE ClienteRef = @cr");
        if (ya.recordset.length > 0) serverId = ya.recordset[0].ConteoID;
      }

      if (serverId === null) {
        const ins = await new sql.Request(tx)
          .input("numeroConteo", sql.Int, c.numeroConteo)
          .input("fechaInicio", sql.Date, c.fechaInicio)
          .input("padreId", sql.Int, c.conteoPadreId ?? null)
          .input("cr", sql.VarChar, c.clienteRef ?? null)
          .query(`
            INSERT INTO Conteo (NumeroConteo, EstadoProcesoID, FechaInicio, ConteoPadreID, ClienteRef)
            OUTPUT INSERTED.ConteoID
            VALUES (@numeroConteo, 1, @fechaInicio, @padreId, @cr)
          `);
        serverId = ins.recordset[0].ConteoID;
      }

      if (c.localId != null) mapa[c.localId] = serverId;
      if (c.finalizar === true) aFinalizar.add(serverId);
    }

    // Resuelve el ConteoID real de un detalle/hallazgo.
    const resolverConteo = (item) => {
      if (item.conteoServerId != null) return item.conteoServerId;
      if (item.refLocalId != null && mapa[item.refLocalId] != null) {
        return mapa[item.refLocalId];
      }
      return null;
    };

    // ---------- 2) Detalles ----------
    for (const d of detalles) {
      const conteoId = resolverConteo(d);
      if (conteoId == null) {
        throw new Error("No se pudo resolver el conteo de un detalle");
      }
      const nRonda = d.numeroConteo || 1;

      // 2a) Lectura cruda (auditoría), idempotente por ClienteRef.
      let existeLectura = false;
      if (d.clienteRef) {
        const yl = await new sql.Request(tx)
          .input("cr", sql.VarChar, d.clienteRef)
          .query("SELECT LecturaID FROM DetalleConteo_Conflictos WHERE ClienteRef = @cr");
        existeLectura = yl.recordset.length > 0;
      }
      if (!existeLectura) {
        await new sql.Request(tx)
          .input("conteoId", sql.Int, conteoId)
          .input("numeroConteo", sql.Int, nRonda)
          .input("productoId", sql.Int, d.productoId)
          .input("cantidadFisica", sql.Decimal(12, 2), d.cantidadFisica)
          .input("cantidadSistema", sql.Decimal(12, 2), await cantidadSistema(tx, d.productoId))
          .input("usuarioId", sql.Int, d.usuarioId)
          .input("dispositivo", sql.VarChar, d.dispositivo || null)
          .input("cr", sql.VarChar, d.clienteRef || null)
          .query(`
            INSERT INTO DetalleConteo_Conflictos
              (ConteoID, NumeroConteo, ProductoID, CantidadFisica, CantidadSistema, UsuarioID, Dispositivo, ClienteRef)
            VALUES (@conteoId, @numeroConteo, @productoId, @cantidadFisica, @cantidadSistema, @usuarioId, @dispositivo, @cr)
          `);
      }

      // 2b) Detalle oficial: primera lectura crea; si difiere, conflicto.
      const ofi = await new sql.Request(tx)
        .input("conteoId", sql.Int, conteoId)
        .input("productoId", sql.Int, d.productoId)
        .query("SELECT DetalleID, CantidadFisica FROM DetalleConteo WHERE ConteoID = @conteoId AND ProductoID = @productoId");

      if (ofi.recordset.length === 0) {
        try {
          await new sql.Request(tx)
            .input("conteoId", sql.Int, conteoId)
            .input("numeroConteo", sql.Int, nRonda)
            .input("productoId", sql.Int, d.productoId)
            .input("cantidadFisica", sql.Decimal(12, 2), d.cantidadFisica)
            .input("cantidadSistema", sql.Decimal(12, 2), await cantidadSistema(tx, d.productoId))
            .input("usuarioId", sql.Int, d.usuarioId)
            .input("dispositivo", sql.VarChar, d.dispositivo || null)
            .input("cr", sql.VarChar, d.clienteRef || null)
            .query(`
              INSERT INTO DetalleConteo
                (ConteoID, NumeroConteo, ProductoID, CantidadFisica, CantidadSistema, UsuarioID, Dispositivo, ClienteRef)
              VALUES (@conteoId, @numeroConteo, @productoId, @cantidadFisica, @cantidadSistema, @usuarioId, @dispositivo, @cr)
            `);
        } catch (err) {
          // Índice único (otra sincronización creó la oficial): marcar
          // conflicto si difiere, en lugar de romper toda la transacción.
          if (err.number === 2627 || err.number === 2601) {
            const otra = await new sql.Request(tx)
              .input("conteoId", sql.Int, conteoId)
              .input("productoId", sql.Int, d.productoId)
              .query("SELECT DetalleID, CantidadFisica FROM DetalleConteo WHERE ConteoID = @conteoId AND ProductoID = @productoId");
            if (otra.recordset.length > 0 &&
                Number(otra.recordset[0].CantidadFisica) !== Number(d.cantidadFisica)) {
              await new sql.Request(tx)
                .input("detalleId", sql.Int, otra.recordset[0].DetalleID)
                .query("UPDATE DetalleConteo SET EstadoDetalleID = 2 WHERE DetalleID = @detalleId");
            }
          } else {
            throw err;
          }
        }
      } else if (Number(ofi.recordset[0].CantidadFisica) !== Number(d.cantidadFisica)) {
        await new sql.Request(tx)
          .input("detalleId", sql.Int, ofi.recordset[0].DetalleID)
          .query("UPDATE DetalleConteo SET EstadoDetalleID = 2 WHERE DetalleID = @detalleId");
      }
    }

    // ---------- 3) Hallazgos ----------
    for (const e of encontrados) {
      const conteoId = resolverConteo(e);
      if (conteoId == null) throw new Error("No se pudo resolver el conteo de un hallazgo");

      let existe = false;
      if (e.clienteRef) {
        const ye = await new sql.Request(tx)
          .input("cr", sql.VarChar, e.clienteRef)
          .query("SELECT EncontradoID FROM DetalleInventario_Faltante WHERE ClienteRef = @cr");
        existe = ye.recordset.length > 0;
      }
      if (!existe) {
        await new sql.Request(tx)
          .input("conteoId", sql.Int, conteoId)
          .input("productoId", sql.Int, e.productoId)
          .input("cantidad", sql.Decimal(12, 2), e.cantidad)
          .input("usuarioId", sql.Int, e.usuarioId ?? null)
          .input("dispositivo", sql.VarChar, e.dispositivo || null)
          .input("cr", sql.VarChar, e.clienteRef || null)
          .query(`
            INSERT INTO DetalleInventario_Faltante
              (ConteoID, ProductoID, Cantidad, UsuarioID, Dispositivo, ClienteRef)
            VALUES (@conteoId, @productoId, @cantidad, @usuarioId, @dispositivo, @cr)
          `);
      }
    }

    // ---------- 4) Cierres ----------
    for (const id of cierresServidor) aFinalizar.add(id);

    for (const conteoId of aFinalizar) {
      await finalizarConteo(tx, conteoId); // lanza si faltan/hay conflicto
    }

    // ---------- 5) Verificación (por ClienteRef) ----------
    const verif = {
      conteosOk: await contarPorRef(tx, "Conteo", conteos.map((c) => c.clienteRef)),
      detallesOk: await contarPorRef(tx, "DetalleConteo_Conflictos", detalles.map((d) => d.clienteRef)),
      encontradosOk: await contarPorRef(tx, "DetalleInventario_Faltante", encontrados.map((e) => e.clienteRef)),
    };

    await tx.commit();

    res.json({
      ok: true,
      mensaje: "Sincronización aplicada",
      mapa,                 // localId -> serverId
      finalizados: [...aFinalizar],
      verificacion: verif,  // filas confirmadas por ClienteRef
    });
  } catch (error) {
    try { await tx.rollback(); } catch (_) {}
    console.error("Sync batch ROLLBACK:", error.message);
    res.status(409).json({ ok: false, mensaje: error.message || "No se pudo sincronizar (rollback)" });
  }
};

// --- Helpers ---

// Cantidad del sistema de un producto (dentro de la transacción).
async function cantidadSistema(tx, productoId) {
  const r = await new sql.Request(tx)
    .input("p", sql.Int, productoId)
    .query("SELECT Cantidad FROM Inventario WHERE ProductoID = @p");
  if (r.recordset.length === 0) throw new Error(`Producto ${productoId} no existe`);
  return r.recordset[0].Cantidad;
}

// Cuenta filas existentes cuyo ClienteRef está en la lista dada.
async function contarPorRef(tx, tabla, refs) {
  const limpias = refs.filter((x) => x != null);
  if (limpias.length === 0) return 0;
  const rq = new sql.Request(tx);
  const params = limpias.map((ref, i) => {
    rq.input(`r${i}`, sql.VarChar, ref);
    return `@r${i}`;
  });
  const r = await rq.query(
    `SELECT COUNT(*) AS n FROM ${tabla} WHERE ClienteRef IN (${params.join(",")})`
  );
  return r.recordset[0].n;
}

// Finaliza un conteo dentro de la transacción; lanza si no se puede.
async function finalizarConteo(tx, conteoId) {
  const info = await new sql.Request(tx)
    .input("conteoId", sql.Int, conteoId)
    .query("SELECT ConteoPadreID FROM Conteo WHERE ConteoID = @conteoId");
  if (info.recordset.length === 0) {
    throw new Error(`Conteo ${conteoId} no encontrado al finalizar`);
  }

  const conf = await new sql.Request(tx)
    .input("conteoId", sql.Int, conteoId)
    .query("SELECT COUNT(*) AS n FROM DetalleConteo WHERE ConteoID = @conteoId AND EstadoDetalleID = 2");
  if (conf.recordset[0].n > 0) {
    throw new Error(`Conteo ${conteoId}: hay ${conf.recordset[0].n} producto(s) en conflicto`);
  }

  const padreId = info.recordset[0].ConteoPadreID;
  let faltan;
  if (padreId === null) {
    const r = await new sql.Request(tx)
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT COUNT(*) AS faltan FROM Inventario p
        WHERE p.ProductoID NOT IN (SELECT ProductoID FROM DetalleConteo WHERE ConteoID = @conteoId)
      `);
    faltan = r.recordset[0].faltan;
  } else {
    const r = await new sql.Request(tx)
      .input("conteoId", sql.Int, conteoId)
      .input("padreId", sql.Int, padreId)
      .query(`
        SELECT COUNT(*) AS faltan FROM (
          SELECT d.ProductoID FROM DetalleConteo_Espejo d
          WHERE d.DetalleID IN (
            SELECT MAX(d2.DetalleID) FROM DetalleConteo_Espejo d2
            WHERE d2.ConteoID = @padreId GROUP BY d2.ProductoID
          ) AND d.Diferencia <> 0
        ) pend
        WHERE pend.ProductoID NOT IN (SELECT ProductoID FROM DetalleConteo WHERE ConteoID = @conteoId)
      `);
    faltan = r.recordset[0].faltan;
  }

  if (faltan > 0) {
    throw new Error(`Conteo ${conteoId}: aún faltan ${faltan} productos por contar`);
  }

  await new sql.Request(tx)
    .input("conteoId", sql.Int, conteoId)
    .query(`
      UPDATE Conteo
      SET FechaFin = CAST(GETDATE() AS DATE),
          FechaGrabado = CAST(GETDATE() AS DATE),
          EstadoProcesoID = 2
      WHERE ConteoID = @conteoId
    `);
}