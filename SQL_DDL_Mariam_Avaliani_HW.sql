SELECT 'CREATE DATABASE E-commerce_marketplace'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'E-commerce_marketplace'
);
-- ==========================================
-- 1. CREATE DATABASE
-- ==========================================

CREATE SCHEMA IF NOT EXISTS marketplace;
SET search_path TO marketplace;

-- ==========================================
-- IMPORTANT NOTE ABOUT ORDER:
-- Parent tables (users) must be created BEFORE child tables (buyers, sellers).
-- Otherwise PostgreSQL throws:
-- ERROR: relation "users" does not exist
-- ==========================================


-- ==========================================
-- USERS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.users (
    user_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- GENERATED ALWAYS ensures DB controls ID generation (prevents manual errors)

    email VARCHAR(255) UNIQUE NOT NULL,
    -- UNIQUE prevents duplicate accounts
    -- Without it → multiple users could share same email → login ambiguity

    password_hash VARCHAR(255) NOT NULL,
    -- NOT NULL ensures authentication data always exists
    -- Without it → user could exist without password

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    -- DEFAULT ensures timestamp auto-filled
    -- Without it → inconsistent or missing registration dates

    CHECK (created_at > '2000-01-01'),
    -- Prevents invalid old dates
    -- Without it → corrupted historical data possible

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL
);

-- ==========================================
-- BUYERS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.buyers (
    buyer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    user_id INT NOT NULL,
    -- FK ensures buyer must exist in users

    loyalty_points INT DEFAULT 0 CHECK (loyalty_points >= 0),
    -- Prevents negative values
    -- Without it → impossible states (negative points)

    membership_level VARCHAR(20) NOT NULL
    CHECK (membership_level IN ('bronze','silver','gold')),
    -- Restricts allowed values
    -- Without it → inconsistent values like 'vip', 'random'

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    CONSTRAINT fk_buyer_user FOREIGN KEY (user_id)
        REFERENCES marketplace.users(user_id)
        ON DELETE CASCADE
    -- If FK missing:
    -- buyer could reference non-existent user → broken relationship
);

-- ==========================================
-- SELLERS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.sellers (
    seller_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    user_id INT NOT NULL,

    store_name VARCHAR(150) NOT NULL,
    store_description TEXT,

    joined_date DATE DEFAULT CURRENT_DATE
    CHECK (joined_date > '2000-01-01'),

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    CONSTRAINT fk_seller_user FOREIGN KEY (user_id)
        REFERENCES marketplace.users(user_id)
        ON DELETE CASCADE
);

-- ==========================================
-- PRODUCTS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.products (
    product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    seller_id INT NOT NULL,

    name VARCHAR(200) NOT NULL,

    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    -- Prevents negative price
    -- Without it → invalid financial calculations

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    CONSTRAINT fk_product_seller FOREIGN KEY (seller_id)
        REFERENCES marketplace.sellers(seller_id)
        ON DELETE CASCADE
);

-- ==========================================
-- CATEGORIES TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.categories (
    category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    name VARCHAR(100) UNIQUE NOT NULL,
    -- Prevent duplicate category names

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL
);

-- ==========================================
-- PRODUCT_CATEGORIES (M:N)
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.product_categories (
    product_id INT NOT NULL,
    category_id INT NOT NULL,

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    PRIMARY KEY (product_id, category_id),

    FOREIGN KEY (product_id)
        REFERENCES marketplace.products(product_id)
        ON DELETE CASCADE,

    FOREIGN KEY (category_id)
        REFERENCES marketplace.categories(category_id)
        ON DELETE CASCADE
);

-- ==========================================
-- ORDERS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.orders (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    buyer_id INT NOT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    FOREIGN KEY (buyer_id)
        REFERENCES marketplace.buyers(buyer_id)
        ON DELETE CASCADE
);

-- ==========================================
-- ORDER_ITEMS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.order_items (
    order_item_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    order_id INT NOT NULL,
    product_id INT NOT NULL,

    quantity INT NOT NULL CHECK (quantity > 0),
    -- Prevents zero/negative quantity

    price_snapshot NUMERIC(10,2) NOT NULL CHECK (price_snapshot >= 0),

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    FOREIGN KEY (order_id)
        REFERENCES marketplace.orders(order_id)
        ON DELETE CASCADE,

    FOREIGN KEY (product_id)
        REFERENCES marketplace.products(product_id)
        ON DELETE CASCADE
);

