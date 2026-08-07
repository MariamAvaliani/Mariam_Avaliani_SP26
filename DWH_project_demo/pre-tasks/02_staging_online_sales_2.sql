-- =====================================================================
-- Introduction to DWH and ETL -- Task 5 (External tables on the staging layer)
-- Source system 2: ONLINE (e-commerce) sales
-- Target RDBMS: PostgreSQL
--
-- Layer:  SA_ONLINE  (Source Abstraction / staging schema for this dataset)
-- Objects created:
--   1. Schema sa_online
--   2. EXT_ONLINE_SALES  -- foreign table, zero-copy read of the raw CSV
--   3. SRC_ONLINE_SALES  -- real staging table: correct data types +
--                           duplicates removed + audit/source-triplet columns
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema (one schema per data set, per naming convention)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS sa_online;

-- ---------------------------------------------------------------------
-- 2. External (foreign) table -- reads the CSV file directly, no data
--    is copied into PostgreSQL yet. Requires the file_fdw extension.
--    NOTE: filename is set to C:/Users/Mariam/Desktop/sources/online_500k.csv.
--    This path must be readable by the machine running the PostgreSQL
--    server process itself (not just your psql/pgAdmin client) --
--    if the server runs on a different machine than this file lives on,
--    update the path accordingly, or copy the CSV to the server first.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS file_fdw;

CREATE SERVER IF NOT EXISTS online_file_server
    FOREIGN DATA WRAPPER file_fdw;

DROP FOREIGN TABLE IF EXISTS sa_online.ext_online_sales;

CREATE FOREIGN TABLE sa_online.ext_online_sales (
    customer_id            INTEGER,
    customer_segment       VARCHAR(50),
    customer_type          VARCHAR(50),
    customer_city          VARCHAR(100),
    loyalty_score          INTEGER,
    age_group              VARCHAR(30),
    product_id             INTEGER,
    product_name           VARCHAR(255),
    product_category       VARCHAR(100),
    product_subcategory    VARCHAR(100),
    product_brand          VARCHAR(100),
    product_price          NUMERIC,
    transaction_id         BIGINT,
    transaction_date       TEXT,        -- kept as raw text; see note below
    quantity               INTEGER,
    unit_price             NUMERIC,
    sales_value             NUMERIC,
    discount                 NUMERIC,
    cost_price                NUMERIC,
    shipping_cost              NUMERIC,
    total_cost                  NUMERIC,
    profit                       NUMERIC,
    payment_method                VARCHAR(50),
    payment_type                  VARCHAR(50),
    payment_status                 VARCHAR(50),
    currency                        VARCHAR(10),
    transaction_channel              VARCHAR(20),
    payment_risk_score                NUMERIC,
    delivery_type                      VARCHAR(50),
    delivery_status                     VARCHAR(50),
    delivery_time                        INTEGER,
    store_id                             INTEGER,
    store_location                        VARCHAR(255),
    store_type                             VARCHAR(50),
    country                                 VARCHAR(100)
)
SERVER online_file_server
OPTIONS (
    format 'csv',
    filename 'C:/Users/Mariam/Desktop/sources/online_500k.csv',
    header 'true',
    delimiter ','
);

-- transaction_date is intentionally staged as TEXT rather than DATE, for
-- the same reason as in the retail script (safer explicit TO_DATE cast
-- when loading SRC_, instead of relying on file_fdw's implicit DateStyle
-- parsing of ambiguous M/D/YYYY text).

-- Quick look at what the foreign table sees (screenshot this for the
-- "SELECT from ext_..." deliverable):
-- SELECT * FROM sa_online.ext_online_sales LIMIT 20;

-- ---------------------------------------------------------------------
-- 3. Duplicate check on the raw extract
-- ---------------------------------------------------------------------
-- SELECT transaction_id, COUNT(*)
-- FROM sa_online.ext_online_sales
-- GROUP BY transaction_id
-- HAVING COUNT(*) > 1
-- ORDER BY COUNT(*) DESC;

-- ---------------------------------------------------------------------
-- 4. Source (staging) table
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sa_online.src_online_sales;

