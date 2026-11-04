// server.js
// Punto de entrada del servidor. Solo configura Express y conecta
// las rutas. La lógica de cada endpoint vive en su controlador.

const express = require("express");
const cors = require("cors");

const app = express();

app.use(cors());
app.use(express.json());

// --- Rutas (cada grupo en su archivo) ---
app.use(require("./routes/salud.routes"));
app.use(require("./routes/auth.routes"));
app.use(require("./routes/productos.routes"));
app.use(require("./routes/conteos.routes"));
app.use(require("./routes/usuarios.routes"));
app.use(require("./routes/reportes.routes"));

// --- Arrancar el servidor ---
const PORT = 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Servidor escuchando en el puerto ${PORT}`);
});



const sql = require("mssql");


const config = {
  user: "sa",                     
  password: "Tantau2024",   
  server: "ASISTENTEIT\\PRODUCCIONIT",              
  database: "conteoAlmacen",           
  options: {
    encrypt: false,                 
    trustServerCertificate: true,   
  },
};


const poolPromise = new sql.ConnectionPool(config)
  .connect()
  .then((pool) => {
    console.log("==================================");
    console.log("Conectado correctamente a SQL Server");
    console.log("==================================");
    return pool;
  })
  .catch((err) => {
    console.log("==================================");
    console.log("Error al conectar con SQL Server");
    console.error(err);
    console.log("==================================");
  });

module.exports = {
  sql,
  poolPromise,
};