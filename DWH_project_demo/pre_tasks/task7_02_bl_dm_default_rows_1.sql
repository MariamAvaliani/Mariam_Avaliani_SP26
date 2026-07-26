-- =====================================================================
-- Introduction to DWH and ETL -- Task 7 (Dimensional Model creation)
-- Script 2 of 2 : default ("-1" / "n. a.") row for every BL_DM dimension.
-- Target RDBMS: PostgreSQL
--
-- Run ONCE, immediately after script 1 (task7_01_bl_dm_ddl.sql).
-- Per PostgreSQL_DB_for_DWH_and_ETL_Additional_materials -- Default
-- value.pptx (the same rule already applied at the BL_3NF layer in
-- Task 6), every dimension gets exactly one default row so that a fact
-- row whose natural key cannot be matched to any dimension row (e.g. a
-- retail transaction, which has no delivery leg) can still be loaded, by
-- pointing its FK at -1 instead of being left NULL or dropped.
-- FCT_TRANSACTIONS_DD (the fact table) is deliberately excluded --
-- default rows are for dimensions only. There are no cross-dimension FKs
-- on the BL_DM layer (each dimension is fully flattened), so the five
-- inserts below are independent of one another and can run in any order.
--
-- Rerunnable: every INSERT is guarded by "WHERE NOT EXISTS", so running
-- this script again after the default rows already exist is a no-op and
-- raises no errors / creates no duplicates.
--
-- Default-value rules used below (same convention as Task 6):
--   numeric columns              -> -1
--   text columns                  -> 'n. a.'
--   src_id                        -> 'n. a.'
--   source_system/source_entity   -> 'MANUAL'
--   start/insert/update dates     -> 1900-01-01
--   end date                      -> 9999-12-31
--   boolean / status flags        -> the "active" value, since the row
--                                     must be usable in joins
-- =====================================================================

-- ---------------------------------------------------------------------
-- DIM_CUSTOMERS_SCD
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_customers_scd (
    customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
    customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active,
    insert_dt, update_dt, source_system, source_entity
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', 'n. a.',
       -1, 'n. a.', DATE '1900-01-01', DATE '9999-12-31', 'Y',
       DATE '1900-01-01', DATE '1900-01-01', 'MANUAL', 'MANUAL'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_customers_scd WHERE customer_surr_id = -1);

-- ---------------------------------------------------------------------
-- DIM_PRODUCTS
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_products (
    product_surr_id, product_src_id, product_name, product_category, product_subcategory,
    product_brand, product_price_amt, insert_dt, update_dt, source_system, source_entity
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', 'n. a.',
       'n. a.', -1, DATE '1900-01-01', DATE '1900-01-01', 'MANUAL', 'MANUAL'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_products WHERE product_surr_id = -1);

-- ---------------------------------------------------------------------
-- DIM_STORES
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_stores (
    store_surr_id, store_src_id, store_location, store_type, store_region, store_country,
    insert_dt, update_dt, source_system, source_entity
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', 'n. a.', 'n. a.',
       DATE '1900-01-01', DATE '1900-01-01', 'MANUAL', 'MANUAL'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_stores WHERE store_surr_id = -1);

-- ---------------------------------------------------------------------
-- DIM_PAYMENTS
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_payments (
    payment_surr_id, payment_src_id, payment_method, payment_status, payment_risk_score,
    insert_dt, update_dt, source_system, source_entity
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', -1,
       DATE '1900-01-01', DATE '1900-01-01', 'MANUAL', 'MANUAL'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_payments WHERE payment_surr_id = -1);

-- ---------------------------------------------------------------------
-- DIM_DELIVERIES
-- Every retail (in-store) transaction is linked to this row, since the
-- retail channel has no delivery leg (see Chapter 3, Step 6).
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_deliveries (
    delivery_surr_id, delivery_src_id, delivery_type, delivery_status,
    delivery_fulfillment_time_num, insert_dt, update_dt, source_system, source_entity
)
SELECT -1, 'n. a.', 'n. a.', 'n. a.',
       -1, DATE '1900-01-01', DATE '1900-01-01', 'MANUAL', 'MANUAL'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_deliveries WHERE delivery_surr_id = -1);

-- ---------------------------------------------------------------------
-- DIM_DATES
-- Included here as well (guarded, so it is a no-op if
-- DIM_DATES_create_and_populate.sql already inserted this row in Task 4)
-- purely so this script alone fully satisfies "default rows in every
-- BL_DM dimension" even if run in isolation.
-- ---------------------------------------------------------------------
INSERT INTO bl_dm.dim_dates (
    date_surr_id, full_date, day_of_month_num, day_of_week_num, day_of_week_desc,
    weekend_flag, month_num, month_desc, quarter_num, quarter_desc, year_num, insert_dt
)
SELECT -1, DATE '1900-01-01', 1, 1, 'n.a.',
       'N', 1, 'n.a.', 1, 'NA', 1900, DATE '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_dates WHERE date_surr_id = -1);

COMMIT;
