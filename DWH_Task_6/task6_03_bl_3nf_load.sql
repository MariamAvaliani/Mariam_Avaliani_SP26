-- =====================================================================
-- Introduction to DWH and ETL -- Task 6 (3NF layer loading)
-- Script 3 of 3 : regular incremental load, BL_3NF from the staging
-- (SA_RETAIL / SA_ONLINE) layer built in Task 5.
-- Target RDBMS: PostgreSQL
-- REVISION 2 -- updated to address mentor feedback on Task 3:
--   1. Product hierarchy load added (CE_CATEGORY -> CE_SUBCATEGORY,
--      then CE_PRODUCT resolves subcategory_sk instead of storing
--      category/subcategory text).
--   2. Location hierarchy load added (CE_COUNTRY -> CE_REGION, then
--      CE_STORE resolves region_sk instead of storing region/country
--      text). Online has no REGION column at all, so its rows are
--      COALESCE'd to the 'n. a.' region under the correct country --
--      another concrete use of the NULLs-handling / default-row pattern.
--   3. CE_DATE load trimmed -- no more day/month/year computation.
--   4. CE_TRANSACTION.customer_sk is now resolved "as of" the
--      transaction date (transaction_date BETWEEN cu.start_dt AND
--      cu.end_dt) instead of "whichever version is active today" --
--      see the design note on CE_CUSTOMER in script 1.
--
-- Run this script every time new data lands in staging (e.g. daily).
-- Every INSERT is rerunnable: dimensions use NOT EXISTS against the
-- natural key so re-running the script never creates duplicate rows,
-- and CE_CUSTOMER uses SCD2 change detection so an unchanged customer
-- is neither re-closed nor re-inserted on a second run with the same
-- source data.
--
-- Load order matters: parents before children within each hierarchy,
-- and all dimensions before the fact table, because the fact load
-- looks up every dimension's surrogate key.
-- =====================================================================


-- =====================================================================
-- 1. CE_CATEGORY  (parent of CE_SUBCATEGORY)
-- =====================================================================
INSERT INTO bl_3nf.ce_category (
    category_sk, category_name, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_category'),
    dedup.category_name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
    dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (category_name)
        category_name, source_system, source_entity, source_id
    FROM (
        SELECT product_category AS category_name,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               product_category AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT product_category AS category_name,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               product_category AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY category_name, src_priority
) dedup
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_category c WHERE c.category_name = dedup.category_name
);


-- =====================================================================
-- 2. CE_SUBCATEGORY  (FK -> CE_CATEGORY)
-- Natural key is composite (subcategory_name, category_sk): the same
-- subcategory name is allowed to exist under two different categories.
-- =====================================================================
INSERT INTO bl_3nf.ce_subcategory (
    subcategory_sk, subcategory_name, category_sk, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_subcategory'),
    dedup.subcategory_name, cat.category_sk, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
    dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (subcategory_name, category_name)
        subcategory_name, category_name, source_system, source_entity, source_id
    FROM (
        SELECT product_subcategory AS subcategory_name, product_category AS category_name,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               product_subcategory AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT product_subcategory AS subcategory_name, product_category AS category_name,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               product_subcategory AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY subcategory_name, category_name, src_priority
) dedup
JOIN bl_3nf.ce_category cat ON cat.category_name = dedup.category_name
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_subcategory s
    WHERE s.subcategory_name = dedup.subcategory_name AND s.category_sk = cat.category_sk
);


-- =====================================================================
-- 3. CE_PRODUCT  (FK -> CE_SUBCATEGORY)
-- =====================================================================
INSERT INTO bl_3nf.ce_product (
    product_sk, product_id, product_name, subcategory_sk, product_brand, product_price,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_product'),
    dedup.product_id, dedup.product_name, sub.subcategory_sk, dedup.product_brand, dedup.product_price,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (product_id)
        product_id, product_name, product_category, product_subcategory, product_brand, product_price,
        source_system, source_entity, source_id
    FROM (
        SELECT product_id, product_name, product_category, product_subcategory, product_brand, product_price,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               product_id::VARCHAR(100) AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT product_id, product_name, product_category, product_subcategory, product_brand, product_price,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               product_id::VARCHAR(100) AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY product_id, src_priority
) dedup
JOIN bl_3nf.ce_category cat    ON cat.category_name = dedup.product_category
JOIN bl_3nf.ce_subcategory sub ON sub.subcategory_name = dedup.product_subcategory AND sub.category_sk = cat.category_sk
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_product p WHERE p.product_id = dedup.product_id
);


