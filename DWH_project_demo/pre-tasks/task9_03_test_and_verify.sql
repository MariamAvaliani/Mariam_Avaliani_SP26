-- =====================================================================
-- Introduction to DWH and ETL -- Task 9 (PL/pgSQL. Loading fact on 3NF / DM)
-- Script 3 of 3 : test / verification script.
-- Run this AFTER task9_01_fct_partition_ddl.sql and
-- task9_02_bl_cl_procedures.sql, against a BL_3NF/BL_DM already built
-- from Task 6, Task 7 and Task 8.
-- =====================================================================

-- =====================================================================
-- STEP 1 -- first load, on whatever data is currently in staging
-- =====================================================================
CALL bl_cl.prc_run_all_loads();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id;


-- =====================================================================
-- STEP 2 -- repeatability check: run again with nothing new in staging.
-- Every procedure should log rows_affected = 0.
-- =====================================================================
CALL bl_cl.prc_run_all_loads();

SELECT log_id, procedure_name, rows_affected, status
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 8;


-- =====================================================================
-- STEP 3 -- rolling window in action.
-- Load a new month's worth of rows into SA_RETAIL / SA_ONLINE (a later
-- transaction_date than anything loaded so far), re-run the 3NF
-- dimension refresh (CE_DATE / CE_PAYMENT / CE_DELIVERY pick up values
-- for the new rows the same way they always have, since Task 6), then
-- run the wrapper again.
-- Expect: PRC_MANAGE_FCT_PARTITIONS attaches the new month and detaches
-- the oldest one (message column shows exactly which); the fact
-- procedures log only the new month's row count, not the whole table.
-- =====================================================================
CALL bl_cl.prc_run_all_loads();

SELECT log_id, procedure_name, rows_affected, status, message
FROM bl_cl.mta_etl_log
ORDER BY log_id DESC
LIMIT 8;

-- Partitions currently attached:
SELECT c.relname, pg_get_expr(c.relpartbound, c.oid) AS bound
FROM pg_inherits i
JOIN pg_class c   ON c.oid = i.inhrelid
JOIN pg_class p   ON p.oid = i.inhparent
JOIN pg_namespace n ON n.oid = p.relnamespace
WHERE n.nspname = 'bl_dm' AND p.relname = 'fct_transactions_dd'
ORDER BY 1;

-- A detached month is not gone -- it is still a plain, queryable table:
-- SELECT COUNT(*) FROM bl_dm.fct_transactions_dd_<year>_<month>;


-- =====================================================================
-- STEP 4 -- no duplicates (Test group 1)
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


-- =====================================================================
-- STEP 5 -- every business key made it through (Test group 2)
-- =====================================================================

-- 5a. Every SA transaction_id exists on BL_3NF.
SELECT COUNT(*) AS missing_from_3nf
FROM (
    SELECT transaction_id FROM sa_retail.src_retail_sales
    UNION ALL
    SELECT transaction_id FROM sa_online.src_online_sales
) s
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_transaction ct WHERE ct.transaction_id = s.transaction_id
);

-- 5b. Every BL_3NF transaction_id is somewhere on BL_DM -- either in the
-- live partitioned fact table, or archived in a detached monthly
-- partition (rolled out on purpose, not lost). List every detached
-- partition table you have with OR NOT EXISTS clauses like the one
-- below (add one per detached table).
SELECT COUNT(*) AS missing_from_dm_including_archives
FROM bl_3nf.ce_transaction ct
WHERE ct.transaction_sk <> -1
  AND NOT EXISTS (
      SELECT 1 FROM bl_dm.fct_transactions_dd f WHERE f.transaction_src_id = ct.transaction_id::VARCHAR(50)
  )
  -- AND NOT EXISTS (SELECT 1 FROM bl_dm.fct_transactions_dd_2025_05 f WHERE f.transaction_src_id = ct.transaction_id::VARCHAR(50))
  ;


-- =====================================================================
-- STEP 6 -- sanity: row counts per layer
-- =====================================================================
SELECT 'bl_3nf.ce_transaction (all-time)' AS layer, COUNT(*) FROM bl_3nf.ce_transaction WHERE transaction_sk <> -1
UNION ALL
SELECT 'bl_dm.fct_transactions_dd (current window only)', COUNT(*) FROM bl_dm.fct_transactions_dd;

SELECT tableoid::regclass AS partition, COUNT(*)
FROM bl_dm.fct_transactions_dd
GROUP BY 1
ORDER BY 1;
