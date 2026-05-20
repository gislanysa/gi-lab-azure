require('dotenv').config();
const express = require('express');
const mysql   = require('mysql2/promise');

const app = express();
app.use(express.json());

const pool = mysql.createPool({
  host:     process.env.DB_HOST,
  port:     Number(process.env.DB_PORT || 3306),
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit:    10,
  connectTimeout:     5000,
});

app.use((req, _res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  next();
});

app.get('/health', async (_req, res) => {
  try {
    const [rows] = await pool.query('SELECT 1 AS ok');
    res.json({ app: 'ok', db: rows[0].ok === 1 ? 'ok' : 'fail' });
  } catch (err) {
    res.status(500).json({ app: 'ok', db: 'fail', error: err.code || err.message });
  }
});

app.get('/produtos', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, sku, nome, preco, estoque, ativo FROM produtos ORDER BY id'
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.code || err.message });
  }
});

app.post('/produtos', async (req, res) => {
  const { sku, nome, descricao, preco, estoque } = req.body || {};
  if (!sku || !nome || preco == null) {
    return res.status(400).json({ error: 'sku, nome e preco sao obrigatorios' });
  }
  try {
    const [r] = await pool.execute(
      `INSERT INTO produtos (sku, nome, descricao, preco, estoque)
       VALUES (?, ?, ?, ?, ?)`,
      [sku, nome, descricao || null, preco, estoque || 0]
    );
    res.status(201).json({ id: r.insertId, sku, nome });
  } catch (err) {
    res.status(500).json({ error: err.code || err.message });
  }
});

app.get('/clientes', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, nome, email, telefone, cidade, uf FROM clientes ORDER BY id'
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.code || err.message });
  }
});

app.get('/pedidos', async (_req, res) => {
  try {
    const [rows] = await pool.query(`
      SELECT p.id,
             p.status,
             p.total,
             p.created_at,
             c.nome   AS cliente,
             JSON_ARRAYAGG(
               JSON_OBJECT(
                 'produto_id', i.produto_id,
                 'sku',        pr.sku,
                 'quantidade', i.quantidade,
                 'preco_unit', i.preco_unit,
                 'subtotal',   i.subtotal
               )
             ) AS itens
        FROM pedidos      p
        JOIN clientes     c  ON c.id = p.cliente_id
   LEFT JOIN pedido_itens i  ON i.pedido_id = p.id
   LEFT JOIN produtos     pr ON pr.id = i.produto_id
       GROUP BY p.id, p.status, p.total, p.created_at, c.nome
       ORDER BY p.id DESC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.code || err.message });
  }
});

app.use((_req, res) => res.status(404).json({ error: 'not found' }));

const port = Number(process.env.PORT || 3000);
app.listen(port, '127.0.0.1', () => {
  console.log(`marcozero api on 127.0.0.1:${port} -> ${process.env.DB_HOST}:${process.env.DB_PORT}`);
});