-- =====================================================================
-- 4. CE_COUNTRY  (parent of CE_REGION)
-- =====================================================================
INSERT INTO bl_3nf.ce_country (
    country_sk, country_name, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_country'),
    dedup.country_name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
    dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (country_name)
        country_name, source_system, source_entity, source_id
    FROM (
        SELECT country AS country_name,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               country AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT country AS country_name,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               country AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY country_name, src_priority
) dedup
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_country c WHERE c.country_name = dedup.country_name
);


-- =====================================================================
-- 5. CE_REGION  (FK -> CE_COUNTRY)
-- The Online source has no REGION column at all -- every online row is
-- mapped to the 'n. a.' region under its (real) country. NULLs handling
-- (COALESCE) applies to the Retail branch too, in case a region value
-- is blank for an individual row.
-- =====================================================================
INSERT INTO bl_3nf.ce_region (
    region_sk, region_name, country_sk, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_region'),
    dedup.region_name, ctry.country_sk, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
    dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (region_name, country_name)
        region_name, country_name, source_system, source_entity, source_id
    FROM (
        SELECT COALESCE(region, 'n. a.') AS region_name, country AS country_name,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               COALESCE(region, 'n. a.') AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT 'n. a.' AS region_name, country AS country_name,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               'n. a.' AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY region_name, country_name, src_priority
) dedup
JOIN bl_3nf.ce_country ctry ON ctry.country_name = dedup.country_name
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_region r
    WHERE r.region_name = dedup.region_name AND r.country_sk = ctry.country_sk
);


-- =====================================================================
-- 6. CE_STORE  (FK -> CE_REGION)
-- =====================================================================
INSERT INTO bl_3nf.ce_store (
    store_sk, store_id, store_location, store_type, region_sk,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_store'),
    dedup.store_id, dedup.store_location, dedup.store_type, reg.region_sk,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (store_id)
        store_id, store_location, store_type, region_name, country_name,
        source_system, source_entity, source_id
    FROM (
        SELECT store_id, store_location, store_type,
               COALESCE(region, 'n. a.') AS region_name, country AS country_name,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               store_id::VARCHAR(100) AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT store_id, store_location, store_type,
               'n. a.' AS region_name, country AS country_name,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               store_id::VARCHAR(100) AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY store_id, src_priority
) dedup
JOIN bl_3nf.ce_country ctry ON ctry.country_name = dedup.country_name
JOIN bl_3nf.ce_region  reg  ON reg.region_name = dedup.region_name AND reg.country_sk = ctry.country_sk
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_store st WHERE st.store_id = dedup.store_id
);


-- =====================================================================
-- 7. CE_CUSTOMER (SCD Type 2)
-- Tracked attributes: customer_segment, customer_type, customer_city,
-- loyalty_score, age_group. Unchanged by this revision -- the key /
-- versioning fix from the mentor's comment is in how CE_TRANSACTION
-- *reads* this table (step 10 below), not in how it's maintained here.
-- =====================================================================

-- One attribute snapshot per customer_id: the row from that customer's
-- most recent transaction (across both source systems), so change
-- detection reflects the customer's latest known state rather than an
-- arbitrary row. Ties on the same transaction_date fall back to retail
-- as the system of record (src_priority), then row order (ctid).
WITH stg_customer AS (
    SELECT DISTINCT ON (customer_id)
        customer_id, customer_segment, customer_type, customer_city,
        loyalty_score, age_group, source_system, source_entity, source_id
    FROM (
        SELECT customer_id, customer_segment, customer_type, customer_city,
               loyalty_score, age_group, transaction_date,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               customer_id::VARCHAR(100) AS source_id, 1 AS src_priority, ctid
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT customer_id, customer_segment, customer_type, customer_city,
               loyalty_score, age_group, transaction_date,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               customer_id::VARCHAR(100) AS source_id, 2 AS src_priority, ctid
        FROM sa_online.src_online_sales
    ) u
    ORDER BY customer_id, transaction_date DESC, src_priority, ctid
)
-- 7a. Close the active version of every customer whose tracked
--     attributes changed since the last load.
UPDATE bl_3nf.ce_customer c
SET end_dt    = (CURRENT_DATE - INTERVAL '1 day')::DATE,
    is_active = 'N',
    update_dt = CURRENT_TIMESTAMP
