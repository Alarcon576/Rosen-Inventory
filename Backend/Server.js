// server.js
// Punto de entrada del servidor. Solo configura Express y conecta
// las rutas. La lógica de cada endpoint vive en su controlador.

// Variables de entorno (.env): JWT_SECRET, JWT_EXPIRES_IN
require("dotenv").config();

const express = require("express");
const cors = require("cors");

const { verificarToken } = require("./middleware/auth.middleware");

const app = express();

app.use(cors());
app.use(express.json());

// --- Rutas públicas: GET / (prueba de conexión) y POST /login ---
app.use(require("./routes/salud.routes"));
app.use(require("./routes/auth.routes"));

// --- Desde aquí TODO exige token. Cada archivo de rutas indica además
//     qué roles pueden usar cada endpoint. ---
app.use(verificarToken);
app.use(require("./routes/productos.routes"));
app.use(require("./routes/conteos.routes"));
app.use(require("./routes/usuarios.routes"));
app.use(require("./routes/reportes.routes"));

// --- Arrancar el servidor ---
const PORT = 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Servidor escuchando en el puerto ${PORT}`);
});
