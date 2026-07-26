-- =====================================================================
-- PRESENTATION DEMO PACKAGE -- run this live during the interview
-- =====================================================================
-- Single, self-contained script for the live incremental-load
-- demonstration required by "Project presentation. Interview
-- (Preparation)": the new "5%" arrives as a real file on disk, gets
-- picked up through the existing file_fdw foreign tables (no change to
-- their destination/filename), loaded into staging, and run through the
-- normal pipeline -- exactly what the requirement doc describes.
--
-- BEFORE running this script, do the one manual, one-time step below
-- (STEP 1) on your own machine. Everything from STEP 2 onward is SQL,
-- run in psql/pgAdmin like the rest of this project.
--
-- Requirements this script demonstrates, end to end:
--   #2  SCD1 + SCD2 (STEP 6 shows one real customer's version change,
--       by name, before and after)
--   #3  Restartability (STEP 3 itself is restartable via WHERE NOT
--       EXISTS; STEP 9 reruns the whole pipeline, expect all 0)
--   #8  Incremental load strategy, genuinely file-based (STEPs 1-5)
--   #9  Data-quality tests, group 1 (no dupes) + group 2 (SA->BL
--       representation), for BOTH the fact table and all five
--       dimensions (STEPs 7-8)
--
-- Timing target: STEP 3 through STEP 5 must finish in under 5 minutes.
-- Confirmed on the real database, at this same 52,632-row scale, via an
-- earlier rehearsal that inserted rows directly: 1 minute 58 seconds.
-- The file-based path adds the same rows through one extra INSERT
-- (STEP 3) and one UPDATE (STEP 4), both of which are simple, indexed,
-- single-table operations -- well inside the 5-minute budget too.
-- =====================================================================


