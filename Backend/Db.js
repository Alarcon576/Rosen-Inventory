
require('dotenv').config();

const sql = require('mssql');

const obligatorias = [
  'DB_USER',
  'DB_PASSWORD',
  'DB_SERVER',
  'DB_DATABASE',
];

for (const variable of obligatorias) {
  if (!process.env[variable]) {
    throw new Error(
      `Falta configurar la variable de entorno ${variable}`
    );
  }
}

const config = {
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  server: process.env.DB_SERVER,
  database: process.env.DB_DATABASE,

  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate:
      process.env.DB_TRUST_SERVER_CERTIFICATE === 'true',
  },

  connectionTimeout: 15000,
  requestTimeout: 30000,
};

const poolPromise = new sql.ConnectionPool(config)
  .connect()
  .then((pool) => {
    console.log('==================================');
    console.log('Conectado correctamente a SQL Server');
    console.log('==================================');

    return pool;
  })
  .catch((err) => {
    console.error('Error al conectar con SQL Server:', err.message);
    throw err;
  });

module.exports = {
  sql,
  poolPromise,
};
