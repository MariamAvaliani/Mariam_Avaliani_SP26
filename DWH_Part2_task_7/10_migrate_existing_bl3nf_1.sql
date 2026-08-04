\timing on
-- =====================================================================
-- MIGRATION -- run this ONCE against your REAL database (the one that
-- already has BL_3NF populated from the Introduction to DWH and ETL
-- course's Task 6, task6_03_bl_3nf_load.sql).
--
-- Why this script exists: 02_bl_3nf_ddl.sql uses CREATE TABLE IF NOT
-- EXISTS everywhere, which is safe to re-run but means it will NOT
-- touch tables that already exist -- and on your real database,
-- CE_TRANSACTION / CE_PAYMENT / CE_DELIVERY / CE_DATE already exist
-- with the OLD (Revision 2) structure. Re-running 02_bl_3nf_ddl.sql
-- alone will silently do nothing to fix them. This script performs the
-- actual structural migration, in place, without losing your already
-- loaded data.
--
-- BACK UP FIRST (pg_dump the bl_3nf schema, or at minimum take a note
-- of your current row counts) -- this script drops a column and a
-- table. It is wrapped in a single transaction: if anything fails
-- partway, the whole migration rolls back and your database is
-- unchanged.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- STEP 1 (point g): fold CE_DATE into CE_TRANSACTION.transaction_date,
-- then drop CE_DATE. Add the new column and backfill it from the
-- existing date_sk link BEFORE dropping anything, so no information is
-- lost in between.
-- ---------------------------------------------------------------------
ALTER TABLE bl_3nf.ce_transaction ADD COLUMN IF NOT EXISTS transaction_date DATE;

UPDATE bl_3nf.ce_transaction t
SET transaction_date = d.full_date
FROM bl_3nf.ce_date d
WHERE d.date_sk = t.date_sk
  AND t.transaction_date IS NULL;

-- sanity check before going further -- every row must now have a
-- transaction_date; abort the whole migration if not (something in
-- your data doesn't match this script's assumptions)
DO $$
DECLARE v_missing INTEGER;
BEGIN
    SELECT count(*) INTO v_missing FROM bl_3nf.ce_transaction WHERE transaction_date IS NULL;
    IF v_missing > 0 THEN
        RAISE EXCEPTION 'STOP: % ce_transaction rows have no resolvable transaction_date -- inspect before continuing', v_missing;
    END IF;
END $$;

ALTER TABLE bl_3nf.ce_transaction ALTER COLUMN transaction_date SET NOT NULL;
ALTER TABLE bl_3nf.ce_transaction DROP CONSTRAINT IF EXISTS fk_ce_transaction2date;
ALTER TABLE bl_3nf.ce_transaction DROP COLUMN IF EXISTS date_sk;

DROP TABLE IF EXISTS bl_3nf.ce_date;
DROP SEQUENCE IF EXISTS bl_3nf.seq_ce_date;

-- ---------------------------------------------------------------------
-- STEP 2 (point e): composite source-triplet uniqueness on
-- CE_TRANSACTION / CE_PAYMENT / CE_DELIVERY. Check for collisions
-- FIRST -- if your real retail/online transaction_id ranges never
-- actually overlapped, this is a no-op rename of the constraint; if
-- they did overlap, the old bare-id NOT EXISTS load logic would have
-- silently under-loaded rows already, and you'll want to know that
-- before (not after) tightening the constraint.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_dupe_payment INTEGER; v_dupe_delivery INTEGER; v_dupe_txn INTEGER;
BEGIN
    SELECT count(*) INTO v_dupe_txn FROM (
        SELECT source_system, transaction_id FROM bl_3nf.ce_transaction
        GROUP BY source_system, transaction_id HAVING count(*) > 1
    ) x;
    SELECT count(*) INTO v_dupe_payment FROM (
        SELECT source_system, payment_id FROM bl_3nf.ce_payment
        GROUP BY source_system, payment_id HAVING count(*) > 1
    ) x;
    SELECT count(*) INTO v_dupe_delivery FROM (
        SELECT source_system, delivery_id FROM bl_3nf.ce_delivery
        GROUP BY source_system, delivery_id HAVING count(*) > 1
    ) x;
    IF v_dupe_txn > 0 OR v_dupe_payment > 0 OR v_dupe_delivery > 0 THEN
        RAISE EXCEPTION 'STOP: existing duplicates under (source_system, id) -- ce_transaction=%, ce_payment=%, ce_delivery=% -- resolve before adding the composite constraint', v_dupe_txn, v_dupe_payment, v_dupe_delivery;
    END IF;
END $$;

ALTER TABLE bl_3nf.ce_transaction DROP CONSTRAINT IF EXISTS uq_ce_transaction_id;
ALTER TABLE bl_3nf.ce_transaction ADD CONSTRAINT uq_ce_transaction_srctriplet UNIQUE (source_system, transaction_id);

ALTER TABLE bl_3nf.ce_payment DROP CONSTRAINT IF EXISTS uq_ce_payment_id;
ALTER TABLE bl_3nf.ce_payment ADD CONSTRAINT uq_ce_payment_srctriplet UNIQUE (source_system, payment_id);

ALTER TABLE bl_3nf.ce_delivery DROP CONSTRAINT IF EXISTS uq_ce_delivery_id;
ALTER TABLE bl_3nf.ce_delivery ADD CONSTRAINT uq_ce_delivery_srctriplet UNIQUE (source_system, delivery_id);

-- ---------------------------------------------------------------------
-- STEP 3: report what changed, still inside the transaction -- review
-- this output, then either COMMIT or ROLLBACK below.
-- ---------------------------------------------------------------------
SELECT 'ce_transaction' AS tbl, count(*) AS row_count, min(transaction_date) AS min_dt, max(transaction_date) AS max_dt FROM bl_3nf.ce_transaction
UNION ALL
SELECT 'ce_payment', count(*), NULL, NULL FROM bl_3nf.ce_payment
UNION ALL
SELECT 'ce_delivery', count(*), NULL, NULL FROM bl_3nf.ce_delivery;

-- Review the counts above against your notes from before running this
-- script. If they match (no rows lost) and everything above ran without
-- the RAISE EXCEPTION checks firing:
COMMIT;
-- If anything looked wrong, run ROLLBACK; instead of COMMIT; above and
-- nothing in this script will have taken effect.

-- ---------------------------------------------------------------------
-- STEP 4 (run separately, AFTER the migration above is committed):
-- CE_CUSTOMER's existing SCD2 rows were loaded under the OLD
-- CURRENT_DATE-based logic (point f) -- their start_dt values are
-- whatever date each load script happened to run on, not the real
-- effective date. This migration does NOT rewrite that existing
-- history (there is no way to recover the true historical effective
-- dates after the fact -- that information was never captured). Going
-- forward, every load through bl_cl.load_ce_customer() computes
-- correct effective dates for NEW changes; existing rows are simply
-- left as they are, with their limitation understood and documented
-- rather than silently left unstated.
-- ---------------------------------------------------------------------
