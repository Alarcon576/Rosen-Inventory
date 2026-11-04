// conteos.controller.js
// Todo lo relacionado con conteos: crear, guardar detalle, faltantes,
// pendientes de reconteo, terminar, resumen, contados (polling), activos.

const { poolPromise, sql } = require("../db");

// Crear el encabezado de un conteo.
exports.crear = async (req, res) => {
  try {
    const { numeroConteo, fechaInicio, conteoPadreId, clienteRef } = req.body;

    if (!numeroConteo || !fechaInicio) {
      return res.status(400).json({
        ok: false,
        mensaje: "Faltan el número de conteo o la fecha de inicio",
      });
    }

    const pool0 = await poolPromise;

    // IDEMPOTENCIA: si este conteo ya se creó antes (mismo clienteRef),
    // devolvemos el existente en lugar de crear un duplicado. Cubre el
    // caso de un timeout donde el servidor sí guardó pero el cliente
    // reintenta, y el re-envío al sincronizar.
    if (clienteRef) {
      const yaActivo = await pool0
        .request()
        .input("cr", sql.VarChar, clienteRef)
        .query("SELECT ConteoID, ConteoPadreID FROM Conteo WHERE ClienteRef = @cr");
      if (yaActivo.recordset.length > 0) {
        const r = yaActivo.recordset[0];
        return res.status(201).json({
          ok: true,
          conteoId: r.ConteoID,
          conteoPadreId: r.ConteoPadreID,
          esReconteo: r.ConteoPadreID !== null,
          duplicado: true,
        });
      }
    }

    // REGLA: no se puede crear un conteo nuevo si ya hay uno EN PROCESO
    // (sin terminar). Primero hay que finalizar el activo. Después del #1,
    // el siguiente se creará como RECONTEO de los descuadrados.
    const enProceso = await pool0
      .request()
      .query("SELECT TOP 1 NumeroConteo FROM Conteo WHERE EstadoProcesoID <> 2 ORDER BY ConteoID");
    if (enProceso.recordset.length > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: `Ya hay un conteo en proceso (#${enProceso.recordset[0].NumeroConteo}). Termínalo antes de crear otro.`,
      });
    }

    // No se permiten fechas anteriores a hoy. Se compara solo por día
    // (sin hora) usando la fecha del propio servidor, no un valor quemado.
    const hoy = new Date();
    hoy.setHours(0, 0, 0, 0);
    const fecha = new Date(`${fechaInicio}T00:00:00`);
    if (isNaN(fecha.getTime())) {
      return res.status(400).json({ ok: false, mensaje: "Fecha inválida" });
    }
    if (fecha < hoy) {
      return res.status(400).json({
        ok: false,
        mensaje: "No se pueden crear conteos con fecha anterior a hoy",
      });
    }

    const pool = await poolPromise;

    const existe = await pool
      .request()
      .input("numeroConteo", sql.Int, numeroConteo)
      .query("SELECT ConteoID FROM Conteo WHERE NumeroConteo = @numeroConteo");

    if (existe.recordset.length > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: "Ese número de conteo ya existe. Usa uno diferente.",
      });
    }

    // ¿Es un reconteo? Los conteos después del #1 solo recuentan los
    // productos que quedaron descuadrados en el conteo anterior. El
    // "padre" se deduce aquí (no se confía en la app): es el último
    // conteo FINALIZADO (vive en el espejo). Si el número es 1, o si
    // aún no hay ningún conteo finalizado, es un conteo completo.
    let padreFinal = conteoPadreId || null;
    if (!padreFinal && numeroConteo > 1) {
      const padre = await pool.request().query(`
        SELECT TOP 1 ConteoID
        FROM Conteo_Espejo
        ORDER BY ConteoID DESC
      `);
      if (padre.recordset.length > 0) {
        padreFinal = padre.recordset[0].ConteoID;
      }
    }

    const resultado = await pool
      .request()
      .input("numeroConteo", sql.Int, numeroConteo)
      .input("fechaInicio", sql.Date, fechaInicio)
      .input("conteoPadreId", sql.Int, padreFinal)
      .input("clienteRef", sql.VarChar, clienteRef || null)
      .query(`
        INSERT INTO Conteo (NumeroConteo, EstadoProcesoID, FechaInicio, ConteoPadreID, ClienteRef)
        OUTPUT INSERTED.ConteoID
        VALUES (@numeroConteo, 1, @fechaInicio, @conteoPadreId, @clienteRef)
      `);

    res.status(201).json({
      ok: true,
      conteoId: resultado.recordset[0].ConteoID,
      conteoPadreId: padreFinal,          // null si es conteo completo
      esReconteo: padreFinal !== null,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error creando el conteo" });
  }
};