CREATE TABLE sa_online.src_online_sales (
    customer_id            INTEGER      NOT NULL,
    customer_segment       VARCHAR(50)  NOT NULL,
    customer_type          VARCHAR(50)  NOT NULL,
    customer_city          VARCHAR(100) NOT NULL,
    loyalty_score          INTEGER      NOT NULL,
    age_group              VARCHAR(30)  NOT NULL,
    product_id             INTEGER      NOT NULL,
    product_name           VARCHAR(255) NOT NULL,
    product_category       VARCHAR(100) NOT NULL,
    product_subcategory    VARCHAR(100) NOT NULL,
    product_brand           VARCHAR(100) NOT NULL,
    product_price             NUMERIC(12,2) NOT NULL,
    transaction_id             BIGINT        NOT NULL,
    transaction_date           DATE          NOT NULL,
    quantity                    INTEGER       NOT NULL,
    unit_price                   NUMERIC(12,2) NOT NULL,
    sales_value                   NUMERIC(12,2) NOT NULL,
    discount                       NUMERIC(12,2) NOT NULL,
    cost_price                      NUMERIC(12,2) NOT NULL,
    shipping_cost                    NUMERIC(12,2) NOT NULL,
    total_cost                        NUMERIC(12,2) NOT NULL,
    profit                              NUMERIC(12,2) NOT NULL,
    payment_method                       VARCHAR(50)   NOT NULL,
    payment_type                          VARCHAR(50)   NOT NULL,
    payment_status                         VARCHAR(50)   NOT NULL,
    currency                                VARCHAR(10)   NOT NULL,
    transaction_channel                      VARCHAR(20)   NOT NULL,
    payment_risk_score                        NUMERIC(12,2) NOT NULL,
    delivery_type                              VARCHAR(50)   NOT NULL,
    delivery_status                             VARCHAR(50)   NOT NULL,
    delivery_time                                INTEGER       NOT NULL,
    store_id                                      INTEGER       NOT NULL,
    store_location                                 VARCHAR(255)  NOT NULL,
    store_type                                      VARCHAR(50)   NOT NULL,
    country                                          VARCHAR(100)  NOT NULL,
    -- technical / audit columns (Naming_Conventions.docx)
    insert_dt                                        DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system                                    VARCHAR(30)   NOT NULL DEFAULT 'SA_ONLINE',
    source_entity                                    VARCHAR(50)   NOT NULL DEFAULT 'EXT_ONLINE_SALES',
    CONSTRAINT pk_src_online_sales PRIMARY KEY (transaction_id)
);

-- ---------------------------------------------------------------------
-- 5. Load SRC_ from EXT_ with deduplication (same DISTINCT ON pattern
--    as the retail script).
-- ---------------------------------------------------------------------
INSERT INTO sa_online.src_online_sales (
    customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
    product_id, product_name, product_category, product_subcategory, product_brand, product_price,
    transaction_id, transaction_date, quantity, unit_price, sales_value, discount, cost_price,
    shipping_cost, total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, delivery_type, delivery_status, delivery_time,
    store_id, store_location, store_type, country
)
SELECT DISTINCT ON (transaction_id)
    customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
    product_id, product_name, product_category, product_subcategory, product_brand, product_price,
    transaction_id,
    CASE
        WHEN transaction_date ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN TO_DATE(transaction_date, 'YYYY-MM-DD')
        WHEN transaction_date ~ '^\d{1,2}/\d{1,2}/\d{4}$'  THEN TO_DATE(transaction_date, 'MM/DD/YYYY')
        ELSE NULL
    END AS transaction_date,
    quantity, unit_price, sales_value, discount, cost_price,
    shipping_cost, total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, delivery_type, delivery_status, delivery_time,
    store_id, store_location, store_type, country
FROM sa_online.ext_online_sales
ORDER BY transaction_id, ctid;

-- Verification (screenshot this for the "SELECT from src_..." deliverable):
-- SELECT * FROM sa_online.src_online_sales ORDER BY transaction_id LIMIT 20;

-- SELECT
--     (SELECT COUNT(*) FROM sa_online.ext_online_sales) AS ext_row_count,
--     (SELECT COUNT(*) FROM sa_online.src_online_sales) AS src_row_count;
