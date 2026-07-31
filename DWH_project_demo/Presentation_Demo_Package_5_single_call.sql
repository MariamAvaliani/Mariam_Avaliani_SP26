-- =====================================================================
-- PRESENTATION DEMO PACKAGE v5 -- run this live during the interview
-- =====================================================================
-- Same demonstration as Presentation_Demo_Package_4.sql (file-based 5%
-- increment -> staging -> BL_3NF -> BL_DM, SCD2 proof, restartability,
-- data-quality Test Groups 1 & 2), but the incremental staging load is
-- no longer two hand-run SQL statements (INSERT + UPDATE) -- it is now
-- BL_CL.PRC_LOAD_STAGING_INCREMENTAL, a real, logged, exception-handled
-- procedure (see task9_10_prc_load_staging_incremental.sql), called
-- together with the existing pipeline through ONE wrapper:
-- BL_CL.PRC_RUN_INCREMENTAL_DEMO.
--
-- PREREQUISITE: run task9_10_prc_load_staging_incremental.sql once
-- (creates both procedures) before using this script.
--
-- From STEP 1 (the one unavoidable, one-time OS-level action: appending
-- the new CSV rows to disk) onward, the entire load -- staging AND
-- BL_3NF/BL_DM -- is exactly ONE CALL. Everything else in this script is
-- verification (SELECTs), not loading.
--
-- Requirements this script demonstrates, end to end:
--   #2  SCD1 + SCD2 (STEP 4 shows one real customer's version change)
--   #3  Restartability (STEP 7 reruns the SAME single CALL used to load
--       the increment -- expect 0 everywhere, staging included)
--   #8  Incremental load strategy, genuinely file-based (STEP 1-2)
--   #9  Data-quality tests, group 1 (no dupes) + group 2 (SA->BL
--       representation), fact table + all five dimensions (STEP 5-6)
--
-- Timing target: STEP 2 must finish in under 5 minutes.
-- =====================================================================


-- =====================================================================
-- STEP 1 -- ONE-TIME, MANUAL, on your own machine (not SQL). Same as
-- Presentation_Demo_Package_4.sql's STEP 1 -- appends the new "5%" batch
-- to the SAME retail_500k.csv / online_500k.csv the foreign tables
-- already point to. Do this once, any time before the interview, or
-- live at the start of the demo (it takes a couple of seconds):
--
--   Get-Content "C:\Users\Mariam\Desktop\sources\retail_increment_5pct.csv" | Select-Object -Skip 1 | Add-Content "C:\Users\Mariam\Desktop\sources\retail_500k.csv"
--   Get-Content "C:\Users\Mariam\Desktop\sources\online_increment_5pct.csv" | Select-Object -Skip 1 | Add-Content "C:\Users\Mariam\Desktop\sources\online_500k.csv"
--
-- Everything from here on is SQL, run in pgAdmin like the rest of this
-- project.
-- =====================================================================


-- =====================================================================
-- STEP 0 -- BEFORE snapshot. Run this first so you have a clean "before"
-- to show against STEP 4's "after".
-- =====================================================================
SELECT 'sa_retail.src_retail_sales'  AS tbl, COUNT(*) FROM sa_retail.src_retail_sales
UNION ALL SELECT 'sa_online.src_online_sales', COUNT(*) FROM sa_online.src_online_sales
UNION ALL SELECT 'bl_3nf.ce_transaction (real)', COUNT(*) FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1
UNION ALL SELECT 'bl_dm.fct_transactions_dd', COUNT(*) FROM bl_dm.fct_transactions_dd
UNION ALL SELECT 'bl_dm.dim_customers_scd (active)', COUNT(*) FROM bl_dm.dim_customers_scd WHERE is_active = 'Y';

-- SCD2 test case, part 1 -- the "before" state. CustomerID 1000 is a
-- real customer, confirmed via a rehearsal run, whose resampled
-- transaction (in the increment file) carries genuinely different
-- attributes than their current active row (segment B -> C, type
-- Regular -> New, loyalty_score 15 -> 67; city/age_group unchanged).
-- (Customer 1464, used in earlier drafts of this demo, turned out NOT
-- to actually version on a real rehearsal run -- 1000 is verified.)
SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '1000'
ORDER BY customer_surr_id;
-- Expect one active (is_active='Y') row here, ending in '9999-12-31',
-- with customer_segment = 'B', customer_type = 'Regular', loyalty 15.