// Guardar un detalle (un producto contado).
exports.guardarDetalle = async (req, res) => {
  try {
    const {
      conteoId, numeroConteo, productoId,
      cantidadFisica, usuarioId, dispositivo, clienteRef,
    } = req.body;

    if (!conteoId || !productoId || cantidadFisica == null || !usuarioId) {
      return res.status(400).json({
        ok: false,
        mensaje: "Faltan datos obligatorios del detalle",
      });
    }

    const pool = await poolPromise;

    // IDEMPOTENCIA: si esta misma lectura ya se guardó (mismo clienteRef),
    // se responde OK sin duplicar (cubre timeouts y re-sincronización).
    if (clienteRef) {
      const yaRef = await pool
        .request()
        .input("cr", sql.VarChar, clienteRef)
        .query("SELECT LecturaID FROM DetalleConteo_Conflictos WHERE ClienteRef = @cr");
      if (yaRef.recordset.length > 0) {
        return res.status(201).json({ ok: true, duplicado: true });
      }
    }

    const prod = await pool
      .request()
      .input("productoId", sql.Int, productoId)
      .query("SELECT Cantidad FROM Inventario WHERE ProductoID = @productoId");

    if (prod.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "El producto no existe" });
    }

    const cantidadSistema = prod.recordset[0].Cantidad;
    const nRonda = numeroConteo || 1;

    // 1) Guardar SIEMPRE la lectura cruda en la tabla puente (auditoría).
    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .input("numeroConteo", sql.Int, nRonda)
      .input("productoId", sql.Int, productoId)
      .input("cantidadFisica", sql.Decimal(12, 2), cantidadFisica)
      .input("cantidadSistema", sql.Decimal(12, 2), cantidadSistema)
      .input("usuarioId", sql.Int, usuarioId)
      .input("dispositivo", sql.VarChar, dispositivo || null)
      .input("clienteRef", sql.VarChar, clienteRef || null)
      .query(`
        INSERT INTO DetalleConteo_Conflictos
          (ConteoID, NumeroConteo, ProductoID, CantidadFisica, CantidadSistema, UsuarioID, Dispositivo, ClienteRef)
        VALUES
          (@conteoId, @numeroConteo, @productoId, @cantidadFisica, @cantidadSistema, @usuarioId, @dispositivo, @clienteRef)
      `);

    // 2) ¿Ya existe el detalle "oficial" de este producto en el conteo?
    const existente = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .input("productoId", sql.Int, productoId)
      .query(`
        SELECT DetalleID, CantidadFisica FROM DetalleConteo
        WHERE ConteoID = @conteoId AND ProductoID = @productoId
      `);

    let enConflicto = false;

    if (existente.recordset.length === 0) {
      // Primera lectura: se crea el detalle oficial (sin conflicto).
      // Si dos lecturas llegan al MISMO tiempo, el índice único
      // UX_DetalleConteo_Conteo_Producto impide la segunda: ahí lo
      // tratamos como conflicto en lugar de fallar (anti race-condition).
      try {
        await pool
          .request()
          .input("conteoId", sql.Int, conteoId)
          .input("numeroConteo", sql.Int, nRonda)
          .input("productoId", sql.Int, productoId)
          .input("cantidadFisica", sql.Decimal(12, 2), cantidadFisica)
          .input("cantidadSistema", sql.Decimal(12, 2), cantidadSistema)
          .input("usuarioId", sql.Int, usuarioId)
          .input("dispositivo", sql.VarChar, dispositivo || null)
          .input("clienteRef", sql.VarChar, clienteRef || null)
          .query(`
            INSERT INTO DetalleConteo
              (ConteoID, NumeroConteo, ProductoID, CantidadFisica, CantidadSistema, UsuarioID, Dispositivo, ClienteRef)
            VALUES
              (@conteoId, @numeroConteo, @productoId, @cantidadFisica, @cantidadSistema, @usuarioId, @dispositivo, @clienteRef)
          `);
      } catch (e) {
        // 2627/2601 = violación de índice único: otra lectura la creó
        // primero (carrera). Comparamos y marcamos conflicto si difiere.
        if (e.number === 2627 || e.number === 2601) {
          const otra = await pool
            .request()
            .input("conteoId", sql.Int, conteoId)
            .input("productoId", sql.Int, productoId)
            .query(`
              SELECT DetalleID, CantidadFisica FROM DetalleConteo
              WHERE ConteoID = @conteoId AND ProductoID = @productoId
            `);
          if (otra.recordset.length > 0 &&
              Number(otra.recordset[0].CantidadFisica) !== Number(cantidadFisica)) {
            enConflicto = true;
            await pool
              .request()
              .input("detalleId", sql.Int, otra.recordset[0].DetalleID)
              .query("UPDATE DetalleConteo SET EstadoDetalleID = 2 WHERE DetalleID = @detalleId");
          }
        } else {
          throw e;
        }
      }
    } else {
      const row = existente.recordset[0];
      // Otra lectura del mismo producto: si NO coincide con la oficial,
      // se marca EN CONFLICTO (se conserva el valor oficial; se resuelve
      // recontando). Si coincide, no pasa nada (los dos están de acuerdo).
      if (Number(row.CantidadFisica) !== Number(cantidadFisica)) {
        enConflicto = true;
        await pool
          .request()
          .input("detalleId", sql.Int, row.DetalleID)
          .query("UPDATE DetalleConteo SET EstadoDetalleID = 2 WHERE DetalleID = @detalleId");
      }
    }

    res.status(201).json({
      ok: true,
      enConflicto,
      mensaje: enConflicto
        ? "Lectura guardada, pero hay un conflicto con otra cuenta"
        : "Detalle guardado correctamente",
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error guardando el detalle" });
  }
};

