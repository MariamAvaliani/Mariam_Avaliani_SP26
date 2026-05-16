-- =========================================================
-- Household Appliances Store Database
-- Physical Model (3NF)
-- Includes:
-- DATABASE + SCHEMA
-- PK / FK
-- DEFAULT values
-- GENERATED ALWAYS AS columns
-- ALTER TABLE CHECK constraints
-- UNIQUE / NOT NULL constraints
-- Re-runnable script
-- =========================================================

-- =====================================================
-- Uses IF NOT EXISTS where appropriate
-- =====================================================

-- STEP 2: CREATE DATABASE
-- =========================================================

/*CREATE DATABASE household_appliances_store;*/



-- Create schema safely
CREATE SCHEMA IF NOT EXISTS household_store;
SET search_path TO household_store;

-- =====================================================
-- 1. PARENT TABLES
-- =====================================================

CREATE TABLE IF NOT EXISTS household_store.category (
    category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS household_store.supplier (
    supplier_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    address VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS household_store.customer (
    customer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    address VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS household_store.employee (
    employee_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    position VARCHAR(100) NOT NULL,
    salary NUMERIC(10,2) NOT NULL,
    hire_date DATE NOT NULL,
    phone VARCHAR(20) UNIQUE
);

-- =====================================================
-- 2. CHILD TABLES
-- =====================================================

CREATE TABLE IF NOT EXISTS household_store.product (
    product_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_name VARCHAR(150) NOT NULL,
    brand VARCHAR(100) NOT NULL,
    model VARCHAR(100) NOT NULL,
    category_id INT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    stock_quantity INT NOT NULL DEFAULT 0,
    warranty_months INT DEFAULT 0,

    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id)
        REFERENCES category(category_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS household_store.orders (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INT NOT NULL,
    employee_id INT NOT NULL,
    order_date DATE NOT NULL,
    order_status VARCHAR(50) NOT NULL DEFAULT 'Pending',
    total_amount NUMERIC(10,2) DEFAULT 0,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_orders_employee
        FOREIGN KEY (employee_id)
        REFERENCES employee(employee_id)
        ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS household_store.order_item (
    order_id INT,
    product_id INT,
    quantity INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,

    CONSTRAINT pk_order_item PRIMARY KEY (order_id, product_id),

    CONSTRAINT fk_orderitem_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_orderitem_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS household_store.procurement (
    procurement_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id INT NOT NULL,
    product_id INT NOT NULL,
    employee_id INT NOT NULL,
    procurement_date DATE NOT NULL,
    quantity INT NOT NULL,
    cost_price NUMERIC(10,2) NOT NULL,

    CONSTRAINT fk_proc_supplier
        FOREIGN KEY (supplier_id)
        REFERENCES supplier(supplier_id),

    CONSTRAINT fk_proc_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id),

    CONSTRAINT fk_proc_employee
        FOREIGN KEY (employee_id)
        REFERENCES employee(employee_id)
);

-- =====================================================
-- 3. CHECK CONSTRAINTS (SAFE ADD)
-- PostgreSQL does NOT support IF NOT EXISTS for constraints
-- So we use DO blocks to avoid duplication errors
-- =====================================================


-- ============================================
--  ALTER TABLE CHECK CONSTRAINTS
-- ============================================

-- PRODUCT TABLE CONSTRAINTS

-- Price must be positive
ALTER TABLE household_store.product
ADD CONSTRAINT chk_product_price_positive
CHECK (price > 0);

-- Stock cannot be negative
ALTER TABLE household_store.product
ADD CONSTRAINT chk_product_stock_non_negative
CHECK (stock_quantity >= 0);

-- Warranty cannot be negative
ALTER TABLE household_store.product
ADD CONSTRAINT chk_product_warranty_non_negative
CHECK (warranty_months >= 0);


-- ORDERS TABLE CONSTRAINTS

-- Allowed order statuses only
ALTER TABLE household_store.orders
ADD CONSTRAINT chk_orders_status_valid
CHECK (order_status IN ('Pending','Shipped','Delivered','Cancelled'));

-- Orders must be after Jan 1, 2026
ALTER TABLE household_store.orders
ADD CONSTRAINT chk_orders_date_after_2026
CHECK (order_date > DATE '2026-01-01');


-- EMPLOYEE TABLE CONSTRAINTS

-- Salary must be positive
ALTER TABLE household_store.employee
ADD CONSTRAINT chk_employee_salary_positive
CHECK (salary > 0);


-- PROCUREMENT TABLE CONSTRAINTS

-- Quantity must be positive
ALTER TABLE household_store.procurement
ADD CONSTRAINT chk_procurement_quantity_positive
CHECK (quantity > 0);

-- Cost price must be positive
ALTER TABLE household_store.procurement
ADD CONSTRAINT chk_procurement_cost_positive
CHECK (cost_price > 0);


-- ORDER_ITEM TABLE CONSTRAINTS

-- Quantity must be positive
ALTER TABLE household_store.order_item
ADD CONSTRAINT chk_orderitem_quantity_positive
CHECK (quantity > 0);

-- Unit price must be positive
ALTER TABLE household_store.order_item
ADD CONSTRAINT chk_orderitem_price_positive
CHECK (unit_price > 0);

-- =====================================================
-- DML SCRIPT (FINAL, FIXED, RERUNNABLE)
-- No surrogate keys
-- No reserved keywords
-- No duplicates
-- Uses subqueries instead of hardcoded IDs
-- =====================================================

SET search_path TO household_store;

-- =====================================================
-- CATEGORY (6 rows)
-- =====================================================


-- =====================================================
-- DML SCRIPT (SAFE + RERUNNABLE)
-- No surrogate keys used
-- Uses WHERE NOT EXISTS to avoid duplicates
-- Dates: last 3 months
-- =====================================================

INSERT INTO household_store.category (category_name, description)
SELECT * FROM (VALUES
    ('Refrigerator', 'Cooling appliances'),
    ('Television', 'Smart TVs and displays'),
    ('Washing Machine', 'Laundry appliances'),
    ('Air Conditioner', 'Cooling systems'),
    ('Microwave', 'Kitchen heating appliances'),
    ('Dishwasher', 'Automatic dish cleaning')
) AS v(category_name, description)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.category c WHERE c.category_name = v.category_name
);

-- =====================================================
-- SUPPLIER (6 rows)
-- =====================================================

INSERT INTO household_store.supplier (supplier_name, phone, email, address)
SELECT * FROM (VALUES
    ('LG Supplier', '555-1001', 'lg@supplier.com', 'Seoul'),
    ('Samsung Distributor', '555-1002', 'samsung@supplier.com', 'Busan'),
    ('Bosch Supply', '555-1003', 'bosch@supplier.com', 'Berlin'),
    ('Whirlpool Co', '555-1004', 'whirlpool@supplier.com', 'USA'),
    ('Panasonic Trade', '555-1005', 'panasonic@supplier.com', 'Tokyo'),
    ('Philips Supply', '555-1006', 'philips@supplier.com', 'Amsterdam')
) AS v(name, phone, email, address)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.supplier s WHERE s.phone = v.phone
);

-- =====================================================
-- CUSTOMER (6 rows)
-- =====================================================

INSERT INTO household_store.customer (first_name, last_name, phone, email, address)
SELECT * FROM (VALUES
    ('John','Doe','555-2001','john@email.com','Tbilisi'),
    ('Anna','Smith','555-2002','anna@email.com','Kutaisi'),
    ('David','Brown','555-2003','david@email.com','Batumi'),
    ('Nino','Gelashvili','555-2004','nino@email.com','Rustavi'),
    ('Giorgi','Kapanadze','555-2005','giorgi@email.com','Gori'),
    ('Luka','Mchedlidze','555-2006','luka@email.com','Zugdidi')
) AS v(fn, ln, phone, email, address)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.customer c WHERE c.phone = v.phone
);

-- =====================================================
-- EMPLOYEE (6 rows)
-- =====================================================

INSERT INTO household_store.employee (first_name, last_name, position, salary, hire_date, phone)
SELECT * FROM (VALUES
    ('Mariam','K','Manager',3000,CURRENT_DATE - INTERVAL '1 year','555-3001'),
    ('Giorgi','L','Sales',1800,CURRENT_DATE - INTERVAL '8 months','555-3002'),
    ('Nika','T','Sales',1700,CURRENT_DATE - INTERVAL '6 months','555-3003'),
    ('Ana','D','Support',1500,CURRENT_DATE - INTERVAL '5 months','555-3004'),
    ('Saba','Q','Warehouse',1400,CURRENT_DATE - INTERVAL '4 months','555-3005'),
    ('Tamar','Z','Sales',1900,CURRENT_DATE - INTERVAL '3 months','555-3006')
) AS v(fn, ln, pos, salary, hire, phone)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.employee e WHERE e.phone = v.phone
);

-- =====================================================
-- PRODUCT (6 rows)
-- =====================================================

INSERT INTO household_store.product (product_name, brand, model, category_id, price, stock_quantity, warranty_months)
SELECT * FROM (
VALUES
('LG Fridge','LG','F100',
 (SELECT category_id FROM household_store.category WHERE category_name='Refrigerator'),
 1200,10,24),

('Samsung TV','Samsung','TV200',
 (SELECT category_id FROM household_store.category WHERE category_name='Television'),
 900,15,24),

('Bosch Washer','Bosch','W300',
 (SELECT category_id FROM household_store.category WHERE category_name='Washing Machine'),
 800,8,36),

('Panasonic AC','Panasonic','AC400',
 (SELECT category_id FROM household_store.category WHERE category_name='Air Conditioner'),
 1500,5,24),

('Philips Microwave','Philips','M500',
 (SELECT category_id FROM household_store.category WHERE category_name='Microwave'),
 300,20,12),

('Whirlpool Dishwasher','Whirlpool','D600',
 (SELECT category_id FROM household_store.category WHERE category_name='Dishwasher'),
 700,7,24)

) AS v(name, brand, model, cat_id, price, stock, warranty)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.product p WHERE p.product_name = v.name
);

