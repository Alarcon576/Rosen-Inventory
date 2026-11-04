// crear-usuario.js
// Script de un solo uso para crear un usuario con contraseña hasheada.
// Se ejecuta con: node crear-usuario.js
// Puedes cambiar los datos de abajo y correrlo de nuevo para más usuarios.

const bcrypt = require("bcrypt");
const { poolPromise, sql } = require("./db");

// ---- DATOS DEL USUARIO A CREAR (cámbialos a tu gusto) ----
const NOMBRE = "Admin";
const CONTRASENA = "123";    
const ROL_ID = 2;                
// ----------------------------------------------------------

async function crearUsuario() {
  try {
    // 1. Hashear la contraseña. El "10" es el nivel de seguridad
    //    (cuántas vueltas de encriptación). 10 es el estándar.
    const hash = await bcrypt.hash(CONTRASENA, 10);

    console.log("Contraseña original:", CONTRASENA);
    console.log("Hash generado:", hash);

    
    const pool = await poolPromise;
    await pool
      .request()
      .input("nombre", sql.VarChar, NOMBRE)
      .input("contrasena", sql.VarChar, hash)
      .input("rolId", sql.Int, ROL_ID)
      .query(
        "INSERT INTO Usuarios (Nombre, Contrasena, RolID) VALUES (@nombre, @contrasena, @rolId)"
      );

    console.log("==================================");
    console.log("Usuario creado correctamente:", NOMBRE);
    console.log("==================================");

    process.exit(0);   
  } catch (error) {
    console.error("Error creando el usuario:", error);
    process.exit(1);
  }
}

crearUsuario();