// Inventario que FALTAN por contar en un conteo.
exports.faltantes = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT p.ProductoID, p.Nombre, p.UnidadMedida, p.Grupo
        FROM Inventario p
        WHERE p.ProductoID NOT IN (
          SELECT d.ProductoID FROM DetalleConteo d WHERE d.ConteoID = @conteoId
        )
        ORDER BY p.Nombre
      `);

    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo faltantes" });
  }
};

// Inventario que NO cuadraron en un conteo (para el reconteo).
exports.pendientesReconteo = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT
          ud.ProductoID, p.Nombre, p.UnidadMedida, p.Grupo,
          ud.CantidadFisica, ud.CantidadSistema, ud.Diferencia
        FROM vista_ultimo_detalle_espejo ud
        JOIN Inventario p ON p.ProductoID = ud.ProductoID
        WHERE ud.ConteoID = @conteoId
        AND ud.Diferencia <> 0
        ORDER BY p.Nombre
      `);

    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo pendientes" });
  }
};

// Descuadrados del ÚLTIMO conteo finalizado (el que sería "padre" del
// próximo reconteo). Sirve para CACHEAR y poder hacer el reconteo
// OFFLINE restringido a esos productos.
exports.pendientesReconteoActual = async (req, res) => {
  try {
    const pool = await poolPromise;
    const padre = await pool.request().query(`
      SELECT TOP 1 ConteoID, NumeroConteo, FechaInicio
      FROM Conteo_Espejo
      ORDER BY ConteoID DESC
    `);

    if (padre.recordset.length === 0) {
      return res.json({ padreId: null, pendientes: [] });
    }

    const p = padre.recordset[0];
    const pend = await pool
      .request()
      .input("conteoId", sql.Int, p.ConteoID)
      .query(`
        SELECT
          ud.ProductoID, pr.Nombre, pr.UnidadMedida, pr.Grupo,
          ud.CantidadFisica, ud.CantidadSistema, ud.Diferencia
        FROM vista_ultimo_detalle_espejo ud
        JOIN Inventario pr ON pr.ProductoID = ud.ProductoID
        WHERE ud.ConteoID = @conteoId
        AND ud.Diferencia <> 0
        ORDER BY pr.Nombre
      `);

    res.json({
      padreId: p.ConteoID,
      numeroPadre: p.NumeroConteo,
      fechaPadre: p.FechaInicio,
      pendientes: pend.recordset,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo pendientes actuales" });
  }
};

// Inventario EN CONFLICTO de un conteo (dos lecturas distintas), con sus
// lecturas crudas para poder decidir al recontar.
exports.conflictos = async (req, res) => {
  try {
    const { conteoId } = req.params;
    const pool = await poolPromise;

    const oficiales = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT d.ProductoID, p.Nombre, p.UnidadMedida, p.Grupo,
               d.CantidadFisica AS CantidadOficial, d.CantidadSistema
        FROM DetalleConteo d
        JOIN Inventario p ON p.ProductoID = d.ProductoID
        WHERE d.ConteoID = @conteoId AND d.EstadoDetalleID = 2
        ORDER BY p.Nombre
      `);

    const lecturas = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT ProductoID, CantidadFisica, Dispositivo, UsuarioID, Fecha
        FROM DetalleConteo_Conflictos
        WHERE ConteoID = @conteoId
        ORDER BY Fecha
      `);

    const porProducto = {};
    for (const l of lecturas.recordset) {
      (porProducto[l.ProductoID] = porProducto[l.ProductoID] || []).push(l);
    }

    const salida = oficiales.recordset.map((r) => ({
      ...r,
      lecturas: porProducto[r.ProductoID] || [],
    }));

    res.json(salida);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo conflictos" });
  }
};

// Resolver un conflicto: la cantidad enviada (recuento) queda como
// definitiva y se limpia la marca de conflicto.
exports.resolverConflicto = async (req, res) => {
  try {
    const { conteoId, productoId } = req.params;
    const { cantidadFisica, usuarioId, dispositivo, numeroConteo, clienteRef } = req.body;

    if (cantidadFisica == null || !usuarioId) {
      return res.status(400).json({ ok: false, mensaje: "Faltan datos para resolver" });
    }

    const pool = await poolPromise;

    // Idempotencia: si esta resolución ya se aplicó (mismo clienteRef), OK.
    if (clienteRef) {
      const yaRef = await pool
        .request()
        .input("cr", sql.VarChar, clienteRef)
        .query("SELECT LecturaID FROM DetalleConteo_Conflictos WHERE ClienteRef = @cr");
      if (yaRef.recordset.length > 0) {
        return res.status(200).json({ ok: true, duplicado: true });
      }
    }

    const prod = await pool
      .request()
      .input("productoId", sql.Int, productoId)
      .query("SELECT Cantidad FROM Inventario WHERE ProductoID = @productoId");
    if (prod.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "El producto no existe" });
    }
    const cantidadSistema = prod.recordset[0].Cantidad;
    const nRonda = numeroConteo || 1;

    // Registrar la lectura de resolución (auditoría).
    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .input("numeroConteo", sql.Int, nRonda)
      .input("productoId", sql.Int, productoId)
      .input("cantidadFisica", sql.Decimal(12, 2), cantidadFisica)
      .input("cantidadSistema", sql.Decimal(12, 2), cantidadSistema)
      .input("usuarioId", sql.Int, usuarioId)
      .input("dispositivo", sql.VarChar, dispositivo || null)
      .input("clienteRef", sql.VarChar, clienteRef || null)
      .query(`
        INSERT INTO DetalleConteo_Conflictos
          (ConteoID, NumeroConteo, ProductoID, CantidadFisica, CantidadSistema,
           UsuarioID, Dispositivo, ClienteRef, EstadoConflictoID)
        VALUES
          (@conteoId, @numeroConteo, @productoId, @cantidadFisica, @cantidadSistema,
           @usuarioId, @dispositivo, @clienteRef, 2)
      `);

    // Dejar el valor definitivo en el detalle oficial y limpiar conflicto.
    const upd = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .input("productoId", sql.Int, productoId)
      .input("cantidadFisica", sql.Decimal(12, 2), cantidadFisica)
      .input("cantidadSistema", sql.Decimal(12, 2), cantidadSistema)
      .input("usuarioId", sql.Int, usuarioId)
      .input("dispositivo", sql.VarChar, dispositivo || null)
      .query(`
        UPDATE DetalleConteo
        SET CantidadFisica = @cantidadFisica,
            CantidadSistema = @cantidadSistema,
            UsuarioID = @usuarioId,
            Dispositivo = @dispositivo,
            EstadoDetalleID = 1
        WHERE ConteoID = @conteoId AND ProductoID = @productoId
      `);

    res.json({ ok: true, mensaje: "Conflicto resuelto", actualizados: upd.rowsAffected[0] });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error resolviendo el conflicto" });
  }
};

