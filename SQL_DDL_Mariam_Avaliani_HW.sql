-- ==========================================
-- DATABASE (run once manually)
-- ==========================================
-- CREATE DATABASE "E-commerce_marketplace";

-- ==========================================
-- SCHEMA
-- ==========================================
CREATE SCHEMA IF NOT EXISTS marketplace;
SET search_path TO marketplace;

-- ==========================================
-- TABLES (same as yours but with needed UNIQUE constraints)
-- ==========================================

CREATE TABLE IF NOT EXISTS marketplace.users (
    user_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CHECK (created_at > '2000-01-01'),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS marketplace.buyers (
    buyer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    loyalty_points INT DEFAULT 0 CHECK (loyalty_points >= 0),
    membership_level VARCHAR(20) NOT NULL
        CHECK (membership_level IN ('bronze','silver','gold')),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    FOREIGN KEY (user_id) REFERENCES marketplace.users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.sellers (
    seller_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    store_name VARCHAR(150) NOT NULL,
    store_description TEXT,
    joined_date DATE DEFAULT CURRENT_DATE CHECK (joined_date > '2000-01-01'),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    FOREIGN KEY (user_id) REFERENCES marketplace.users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.products (
    product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id INT NOT NULL,
    name VARCHAR(200) NOT NULL,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (seller_id, name),
    FOREIGN KEY (seller_id) REFERENCES marketplace.sellers(seller_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.categories (
    category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS marketplace.product_categories (
    product_id INT NOT NULL,
    category_id INT NOT NULL,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    PRIMARY KEY (product_id, category_id),
    FOREIGN KEY (product_id) REFERENCES marketplace.products(product_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES marketplace.categories(category_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.orders (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    buyer_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (buyer_id, created_at),
    FOREIGN KEY (buyer_id) REFERENCES marketplace.buyers(buyer_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.order_items (
    order_item_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    price_snapshot NUMERIC(10,2) NOT NULL CHECK (price_snapshot >= 0),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (order_id, product_id),
    FOREIGN KEY (order_id) REFERENCES marketplace.orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES marketplace.products(product_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.payments (
    payment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    method VARCHAR(50) NOT NULL
        CHECK (method IN ('Credit Card','PayPal','Bank Transfer')),
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (order_id, method, amount),
    FOREIGN KEY (order_id) REFERENCES marketplace.orders(order_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.shipments (
    shipment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL UNIQUE,
    address TEXT NOT NULL,
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    FOREIGN KEY (order_id) REFERENCES marketplace.orders(order_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.reviews (
    review_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id INT NOT NULL,
    buyer_id INT NOT NULL,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (product_id, buyer_id),
    FOREIGN KEY (product_id) REFERENCES marketplace.products(product_id) ON DELETE CASCADE,
    FOREIGN KEY (buyer_id) REFERENCES marketplace.buyers(buyer_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.inventory_history (
    inventory_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reason VARCHAR(100) NOT NULL,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (product_id, changed_at, reason),
    FOREIGN KEY (product_id) REFERENCES marketplace.products(product_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.order_status_history (
    status_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL,
    status VARCHAR(50) NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (order_id, status, changed_at),
    FOREIGN KEY (order_id) REFERENCES marketplace.orders(order_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS marketplace.discounts (
    discount_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id INT NOT NULL,
    discount_percent NUMERIC(5,2) NOT NULL CHECK (discount_percent BETWEEN 0 AND 100),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL CHECK (end_date > start_date),
    discount_fraction NUMERIC(5,2) GENERATED ALWAYS AS (discount_percent / 100) STORED,
    record_ts DATE DEFAULT CURRENT_DATE NOT NULL,
    UNIQUE (product_id, start_date, end_date),
    FOREIGN KEY (product_id) REFERENCES marketplace.products(product_id) ON DELETE CASCADE
);

-- ==========================================
-- INSERTS (ALL using WHERE NOT EXISTS)
-- ==========================================

-- USERS
INSERT INTO marketplace.users (email, password_hash, created_at)
SELECT * FROM (VALUES
 ('nona@gmail.com','hash123','2024-01-15'),
 ('ana@gmail.com','hash234','2024-02-20'),
 ('bob@gmail.com','hash256','2024-03-01')
) v(email, password_hash, created_at)
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.users u WHERE u.email = v.email
);

-- BUYERS
INSERT INTO marketplace.buyers (user_id, loyalty_points, membership_level)
SELECT u.user_id, v.points, v.level
FROM (VALUES
 ('nona@gmail.com',1500,'gold'),
 ('ana@gmail.com',750,'silver'),
 ('bob@gmail.com',0,'bronze')
) v(email, points, level)
JOIN marketplace.users u ON u.email = v.email
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.buyers b WHERE b.user_id = u.user_id
);

-- SELLERS
INSERT INTO marketplace.sellers (user_id, store_name, store_description)
SELECT u.user_id, v.name, v.desc
FROM (VALUES
 ('nona@gmail.com','Tech Haven','Electronics'),
 ('ana@gmail.com','Fashion Hub','Clothing'),
 ('bob@gmail.com','Bookworm''s Paradise','Books')
) v(email, name, desc)
JOIN marketplace.users u ON u.email = v.email
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.sellers s WHERE s.user_id = u.user_id
);

-- CATEGORIES
INSERT INTO marketplace.categories (name)
SELECT v.name FROM (VALUES
 ('Electronics'),('Smartphones'),('Laptops')
) v(name)
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.categories c WHERE c.name = v.name
);

-- PRODUCTS
INSERT INTO marketplace.products (seller_id, name, price)
SELECT s.seller_id, v.name, v.price
FROM (VALUES
 ('Tech Haven','iPhone 13',999.99),
 ('Tech Haven','MacBook Pro',1999.99),
 ('Fashion Hub','Summer Dress',49.99)
) v(store_name, name, price)
JOIN marketplace.sellers s ON s.store_name = v.store_name
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.products p
    WHERE p.seller_id = s.seller_id AND p.name = v.name
);

-- PRODUCT_CATEGORIES
INSERT INTO marketplace.product_categories (product_id, category_id)
SELECT p.product_id, c.category_id
FROM (VALUES
 ('iPhone 13','Smartphones'),
 ('MacBook Pro','Laptops'),
 ('Summer Dress','Electronics')
) v(product, category)
JOIN marketplace.products p ON p.name = v.product
JOIN marketplace.categories c ON c.name = v.category
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.product_categories pc
    WHERE pc.product_id = p.product_id AND pc.category_id = c.category_id
);

-- ORDERS
INSERT INTO marketplace.orders (buyer_id, created_at, total_price)
SELECT b.buyer_id, v.created_at, v.total
FROM (VALUES
 ('nona@gmail.com','2024-03-05 14:30:00',999.99),
 ('nona@gmail.com','2024-03-04 14:30:00',1999.99),
 ('ana@gmail.com','2024-03-05 14:30:00',49.99)
) v(email, created_at, total)
JOIN marketplace.users u ON u.email = v.email
JOIN marketplace.buyers b ON b.user_id = u.user_id
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders o
    WHERE o.buyer_id = b.buyer_id AND o.created_at = v.created_at
);

-- ORDER_ITEMS
INSERT INTO marketplace.order_items (order_id, product_id, quantity, price_snapshot)
SELECT o.order_id, p.product_id, v.qty, v.price
FROM (VALUES
 ('2024-03-05 14:30:00','iPhone 13',1,999.99),
 ('2024-03-04 14:30:00','MacBook Pro',1,1999.99),
 ('2024-03-05 14:30:00','Summer Dress',1,49.99)
) v(order_time, product, qty, price)
JOIN marketplace.orders o ON o.created_at = v.order_time
JOIN marketplace.products p ON p.name = v.product
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.order_items oi
    WHERE oi.order_id = o.order_id AND oi.product_id = p.product_id
);

-- PAYMENTS
INSERT INTO marketplace.payments (order_id, amount, method)
SELECT o.order_id, v.amount, v.method
FROM (VALUES
 ('2024-03-05 14:30:00',999.99,'Credit Card'),
 ('2024-03-05 14:30:00',125.50,'PayPal'),
 ('2024-03-04 14:30:00',1999.99,'Credit Card')
) v(order_time, amount, method)
JOIN marketplace.orders o ON o.created_at = v.order_time
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.payments p
    WHERE p.order_id = o.order_id AND p.method = v.method AND p.amount = v.amount
);

-- SHIPMENTS
INSERT INTO marketplace.shipments (order_id, address, shipped_at)
SELECT o.order_id, v.address, v.shipped
FROM (VALUES
 ('2024-03-05 14:30:00','123 Main St','2024-03-06 10:00:00'),
 ('2024-03-04 14:30:00','456 Oak Ave',NULL)
) v(order_time, address, shipped)
JOIN marketplace.orders o ON o.created_at = v.order_time
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.shipments s WHERE s.order_id = o.order_id
);

-- REVIEWS
INSERT INTO marketplace.reviews (product_id, buyer_id, rating, comment, created_at)
SELECT p.product_id, b.buyer_id, v.rating, v.comment, v.created
FROM (VALUES
 ('nona@gmail.com','iPhone 13',5,'Excellent','2024-03-06'),
 ('ana@gmail.com','iPhone 13',4,'Good','2024-03-07'),
 ('bob@gmail.com','Summer Dress',5,'Perfect','2024-03-06')
) v(email, product, rating, comment, created)
JOIN marketplace.users u ON u.email = v.email
JOIN marketplace.buyers b ON b.user_id = u.user_id
JOIN marketplace.products p ON p.name = v.product
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.reviews r
    WHERE r.product_id = p.product_id AND r.buyer_id = b.buyer_id
);

-- INVENTORY_HISTORY
INSERT INTO marketplace.inventory_history (product_id, quantity, changed_at, reason)
SELECT p.product_id, v.qty, v.time, v.reason
FROM (VALUES
 ('iPhone 13',50,'2024-03-01','Initial stock'),
 ('iPhone 13',-20,'2024-03-01 09:30','Order'),
 ('Summer Dress',100,'2024-03-01','Initial stock')
) v(product, qty, time, reason)
JOIN marketplace.products p ON p.name = v.product
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.inventory_history i
    WHERE i.product_id = p.product_id AND i.changed_at = v.time AND i.reason = v.reason
);

-- ORDER_STATUS_HISTORY
INSERT INTO marketplace.order_status_history (order_id, status, changed_at)
SELECT o.order_id, v.status, v.time
FROM (VALUES
 ('2024-03-05 14:30:00','Pending','2024-03-05 15:00'),
 ('2024-03-05 14:30:00','Shipped','2024-03-06 10:00'),
 ('2024-03-04 14:30:00','Pending','2024-03-04 15:00')
) v(order_time, status, time)
JOIN marketplace.orders o ON o.created_at = v.order_time
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.order_status_history s
    WHERE s.order_id = o.order_id AND s.status = v.status AND s.changed_at = v.time
);

-- DISCOUNTS
INSERT INTO marketplace.discounts (product_id, discount_percent, start_date, end_date)
SELECT p.product_id, v.percent, v.start_d, v.end_d
FROM (VALUES
 ('iPhone 13',10,'2024-03-01','2024-03-31'),
 ('Summer Dress',20,'2024-03-01','2024-03-15')
) v(product, percent, start_d, end_d)
JOIN marketplace.products p ON p.name = v.product
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.discounts d
    WHERE d.product_id = p.product_id AND d.start_date = v.start_d AND d.end_date = v.end_d
);

-- ==========================================
-- ADD record_ts USING ALTER (ASSIGNMENT REQUIREMENT)
-- ==========================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE users SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE users ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE buyers ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE buyers SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE buyers ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE sellers ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE sellers SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE sellers ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE products ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE products SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE products ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE categories ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE categories SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE categories ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE product_categories SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE product_categories ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE orders SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE orders ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE order_items ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE order_items SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE order_items ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE payments ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE payments SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE payments ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE shipments ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE shipments SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE shipments ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE reviews ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE reviews SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE reviews ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE inventory_history ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE inventory_history SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE inventory_history ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE order_status_history ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE order_status_history SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE order_status_history ALTER COLUMN record_ts SET NOT NULL;

ALTER TABLE discounts ADD COLUMN IF NOT EXISTS record_ts DATE DEFAULT CURRENT_DATE;
UPDATE discounts SET record_ts = CURRENT_DATE WHERE record_ts IS NULL;
ALTER TABLE discounts ALTER COLUMN record_ts SET NOT NULL;