-- Optional: confirm the foreign tables now see the appended rows before
-- calling the procedure (sanity check only -- not required, the
-- procedure itself reads live from these).
SELECT 'sa_retail.ext_retail_sales' AS tbl, COUNT(*) FROM sa_retail.ext_retail_sales
UNION ALL SELECT 'sa_online.ext_online_sales', COUNT(*) FROM sa_online.ext_online_sales;
-- Expect ~526,316 for each (500,000 original + 26,316 new).


-- =====================================================================
-- STEP 2 -- THE ENTIRE LOAD. One CALL: incremental staging load (file-
-- based, restartable) + the full BL_3NF/BL_DM pipeline. Time it live.
-- =====================================================================
\timing on
CALL bl_cl.prc_run_incremental_demo();


-- =====================================================================
-- STEP 3 -- verify: per-procedure timing/row breakdown for this run.
-- =====================================================================
SELECT log_id, procedure_name, start_ts, end_ts,
       EXTRACT(EPOCH FROM (end_ts - start_ts)) AS duration_seconds,
       rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 12;


-- =====================================================================
-- STEP 4 -- AFTER snapshot. Compare against STEP 0.
-- =====================================================================
SELECT 'bl_3nf.ce_transaction (real)' AS tbl, COUNT(*) FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1
UNION ALL SELECT 'bl_dm.fct_transactions_dd', COUNT(*) FROM bl_dm.fct_transactions_dd
UNION ALL SELECT 'bl_dm.dim_customers_scd (active)', COUNT(*) FROM bl_dm.dim_customers_scd WHERE is_active = 'Y';

-- SCD2 test case, part 2 -- the "after" state, same customer as STEP 0.
-- Expect TWO rows now: the old one closed (is_active='N') and a new one
-- open (is_active='Y', end_dt = 9999-12-31) with the resampled attributes
-- (segment C, type New, city Dallas, loyalty 67, age group 26-35 --
-- verified via an actual rehearsal run, not an assumption).
SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '1000'
ORDER BY customer_surr_id;

-- All customers whose SCD2 version genuinely changed from this batch.
-- NOTE: NOT "WHERE start_dt = CURRENT_DATE" -- on a day when BL_DM was
-- also freshly rebuilt from scratch (task9_09), EVERY customer's very
-- first version also gets start_dt = CURRENT_DATE, which would count
-- the entire customer base, not just genuine SCD2 changes. Counting by
-- "2 or more versions exist" is correct regardless of same-day timing.
SELECT COUNT(*) AS customers_versioned
FROM (
    SELECT customer_src_id
    FROM bl_dm.dim_customers_scd
    GROUP BY customer_src_id
    HAVING COUNT(*) >= 2
) v;

-- Newly loaded fact rows (audit column, not business date).
SELECT transaction_src_id, event_dt, customer_surr_id, product_surr_id
FROM bl_dm.fct_transactions_dd
WHERE insert_dt = CURRENT_DATE
ORDER BY transaction_src_id
LIMIT 20;


-- =====================================================================
-- STEP 5 -- Test group 1: no duplicates. Fact table + all five
-- dimensions. Every query below must return ZERO rows.
-- =====================================================================
SELECT transaction_id, COUNT(*)
FROM bl_3nf.ce_transaction
WHERE transaction_sk <> -1
GROUP BY transaction_id
HAVING COUNT(*) > 1;

SELECT transaction_src_id, event_dt, COUNT(*)
FROM bl_dm.fct_transactions_dd
GROUP BY transaction_src_id, event_dt
HAVING COUNT(*) > 1;

SELECT source_system, source_entity, product_src_id, COUNT(*) FROM bl_dm.dim_products GROUP BY source_system, source_entity, product_src_id HAVING COUNT(*) > 1;
SELECT source_system, source_entity, store_src_id, COUNT(*) FROM bl_dm.dim_stores GROUP BY source_system, source_entity, store_src_id HAVING COUNT(*) > 1;
SELECT source_system, source_entity, payment_src_id, COUNT(*) FROM bl_dm.dim_payments GROUP BY source_system, source_entity, payment_src_id HAVING COUNT(*) > 1;
SELECT source_system, source_entity, delivery_src_id, COUNT(*) FROM bl_dm.dim_deliveries GROUP BY source_system, source_entity, delivery_src_id HAVING COUNT(*) > 1;