// Guardar un HALLAZGO: producto físico fuera de inventario, buscado en
// el catálogo general. Va a una tabla aparte (no afecta plata ni faltantes).
exports.guardarEncontrado = async (req, res) => {
  try {
    const { conteoId } = req.params;
    const { productoId, cantidad, usuarioId, dispositivo, clienteRef } = req.body;

    if (!productoId || cantidad == null) {
      return res.status(400).json({ ok: false, mensaje: "Faltan datos del hallazgo" });
    }

    const pool = await poolPromise;

    // Idempotencia.
    if (clienteRef) {
      const ya = await pool
        .request()
        .input("cr", sql.VarChar, clienteRef)
        .query("SELECT EncontradoID FROM DetalleInventario_Faltante WHERE ClienteRef = @cr");
      if (ya.recordset.length > 0) {
        return res.status(201).json({ ok: true, duplicado: true });
      }
    }

    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .input("productoId", sql.Int, productoId)
      .input("cantidad", sql.Decimal(12, 2), cantidad)
      .input("usuarioId", sql.Int, usuarioId || null)
      .input("dispositivo", sql.VarChar, dispositivo || null)
      .input("clienteRef", sql.VarChar, clienteRef || null)
      .query(`
        INSERT INTO DetalleInventario_Faltante
          (ConteoID, ProductoID, Cantidad, UsuarioID, Dispositivo, ClienteRef)
        VALUES
          (@conteoId, @productoId, @cantidad, @usuarioId, @dispositivo, @clienteRef)
      `);

    res.status(201).json({ ok: true, mensaje: "Hallazgo registrado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error guardando el hallazgo" });
  }
};