-- ==========================================
-- PAYMENTS TABLE
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.payments (
    payment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    order_id INT NOT NULL,

    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),

    method VARCHAR(50) NOT NULL
    CHECK (method IN ('Credit Card','PayPal','Bank Transfer')),
    -- Restricts allowed payment methods

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    FOREIGN KEY (order_id)
        REFERENCES marketplace.orders(order_id)
        ON DELETE CASCADE
);

-- ==========================================
-- DISCOUNTS TABLE (GENERATED COLUMN)
-- ==========================================
CREATE TABLE IF NOT EXISTS marketplace.discounts (
    discount_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    product_id INT NOT NULL,

    discount_percent NUMERIC(5,2) NOT NULL
    CHECK (discount_percent BETWEEN 0 AND 100),

    start_date DATE NOT NULL CHECK (start_date > '2000-01-01'),
    end_date DATE NOT NULL CHECK (end_date > start_date),

    -- GENERATED column example
    discount_fraction NUMERIC(5,2)
    GENERATED ALWAYS AS (discount_percent / 100) STORED,
    -- Automatically computed value
    -- Without it → duplication or calculation errors in queries

    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,

    FOREIGN KEY (product_id)
        REFERENCES marketplace.products(product_id)
        ON DELETE CASCADE
);


-- ORDER_STATUS_HISTORY
CREATE TABLE IF NOT EXISTS marketplace.order_status_history (
    status_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES marketplace.orders(order_id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- INVENTORY_HISTORY
CREATE TABLE IF NOT EXISTS marketplace.inventory_history (
    inventory_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES marketplace.products(product_id) ON DELETE CASCADE,
    quantity INT NOT NULL, -- can be positive or negative
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reason VARCHAR(100) NOT NULL
);

-- REVIEWS
CREATE TABLE IF NOT EXISTS marketplace.reviews (
    review_id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES marketplace.products(product_id) ON DELETE CASCADE,
    buyer_id INT NOT NULL REFERENCES marketplace.buyers(buyer_id) ON DELETE CASCADE,
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SHIPMENTS
CREATE TABLE IF NOT EXISTS marketplace.shipments (
    shipment_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES marketplace.orders(order_id) ON DELETE CASCADE,
    address TEXT NOT NULL,
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP
);






-- ==========================================
-- 16. SAMPLE DATA INSERTION
-- Using ON CONFLICT DO NOTHING to avoid duplicates
-- ==========================================

-- ==============================================
-- Legacy inserts for GENERATED ALWAYS AS IDENTITY
-- Rerunnable, ON CONFLICT DO NOTHING
-- ==============================================

-- ==========================================
-- RERUNNABLE INSERTS FOR ALL TABLES
-- ==========================================
-- ==========================================
-- USERS
-- ==========================================
INSERT INTO marketplace.users (email, password_hash, created_at)
VALUES
  ('nona@gmail.com','hash123','2024-01-15 10:30:00'),
  ('ana@gmail.com','hash234','2024-02-20 09:15:00'),
  ('bob@gmail.com','hash256','2024-03-01 11:00:00')
ON CONFLICT (email) DO NOTHING;

-- ==========================================
-- BUYERS
-- ==========================================
INSERT INTO marketplace.buyers (user_id, loyalty_points, membership_level)
VALUES
  ((SELECT user_id FROM marketplace.users WHERE email='nona@gmail.com' LIMIT 1),1500,'gold'),
  ((SELECT user_id FROM marketplace.users WHERE email='ana@gmail.com' LIMIT 1),750,'silver'),
  ((SELECT user_id FROM marketplace.users WHERE email='bob@gmail.com' LIMIT 1),0,'bronze')
ON CONFLICT (buyer_id) DO NOTHING;

-- ==========================================
-- SELLERS
-- ==========================================
INSERT INTO marketplace.sellers (user_id, store_name, store_description, joined_date)
VALUES
  ((SELECT user_id FROM marketplace.users WHERE email='nona@gmail.com' LIMIT 1),'Tech Haven','Electronics and gadgets store','2024-01-15'),
  ((SELECT user_id FROM marketplace.users WHERE email='ana@gmail.com' LIMIT 1),'Fashion Hub','Trendy clothing and accessories','2024-02-20'),
  ((SELECT user_id FROM marketplace.users WHERE email='bob@gmail.com' LIMIT 1),'Bookworm''s Paradise','New and used books','2024-03-01')
ON CONFLICT (seller_id) DO NOTHING;

-- ==========================================
-- CATEGORIES
-- ==========================================
INSERT INTO marketplace.categories (name)
VALUES
  ('Electronics'),
  ('Smartphones'),
  ('Laptops')
ON CONFLICT (name) DO NOTHING;

-- ==========================================
-- PRODUCTS
-- ==========================================
INSERT INTO marketplace.products (seller_id, name, price)
VALUES
  ((SELECT seller_id FROM marketplace.sellers WHERE store_name='Tech Haven' LIMIT 1),'iPhone 13',999.99),
  ((SELECT seller_id FROM marketplace.sellers WHERE store_name='Tech Haven' LIMIT 1),'MacBook Pro',1999.99),
  ((SELECT seller_id FROM marketplace.sellers WHERE store_name='Fashion Hub' LIMIT 1),'Summer Dress',49.99)
ON CONFLICT (product_id) DO NOTHING;

-- ==========================================
-- PRODUCT_CATEGORIES
-- ==========================================
INSERT INTO marketplace.product_categories (product_id, category_id)
VALUES
  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),
   (SELECT category_id FROM marketplace.categories WHERE name='Smartphones' LIMIT 1)),
  ((SELECT product_id FROM marketplace.products WHERE name='MacBook Pro' LIMIT 1),
   (SELECT category_id FROM marketplace.categories WHERE name='Laptops' LIMIT 1)),
  ((SELECT product_id FROM marketplace.products WHERE name='Summer Dress' LIMIT 1),
   (SELECT category_id FROM marketplace.categories WHERE name='Electronics' LIMIT 1))
ON CONFLICT (product_id, category_id) DO NOTHING;

-- ==========================================
-- ORDERS
-- ==========================================
INSERT INTO marketplace.orders (buyer_id, created_at, total_price)
VALUES
  ((SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='nona@gmail.com' LIMIT 1) LIMIT 1),'2024-03-05 14:30:00',999.99),
  ((SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='nona@gmail.com' LIMIT 1) LIMIT 1),'2024-03-04 14:30:00',1999.99),
  ((SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='ana@gmail.com' LIMIT 1) LIMIT 1),'2024-03-05 14:30:00',49.99)
