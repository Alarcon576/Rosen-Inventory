// middleware/verifyToken.js
const jwt = require("jsonwebtoken");

const JWT_SECRET = process.env.JWT_SECRET || "tu_clave_secreta_muy_segura_2024";

const verificarToken = (req, res, next) => {
  // Obtener el token del header Authorization
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1]; // "Bearer TOKEN"

  if (!token) {
    return res.status(401).json({
      ok: false,
      mensaje: "Acceso denegado. No se proporcionó token.",
    });
  }

  // Verificar el token
  jwt.verify(token, JWT_SECRET, (err, usuario) => {
    if (err) {
      if (err.name === "TokenExpiredError") {
        return res.status(401).json({
          ok: false,
          mensaje: "Token expirado. Inicie sesión nuevamente.",
          expirado: true,
        });
      }
      return res.status(403).json({
        ok: false,
        mensaje: "Token inválido.",
      });
    }

    // Token válido: adjuntar usuario a la request
    req.usuario = usuario;
    next();
  });
};

module.exports = verificarToken;