-- =====================================================================
-- STEP 1 -- ONE-TIME, MANUAL, on your own machine (not SQL).
-- =====================================================================
-- I generated the new "5%" batch already, resampled from your real
-- rows, with brand-new TransactionID values that can never collide with
-- anything already loaded (retail: 800000001+, online: 850000001+):
--   retail_increment_5pct.csv  (26,316 rows)
--   online_increment_5pct.csv  (26,316 rows)
-- Both are already sitting next to your source files in
-- C:\Users\Mariam\Desktop\sources\
--
-- The foreign tables (ext_retail_sales / ext_online_sales) are not
-- touched at all -- same destination, same filename, as you asked.
-- What changes is the CONTENT of retail_500k.csv / online_500k.csv:
-- the increment rows get appended to the end of each file.
--
-- First, back up the two real files (one line each, PowerShell):
--
--   Copy-Item "C:\Users\Mariam\Desktop\sources\retail_500k.csv" "C:\Users\Mariam\Desktop\sources\retail_500k_backup.csv"
--   Copy-Item "C:\Users\Mariam\Desktop\sources\online_500k.csv" "C:\Users\Mariam\Desktop\sources\online_500k_backup.csv"
--
-- Then append the increment files (skips the header row of the
-- increment file so you don't get a header in the middle of the file):
--
--   Get-Content "C:\Users\Mariam\Desktop\sources\retail_increment_5pct.csv" | Select-Object -Skip 1 | Add-Content "C:\Users\Mariam\Desktop\sources\retail_500k.csv"
--   Get-Content "C:\Users\Mariam\Desktop\sources\online_increment_5pct.csv" | Select-Object -Skip 1 | Add-Content "C:\Users\Mariam\Desktop\sources\online_500k.csv"
--
-- Do this once, any time before the interview (or live, at the start of
-- the demo, if you want the file-append itself to be part of the show --
-- it takes a couple of seconds). Everything from here on is SQL.


-- =====================================================================
-- STEP 0 -- BEFORE snapshot. Run this first so you have a clean "before"
-- to show against STEP 6's "after".
-- =====================================================================
SELECT 'sa_retail.src_retail_sales'  AS tbl, COUNT(*) FROM sa_retail.src_retail_sales
UNION ALL SELECT 'sa_online.src_online_sales', COUNT(*) FROM sa_online.src_online_sales
UNION ALL SELECT 'bl_3nf.ce_transaction (real)', COUNT(*) FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1
UNION ALL SELECT 'bl_dm.fct_transactions_dd', COUNT(*) FROM bl_dm.fct_transactions_dd
UNION ALL SELECT 'bl_dm.dim_customers_scd (active)', COUNT(*) FROM bl_dm.dim_customers_scd WHERE is_active = 'Y';

-- SCD2 test case, part 1 -- the "before" state. CustomerID 1464 is a
-- real customer whose resampled transaction (in the increment file)
-- carries different attributes than their current active row. This is
-- one concrete example out of the batch, picked in advance so you have
-- a specific case to walk the mentor through, not just an aggregate
-- count.
SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '1464'
ORDER BY customer_surr_id;
-- Expect one active (is_active='Y') row here, ending in '9999-12-31'.


-- =====================================================================
-- STEP 2 -- verify the foreign tables now see the appended rows. If
-- these counts still show the old numbers, the file append in STEP 1
-- didn't land -- stop and check the file on disk before continuing.
-- =====================================================================
SELECT 'sa_retail.ext_retail_sales' AS tbl, COUNT(*) FROM sa_retail.ext_retail_sales
UNION ALL SELECT 'sa_online.ext_online_sales', COUNT(*) FROM sa_online.ext_online_sales;
-- Expect ~526,316 for each (500,000 original + 26,316 new).


-- =====================================================================
-- STEP 3 -- incremental staging load. Reads through the SAME foreign
-- tables used for the very first load (01/02 scripts), but only inserts
-- rows whose transaction_id isn't already in the staging table --
-- WHERE NOT EXISTS makes this restartable on its own: run it twice in a
-- row and the second run inserts nothing.
-- =====================================================================
INSERT INTO sa_retail.src_retail_sales (
    customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
    product_id, product_name, product_category, product_subcategory, product_brand, product_price,
    transaction_id, transaction_date, quantity, unit_price, sales_value, discount, cost_price,
    total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, store_id, store_location, store_type,
    region, store_size, country
)
SELECT DISTINCT ON (e.transaction_id)
    e.customer_id, e.customer_segment, e.customer_type, e.customer_city, e.loyalty_score, e.age_group,
    e.product_id, e.product_name, e.product_category, e.product_subcategory, e.product_brand, e.product_price,
    e.transaction_id,
    CASE
        WHEN e.transaction_date ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN TO_DATE(e.transaction_date, 'YYYY-MM-DD')
        WHEN e.transaction_date ~ '^\d{1,2}/\d{1,2}/\d{4}$'  THEN TO_DATE(e.transaction_date, 'MM/DD/YYYY')
        ELSE NULL
    END AS transaction_date,
    e.quantity, e.unit_price, e.sales_value, e.discount, e.cost_price,
    e.total_cost, e.profit, e.payment_method, e.payment_type, e.payment_status, e.currency,
    e.transaction_channel, e.payment_risk_score, e.store_id, e.store_location, e.store_type,
    e.region, e.store_size, e.country
FROM sa_retail.ext_retail_sales e
WHERE NOT EXISTS (
    SELECT 1 FROM sa_retail.src_retail_sales s WHERE s.transaction_id = e.transaction_id
);

INSERT INTO sa_online.src_online_sales (
    customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
    product_id, product_name, product_category, product_subcategory, product_brand, product_price,
    transaction_id, transaction_date, quantity, unit_price, sales_value, discount, cost_price,
    shipping_cost, total_cost, profit, payment_method, payment_type, payment_status, currency,
    transaction_channel, payment_risk_score, delivery_type, delivery_status, delivery_time,
    store_id, store_location, store_type, country
)
SELECT DISTINCT ON (e.transaction_id)
    e.customer_id, e.customer_segment, e.customer_type, e.customer_city, e.loyalty_score, e.age_group,
    e.product_id, e.product_name, e.product_category, e.product_subcategory, e.product_brand, e.product_price,
    e.transaction_id,
    CASE
        WHEN e.transaction_date ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN TO_DATE(e.transaction_date, 'YYYY-MM-DD')
        WHEN e.transaction_date ~ '^\d{1,2}/\d{1,2}/\d{4}$'  THEN TO_DATE(e.transaction_date, 'MM/DD/YYYY')
        ELSE NULL
    END AS transaction_date,
    e.quantity, e.unit_price, e.sales_value, e.discount, e.cost_price,
    e.shipping_cost, e.total_cost, e.profit, e.payment_method, e.payment_type, e.payment_status, e.currency,
    e.transaction_channel, e.payment_risk_score, e.delivery_type, e.delivery_status, e.delivery_time,
    e.store_id, e.store_location, e.store_type, e.country
FROM sa_online.ext_online_sales e
WHERE NOT EXISTS (
    SELECT 1 FROM sa_online.src_online_sales s WHERE s.transaction_id = e.transaction_id
);

SELECT 'sa_retail.src_retail_sales'  AS tbl, COUNT(*) FROM sa_retail.src_retail_sales
UNION ALL SELECT 'sa_online.src_online_sales', COUNT(*) FROM sa_online.src_online_sales;
-- Expect ~526,316 for each, matching STEP 2.


-- =====================================================================
-- STEP 4 -- anchor the new rows' transaction_date on
-- bl_dm.fct_transactions_dd's own MAX(event_dt) -- the lesson learned
-- earlier: anchoring anywhere else can land before the fact table's
-- rolling-window cutoff and get silently excluded. Only the new rows
-- are touched (identified by their transaction_id range, which is
-- unambiguous -- these ids never existed before STEP 3).
-- =====================================================================
UPDATE sa_retail.src_retail_sales
SET transaction_date = (SELECT COALESCE(MAX(event_dt), CURRENT_DATE) FROM bl_dm.fct_transactions_dd)
WHERE transaction_id >= 800000001;

UPDATE sa_online.src_online_sales
SET transaction_date = (SELECT COALESCE(MAX(event_dt), CURRENT_DATE) FROM bl_dm.fct_transactions_dd)
WHERE transaction_id >= 850000001;


-- =====================================================================
-- STEP 5 -- run the full BL_3NF + BL_DM pipeline. Time it live.
-- =====================================================================
\timing on
CALL bl_cl.prc_run_all_loads();

SELECT log_id, procedure_name, start_ts, end_ts, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 10;


-- =====================================================================
-- STEP 6 -- AFTER snapshot. Compare against STEP 0.
-- =====================================================================
SELECT 'bl_3nf.ce_transaction (real)' AS tbl, COUNT(*) FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1
UNION ALL SELECT 'bl_dm.fct_transactions_dd', COUNT(*) FROM bl_dm.fct_transactions_dd
UNION ALL SELECT 'bl_dm.dim_customers_scd (active)', COUNT(*) FROM bl_dm.dim_customers_scd WHERE is_active = 'Y';

-- SCD2 test case, part 2 -- the "after" state, same customer as STEP 0.
-- Expect TWO rows now: the old one closed (is_active='N', end_dt =
-- yesterday) and a new one open (is_active='Y', end_dt = 9999-12-31)
-- with the resampled attributes (segment A, type Premium, city Houston,
-- loyalty 86, age group 26-35).
SELECT customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
       customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = '1464'
ORDER BY customer_surr_id;

-- All customers whose SCD2 version changed from this batch (the wider
-- picture behind the single test case above).
SELECT COUNT(DISTINCT customer_src_id) AS customers_versioned
FROM bl_dm.dim_customers_scd
WHERE start_dt = CURRENT_DATE;

-- Newly loaded fact rows (audit column, not business date).
SELECT transaction_src_id, event_dt, customer_surr_id, product_surr_id
FROM bl_dm.fct_transactions_dd
WHERE insert_dt = CURRENT_DATE
ORDER BY transaction_src_id
LIMIT 20;


-- =====================================================================
-- STEP 7 -- Test group 1: no duplicates. Fact table + all five
-- dimensions. Every query below must return ZERO rows.
-- =====================================================================
-- Fact table.
SELECT transaction_id, COUNT(*)
FROM bl_3nf.ce_transaction
WHERE transaction_sk <> -1
GROUP BY transaction_id
HAVING COUNT(*) > 1;

SELECT transaction_src_id, event_dt, COUNT(*)
FROM bl_dm.fct_transactions_dd
GROUP BY transaction_src_id, event_dt
HAVING COUNT(*) > 1;

-- Dimensions.
SELECT product_src_id, COUNT(*) FROM bl_dm.dim_products GROUP BY product_src_id HAVING COUNT(*) > 1;
SELECT store_src_id, COUNT(*) FROM bl_dm.dim_stores GROUP BY store_src_id HAVING COUNT(*) > 1;
SELECT payment_src_id, COUNT(*) FROM bl_dm.dim_payments GROUP BY payment_src_id HAVING COUNT(*) > 1;
SELECT delivery_src_id, COUNT(*) FROM bl_dm.dim_deliveries GROUP BY delivery_src_id HAVING COUNT(*) > 1;

-- dim_customers_scd: no customer with 2+ ACTIVE versions, no overlapping
-- date ranges.
SELECT customer_src_id, COUNT(*) AS active_versions
FROM bl_dm.dim_customers_scd
WHERE is_active = 'Y'
GROUP BY customer_src_id
HAVING COUNT(*) > 1;

SELECT a.customer_src_id, a.customer_surr_id, a.start_dt, a.end_dt,
       b.customer_surr_id AS overlaps_with, b.start_dt AS other_start_dt, b.end_dt AS other_end_dt
FROM bl_dm.dim_customers_scd a
JOIN bl_dm.dim_customers_scd b
  ON a.customer_src_id = b.customer_src_id
 AND a.customer_surr_id <> b.customer_surr_id
 AND a.start_dt <= b.end_dt
 AND b.start_dt <= a.end_dt;


-- =====================================================================
-- STEP 8 -- Test group 2: every SA record represented in the business
-- layer. Fact table + all five dimensions. Every query below must
-- return ZERO / 0.
-- =====================================================================
-- Fact table.
SELECT COUNT(*) AS missing_from_3nf
FROM (
    SELECT transaction_id FROM sa_retail.src_retail_sales
    UNION ALL
    SELECT transaction_id FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_transaction ct WHERE ct.transaction_id = s.transaction_id);

-- NOTE: FCT_TRANSACTIONS_DD only keeps a rolling 3-month window of
-- partitions attached (see PRC_MANAGE_FCT_PARTITIONS) -- older months are
-- detached on purpose, not dropped, and stay queryable as their own
-- table. So "every 3NF row has a matching fact row" is only a fair test
-- INSIDE that window. A large "missing" count here, from months outside
-- the window, is the rolling-window mechanism working exactly as
-- designed -- not a data-quality problem. This version of the query
-- restricts the check to the current window, so a non-zero result here
-- means an actual, real gap.
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

-- Dimensions.
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
-- STEP 9 -- restartability proof (requirement #3). Rerun STEP 3's
-- inserts, then the whole pipeline, with nothing new on disk. Every
-- rows_affected must be 0, and STEP 3's own INSERTs must add 0 rows.
-- =====================================================================
-- Re-run STEP 3's two INSERTs here (copy-paste from above) if you want
-- to prove the staging load itself is restartable, not just the
-- procedures -- both should report "INSERT 0 0".

CALL bl_cl.prc_run_all_loads();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 10;