FROM stg_customer s
WHERE c.customer_id = s.customer_id
  AND c.is_active = 'Y'
  AND c.customer_sk <> -1                       -- never touch the default row
  AND (    c.customer_segment IS DISTINCT FROM s.customer_segment
        OR c.customer_type    IS DISTINCT FROM s.customer_type
        OR c.customer_city    IS DISTINCT FROM s.customer_city
        OR c.loyalty_score    IS DISTINCT FROM s.loyalty_score
        OR c.age_group        IS DISTINCT FROM s.age_group);

-- 7b. Insert a new active version for brand-new customers, and for
--     customers whose previous active row was just closed in step 7a
--     (NULLs handled with COALESCE in case a staged attribute is
--     missing/blank for a given source row).
WITH stg_customer AS (
    SELECT DISTINCT ON (customer_id)
        customer_id, customer_segment, customer_type, customer_city,
        loyalty_score, age_group, source_system, source_entity, source_id
    FROM (
        SELECT customer_id, customer_segment, customer_type, customer_city,
               loyalty_score, age_group, transaction_date,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               customer_id::VARCHAR(100) AS source_id, 1 AS src_priority, ctid
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT customer_id, customer_segment, customer_type, customer_city,
               loyalty_score, age_group, transaction_date,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               customer_id::VARCHAR(100) AS source_id, 2 AS src_priority, ctid
        FROM sa_online.src_online_sales
    ) u
    ORDER BY customer_id, transaction_date DESC, src_priority, ctid
)
INSERT INTO bl_3nf.ce_customer (
    customer_sk, customer_id, customer_segment, customer_type, customer_city,
    loyalty_score, age_group, start_dt, end_dt, is_active,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_customer'),
    s.customer_id,
    COALESCE(s.customer_segment, 'n. a.'),
    COALESCE(s.customer_type, 'n. a.'),
    COALESCE(s.customer_city, 'n. a.'),
    COALESCE(s.loyalty_score, -1),
    COALESCE(s.age_group, 'n. a.'),
    CURRENT_DATE,
    DATE '9999-12-31',
    'Y',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    s.source_system,
    s.source_entity,
    s.source_id
FROM stg_customer s
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_customer c
    WHERE c.customer_id = s.customer_id
      AND c.is_active = 'Y'
);


-- =====================================================================
-- 8. CE_PAYMENT
-- ASSUMPTION: neither source system has a dedicated payment business
-- key. Every transaction has exactly one payment event, so payment_id
-- is derived from transaction_id (see design note in script 1).
-- =====================================================================
INSERT INTO bl_3nf.ce_payment (
    payment_sk, payment_id, payment_method, payment_status, payment_risk_score,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_payment'),
    dedup.payment_id, dedup.payment_method, dedup.payment_status, dedup.payment_risk_score,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (payment_id)
        payment_id, payment_method, payment_status, payment_risk_score,
        source_system, source_entity, source_id
    FROM (
        SELECT transaction_id AS payment_id, payment_method, payment_status,
               ROUND(payment_risk_score)::INTEGER AS payment_risk_score,
               'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
               transaction_id::VARCHAR(100) AS source_id, 1 AS src_priority
        FROM sa_retail.src_retail_sales
        UNION ALL
        SELECT transaction_id AS payment_id, payment_method, payment_status,
               ROUND(payment_risk_score)::INTEGER AS payment_risk_score,
               'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
               transaction_id::VARCHAR(100) AS source_id, 2 AS src_priority
        FROM sa_online.src_online_sales
    ) u
    ORDER BY payment_id, src_priority
) dedup
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_payment pm WHERE pm.payment_id = dedup.payment_id
);


