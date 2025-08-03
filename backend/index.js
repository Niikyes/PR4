const express = require('express');
const cors = require('cors');
const pool = require('./db');
const axios = require('axios');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Crear tabla si no existe
pool.query(`
  CREATE TABLE IF NOT EXISTS contacts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    phone VARCHAR(20)
  )
`);

// Endpoint: agregar contacto
app.post('/api/contacts', async (req, res) => {
  try {
    const { name, phone } = req.body;
    await pool.query('INSERT INTO contacts (name, phone) VALUES ($1, $2)', [name, phone]);
    res.json({ message: 'Contact saved!' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Database error' });
  }
});

// Endpoint: obtener contactos
app.get('/api/contacts', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM contacts');
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Database error' });
  }
});

// Endpoint: consumir API externa (joke)
app.get('/api/joke', async (req, res) => {
  try {
    const response = await axios.get('https://v2.jokeapi.dev/joke/Any');
    res.json(response.data);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'API error' });
  }
});

// Levantar servidor
app.listen(process.env.PORT, () => {
  console.log(`Backend running on port ${process.env.PORT}`);
});