// Listar los HALLAZGOS de un conteo (para el Excel: Producto + Unidad).
exports.encontrados = async (req, res) => {
  try {
    const { conteoId } = req.params;
    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        -- Activa + espejo: un conteo finalizado ya movió sus hallazgos al
        -- espejo, así que se leen de ambas para el Excel/reportes.
        SELECT ProductoID, Nombre, UnidadMedida, Cantidad FROM (
          SELECT e.ProductoID, c.Nombre, c.UnidadMedida, e.Cantidad
          FROM DetalleInventario_Faltante e
          JOIN Productos c ON c.ProductoID = e.ProductoID
          WHERE e.ConteoID = @conteoId
          UNION ALL
          SELECT e.ProductoID, c.Nombre, c.UnidadMedida, e.Cantidad
          FROM DetalleInventario_Faltante_Espejo e
          JOIN Productos c ON c.ProductoID = e.ProductoID
          WHERE e.ConteoID = @conteoId
        ) t
        ORDER BY Nombre
      `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo hallazgos" });
  }
};

// Terminar un conteo (solo si no quedan faltantes).
exports.terminar = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;

    const info = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT ConteoPadreID FROM Conteo WHERE ConteoID = @conteoId");

    if (info.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "Conteo no encontrado" });
    }

    // No se puede cerrar si hay productos EN CONFLICTO (dos lecturas
    // distintas). Hay que resolverlos (recontar) primero.
    const conf = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT COUNT(*) AS n FROM DetalleConteo WHERE ConteoID = @conteoId AND EstadoDetalleID = 2");
    if (conf.recordset[0].n > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: `Hay ${conf.recordset[0].n} producto(s) en conflicto. Resuélvelos antes de terminar.`,
      });
    }

    const conteoPadreId = info.recordset[0].ConteoPadreID;
    let faltan;

    if (conteoPadreId === null) {
      const r = await pool
        .request()
        .input("conteoId", sql.Int, conteoId)
        .query(`
          SELECT COUNT(*) AS faltan
          FROM Inventario p
          WHERE p.ProductoID NOT IN (
            SELECT ProductoID FROM DetalleConteo WHERE ConteoID = @conteoId
          )
        `);
      faltan = r.recordset[0].faltan;
    } else {
      const r = await pool
        .request()
        .input("conteoId", sql.Int, conteoId)
        .input("padreId", sql.Int, conteoPadreId)
        .query(`
          SELECT COUNT(*) AS faltan
          FROM (
            -- Los pendientes del padre se leen del ESPEJO
            -- (el padre ya se archivó al finalizar).
            SELECT d.ProductoID
            FROM DetalleConteo_Espejo d
            WHERE d.DetalleID IN (
              SELECT MAX(d2.DetalleID)
              FROM DetalleConteo_Espejo d2
              WHERE d2.ConteoID = @padreId
              GROUP BY d2.ProductoID
            )
            AND d.Diferencia <> 0
          ) pendientes
          WHERE pendientes.ProductoID NOT IN (
            SELECT ProductoID FROM DetalleConteo WHERE ConteoID = @conteoId
          )
        `);
      faltan = r.recordset[0].faltan;
    }

    if (faltan > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: `Aún faltan ${faltan} productos por contar. No se puede terminar.`,
      });
    }

    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        UPDATE Conteo
        SET FechaFin = CAST(GETDATE() AS DATE),
            FechaGrabado = CAST(GETDATE() AS DATE),
            EstadoProcesoID = 2
        WHERE ConteoID = @conteoId
      `);

    res.json({ ok: true, mensaje: "Conteo finalizado correctamente" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error terminando el conteo" });
  }
};

// Pausar un conteo (En proceso -> En pausa). Los datos quedan intactos en
// las tablas activas; NO se archiva al espejo (eso solo pasa al finalizar).
// Un conteo en pausa sigue bloqueando la creación de otros (EstadoProcesoID
// <> 2), así que la regla es: mientras esté en pausa, solo se puede reanudar
// o borrar; no se pueden crear conteos nuevos.
exports.pausar = async (req, res) => {
  try {
    const { conteoId } = req.params;
    const pool = await poolPromise;

    const info = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT EstadoProcesoID FROM Conteo WHERE ConteoID = @conteoId");

    if (info.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "Conteo no encontrado" });
    }
    if (info.recordset[0].EstadoProcesoID !== 1) {
      return res.status(409).json({
        ok: false,
        mensaje: "Solo se puede pausar un conteo que está en proceso.",
      });
    }

    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("UPDATE Conteo SET EstadoProcesoID = 3 WHERE ConteoID = @conteoId");

    res.json({ ok: true, mensaje: "Conteo pausado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error al pausar el conteo" });
  }
};