-- =====================================================================
-- 9. CE_DELIVERY
-- Online (e-commerce) transactions only -- the retail channel has no
-- delivery leg, so retail transactions are simply never inserted here.
-- They will pick up the -1 default row in the fact load below, exactly
-- the pattern shown in the "Usage of Default Row" example.
-- =====================================================================
INSERT INTO bl_3nf.ce_delivery (
    delivery_sk, delivery_id, delivery_type, delivery_status, fulfillment_time,
    insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_delivery'),
    dedup.delivery_id, dedup.delivery_type, dedup.delivery_status, dedup.fulfillment_time,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
FROM (
    SELECT DISTINCT ON (delivery_id)
        transaction_id::VARCHAR(50) AS delivery_id,
        delivery_type, delivery_status, delivery_time AS fulfillment_time,
        'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity,
        transaction_id::VARCHAR(100) AS source_id
    FROM sa_online.src_online_sales
) dedup
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_delivery d WHERE d.delivery_id = dedup.delivery_id
);


-- =====================================================================
-- 10. CE_DATE
-- Trimmed per mentor feedback: only the surrogate key and the natural
-- key (FULL_DATE) are stored. Populated with the distinct transaction
-- dates actually present in staging.
-- =====================================================================
INSERT INTO bl_3nf.ce_date (
    date_sk, full_date, insert_dt
)
SELECT
    nextval('bl_3nf.seq_ce_date'),
    dedup.full_date,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT transaction_date AS full_date FROM sa_retail.src_retail_sales
    UNION
    SELECT DISTINCT transaction_date AS full_date FROM sa_online.src_online_sales
) dedup
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_date d WHERE d.full_date = dedup.full_date
);