-- =====================================================
-- ORDERS (6 rows, last 3 months)
-- =====================================================

INSERT INTO household_store.orders (customer_id, employee_id, order_date, order_status)
SELECT * FROM (
VALUES
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2001'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3002'),
 CURRENT_DATE - INTERVAL '10 days',
 'Delivered'
),
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2002'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3003'),
 CURRENT_DATE - INTERVAL '20 days',
 'Shipped'
),
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2003'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3004'),
 CURRENT_DATE - INTERVAL '1 month',
 'Pending'
),
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2004'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '2 months',
 'Delivered'
),
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2005'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3006'),
 CURRENT_DATE - INTERVAL '15 days',
 'Cancelled'
),
(
 (SELECT customer_id FROM household_store.customer WHERE phone='555-2006'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3002'),
 CURRENT_DATE - INTERVAL '5 days',
 'Pending'
)
) AS v(cust, emp, order_date, status)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.orders o 
    WHERE o.customer_id = v.cust 
    AND o.order_date = v.order_date
);

-- =====================================================
-- ORDER_ITEM (6+ rows)
-- =====================================================

INSERT INTO household_store.order_item (order_id, product_id, quantity, unit_price)
SELECT 
    o.order_id,
    p.product_id,
    2,
    p.price
FROM household_store.orders o
JOIN household_store.product p ON p.product_name IN ('LG Fridge','Samsung TV')
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.order_item oi 
    WHERE oi.order_id = o.order_id AND oi.product_id = p.product_id
)
LIMIT 6;