ON CONFLICT (order_id) DO NOTHING;

-- ==========================================
-- ORDER_ITEMS
-- ==========================================
INSERT INTO marketplace.order_items (order_id, product_id, quantity, price_snapshot)
VALUES
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),
   (SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),1,999.99),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at OFFSET 1 LIMIT 1),
   (SELECT product_id FROM marketplace.products WHERE name='MacBook Pro' LIMIT 1),1,1999.99),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at OFFSET 2 LIMIT 1),
   (SELECT product_id FROM marketplace.products WHERE name='Summer Dress' LIMIT 1),1,49.99)
ON CONFLICT (order_item_id) DO NOTHING;

-- ==========================================
-- PAYMENTS
-- ==========================================
INSERT INTO marketplace.payments (order_id, amount, method)
VALUES
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),999.99,'Credit Card'),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),125.50,'PayPal'),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at OFFSET 1 LIMIT 1),1999.99,'Credit Card')
ON CONFLICT (payment_id) DO NOTHING;

-- ==========================================
-- SHIPMENTS
-- ==========================================
INSERT INTO marketplace.shipments (order_id, address, shipped_at)
VALUES
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),'123 Main St, City, ST 12345','2024-03-06 10:00:00'),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at OFFSET 1 LIMIT 1),'456 Oak Ave, Town, ST 67890',NULL)
ON CONFLICT (shipment_id) DO NOTHING;

-- ==========================================
-- REVIEWS
-- ==========================================
INSERT INTO marketplace.reviews (product_id, buyer_id, rating, comment, created_at)
VALUES
  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),
   (SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='nona@gmail.com' LIMIT 1) LIMIT 1),5,'Excellent phone! Battery life is amazing.','2024-03-06 15:30:00'),

  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),
   (SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='ana@gmail.com' LIMIT 1) LIMIT 1),4,'Great phone but a bit expensive','2024-03-07 09:45:00'),

  ((SELECT product_id FROM marketplace.products WHERE name='Summer Dress' LIMIT 1),
   (SELECT buyer_id FROM marketplace.buyers WHERE user_id=(SELECT user_id FROM marketplace.users WHERE email='bob@gmail.com' LIMIT 1) LIMIT 1),5,'Love this dress, perfect fit!','2024-03-06 15:30:00')