-- =====================================================================
-- 11. CE_TRANSACTION (fact table)
-- Grain: one row per transaction_id, from either source system.
-- Every dimension lookup is a LEFT JOIN, and every surrogate key is
-- wrapped in COALESCE(..., -1) -- so a transaction that cannot be
-- matched to a dimension row (most commonly: a retail transaction
-- looking for a delivery it doesn't have) still loads cleanly and
-- points at that dimension's default row instead of being lost or
-- given a NULL FK. shipping_cost is COALESCE'd to 0 for the same
-- reason: it simply does not exist for retail sales.
--
-- CUSTOMER_SK is resolved "as of" the transaction date -- the version
-- of the customer that was active WHEN THE TRANSACTION HAPPENED, not
-- simply whichever version is active today. This is the fix for the
-- mentor's comment on Task 3: without the date-range condition, a
-- transaction loaded (or re-loaded) after a later customer change
-- would silently point at the customer's *current* attributes instead
-- of the ones that were true at the time of the sale.
-- =====================================================================
INSERT INTO bl_3nf.ce_transaction (
    transaction_sk, transaction_id, customer_sk, product_sk, store_sk, payment_sk, delivery_sk, date_sk,
    quantity, unit_price, sales_value, discount, cost_price, shipping_cost, total_cost, profit,
    transaction_channel, insert_dt, update_dt, source_system, source_entity, source_id
)
SELECT
    nextval('bl_3nf.seq_ce_transaction'),
    t.transaction_id,
    COALESCE(cu.customer_sk, -1),
    COALESCE(pr.product_sk, -1),
    COALESCE(st.store_sk, -1),
    COALESCE(pm.payment_sk, -1),
    COALESCE(dl.delivery_sk, -1),
    COALESCE(dt.date_sk, -1),
    t.quantity,
    t.unit_price,
    t.sales_value,
    t.discount,
    t.cost_price,
    COALESCE(t.shipping_cost, 0),
    t.total_cost,
    t.profit,
    t.transaction_channel,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    t.source_system,
    t.source_entity,
    t.transaction_id::VARCHAR(100)
FROM (
    SELECT transaction_id, customer_id, product_id, store_id, transaction_date, quantity, unit_price,
           sales_value, discount, cost_price, NULL::NUMERIC(12,2) AS shipping_cost, total_cost, profit,
           transaction_channel, 'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity
    FROM sa_retail.src_retail_sales
    UNION ALL
    SELECT transaction_id, customer_id, product_id, store_id, transaction_date, quantity, unit_price,
           sales_value, discount, cost_price, shipping_cost, total_cost, profit,
           transaction_channel, 'SA_ONLINE' AS source_system, 'SRC_ONLINE_SALES' AS source_entity
    FROM sa_online.src_online_sales
) t
LEFT JOIN bl_3nf.ce_customer cu ON cu.customer_id = t.customer_id
                                AND t.transaction_date BETWEEN cu.start_dt AND cu.end_dt
LEFT JOIN bl_3nf.ce_product  pr ON pr.product_id  = t.product_id
LEFT JOIN bl_3nf.ce_store    st ON st.store_id    = t.store_id
LEFT JOIN bl_3nf.ce_payment  pm ON pm.payment_id  = t.transaction_id
LEFT JOIN bl_3nf.ce_delivery dl ON dl.delivery_id = t.transaction_id::VARCHAR(50)
LEFT JOIN bl_3nf.ce_date     dt ON dt.full_date   = t.transaction_date
WHERE NOT EXISTS (
    SELECT 1 FROM bl_3nf.ce_transaction ct WHERE ct.transaction_id = t.transaction_id
);

COMMIT;


-- =====================================================================
-- Verification queries (run manually, not part of the load)
-- =====================================================================
-- Row counts per table:
-- SELECT 'ce_category' tbl, COUNT(*) FROM bl_3nf.ce_category
-- UNION ALL SELECT 'ce_subcategory', COUNT(*) FROM bl_3nf.ce_subcategory
-- UNION ALL SELECT 'ce_product', COUNT(*) FROM bl_3nf.ce_product
-- UNION ALL SELECT 'ce_country', COUNT(*) FROM bl_3nf.ce_country
-- UNION ALL SELECT 'ce_region', COUNT(*) FROM bl_3nf.ce_region
-- UNION ALL SELECT 'ce_store', COUNT(*) FROM bl_3nf.ce_store
-- UNION ALL SELECT 'ce_customer', COUNT(*) FROM bl_3nf.ce_customer
-- UNION ALL SELECT 'ce_payment', COUNT(*) FROM bl_3nf.ce_payment
-- UNION ALL SELECT 'ce_delivery', COUNT(*) FROM bl_3nf.ce_delivery
-- UNION ALL SELECT 'ce_date', COUNT(*) FROM bl_3nf.ce_date
-- UNION ALL SELECT 'ce_transaction', COUNT(*) FROM bl_3nf.ce_transaction;

-- How many retail (in-store) transactions correctly fell back to the
-- CE_DELIVERY default row (-1), because retail has no delivery leg:
-- SELECT COUNT(*) FROM bl_3nf.ce_transaction WHERE delivery_sk = -1;

-- Re-run this whole script a second time with no new staging data and
-- confirm the row counts above are unchanged -- that is the
-- "rerunnable / no duplicates" check.

-- SCD2 sanity check -- every customer_id must have exactly one active
-- (is_active = 'Y') row, default row excluded:
-- SELECT customer_id, COUNT(*)
-- FROM bl_3nf.ce_customer
-- WHERE is_active = 'Y' AND customer_sk <> -1
-- GROUP BY customer_id
-- HAVING COUNT(*) > 1;

-- SCD2 "as-of" join check -- pick a customer with more than one version
-- and confirm their older transactions still point at the customer_sk
-- that was active on the transaction's own date, not the newest one:
-- SELECT t.transaction_id, t.transaction_date, t.customer_sk,
--        c.customer_city, c.start_dt, c.end_dt, c.is_active
-- FROM bl_3nf.ce_transaction t
-- JOIN bl_3nf.ce_customer c ON c.customer_sk = t.customer_sk
-- WHERE t.customer_sk IN (
--     SELECT customer_sk FROM bl_3nf.ce_customer
--     WHERE customer_id IN (SELECT customer_id FROM bl_3nf.ce_customer GROUP BY customer_id HAVING COUNT(*) > 1)
-- )
-- ORDER BY t.transaction_date;

-- Hierarchy check -- every product resolves all the way up to a real
-- (non-default) category, for products with a real (non-default)
-- subcategory:
-- SELECT p.product_id, p.subcategory_sk, s.subcategory_name, s.category_sk, c.category_name
-- FROM bl_3nf.ce_product p
-- JOIN bl_3nf.ce_subcategory s ON s.subcategory_sk = p.subcategory_sk
-- JOIN bl_3nf.ce_category c ON c.category_sk = s.category_sk
-- WHERE p.product_sk <> -1
-- LIMIT 20;