-- =====================================================
-- PROCUREMENT (6 rows)
-- =====================================================

INSERT INTO household_store.procurement (supplier_id, product_id, employee_id, procurement_date, quantity, cost_price)
SELECT * FROM (
VALUES
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1001'),
 (SELECT product_id FROM household_store.product WHERE product_name='LG Fridge'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '1 month',
 10,800
),
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1002'),
 (SELECT product_id FROM household_store.product WHERE product_name='Samsung TV'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '2 months',
 12,600
),
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1003'),
 (SELECT product_id FROM household_store.product WHERE product_name='Bosch Washer'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '3 weeks',
 5,500
),
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1004'),
 (SELECT product_id FROM household_store.product WHERE product_name='Whirlpool Dishwasher'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '2 weeks',
 6,450
),
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1005'),
 (SELECT product_id FROM household_store.product WHERE product_name='Panasonic AC'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '10 days',
 4,1000
),
(
 (SELECT supplier_id FROM household_store.supplier WHERE phone='555-1006'),
 (SELECT product_id FROM household_store.product WHERE product_name='Philips Microwave'),
 (SELECT employee_id FROM household_store.employee WHERE phone='555-3005'),
 CURRENT_DATE - INTERVAL '5 days',
 15,200
)
) AS v(sup, prod, emp, procurement_date, qty, cost)
WHERE NOT EXISTS (
    SELECT 1 FROM household_store.procurement pr
    WHERE pr.product_id = v.prod 
    AND pr.procurement_date = v.procurement_date
);


