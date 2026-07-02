-- =====================================================================
-- Introduction to DWH and ETL -- Task 6 (3NF layer loading)
-- Script 2 of 3 : default ("n. a.") row for every BL_3NF table except
-- the fact table.
-- Target RDBMS: PostgreSQL
-- REVISION 2 -- default rows added for the new hierarchy tables
-- (CE_CATEGORY, CE_SUBCATEGORY, CE_COUNTRY, CE_REGION); CE_DATE default
-- row trimmed to match its new (smaller) column set.
--
-- Run ONCE, immediately after script 1 (task6_01_bl_3nf_ddl.sql).
-- Per PostgreSQL_DB_for_DWH_and_ETL_Additional_materials -- Default
-- value.pptx, every dimension gets exactly one default row so that a
-- fact row whose natural key cannot be matched to any dimension row
-- (e.g. a retail transaction, which has no delivery leg) can still be
-- loaded, by pointing its FK at -1 instead of being left NULL or
-- dropped. CE_TRANSACTION (the fact table) is deliberately excluded --
-- default rows are for dimensions only.
--
-- Load order matters: parent entities in each hierarchy must get their
-- default row before their children (CE_CATEGORY before CE_SUBCATEGORY,
-- CE_COUNTRY before CE_REGION), since the children's default rows carry
-- an FK pointing at the parent's default row (-1).
--
-- Rerunnable: every INSERT is guarded by "WHERE NOT EXISTS", so running
-- this script again after the default rows already exist is a no-op
-- and raises no errors / creates no duplicates.
--
-- Default-value rules used below (from the pptx):
--   numeric columns            -> -1
--   text columns                -> 'n. a.'
--   source_id                   -> 'n. a.'
--   source_system/source_entity -> 'MANUAL'
--   start/insert/update/event dates -> 1900-01-01
--   end date                    -> 9999-12-31
--   boolean / status flags      -> the "active" value, since the row
--                                   must be usable in joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- CE_CATEGORY (parent of CE_SUBCATEGORY)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_category (
    category_sk, category_name, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, 'n. a.', TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_category WHERE category_sk = -1);

-- ---------------------------------------------------------------------
-- CE_SUBCATEGORY (FK -> CE_CATEGORY)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_subcategory (
    subcategory_sk, subcategory_name, category_sk, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_subcategory WHERE subcategory_sk = -1);

-- ---------------------------------------------------------------------
-- CE_PRODUCT (FK -> CE_SUBCATEGORY)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_product (
    product_sk, product_id, product_name, subcategory_sk, product_brand, product_price,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, -1, 'n. a.', -1, 'n. a.', -1,
       TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_product WHERE product_sk = -1);

-- ---------------------------------------------------------------------
-- CE_COUNTRY (parent of CE_REGION)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_country (
    country_sk, country_name, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, 'n. a.', TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_country WHERE country_sk = -1);

-- ---------------------------------------------------------------------
-- CE_REGION (FK -> CE_COUNTRY)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_region (
    region_sk, region_name, country_sk, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_region WHERE region_sk = -1);

-- ---------------------------------------------------------------------
-- CE_STORE (FK -> CE_REGION)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_store (
    store_sk, store_id, store_location, store_type, region_sk,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, -1, 'n. a.', 'n. a.', -1,
       TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_store WHERE store_sk = -1);

-- ---------------------------------------------------------------------
-- CE_CUSTOMER
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_customer (
    customer_sk, customer_id, customer_segment, customer_type, customer_city,
    loyalty_score, age_group, start_dt, end_dt, is_active,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, -1, 'n. a.', 'n. a.', 'n. a.',
       -1, 'n. a.', DATE '1900-01-01', DATE '9999-12-31', 'Y',
       TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_customer WHERE customer_sk = -1);

-- ---------------------------------------------------------------------
-- CE_PAYMENT
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_payment (
    payment_sk, payment_id, payment_method, payment_status, payment_risk_score,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, -1, 'n. a.', 'n. a.', -1,
       TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_payment WHERE payment_sk = -1);

-- ---------------------------------------------------------------------
-- CE_DELIVERY
-- delivery_id is VARCHAR (per the 3NF diagram), so its default value is
-- the text default 'n. a.' rather than the numeric default -1.
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_delivery (
    delivery_sk, delivery_id, delivery_type, delivery_status, fulfillment_time,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', -1,
       TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_delivery WHERE delivery_sk = -1);

-- ---------------------------------------------------------------------
-- CE_DATE (trimmed -- SK + natural key only)
-- ---------------------------------------------------------------------
INSERT INTO bl_3nf.ce_date (
    date_sk, full_date, insert_dt
)
SELECT -1, DATE '1900-01-01', TIMESTAMP '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_date WHERE date_sk = -1);

COMMIT;
