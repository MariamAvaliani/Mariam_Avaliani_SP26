-- Task 8 test / verification script -- run this after
-- task8_01_bl_cl_load_procedures.sql, against my real BL_3NF.

-- 1) first load -- run every dimension procedure once, log should show
-- non-zero rows_affected for all five
CALL bl_cl.prc_run_all_dim_loads();

SELECT log_id, procedure_name, start_ts, end_ts, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id;


-- 2) repeatability -- run it again with nothing changed, expect
-- rows_affected = 0 for all five this time
CALL bl_cl.prc_run_all_dim_loads();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 5;


-- 3) row counts on BL_DM, sanity check
SELECT 'dim_products' AS dimension, COUNT(*) FROM bl_dm.dim_products
UNION ALL SELECT 'dim_stores', COUNT(*) FROM bl_dm.dim_stores
UNION ALL SELECT 'dim_payments', COUNT(*) FROM bl_dm.dim_payments
UNION ALL SELECT 'dim_deliveries', COUNT(*) FROM bl_dm.dim_deliveries
UNION ALL SELECT 'dim_customers_scd', COUNT(*) FROM bl_dm.dim_customers_scd;


-- 4) SCD2 test -- pick a customer_id, look at current state on both
-- layers, add a changed version to staging, reload, and confirm the
-- old row got closed and a new one opened. Replace <CUSTOMER_ID> below.

SELECT customer_sk, customer_id, customer_segment, customer_type, customer_city,
       loyalty_score, age_group, start_dt, end_dt, is_active
FROM bl_3nf.ce_customer
WHERE customer_id = <CUSTOMER_ID>;

SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '<CUSTOMER_ID>';

-- insert one new row into staging for the same customer_id, with a
-- changed tracked attribute and a later transaction_date (adjust
-- columns/values to match your own staging table)
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

-- re-run the BL_3NF load, then check it picked up the change:
SELECT customer_sk, customer_id, customer_segment, customer_city, loyalty_score, start_dt, end_dt, is_active
FROM bl_3nf.ce_customer
WHERE customer_id = <CUSTOMER_ID>
ORDER BY customer_sk;

-- propagate to BL_DM
CALL bl_cl.prc_load_dim_customers_scd();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 1;

-- expect rows_affected = 2 (1 closed, 1 opened)

SELECT customer_surr_id, customer_src_id, customer_segment, customer_city, customer_loyalty_score,
       start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '<CUSTOMER_ID>'
ORDER BY customer_surr_id;

-- run again with nothing new, expect 0
CALL bl_cl.prc_load_dim_customers_scd();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 1;


-- 5) confirm the grants
SELECT table_schema, string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'bl_cl_role' AND table_schema IN ('bl_3nf', 'bl_dm', 'bl_cl')
GROUP BY table_schema
ORDER BY table_schema;
