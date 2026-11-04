// auth.middleware.js
// Sesiones con token (JWT).
//
// - generarToken(usuario): lo usa /login para entregar el token.
// - verificarToken:       exige "Authorization: Bearer <token>" en la petición.
// - requireRol(...roles): deja pasar solo a los roles indicados.
// - invalidarUsuario(id): olvida el estado en caché de un usuario (se llama
//                         al editarlo o activarlo/desactivarlo).
//
// Además de validar la firma, se consulta (con caché corta) que el usuario
// siga ACTIVO y con qué rol está hoy, así que desactivar a alguien o cambiarle
// el rol surte efecto en segundos y no cuando el token caduque.

const jwt = require("jsonwebtoken");
const { poolPromise, sql } = require("../db");

const SECRET = process.env.JWT_SECRET;
const EXPIRA = process.env.JWT_EXPIRES_IN || "12h";
const CACHE_MS = 30 * 1000; // cuánto se recuerda el estado de un usuario

if (!SECRET || SECRET.length < 32) {
  console.error("==================================");
  console.error("Falta JWT_SECRET (mínimo 32 caracteres) en el archivo .env");
  console.error("Genera uno con:");
  console.error('  node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'hex\'))"');
  console.error("==================================");
  process.exit(1);
}

// id de usuario -> { activo, rol, hasta }
const cache = new Map();

function generarToken(usuario) {
  return jwt.sign(
    {
      id: usuario.UsuarioID,
      nombre: usuario.Nombre,
      rolId: usuario.RolID,
      rol: usuario.Rol,
    },
    SECRET,
    { algorithm: "HS256", expiresIn: EXPIRA }
  );
}

function invalidarUsuario(id) {
  cache.delete(Number(id));
}

// Estado actual del usuario en la base (con caché de unos segundos).
async function estadoUsuario(id) {
  const ahora = Date.now();
  const guardado = cache.get(id);
  if (guardado && guardado.hasta > ahora) return guardado;

  const pool = await poolPromise;
  const r = await pool
    .request()
    .input("id", sql.Int, id)
    .query(`
      SELECT u.Activo, r.Nombre AS Rol
      FROM Usuarios u
      JOIN Roles r ON r.RolID = u.RolID
      WHERE u.UsuarioID = @id
    `);

  const fila = r.recordset[0];
  const estado = {
    activo: !!fila && fila.Activo !== false && fila.Activo !== 0,
    rol: fila ? fila.Rol : null,
    hasta: ahora + CACHE_MS,
  };
  cache.set(id, estado);
  return estado;
}

async function verificarToken(req, res, next) {
  const cabecera = req.headers.authorization || "";
  const [tipo, token] = cabecera.split(" ");

  if (tipo !== "Bearer" || !token) {
    return res.status(401).json({
      ok: false,
      codigo: "SIN_TOKEN",
      mensaje: "Debes iniciar sesión",
    });
  }

  let datos;
  try {
    datos = jwt.verify(token, SECRET, { algorithms: ["HS256"] });
  } catch (e) {
    const expirado = e.name === "TokenExpiredError";
    return res.status(401).json({
      ok: false,
      codigo: expirado ? "TOKEN_EXPIRADO" : "TOKEN_INVALIDO",
      mensaje: expirado
        ? "Tu sesión expiró. Inicia sesión de nuevo"
        : "Sesión no válida. Inicia sesión de nuevo",
    });
  }

  // Revisa que siga activo y toma el rol actual de la base.
  let rol = datos.rol;
  try {
    const estado = await estadoUsuario(datos.id);
    if (!estado.activo) {
      return res.status(401).json({
        ok: false,
        codigo: "USUARIO_INACTIVO",
        mensaje: "Usuario desactivado o inexistente. Contacta al administrador.",
      });
    }
    rol = estado.rol;
  } catch (e) {
    // Si la base no responde, se confía en lo firmado en el token.
    console.error("auth: no se pudo verificar el usuario en la base:", e.message);
  }

  req.usuario = { id: datos.id, nombre: datos.nombre, rolId: datos.rolId, rol };
  next();
}

function requireRol(...roles) {
  return (req, res, next) => {
    if (req.usuario && roles.includes(req.usuario.rol)) return next();
    return res.status(403).json({
      ok: false,
      codigo: "SIN_PERMISO",
      mensaje: "No tienes permiso para esta acción",
    });
  };
}

module.exports = { generarToken, verificarToken, requireRol, invalidarUsuario };