-- =====================================================
-- FUNCTION: update_product_column
-- Purpose:
-- Dynamically update a column in PRODUCT table
-- =====================================================
-- =====================================================
-- Recreate function in correct schema (rerunnable)
-- =====================================================
CREATE OR REPLACE FUNCTION household_store.update_product_column(
    p_product_id INT,
    p_column_name TEXT,
    p_new_value TEXT
)
RETURNS VOID AS
$$
DECLARE
    sql_query TEXT;
    column_type TEXT;
    rows_updated INT;
BEGIN
    -- Prevent PK update
    IF p_column_name = 'product_id' THEN
        RAISE EXCEPTION 'Updating primary key is not allowed';
    END IF;

    -- Get correct PostgreSQL column type
    SELECT format_type(a.atttypid, a.atttypmod)
    INTO column_type
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = 'product'
      AND n.nspname = 'household_store'
      AND a.attname = p_column_name
      AND a.attnum > 0;

    IF column_type IS NULL THEN
        RAISE EXCEPTION 'Column "%" does not exist', p_column_name;
    END IF;

    -- Build query with CORRECT cast
    sql_query := FORMAT(
        'UPDATE household_store.product 
         SET %I = $1::%s 
         WHERE product_id = $2',
        p_column_name,
        column_type
    );

    EXECUTE sql_query USING p_new_value, p_product_id;

    GET DIAGNOSTICS rows_updated = ROW_COUNT;

    RAISE NOTICE 'Rows updated: %', rows_updated;

END;
$$ LANGUAGE plpgsql;
/* Example Usage */
-- Update price
SET search_path TO household_store;

-- numeric column
SELECT update_product_column(1, 'stock_quantity', '50');

-- varchar column
SELECT update_product_column(1, 'product_name', 'Updated Name');

-- numeric decimal
SELECT update_product_column(1, 'price', '1999.99');


select * from household_store.product;

-- =====================================================
-- Function: create_order_transaction
-- Purpose:
-- Inserts a new transaction (order + order_item)
-- using natural keys (phone, product name)
-- =====================================================

-- =========================================================
-- FIXED FUNCTION (IMPORTANT FIX: STRONG DUPLICATE CHECK)
-- =========================================================

CREATE OR REPLACE FUNCTION household_store.create_order_transaction(
    p_customer_phone TEXT,
    p_employee_phone TEXT,
    p_product_name TEXT,
    p_quantity INT,
    p_order_status TEXT DEFAULT 'Pending'
)
RETURNS VOID AS
$$
DECLARE
    v_customer_id INT;
    v_employee_id INT;
    v_product_id INT;
    v_price NUMERIC(10,2);
    v_order_id INT;
    v_duplicate INT;
