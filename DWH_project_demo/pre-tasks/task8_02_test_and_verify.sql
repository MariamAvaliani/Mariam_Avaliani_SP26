-- =====================================================================
-- Introduction to DWH and ETL -- Task 8 (Loading BL_DM dimensions)
-- Test / verification script -- run this AFTER task8_01_bl_cl_load_procedures.sql
-- has been run once against your real BL_3NF (built from your actual
-- retail_500k.csv / online_500k.csv via Task 5 + Task 6).
-- =====================================================================


-- =====================================================================
-- STEP 1 -- first load
-- Run every dimension procedure once. On a fresh BL_DM you should see
-- non-zero rows_affected for all five.
-- =====================================================================
CALL bl_cl.prc_run_all_dim_loads();

SELECT log_id, procedure_name, start_ts, end_ts, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id;


-- =====================================================================
-- STEP 2 -- repeatability check
-- Run the exact same call again with nothing changed in BL_3NF.
-- Every procedure should now log rows_affected = 0.
-- =====================================================================
CALL bl_cl.prc_run_all_dim_loads();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 5;


-- =====================================================================
-- STEP 3 -- row counts on BL_DM (sanity check after loading)
-- =====================================================================
SELECT 'dim_products' AS dimension, COUNT(*) FROM bl_dm.dim_products
UNION ALL SELECT 'dim_stores', COUNT(*) FROM bl_dm.dim_stores
UNION ALL SELECT 'dim_payments', COUNT(*) FROM bl_dm.dim_payments
UNION ALL SELECT 'dim_deliveries', COUNT(*) FROM bl_dm.dim_deliveries
UNION ALL SELECT 'dim_customers_scd', COUNT(*) FROM bl_dm.dim_customers_scd;


-- =====================================================================
-- STEP 4 -- SCD2 test template
-- Pick a REAL customer_id from your own data (check
-- bl_3nf.ce_customer for one that only has one version so far), note
-- its current attributes, then follow the steps below.
-- =====================================================================

-- 4a. Pick a customer and look at their current state on both layers.
-- Replace <CUSTOMER_ID> with a real customer_id from your data.
SELECT customer_sk, customer_id, customer_segment, customer_type, customer_city,
       loyalty_score, age_group, start_dt, end_dt, is_active
FROM bl_3nf.ce_customer
WHERE customer_id = <CUSTOMER_ID>;

SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '<CUSTOMER_ID>';

-- 4b. Insert one new row into your staging table for this same
-- customer_id, with a changed tracked attribute (segment, type, city,
-- loyalty_score or age_group) and a later transaction_date than their
-- existing rows -- this plays the role of "an additional CSV file with
-- some changes". Adjust the column list/values below to match your own
-- staging table (sa_retail.src_retail_sales shown as an example).
--
-- INSERT INTO sa_retail.src_retail_sales (
--     customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
--     product_id, product_name, product_category, product_subcategory, product_brand, product_price,
--     transaction_id, transaction_date, quantity, unit_price, sales_value, discount, cost_price,
--     total_cost, profit, payment_method, payment_type, payment_status, currency,
--     transaction_channel, payment_risk_score, store_id, store_location, store_type,
--     region, store_size, country
-- ) VALUES (
--     <CUSTOMER_ID>, '<NEW_SEGMENT>', '<NEW_TYPE>', '<NEW_CITY>', <NEW_LOYALTY_SCORE>, '<NEW_AGE_GROUP>',
--     <PRODUCT_ID>, '<PRODUCT_NAME>', '<CATEGORY>', '<SUBCATEGORY>', '<BRAND>', <PRICE>,
--     <NEW_UNIQUE_TRANSACTION_ID>, '<A_LATER_DATE>', <QTY>, <UNIT_PRICE>, <SALES_VALUE>, <DISCOUNT>, <COST_PRICE>,
--     <TOTAL_COST>, <PROFIT>, '<PAYMENT_METHOD>', '<PAYMENT_TYPE>', '<PAYMENT_STATUS>', 'USD',
--     'Retail', <RISK_SCORE>, <STORE_ID>, '<STORE_LOCATION>', '<STORE_TYPE>',
--     '<REGION>', '<STORE_SIZE>', '<COUNTRY>'
-- );

-- 4c. Re-run your Task 6 script that loads BL_3NF (it is rerunnable --
-- it will pick up the new row, close the customer's old version and
-- open a new one). Then confirm on BL_3NF:
SELECT customer_sk, customer_id, customer_segment, customer_city, loyalty_score, start_dt, end_dt, is_active
FROM bl_3nf.ce_customer
WHERE customer_id = <CUSTOMER_ID>
ORDER BY customer_sk;

-- 4d. Propagate the change to BL_DM.
CALL bl_cl.prc_load_dim_customers_scd();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 1;

-- Expect rows_affected = 2 (1 row closed, 1 row opened).

SELECT customer_surr_id, customer_src_id, customer_segment, customer_city, customer_loyalty_score,
       start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '<CUSTOMER_ID>'
ORDER BY customer_surr_id;

-- 4e. Run it again with nothing new -- confirm it goes back to 0.
CALL bl_cl.prc_load_dim_customers_scd();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 1;


-- =====================================================================
-- STEP 5 -- confirm the grants (optional, just to double check)
-- =====================================================================
SELECT table_schema, string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'bl_cl_role' AND table_schema IN ('bl_3nf', 'bl_dm', 'bl_cl')
GROUP BY table_schema
ORDER BY table_schema;
