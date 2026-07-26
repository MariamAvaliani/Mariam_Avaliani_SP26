-- =====================================================================
-- Introduction to DWH and ETL -- Task 5 (External tables on the staging layer)
-- Source system 1: RETAIL (in-store) sales
-- Target RDBMS: PostgreSQL
--
-- Layer:  SA_RETAIL  (Source Abstraction / staging schema for this dataset)
-- Objects created:
--   1. Schema sa_retail
--   2. EXT_RETAIL_SALES  -- foreign table, zero-copy read of the raw CSV
--   3. SRC_RETAIL_SALES  -- real staging table: correct data types +
--                           duplicates removed + audit/source-triplet columns
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Schema (one schema per data set, per naming convention)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS sa_retail;

-- ---------------------------------------------------------------------
-- 2. External (foreign) table -- reads the CSV file directly, no data
--    is copied into PostgreSQL yet. Requires the file_fdw extension.
--    NOTE: filename is set to C:/Users/Mariam/Desktop/sources/retail_500k.csv.
--    This path must be readable by the machine running the PostgreSQL
--    server process itself (not just your psql/pgAdmin client) --
--    if the server runs on a different machine than this file lives on,
--    update the path accordingly, or copy the CSV to the server first.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS file_fdw;

CREATE SERVER IF NOT EXISTS retail_file_server
    FOREIGN DATA WRAPPER file_fdw;

DROP FOREIGN TABLE IF EXISTS sa_retail.ext_retail_sales;

CREATE FOREIGN TABLE sa_retail.ext_retail_sales (
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
    sales_value            NUMERIC,
    discount                NUMERIC,
    cost_price              NUMERIC,
    total_cost              NUMERIC,
    profit                  NUMERIC,
    payment_method          VARCHAR(50),
    payment_type            VARCHAR(50),
    payment_status          VARCHAR(50),
    currency                VARCHAR(10),
    transaction_channel     VARCHAR(20),
    payment_risk_score      NUMERIC,
    store_id                INTEGER,
    store_location          VARCHAR(255),
    store_type              VARCHAR(50),
    region                  VARCHAR(100),
    store_size               VARCHAR(50),
    country                  VARCHAR(100)
)
SERVER retail_file_server
OPTIONS (
    format 'csv',
    filename 'C:/Users/Mariam/Desktop/sources/retail_500k.csv',
    header 'true',
    delimiter ','
);

-- transaction_date is intentionally staged as TEXT rather than DATE.
-- file_fdw casts using the server's DateStyle at read time, which is
-- risky for ambiguous M/D/YYYY text; casting explicitly with TO_DATE()
-- when we load SRC_ is safer and keeps the raw value auditable if a
-- row ever fails to parse.

-- Quick look at what the foreign table sees (screenshot this for the
-- "SELECT from ext_..." deliverable):
-- SELECT * FROM sa_retail.ext_retail_sales LIMIT 20;

-- ---------------------------------------------------------------------
-- 3. Duplicate check on the raw extract (run before loading SRC_ to see
--    how many duplicate TRANSACTION_ID rows the file actually has)
-- ---------------------------------------------------------------------
-- SELECT transaction_id, COUNT(*)
-- FROM sa_retail.ext_retail_sales
-- GROUP BY transaction_id
-- HAVING COUNT(*) > 1
-- ORDER BY COUNT(*) DESC;

-- ---------------------------------------------------------------------
-- 4. Source (staging) table -- a real, physical table with correct data
--    types, deduplicated rows, and the technical columns required by
--    Naming_Conventions.docx (audit dates + source triplet).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sa_retail.src_retail_sales;

CREATE TABLE sa_retail.src_retail_sales (
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
    product_price            NUMERIC(12,2) NOT NULL,
    transaction_id            BIGINT        NOT NULL,
    transaction_date          DATE          NOT NULL,
    quantity                  INTEGER       NOT NULL,
    unit_price                NUMERIC(12,2) NOT NULL,
    sales_value                NUMERIC(12,2) NOT NULL,
    discount                    NUMERIC(12,2) NOT NULL,
    cost_price                  NUMERIC(12,2) NOT NULL,
    total_cost                  NUMERIC(12,2) NOT NULL,
    profit                      NUMERIC(12,2) NOT NULL,
    payment_method               VARCHAR(50)   NOT NULL,
    payment_type                 VARCHAR(50)   NOT NULL,
    payment_status                VARCHAR(50)   NOT NULL,
    currency                      VARCHAR(10)   NOT NULL,
    transaction_channel            VARCHAR(20)   NOT NULL,
    payment_risk_score              NUMERIC(12,2) NOT NULL,
    store_id                         INTEGER       NOT NULL,
    store_location                   VARCHAR(255)  NOT NULL,
    store_type                       VARCHAR(50)   NOT NULL,
    region                            VARCHAR(100)  NOT NULL,
    store_size                        VARCHAR(50)   NOT NULL,
    country                           VARCHAR(100)  NOT NULL,
    -- technical / audit columns (Naming_Conventions.docx)
    insert_dt                        DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system                    VARCHAR(30)   NOT NULL DEFAULT 'SA_RETAIL',
    source_entity                    VARCHAR(50)   NOT NULL DEFAULT 'EXT_RETAIL_SALES',
    CONSTRAINT pk_src_retail_sales PRIMARY KEY (transaction_id)
);

-- ---------------------------------------------------------------------
-- 5. Load SRC_ from EXT_ with deduplication.
--    DISTINCT ON (transaction_id) keeps exactly one row per
--    transaction_id -- the pattern recommended in the deduplication
--    material for picking a single "winning" version of a repeated key.
--    ORDER BY ... ctid gives a deterministic tie-break (first physical
--    occurrence in the file) when two duplicate rows are byte-identical.
-- ---------------------------------------------------------------------
INSERT INTO sa_retail.src_retail_sales (
    customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
    product_id, product_name, product_category, product_subcategory, product_brand, product_price,
    transaction_id, transaction_date, quantity, unit_price, sales_value, discount, cost_price,
    total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, store_id, store_location, store_type,
    region, store_size, country
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
    total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, store_id, store_location, store_type,
    region, store_size, country
FROM sa_retail.ext_retail_sales
ORDER BY transaction_id, ctid;

-- Verification (screenshot this for the "SELECT from src_..." deliverable):
-- SELECT * FROM sa_retail.src_retail_sales ORDER BY transaction_id LIMIT 20;

-- Row-count sanity check: ext_ count should be >= src_ count if any
-- duplicates were removed; the difference is the number of duplicate
-- rows eliminated.
-- SELECT
--     (SELECT COUNT(*) FROM sa_retail.ext_retail_sales) AS ext_row_count,
--     (SELECT COUNT(*) FROM sa_retail.src_retail_sales) AS src_row_count;
