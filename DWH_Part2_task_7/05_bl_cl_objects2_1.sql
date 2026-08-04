\timing on
-- =======================================================================
-- 7. CE_CUSTOMER (SCD Type 2). Point (f) fix: start_dt/end_dt are now
--    driven by the actual source transaction_date at which the new
--    attribute combination was first observed ("effective date"), not
--    CURRENT_DATE / the ETL run date. This matters for batch/backfill
--    loads: under the old logic every version looked like it started on
--    the day the script happened to run, regardless of when the change
--    really occurred in the source data.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_customer()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows_closed  INTEGER := 0;
    v_rows_new     INTEGER := 0;
    v_status       VARCHAR := 'SUCCESS';
    v_msg          VARCHAR := 'OK';
BEGIN
    BEGIN
        CREATE TEMP TABLE tmp_stg_raw ON COMMIT DROP AS
        SELECT customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
               transaction_date, source_system, source_entity, source_id, src_priority, ctid_rn
        FROM (
            SELECT customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
                   transaction_date, 'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                   customer_id::VARCHAR(100) AS source_id, 1 AS src_priority, row_number() OVER () AS ctid_rn
            FROM sa_retail.src_retail_sales
            UNION ALL
            SELECT customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
                   transaction_date, 'SA_ONLINE', 'SRC_ONLINE_SALES',
                   customer_id::VARCHAR(100), 2, row_number() OVER ()
            FROM sa_online.src_online_sales
        ) u;

        CREATE TEMP TABLE tmp_stg_latest ON COMMIT DROP AS
        SELECT DISTINCT ON (customer_id)
            customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
            source_system, source_entity, source_id
        FROM tmp_stg_raw
        ORDER BY customer_id, transaction_date DESC, src_priority, ctid_rn;

        -- effective date of the *current* attribute combination: the
        -- earliest transaction_date in this batch at which it was
        -- already true (point f)
        CREATE TEMP TABLE tmp_stg_effective ON COMMIT DROP AS
        SELECT l.customer_id, MIN(r.transaction_date) AS effective_dt
        FROM tmp_stg_latest l
        JOIN tmp_stg_raw r
          ON r.customer_id = l.customer_id
         AND r.customer_segment IS NOT DISTINCT FROM l.customer_segment
         AND r.customer_type    IS NOT DISTINCT FROM l.customer_type
         AND r.customer_city    IS NOT DISTINCT FROM l.customer_city
         AND r.loyalty_score    IS NOT DISTINCT FROM l.loyalty_score
         AND r.age_group        IS NOT DISTINCT FROM l.age_group
        GROUP BY l.customer_id;

        -- 7a. close the active version of every customer whose tracked
        -- attributes changed, end_dt = effective_dt - 1 day (not
        -- CURRENT_DATE - 1)
        UPDATE bl_3nf.ce_customer c
        SET end_dt    = (e.effective_dt - INTERVAL '1 day')::DATE,
            is_active = 'N',
            update_dt = CURRENT_TIMESTAMP
        FROM tmp_stg_latest s
        JOIN tmp_stg_effective e ON e.customer_id = s.customer_id
        WHERE c.customer_id = s.customer_id
          AND c.is_active = 'Y'
          AND c.customer_sk <> -1
          AND e.effective_dt > c.start_dt
          AND (    c.customer_segment IS DISTINCT FROM s.customer_segment
                OR c.customer_type    IS DISTINCT FROM s.customer_type
                OR c.customer_city    IS DISTINCT FROM s.customer_city
                OR c.loyalty_score    IS DISTINCT FROM s.loyalty_score
                OR c.age_group        IS DISTINCT FROM s.age_group);
        GET DIAGNOSTICS v_rows_closed = ROW_COUNT;

        -- 7b. insert a new active version for brand-new customers and for
        -- customers just closed above; start_dt = effective_dt (point f)
        INSERT INTO bl_3nf.ce_customer (
            customer_sk, customer_id, customer_segment, customer_type, customer_city,
            loyalty_score, age_group, start_dt, end_dt, is_active,
            insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT
            nextval('bl_3nf.seq_ce_customer'), s.customer_id,
            COALESCE(s.customer_segment, 'n. a.'), COALESCE(s.customer_type, 'n. a.'),
            COALESCE(s.customer_city, 'n. a.'), COALESCE(s.loyalty_score, -1), COALESCE(s.age_group, 'n. a.'),
            e.effective_dt, DATE '9999-12-31', 'Y',
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, s.source_system, s.source_entity, s.source_id
        FROM tmp_stg_latest s
        JOIN tmp_stg_effective e ON e.customer_id = s.customer_id
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_customer c WHERE c.customer_id = s.customer_id AND c.is_active = 'Y'
        );
        GET DIAGNOSTICS v_rows_new = ROW_COUNT;

        v_msg := format('closed=%s, new_versions=%s', v_rows_closed, v_rows_new);
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows_closed := 0; v_rows_new := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_customer', v_rows_closed + v_rows_new, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_customer failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 8. CE_PAYMENT. Point (e): uniqueness/lookup now on (source_system,
--    payment_id), not payment_id alone -- retail and online each
--    number their own transaction_id (and therefore payment_id) from 1
--    independently, so an unqualified payment_id is not safe to treat
--    as globally unique.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_payment()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_payment (
            payment_sk, payment_id, payment_method, payment_status, payment_risk_score,
            insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT nextval('bl_3nf.seq_ce_payment'), dedup.payment_id, COALESCE(dedup.payment_method, 'n. a.'),
               COALESCE(dedup.payment_status, 'n. a.'), COALESCE(dedup.payment_risk_score, -1),
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT transaction_id AS payment_id, payment_method, payment_status,
                   ROUND(payment_risk_score)::INTEGER AS payment_risk_score,
                   'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                   transaction_id::VARCHAR(100) AS source_id
            FROM sa_retail.src_retail_sales
            UNION ALL
            SELECT transaction_id, payment_method, payment_status, ROUND(payment_risk_score)::INTEGER,
                   'SA_ONLINE', 'SRC_ONLINE_SALES', transaction_id::VARCHAR(100)
            FROM sa_online.src_online_sales
        ) dedup
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_payment pm
            WHERE pm.source_system = dedup.source_system AND pm.payment_id = dedup.payment_id
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_payment', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_payment failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 9. CE_DELIVERY. Same source-triplet uniqueness fix as CE_PAYMENT
--    (point e). Online-only, as before.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_delivery()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_delivery (
            delivery_sk, delivery_id, delivery_type, delivery_status, fulfillment_time,
            insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT nextval('bl_3nf.seq_ce_delivery'), dedup.delivery_id, COALESCE(dedup.delivery_type, 'n. a.'),
               COALESCE(dedup.delivery_status, 'n. a.'), COALESCE(dedup.fulfillment_time, -1),
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT transaction_id::VARCHAR(50) AS delivery_id, delivery_type, delivery_status,
                   delivery_time AS fulfillment_time, 'SA_ONLINE' AS source_system,
                   'SRC_ONLINE_SALES' AS source_entity, transaction_id::VARCHAR(100) AS source_id
            FROM sa_online.src_online_sales
        ) dedup
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_delivery d
            WHERE d.source_system = dedup.source_system AND d.delivery_id = dedup.delivery_id
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_delivery', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_delivery failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 10. CE_TRANSACTION (fact). Point (g): transaction_date stored
--     directly, no CE_DATE/date_sk. Point (e): matched against
--     CE_PAYMENT/CE_DELIVERY/CE_TRANSACTION's own uniqueness via
--     (source_system, id), not id alone. Dimension lookups already used
--     LEFT JOIN + COALESCE(-1) in the original design (they were the
--     one part the mentor's "inconsistently" did NOT flag) -- kept as-is.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_transaction()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_transaction (
            transaction_sk, transaction_id, customer_sk, product_sk, store_sk, payment_sk, delivery_sk,
            transaction_date, quantity, unit_price, sales_value, discount, cost_price, shipping_cost, total_cost, profit,
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
            t.transaction_date,
            t.quantity, t.unit_price, t.sales_value, t.discount, t.cost_price,
            COALESCE(t.shipping_cost, 0), t.total_cost, t.profit,
            t.transaction_channel, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
            t.source_system, t.source_entity, t.transaction_id::VARCHAR(100)
        FROM (
            SELECT transaction_id, customer_id, product_id, store_id, transaction_date, quantity, unit_price,
                   sales_value, discount, cost_price, NULL::NUMERIC(12,2) AS shipping_cost, total_cost, profit,
                   transaction_channel, 'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity
            FROM sa_retail.src_retail_sales
            UNION ALL
            SELECT transaction_id, customer_id, product_id, store_id, transaction_date, quantity, unit_price,
                   sales_value, discount, cost_price, shipping_cost, total_cost, profit,
                   transaction_channel, 'SA_ONLINE', 'SRC_ONLINE_SALES'
            FROM sa_online.src_online_sales
        ) t
        LEFT JOIN bl_3nf.ce_customer cu ON cu.customer_id = t.customer_id
                                        AND t.transaction_date BETWEEN cu.start_dt AND cu.end_dt
        LEFT JOIN bl_3nf.ce_product  pr ON pr.product_id  = t.product_id
        LEFT JOIN bl_3nf.ce_store    st ON st.store_id    = t.store_id
        LEFT JOIN bl_3nf.ce_payment  pm ON pm.source_system = t.source_system AND pm.payment_id = t.transaction_id
        LEFT JOIN bl_3nf.ce_delivery dl ON dl.source_system = t.source_system AND dl.delivery_id = t.transaction_id::VARCHAR(50)
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_transaction ct
            WHERE ct.source_system = t.source_system AND ct.transaction_id = t.transaction_id
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_transaction', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_transaction failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- Reporting FUNCTION, RETURNS TABLE (second, independent example of the
-- "function returns table" requirement -- no FOR loop this time, a
-- plain set-based result. Used for the Task Results verification.)
-- =======================================================================
CREATE OR REPLACE FUNCTION bl_cl.fn_get_load_summary()
RETURNS TABLE(table_name TEXT, row_count BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 'ce_category', count(*) FROM bl_3nf.ce_category
    UNION ALL SELECT 'ce_subcategory', count(*) FROM bl_3nf.ce_subcategory
    UNION ALL SELECT 'ce_product', count(*) FROM bl_3nf.ce_product
    UNION ALL SELECT 'ce_country', count(*) FROM bl_3nf.ce_country
    UNION ALL SELECT 'ce_region', count(*) FROM bl_3nf.ce_region
    UNION ALL SELECT 'ce_store', count(*) FROM bl_3nf.ce_store
    UNION ALL SELECT 'ce_customer', count(*) FROM bl_3nf.ce_customer
    UNION ALL SELECT 'ce_payment', count(*) FROM bl_3nf.ce_payment
    UNION ALL SELECT 'ce_delivery', count(*) FROM bl_3nf.ce_delivery
    UNION ALL SELECT 'ce_transaction', count(*) FROM bl_3nf.ce_transaction;
END;
$$;


-- =======================================================================
-- MASTER PROCEDURE: runs all 10 loads in dependency order. This is the
-- single "repeatable procedure" referenced in the Task 7 idempotency
-- test (parents before children within each hierarchy; all dimensions
-- before the fact load).
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_bl_3nf_all()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL bl_cl.load_ce_category();
    CALL bl_cl.load_ce_subcategory();
    CALL bl_cl.load_ce_product();
    CALL bl_cl.load_ce_country();
    CALL bl_cl.load_ce_region();
    CALL bl_cl.load_ce_store();
    CALL bl_cl.load_ce_customer();
    CALL bl_cl.load_ce_payment();
    CALL bl_cl.load_ce_delivery();
    CALL bl_cl.load_ce_transaction();
END;
$$;