BEGIN

    SELECT customer_id INTO v_customer_id
    FROM household_store.customer WHERE phone = p_customer_phone;

    SELECT employee_id INTO v_employee_id
    FROM household_store.employee WHERE phone = p_employee_phone;

    SELECT product_id, price INTO v_product_id, v_price
    FROM household_store.product WHERE product_name = p_product_name;

    IF v_customer_id IS NULL OR v_employee_id IS NULL OR v_product_id IS NULL THEN
        RAISE EXCEPTION 'Invalid input data';
    END IF;

    --  FIXED: stronger duplicate prevention
    SELECT o.order_id INTO v_duplicate
    FROM household_store.orders o
    JOIN household_store.order_item oi ON o.order_id = oi.order_id
    WHERE o.customer_id = v_customer_id
      AND oi.product_id = v_product_id
      AND o.order_date = CURRENT_DATE
    LIMIT 1;

    IF v_duplicate IS NOT NULL THEN
        RAISE EXCEPTION 'Duplicate order detected (same customer + product + date)';
    END IF;

    INSERT INTO household_store.orders(customer_id, employee_id, order_date, order_status)
    VALUES (v_customer_id, v_employee_id, CURRENT_DATE, p_order_status)
    RETURNING order_id INTO v_order_id;

    INSERT INTO household_store.order_item(order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, v_product_id, p_quantity, v_price);

END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- View: recent_quarter_sales
-- Purpose:
-- Shows basic sales analytics for the most recent quarter
-- =====================================================

CREATE OR REPLACE VIEW household_store.recent_quarter_sales AS

SELECT
    c.first_name || ' ' || c.last_name AS customer_name,
    p.product_name,
    SUM(oi.quantity) AS total_quantity,
    SUM(oi.quantity * oi.unit_price) AS total_revenue,
    COUNT(o.order_id) AS total_orders

FROM household_store.orders o
JOIN household_store.order_item oi 
    ON o.order_id = oi.order_id
JOIN household_store.product p 
    ON oi.product_id = p.product_id
JOIN household_store.customer c 
    ON o.customer_id = c.customer_id

-- Filter for most recent quarter
WHERE DATE_TRUNC('quarter', o.order_date) = (
    SELECT DATE_TRUNC('quarter', MAX(order_date))
    FROM household_store.orders
)

GROUP BY 
    c.first_name, 
    c.last_name, 
    p.product_name;


-- =====================================================
-- ROLE: manager_readonly
-- Purpose:
-- Read-only access to all tables in household_store schema
-- Can log in but cannot modify data
-- =====================================================

-- =====================================================
-- Create a read-only role for manager
-- =====================================================

-- Create role with login capability
CREATE ROLE manager_readonly
LOGIN
PASSWORD 'StrongPassword123';  -- In real systems use a strong secure password


-- =====================================================
-- Grant access to schema
-- =====================================================

-- Allows the role to access objects inside the schema
GRANT USAGE ON SCHEMA household_store TO manager_readonly;


-- =====================================================
-- Grant read-only access to all tables
-- =====================================================

-- Allows SELECT queries only
GRANT SELECT ON ALL TABLES IN SCHEMA household_store TO manager_readonly;


-- =====================================================
-- Ensure future tables are also accessible
-- =====================================================

-- Automatically grant SELECT on new tables created later
ALTER DEFAULT PRIVILEGES IN SCHEMA household_store
GRANT SELECT ON TABLES TO manager_readonly;

SET ROLE manager_readonly;

SELECT * FROM household_store.product;


-- =====================================================
-- Optional: explicitly restrict write operations
-- =====================================================


-- Ensures the role cannot modify data
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA household_store
FROM manager_readonly;

UPDATE household_store.product
SET price = 100;