// Reanudar un conteo (En pausa -> En proceso). Por seguridad se valida que
// no haya OTRO conteo en proceso (con la regla de "un solo conteo vivo" no
// debería, pero se protege igual).
exports.reactivar = async (req, res) => {
  try {
    const { conteoId } = req.params;
    const pool = await poolPromise;

    const info = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT EstadoProcesoID FROM Conteo WHERE ConteoID = @conteoId");

    if (info.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "Conteo no encontrado" });
    }
    if (info.recordset[0].EstadoProcesoID !== 3) {
      return res.status(409).json({
        ok: false,
        mensaje: "Solo se puede reanudar un conteo que está en pausa.",
      });
    }

    const otro = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(
        "SELECT TOP 1 ConteoID FROM Conteo WHERE EstadoProcesoID = 1 AND ConteoID <> @conteoId"
      );
    if (otro.recordset.length > 0) {
      return res.status(409).json({
        ok: false,
        mensaje: "Ya hay otro conteo en proceso. Termínalo antes de reanudar este.",
      });
    }

    await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("UPDATE Conteo SET EstadoProcesoID = 1 WHERE ConteoID = @conteoId");

    res.json({ ok: true, mensaje: "Conteo reanudado" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error al reanudar el conteo" });
  }
};

// Conteos EN CURSO para el admin: en proceso (1) y en pausa (3), con su
// estado y cuántos productos llevan contados. (activos() sigue trayendo
// solo los de estado 1, que son a los que se pueden unir los dispositivos.)
exports.enCurso = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool.request().query(`
      SELECT
        c.ConteoID, c.NumeroConteo, c.FechaInicio, c.ConteoPadreID,
        c.EstadoProcesoID, e.Nombre AS Estado,
        (SELECT COUNT(DISTINCT ProductoID)
         FROM DetalleConteo d WHERE d.ConteoID = c.ConteoID) AS Contados
      FROM Conteo c
      JOIN EstadosProceso e ON e.EstadoProcesoID = c.EstadoProcesoID
      WHERE c.EstadoProcesoID IN (1, 3)
      ORDER BY c.FechaInicio DESC, c.NumeroConteo DESC
    `);
    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo conteos en curso" });
  }
};