SELECT source_system, customer_src_id, COUNT(*) AS active_versions
FROM bl_dm.dim_customers_scd
WHERE is_active = 'Y'
GROUP BY source_system, customer_src_id
HAVING COUNT(*) > 1;

SELECT a.source_system, a.customer_src_id, a.customer_surr_id, a.start_dt, a.end_dt,
       b.customer_surr_id AS overlaps_with, b.start_dt AS other_start_dt, b.end_dt AS other_end_dt
FROM bl_dm.dim_customers_scd a
JOIN bl_dm.dim_customers_scd b
  ON a.source_system = b.source_system
 AND a.customer_src_id = b.customer_src_id
 AND a.customer_surr_id <> b.customer_surr_id
 AND a.start_dt <= b.end_dt
 AND b.start_dt <= a.end_dt;


-- =====================================================================
-- STEP 6 -- Test group 2: every SA record represented in the business
-- layer. Fact table + all five dimensions. Every query below must
-- return ZERO / 0.
-- =====================================================================
SELECT COUNT(*) AS missing_from_3nf
FROM (
    SELECT transaction_id FROM sa_retail.src_retail_sales
    UNION ALL
    SELECT transaction_id FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_transaction ct WHERE ct.transaction_id = s.transaction_id);

-- Scoped to the current rolling window -- see PRC_MANAGE_FCT_PARTITIONS;
-- a non-zero count from OUTSIDE the window is the rolling-window design
-- working correctly, not a bug. This query already restricts to the
-- window, so a non-zero result here means a real gap.
SELECT COUNT(*) AS missing_from_dm_within_window
FROM bl_3nf.ce_transaction ct
WHERE ct.transaction_sk <> -1
  AND ct.transaction_date >= (
        SELECT (GREATEST(
            (SELECT MAX(date_trunc('month', event_dt))::date FROM bl_dm.fct_transactions_dd),
            (SELECT MAX(date_trunc('month', transaction_date))::date FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1)
        ) - 2 * INTERVAL '1 month')::date
      )
  AND NOT EXISTS (SELECT 1 FROM bl_dm.fct_transactions_dd f WHERE f.transaction_src_id = ct.transaction_id::VARCHAR(50));

SELECT COUNT(*) AS missing_products
FROM (
    SELECT DISTINCT product_id::VARCHAR(50) AS product_id FROM sa_retail.src_retail_sales
    UNION
    SELECT DISTINCT product_id::VARCHAR(50) FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_products d WHERE d.product_src_id = s.product_id);

SELECT COUNT(*) AS missing_stores
FROM (
    SELECT DISTINCT store_id::VARCHAR(50) AS store_id FROM sa_retail.src_retail_sales
    UNION
    SELECT DISTINCT store_id::VARCHAR(50) FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_stores d WHERE d.store_src_id = s.store_id);

SELECT COUNT(*) AS missing_payments
FROM (
    SELECT DISTINCT transaction_id::VARCHAR(50) AS transaction_id FROM sa_retail.src_retail_sales
    UNION
    SELECT DISTINCT transaction_id::VARCHAR(50) FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_payments d WHERE d.payment_src_id = s.transaction_id);

SELECT COUNT(*) AS missing_deliveries
FROM (SELECT DISTINCT transaction_id::VARCHAR(50) AS transaction_id FROM sa_online.src_online_sales) s
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_deliveries d WHERE d.delivery_src_id = s.transaction_id);

SELECT COUNT(*) AS missing_active_customers
FROM (
    SELECT DISTINCT customer_id::VARCHAR(50) AS customer_id FROM sa_retail.src_retail_sales
    UNION
    SELECT DISTINCT customer_id::VARCHAR(50) FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (
    SELECT 1 FROM bl_dm.dim_customers_scd d
    WHERE d.customer_src_id = s.customer_id AND d.is_active = 'Y'
);


-- =====================================================================
-- STEP 7 -- restartability proof (requirement #3). Rerun the EXACT SAME
-- single CALL from STEP 2 -- nothing new is on disk, so this proves
-- BOTH the file-based staging load AND the full BL_3NF/BL_DM pipeline
-- are restartable together, not just the pipeline half.
-- =====================================================================
\timing on
CALL bl_cl.prc_run_incremental_demo();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 12;
-- Expect PRC_LOAD_STAGING_INCREMENTAL rows_affected = 0, and every
-- other procedure's rows_affected = 0 too.
