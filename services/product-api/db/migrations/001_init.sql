-- Initial schema for CloudNative Commerce
-- Runs automatically when the postgres container starts for the first time

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Products
CREATE TABLE IF NOT EXISTS products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    description TEXT        NOT NULL DEFAULT '',
    price_cents BIGINT      NOT NULL CHECK (price_cents >= 0),
    sku         TEXT        NOT NULL UNIQUE,
    stock       INTEGER     NOT NULL DEFAULT 0 CHECK (stock >= 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
    id         UUID PRIMARY KEY,
    user_id    UUID        NOT NULL,
    status     TEXT        NOT NULL DEFAULT 'confirmed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Order line items
CREATE TABLE IF NOT EXISTS order_items (
    id         BIGSERIAL   PRIMARY KEY,
    order_id   UUID        NOT NULL REFERENCES orders(id),
    product_id UUID        NOT NULL REFERENCES products(id),
    quantity   INTEGER     NOT NULL CHECK (quantity > 0)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id       ON orders(user_id);

-- Seed data for local development
INSERT INTO products (name, description, price_cents, sku, stock) VALUES
    ('Wireless Headphones', 'Noise-cancelling, 30hr battery', 799900, 'ELEC-WH-001', 50),
    ('Mechanical Keyboard',  'Compact TKL, Cherry MX Brown',  649900, 'ELEC-KB-001', 30),
    ('USB-C Hub',            '7-in-1 multiport adapter',      299900, 'ELEC-HB-001', 100),
    ('Laptop Stand',         'Aluminium, adjustable height',  249900, 'DESK-LS-001', 75)
ON CONFLICT (sku) DO NOTHING;