// Borrar un conteo ACTIVO (en proceso o en pausa) y todo lo suyo. No se
// permite borrar un conteo finalizado (ese ya vive en el espejo). Se hace
// en una transacción, borrando las hijas primero (FK-safe).
exports.eliminar = async (req, res) => {
  const { conteoId } = req.params;
  const { usuarioId, motivo } = req.body || {};
  const pool = await poolPromise;

  try {
    const info = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT EstadoProcesoID FROM Conteo WHERE ConteoID = @conteoId");

    if (info.recordset.length === 0) {
      return res.status(404).json({ ok: false, mensaje: "Conteo no encontrado" });
    }
    if (info.recordset[0].EstadoProcesoID === 2) {
      return res.status(409).json({
        ok: false,
        mensaje: "No se puede borrar un conteo finalizado.",
      });
    }

    const tx = new sql.Transaction(pool);
    await tx.begin();
    try {
      // Helper para queries que solo necesitan @conteoId.
      const q = (texto) =>
        new sql.Request(tx).input("conteoId", sql.Int, conteoId).query(texto);

      // 1) ARCHIVAR a las tablas de borrados (auditoría). El encabezado
      //    lleva quién borró, motivo y fecha (FechaBorrado tiene default).
      await new sql.Request(tx)
        .input("conteoId", sql.Int, conteoId)
        .input("usuarioBorradoId", sql.Int, usuarioId ?? null)
        .input("motivo", sql.NVarChar(500), motivo ?? null)
        .query(`
          INSERT INTO Conteo_Borrado
            (ConteoID, NumeroConteo, EstadoProcesoID, FechaInicio, FechaFin,
             FechaGrabado, ConteoPadreID, ClienteRef, UsuarioBorradoID, Motivo)
          SELECT
            ConteoID, NumeroConteo, EstadoProcesoID, FechaInicio, FechaFin,
            FechaGrabado, ConteoPadreID, ClienteRef, @usuarioBorradoId, @motivo
          FROM Conteo WHERE ConteoID = @conteoId
        `);

      await q(`
        INSERT INTO DetalleConteo_Borrado
          (DetalleID, ConteoID, NumeroConteo, ProductoID, CantidadFisica,
           CantidadSistema, Diferencia, EstadoCoincID, EstadoDetalleID,
           UsuarioID, Dispositivo, ClienteRef)
        SELECT
          DetalleID, ConteoID, NumeroConteo, ProductoID, CantidadFisica,
          CantidadSistema, Diferencia, EstadoCoincID, EstadoDetalleID,
          UsuarioID, Dispositivo, ClienteRef
        FROM DetalleConteo WHERE ConteoID = @conteoId
      `);

      await q(`
        INSERT INTO DetalleConteo_Conflictos_Borrado
          (LecturaID, ConteoID, NumeroConteo, ProductoID, CantidadFisica,
           CantidadSistema, UsuarioID, Dispositivo, ClienteRef, EstadoConflictoID, Fecha)
        SELECT
          LecturaID, ConteoID, NumeroConteo, ProductoID, CantidadFisica,
          CantidadSistema, UsuarioID, Dispositivo, ClienteRef, EstadoConflictoID, Fecha
        FROM DetalleConteo_Conflictos WHERE ConteoID = @conteoId
      `);

      await q(`
        INSERT INTO DetalleInventario_Faltante_Borrado
          (EncontradoID, ConteoID, ProductoID, Cantidad,
           UsuarioID, Dispositivo, ClienteRef, Fecha)
        SELECT
          EncontradoID, ConteoID, ProductoID, Cantidad,
          UsuarioID, Dispositivo, ClienteRef, Fecha
        FROM DetalleInventario_Faltante WHERE ConteoID = @conteoId
      `);

      // 2) BORRAR de las activas (hijas primero, FK-safe).
      await q("DELETE FROM DetalleInventario_Faltante WHERE ConteoID = @conteoId");
      await q("DELETE FROM DetalleConteo_Conflictos WHERE ConteoID = @conteoId");
      await q("DELETE FROM DetalleConteo WHERE ConteoID = @conteoId");
      await q("DELETE FROM Conteo WHERE ConteoID = @conteoId");

      await tx.commit();
      res.json({ ok: true, mensaje: "Conteo borrado y archivado en el historial" });
    } catch (e) {
      await tx.rollback();
      throw e;
    }
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error al borrar el conteo" });
  }
};

