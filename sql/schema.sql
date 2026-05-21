CREATE DATABASE IF NOT EXISTS marcozero_ecommerce
  CHARACTER SET utf8mb4
  COLLATE       utf8mb4_unicode_ci;
USE marcozero_ecommerce;
CREATE TABLE IF NOT EXISTS produtos (
  id           BIGINT UNSIGNED      NOT NULL AUTO_INCREMENT,
  sku          VARCHAR(40)          NOT NULL,
  nome         VARCHAR(160)         NOT NULL,
  descricao    TEXT                 NULL,
  preco        DECIMAL(10,2)        NOT NULL CHECK (preco >= 0),
  estoque      INT UNSIGNED         NOT NULL DEFAULT 0,
  ativo        TINYINT(1)           NOT NULL DEFAULT 1,
  created_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_produtos_sku (sku),
  KEY idx_produtos_ativo (ativo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS clientes (
  id           BIGINT UNSIGNED      NOT NULL AUTO_INCREMENT,
  nome         VARCHAR(160)         NOT NULL,
  email        VARCHAR(160)         NOT NULL,
  telefone     VARCHAR(20)          NULL,
  cidade       VARCHAR(80)          NULL,
  uf           CHAR(2)              NULL,
  created_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_clientes_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS pedidos (
  id           BIGINT UNSIGNED      NOT NULL AUTO_INCREMENT,
  cliente_id   BIGINT UNSIGNED      NOT NULL,
  status       ENUM('CRIADO','PAGO','ENVIADO','ENTREGUE','CANCELADO')
                                     NOT NULL DEFAULT 'CRIADO',
  total        DECIMAL(12,2)        NOT NULL DEFAULT 0.00,
  created_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP            NOT NULL DEFAULT CURRENT_TIMESTAMP
                                     ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_pedidos_cliente (cliente_id),
  KEY idx_pedidos_status  (status),
  CONSTRAINT fk_pedidos_cliente FOREIGN KEY (cliente_id)
    REFERENCES clientes(id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS pedido_itens (
  id           BIGINT UNSIGNED      NOT NULL AUTO_INCREMENT,
  pedido_id    BIGINT UNSIGNED      NOT NULL,
  produto_id   BIGINT UNSIGNED      NOT NULL,
  quantidade   INT UNSIGNED         NOT NULL CHECK (quantidade > 0),
  preco_unit   DECIMAL(10,2)        NOT NULL CHECK (preco_unit >= 0),
  subtotal     DECIMAL(12,2)
               GENERATED ALWAYS AS (quantidade * preco_unit) STORED,
  PRIMARY KEY (id),
  KEY idx_itens_pedido  (pedido_id),
  KEY idx_itens_produto (produto_id),
  CONSTRAINT fk_itens_pedido FOREIGN KEY (pedido_id)
    REFERENCES pedidos(id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_itens_produto FOREIGN KEY (produto_id)
    REFERENCES produtos(id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO produtos (sku, nome, descricao, preco, estoque) VALUES
  ('SAB-LAV-100', 'Sabonete artesanal de lavanda 100g',
     'Sabonete vegetal com óleos essenciais de lavanda', 18.90, 120),
  ('HID-COC-250', 'Hidratante corporal de coco 250ml',
     'Hidratante com manteiga de coco e vitamina E',   34.50,  80),
  ('VEL-CAS-200', 'Vela aromática de cassia 200g',
     'Vela artesanal com óleo essencial de cassia',    42.00,  40)
ON DUPLICATE KEY UPDATE nome = VALUES(nome);
INSERT INTO clientes (nome, email, telefone, cidade, uf) VALUES
  ('Ana Souza',   'ana.souza@example.com',  '81999990001', 'Olinda',  'PE'),
  ('Bruno Lima',  'bruno.lima@example.com', '81999990002', 'Recife',  'PE')
ON DUPLICATE KEY UPDATE nome = VALUES(nome);
INSERT INTO pedidos (cliente_id, status, total)
SELECT c.id, 'PAGO', 0.00
  FROM clientes c
 WHERE c.email = 'ana.souza@example.com'
   AND NOT EXISTS (SELECT 1 FROM pedidos);
INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, preco_unit)
SELECT p.id, pr.id, 2, pr.preco
  FROM pedidos p
  JOIN produtos pr ON pr.sku = 'SAB-LAV-100'
 WHERE p.id = 1
   AND NOT EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = 1);
INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, preco_unit)
SELECT p.id, pr.id, 1, pr.preco
  FROM pedidos p
  JOIN produtos pr ON pr.sku = 'HID-COC-250'
 WHERE p.id = 1
   AND NOT EXISTS (SELECT 1 FROM pedido_itens WHERE pedido_id = 1 AND produto_id = pr.id);
UPDATE pedidos p
   SET total = (SELECT COALESCE(SUM(subtotal),0) FROM pedido_itens i WHERE i.pedido_id = p.id)
 WHERE p.id = 1;