ON CONFLICT (review_id) DO NOTHING;

-- ==========================================
-- INVENTORY_HISTORY
-- ==========================================
INSERT INTO marketplace.inventory_history (product_id, quantity, changed_at, reason)
VALUES
  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),50,'2024-03-01 09:00:00','Initial stock'),
  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),-20,'2024-03-01 09:30:00','Order #3'),
  ((SELECT product_id FROM marketplace.products WHERE name='Summer Dress' LIMIT 1),100,'2024-03-01 10:00:00','Initial stock')
ON CONFLICT (inventory_id) DO NOTHING;

-- ==========================================
-- ORDER_STATUS_HISTORY
-- ==========================================
INSERT INTO marketplace.order_status_history (order_id, status, changed_at)
VALUES
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),'Pending','2024-03-05 15:00:00'),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at LIMIT 1),'Shipped','2024-03-06 10:00:00'),
  ((SELECT order_id FROM marketplace.orders ORDER BY created_at OFFSET 1 LIMIT 1),'Pending','2024-03-04 15:00:00')
ON CONFLICT (status_id) DO NOTHING;

-- ==========================================
-- DISCOUNTS
-- ==========================================
INSERT INTO marketplace.discounts (product_id, discount_percent, start_date, end_date)
VALUES
  ((SELECT product_id FROM marketplace.products WHERE name='iPhone 13' LIMIT 1),10.00,'2024-03-01','2024-03-31'),
  ((SELECT product_id FROM marketplace.products WHERE name='Summer Dress' LIMIT 1),20.00,'2024-03-01','2024-03-15')
ON CONFLICT (discount_id) DO NOTHING;
-- ==========================================
-- 17. ALTER TABLES TO ENSURE record_ts EXISTS FOR EXISTING ROWS
-- ==========================================
-- ==========================================
-- ADD record_ts TO ALL TABLES
-- ==========================================

-- USERS
ALTER TABLE marketplace.users
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.users
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.users
ALTER COLUMN record_ts SET NOT NULL;


-- BUYERS
ALTER TABLE marketplace.buyers
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.buyers
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.buyers
ALTER COLUMN record_ts SET NOT NULL;


-- SELLERS
ALTER TABLE marketplace.sellers
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.sellers
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.sellers
ALTER COLUMN record_ts SET NOT NULL;


-- PRODUCTS
ALTER TABLE marketplace.products
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.products
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.products
ALTER COLUMN record_ts SET NOT NULL;


-- CATEGORIES
ALTER TABLE marketplace.categories
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.categories
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.categories
ALTER COLUMN record_ts SET NOT NULL;


-- PRODUCT_CATEGORIES
ALTER TABLE marketplace.product_categories
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.product_categories
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.product_categories
ALTER COLUMN record_ts SET NOT NULL;


-- ORDERS
ALTER TABLE marketplace.orders
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.orders
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.orders
ALTER COLUMN record_ts SET NOT NULL;


-- ORDER_ITEMS
ALTER TABLE marketplace.order_items
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.order_items
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.order_items
ALTER COLUMN record_ts SET NOT NULL;


-- PAYMENTS
ALTER TABLE marketplace.payments
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.payments
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.payments
ALTER COLUMN record_ts SET NOT NULL;


-- SHIPMENTS
ALTER TABLE marketplace.shipments
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.shipments
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.shipments
ALTER COLUMN record_ts SET NOT NULL;


-- REVIEWS
ALTER TABLE marketplace.reviews
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.reviews
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.reviews
ALTER COLUMN record_ts SET NOT NULL;


-- INVENTORY_HISTORY
ALTER TABLE marketplace.inventory_history
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.inventory_history
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.inventory_history
ALTER COLUMN record_ts SET NOT NULL;


-- ORDER_STATUS_HISTORY
ALTER TABLE marketplace.order_status_history
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.order_status_history
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.order_status_history
ALTER COLUMN record_ts SET NOT NULL;


-- DISCOUNTS
ALTER TABLE marketplace.discounts
ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;

UPDATE marketplace.discounts
SET record_ts = CURRENT_DATE
WHERE record_ts IS NULL;

ALTER TABLE marketplace.discounts
ALTER COLUMN record_ts SET NOT NULL;