// Resumen de un conteo (para el dashboard de cierre).
exports.resumen = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;

    const detalle = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT
          ud.ProductoID, p.Nombre, p.UnidadMedida, p.Grupo,
          ud.CantidadFisica, ud.CantidadSistema, ud.Diferencia, ud.EstadoCoincID
        -- Vista COMBINADA (espejo + activa): así el resumen funciona
        -- tanto si el conteo ya se finalizó (vive en el espejo) como
        -- si sigue en proceso (vive en la tabla activa). Antes leía
        -- solo del espejo y por eso quedaba "mal conectado".
        FROM vista_ultimo_detalle_todo ud
        JOIN Inventario p ON p.ProductoID = ud.ProductoID
        WHERE ud.ConteoID = @conteoId
        ORDER BY ud.Diferencia DESC, p.Nombre
      `);

    const totales = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query("SELECT * FROM vista_resumen_conteo WHERE ConteoID = @conteoId");

    const t = totales.recordset[0] || { Total: 0, Iguales: 0, Diferentes: 0 };

    res.json({
      total: t.Total,
      iguales: t.Iguales,
      diferentes: t.Diferentes,
      detalle: detalle.recordset,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo el resumen" });
  }
};

// IDs de productos ya contados (para el polling multi-dispositivo).
exports.contados = async (req, res) => {
  try {
    const { conteoId } = req.params;

    const pool = await poolPromise;
    const resultado = await pool
      .request()
      .input("conteoId", sql.Int, conteoId)
      .query(`
        SELECT DISTINCT ProductoID
        FROM DetalleConteo
        WHERE ConteoID = @conteoId
      `);

    const ids = resultado.recordset.map((r) => r.ProductoID);
    res.json(ids);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo contados" });
  }
};

// Conteos activos (En proceso) para poder unirse.
exports.activos = async (req, res) => {
  try {
    const pool = await poolPromise;
    const resultado = await pool.request().query(`
      SELECT
        c.ConteoID, c.NumeroConteo, c.FechaInicio, c.ConteoPadreID,
        (SELECT COUNT(DISTINCT ProductoID)
         FROM DetalleConteo d WHERE d.ConteoID = c.ConteoID) AS Contados
      FROM Conteo c
      WHERE c.EstadoProcesoID = 1
      ORDER BY c.FechaInicio DESC, c.NumeroConteo DESC
    `);

    res.json(resultado.recordset);
  } catch (error) {
    console.error(error);
    res.status(500).json({ ok: false, mensaje: "Error obteniendo conteos activos" });
  }
};