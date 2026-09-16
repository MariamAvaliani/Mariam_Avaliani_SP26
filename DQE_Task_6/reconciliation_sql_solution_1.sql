-- ============================================================================
-- Task 6 - Part 1: DWH Data Reconciliation with SQL (dblink)
-- Run this against the TARGET database: dwh_hw_db
-- (channel/table names come from 1_create_sources_postgres.sql and
--  2_create_landing_postgres.sql)
-- ============================================================================

-- 0. One-time setup ----------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS dblink;

-- 1. Reconciliation results table ---------------------------------------------
DROP TABLE IF EXISTS lnd.reconciliation_results;

CREATE TABLE lnd.reconciliation_results (
    table_name              VARCHAR(256),
    key_column               VARCHAR(256),
    src_id                    VARCHAR(256),
    trg_id                    VARCHAR(256),
    reconciliation_status     VARCHAR(256)
);

-- ============================================================================
-- 2. s1_channels  (worked example from the instructions, included for completeness)
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's1_channels' AS table_name,
        'channel_id' AS key_column,
        src.channel_id AS src_id,
        trg.channel_id AS trg_id,
        CASE
            WHEN src.channel_id IS NULL THEN 'Only in target'
            WHEN trg.channel_id IS NULL THEN 'Only in source'
            WHEN src.channel_name <> trg.channel_name THEN 'Mismatch in channel_name'
            WHEN src.channel_location <> trg.channellocation THEN 'Mismatch in channel_location'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s1_channels trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s1.s1_channels'
        ) AS src(channel_id VARCHAR(256), channel_name VARCHAR(256), channel_location VARCHAR(256))
    ) src ON src.channel_id = trg.channel_id
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 3. s1_products
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's1_products' AS table_name,
        'product_id' AS key_column,
        src.product_id AS src_id,
        trg.product_id AS trg_id,
        CASE
            WHEN src.product_id IS NULL THEN 'Only in target'
            WHEN trg.product_id IS NULL THEN 'Only in source'
            WHEN src.cost <> trg.cost THEN 'Mismatch in cost'
            WHEN src.product_name <> trg.product_name THEN 'Mismatch in product_name'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s1_products trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s1.s1_products'
        ) AS src(product_id VARCHAR(256), cost VARCHAR(256), product_name VARCHAR(256))
    ) src ON src.product_id = trg.product_id
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 4. s1_sales
-- NOTE: s1_sales has no single-column natural key, so a composite business
-- key is used instead (client_id + channel_id + product_id + sale_date).
-- If a client legitimately buys the same product through the same channel
-- twice on the same day, those rows share a key and can't be told apart --
-- worth keeping in mind if this table produces mismatches that look odd.
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's1_sales' AS table_name,
        'client_id+channel_id+product_id+sale_date' AS key_column,
        CONCAT_WS('|', src.client_id, src.channel_id, src.product_id, src.sale_date) AS src_id,
        CONCAT_WS('|', trg.client_id, trg.channel_id, trg.product_id, trg.sale_date) AS trg_id,
        CASE
            WHEN src.client_id IS NULL THEN 'Only in target'
            WHEN trg.client_id IS NULL THEN 'Only in source'
            WHEN src.units <> trg.units THEN 'Mismatch in units'
            WHEN src.purchase_date <> trg.purchase_date THEN 'Mismatch in purchase_date'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s1_sales trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s1.s1_sales'
        ) AS src(client_id VARCHAR(256), channel_id VARCHAR(256), sale_date VARCHAR(256),
                  units VARCHAR(256), product_id VARCHAR(256), purchase_date VARCHAR(256))
    ) src
      ON  src.client_id  = trg.client_id
      AND src.channel_id = trg.channel_id
      AND src.product_id = trg.product_id
      AND src.sale_date  = trg.sale_date
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 5. s2_channels
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's2_channels' AS table_name,
        'channel_id' AS key_column,
        src.channel_id AS src_id,
        trg.channel_id AS trg_id,
        CASE
            WHEN src.channel_id IS NULL THEN 'Only in target'
            WHEN trg.channel_id IS NULL THEN 'Only in source'
            WHEN src.channel_name <> trg.channel_name THEN 'Mismatch in channel_name'
            WHEN src.location_id <> trg.location_id THEN 'Mismatch in location_id'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s2_channels trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s2.s2_channels'
        ) AS src(channel_id VARCHAR(256), channel_name VARCHAR(256), location_id VARCHAR(256))
    ) src ON src.channel_id = trg.channel_id
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 6. s2_client_sales
-- NOTE: same composite-key caveat as s1_sales above.
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's2_client_sales' AS table_name,
        'client_id+channel_id+product_id+saled_at' AS key_column,
        CONCAT_WS('|', src.client_id, src.channel_id, src.product_id, src.saled_at) AS src_id,
        CONCAT_WS('|', trg.client_id, trg.channel_id, trg.product_id, trg.saled_at) AS trg_id,
        CASE
            WHEN src.client_id IS NULL THEN 'Only in target'
            WHEN trg.client_id IS NULL THEN 'Only in source'
            WHEN src.product_name <> trg.product_name THEN 'Mismatch in product_name'
            WHEN src.product_price <> trg.product_price THEN 'Mismatch in product_price'
            WHEN src.product_amount <> trg.product_amount THEN 'Mismatch in product_amount'
            WHEN src.sold_date <> trg.sold_date THEN 'Mismatch in sold_date'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s2_client_sales trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s2.s2_client_sales'
        ) AS src(client_id VARCHAR(256), channel_id VARCHAR(256), saled_at VARCHAR(256),
                  product_id VARCHAR(256), product_name VARCHAR(256), product_price VARCHAR(256),
                  product_amount VARCHAR(256), sold_date VARCHAR(256))
    ) src
      ON  src.client_id  = trg.client_id
      AND src.channel_id = trg.channel_id
      AND src.product_id = trg.product_id
      AND src.saled_at   = trg.saled_at
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 7. s2_clients
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's2_clients' AS table_name,
        'client_id' AS key_column,
        src.client_id AS src_id,
        trg.client_id AS trg_id,
        CASE
            WHEN src.client_id IS NULL THEN 'Only in target'
            WHEN trg.client_id IS NULL THEN 'Only in source'
            WHEN src.first_name <> trg.first_name THEN 'Mismatch in first_name'
            WHEN src.last_name <> trg.last_name THEN 'Mismatch in last_name'
            WHEN src.email <> trg.email THEN 'Mismatch in email'
            WHEN src.phone_code <> trg.phone_code THEN 'Mismatch in phone_code'
            WHEN src.phone_number <> trg.phone_number THEN 'Mismatch in phone_number'
            WHEN src.first_purchase <> trg.first_purchase THEN 'Mismatch in first_purchase'
            WHEN src.valid_from <> trg.valid_from THEN 'Mismatch in valid_from'
            WHEN src.valid_to <> trg.valid_to THEN 'Mismatch in valid_to'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s2_clients trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s2.s2_clients'
        ) AS src(client_id VARCHAR(256), first_name VARCHAR(256), last_name VARCHAR(256),
                  email VARCHAR(256), phone_code VARCHAR(256), phone_number VARCHAR(256),
                  first_purchase VARCHAR(256), valid_from VARCHAR(256), valid_to VARCHAR(256))
    ) src ON src.client_id = trg.client_id
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 8. s2_locations
-- ============================================================================
INSERT INTO lnd.reconciliation_results
SELECT table_name, key_column, src_id, trg_id, reconciliation_status
FROM (
    SELECT
        's2_locations' AS table_name,
        'location_id' AS key_column,
        src.location_id AS src_id,
        trg.location_id AS trg_id,
        CASE
            WHEN src.location_id IS NULL THEN 'Only in target'
            WHEN trg.location_id IS NULL THEN 'Only in source'
            WHEN src.location_name <> trg.location_name THEN 'Mismatch in location_name'
            ELSE 'Match'
        END AS reconciliation_status
    FROM lnd.lnd_s2_locations trg
    FULL OUTER JOIN (
        SELECT * FROM dblink(
            'dbname=dwh_src_hw_db user=postgres password=postgres host=localhost port=5433',
            'SELECT * FROM s2.s2_locations'
        ) AS src(location_id VARCHAR(256), location_name VARCHAR(256))
    ) src ON src.location_id = trg.location_id
) recon
WHERE reconciliation_status <> 'Match';

-- ============================================================================
-- 9. Review the results
-- ============================================================================
SELECT * FROM lnd.reconciliation_results
ORDER BY table_name, reconciliation_status;

-- Quick summary count per table/status - handy for a screenshot in the report
SELECT table_name, reconciliation_status, COUNT(*) AS issue_count
FROM lnd.reconciliation_results
GROUP BY table_name, reconciliation_status
ORDER BY table_name, reconciliation_status;
