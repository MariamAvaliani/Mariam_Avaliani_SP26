-- Task 8 -- BL_CL: composite types, logging, and the 5 procedures that
-- load BL_DM dimensions from BL_3NF. DIM_DATES is not here -- it doesn't
-- come from BL_3NF, I already built and populated it back in Task 4.

CREATE SCHEMA IF NOT EXISTS bl_cl;

-- bl_cl_role -- read-only on bl_3nf, read/write on bl_dm and bl_cl,
-- can execute the procedures below.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bl_cl_role') THEN
        CREATE ROLE bl_cl_role NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA bl_3nf TO bl_cl_role;
GRANT SELECT ON ALL TABLES IN SCHEMA bl_3nf TO bl_cl_role;

GRANT USAGE ON SCHEMA bl_dm TO bl_cl_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA bl_dm TO bl_cl_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA bl_dm TO bl_cl_role;

GRANT USAGE ON SCHEMA bl_cl TO bl_cl_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA bl_cl TO bl_cl_role;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA bl_cl TO bl_cl_role;

-- t_dim_product_row: one product row, used in prc_load_dim_products.
-- t_customer_attrs: the SCD2-tracked customer fields, used in
-- prc_load_dim_customers_scd to compare old vs new as one value instead
-- of five separate checks.
DROP TYPE IF EXISTS bl_cl.t_dim_product_row CASCADE;
CREATE TYPE bl_cl.t_dim_product_row AS (
    product_src_id      VARCHAR(50),
    product_name        VARCHAR(255),
    product_category    VARCHAR(100),
    product_subcategory VARCHAR(100),
    product_brand       VARCHAR(100),
    product_price_amt   DECIMAL(12,2),
    source_system       VARCHAR(30),
    source_entity       VARCHAR(50)
);

DROP TYPE IF EXISTS bl_cl.t_customer_attrs CASCADE;
CREATE TYPE bl_cl.t_customer_attrs AS (
    customer_segment       VARCHAR(50),
    customer_type          VARCHAR(50),
    customer_city          VARCHAR(100),
    customer_loyalty_score INTEGER,
    customer_age_group     VARCHAR(30)
);

-- mta_etl_log + the only procedure allowed to write into it.
CREATE SEQUENCE IF NOT EXISTS bl_cl.seq_mta_etl_log;

CREATE TABLE IF NOT EXISTS bl_cl.mta_etl_log (
    log_id          BIGINT       NOT NULL,
    procedure_name  VARCHAR(100) NOT NULL,
    start_ts        TIMESTAMP    NOT NULL,
    end_ts          TIMESTAMP    NOT NULL,
    rows_affected   INTEGER      NOT NULL,
    status          VARCHAR(20)  NOT NULL,
    message         VARCHAR(1000),
    CONSTRAINT pk_mta_etl_log PRIMARY KEY (log_id),
    CONSTRAINT ck_mta_etl_log_status CHECK (status IN ('SUCCESS', 'FAILED'))
);

CREATE OR REPLACE PROCEDURE bl_cl.prc_log_etl_event(
    p_procedure_name VARCHAR,
    p_start_ts       TIMESTAMP,
    p_rows_affected  INTEGER,
    p_status         VARCHAR,
    p_message        VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO bl_cl.mta_etl_log (log_id, procedure_name, start_ts, end_ts, rows_affected, status, message)
    VALUES (nextval('bl_cl.seq_mta_etl_log'), p_procedure_name, p_start_ts, clock_timestamp(), p_rows_affected, p_status, p_message);
END;
$$;

-- prc_load_dim_products
-- cursor FOR loop + composite type + EXECUTE ... USING for the upsert.
-- WHERE clause on ON CONFLICT skips rows that didn't actually change,
-- so a second run reports 0 rows affected.
CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_products()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_ts TIMESTAMP := clock_timestamp();
    v_row      bl_cl.t_dim_product_row;
    v_sql      TEXT;
    v_this     INTEGER;
    v_rows     INTEGER := 0;
BEGIN
    FOR v_row IN
        SELECT
            p.product_id::VARCHAR(50) AS product_src_id,
            p.product_name,
            c.category_name           AS product_category,
            s.subcategory_name        AS product_subcategory,
            p.product_brand,
            p.product_price           AS product_price_amt,
            'BL_3NF'::VARCHAR(30)     AS source_system,
            'CE_PRODUCT'::VARCHAR(50) AS source_entity
        FROM bl_3nf.ce_product p
        JOIN bl_3nf.ce_subcategory s ON s.subcategory_sk = p.subcategory_sk
        JOIN bl_3nf.ce_category c    ON c.category_sk = s.category_sk
        WHERE p.product_sk <> -1
    LOOP
        v_sql := format(
            'INSERT INTO bl_dm.dim_products
                 (product_surr_id, product_src_id, product_name, product_category, product_subcategory,
                  product_brand, product_price_amt, insert_dt, update_dt, source_system, source_entity)
             VALUES (nextval(%L), $1, $2, $3, $4, $5, $6, CURRENT_DATE, CURRENT_DATE, $7, $8)
             ON CONFLICT (product_src_id) DO UPDATE SET
                 product_name        = EXCLUDED.product_name,
                 product_category    = EXCLUDED.product_category,
                 product_subcategory = EXCLUDED.product_subcategory,
                 product_brand       = EXCLUDED.product_brand,
                 product_price_amt   = EXCLUDED.product_price_amt,
                 update_dt           = CURRENT_DATE,
                 source_system       = EXCLUDED.source_system,
                 source_entity       = EXCLUDED.source_entity
             WHERE dim_products.product_name        IS DISTINCT FROM EXCLUDED.product_name
                OR dim_products.product_category    IS DISTINCT FROM EXCLUDED.product_category
                OR dim_products.product_subcategory IS DISTINCT FROM EXCLUDED.product_subcategory
                OR dim_products.product_brand       IS DISTINCT FROM EXCLUDED.product_brand
                OR dim_products.product_price_amt   IS DISTINCT FROM EXCLUDED.product_price_amt',
            'bl_dm.seq_dim_products'
        );

        EXECUTE v_sql USING v_row.product_src_id, v_row.product_name, v_row.product_category,
                             v_row.product_subcategory, v_row.product_brand, v_row.product_price_amt,
                             v_row.source_system, v_row.source_entity;

        GET DIAGNOSTICS v_this = ROW_COUNT;
        v_rows := v_rows + v_this;
    END LOOP;

    CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_PRODUCTS', v_start_ts, v_rows, 'SUCCESS', NULL);
EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_PRODUCTS', v_start_ts, v_rows, 'FAILED', SQLERRM);
        RAISE;
END;
$$;

-- prc_load_dim_stores
-- same idea as products but plain INSERT ... ON CONFLICT, no EXECUTE
-- needed here.
CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_stores()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_ts TIMESTAMP := clock_timestamp();
    v_rec      RECORD;
    v_this     INTEGER;
    v_rows     INTEGER := 0;
BEGIN
    FOR v_rec IN
        SELECT st.store_id, st.store_location, st.store_type, r.region_name, c.country_name
        FROM bl_3nf.ce_store st
        JOIN bl_3nf.ce_region  r ON r.region_sk = st.region_sk
        JOIN bl_3nf.ce_country c ON c.country_sk = r.country_sk
        WHERE st.store_sk <> -1
    LOOP
        INSERT INTO bl_dm.dim_stores (
            store_surr_id, store_src_id, store_location, store_type, store_region, store_country,
            insert_dt, update_dt, source_system, source_entity
        ) VALUES (
            nextval('bl_dm.seq_dim_stores'), v_rec.store_id::VARCHAR(50), v_rec.store_location, v_rec.store_type,
            v_rec.region_name, v_rec.country_name, CURRENT_DATE, CURRENT_DATE, 'BL_3NF', 'CE_STORE'
        )
        ON CONFLICT (store_src_id) DO UPDATE SET
            store_location = EXCLUDED.store_location,
            store_type     = EXCLUDED.store_type,
            store_region   = EXCLUDED.store_region,
            store_country  = EXCLUDED.store_country,
            update_dt      = CURRENT_DATE
        WHERE dim_stores.store_location IS DISTINCT FROM EXCLUDED.store_location
           OR dim_stores.store_type     IS DISTINCT FROM EXCLUDED.store_type
           OR dim_stores.store_region   IS DISTINCT FROM EXCLUDED.store_region
           OR dim_stores.store_country  IS DISTINCT FROM EXCLUDED.store_country;

        GET DIAGNOSTICS v_this = ROW_COUNT;
        v_rows := v_rows + v_this;
    END LOOP;

    CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_STORES', v_start_ts, v_rows, 'SUCCESS', NULL);
EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_STORES', v_start_ts, v_rows, 'FAILED', SQLERRM);
        RAISE;
END;
$$;

-- prc_load_dim_payments
-- explicit cursor variable (refcursor) instead of a FOR loop --
-- OPEN ... FOR SELECT, then FETCH / EXIT WHEN NOT FOUND / CLOSE.
CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_payments()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_ts   TIMESTAMP := clock_timestamp();
    c_payments   refcursor;
    v_rec        RECORD;
    v_this       INTEGER;
    v_rows       INTEGER := 0;
BEGIN
    OPEN c_payments FOR
        SELECT payment_id, payment_method, payment_status, payment_risk_score
        FROM bl_3nf.ce_payment
        WHERE payment_sk <> -1;

    LOOP
        FETCH c_payments INTO v_rec;
        EXIT WHEN NOT FOUND;

        INSERT INTO bl_dm.dim_payments (
            payment_surr_id, payment_src_id, payment_method, payment_status, payment_risk_score,
            insert_dt, update_dt, source_system, source_entity
        ) VALUES (
            nextval('bl_dm.seq_dim_payments'), v_rec.payment_id::VARCHAR(50), v_rec.payment_method,
            v_rec.payment_status, v_rec.payment_risk_score, CURRENT_DATE, CURRENT_DATE, 'BL_3NF', 'CE_PAYMENT'
        )
        ON CONFLICT (payment_src_id) DO UPDATE SET
            payment_method     = EXCLUDED.payment_method,
            payment_status     = EXCLUDED.payment_status,
            payment_risk_score = EXCLUDED.payment_risk_score,
            update_dt          = CURRENT_DATE
        WHERE dim_payments.payment_method     IS DISTINCT FROM EXCLUDED.payment_method
           OR dim_payments.payment_status     IS DISTINCT FROM EXCLUDED.payment_status
           OR dim_payments.payment_risk_score IS DISTINCT FROM EXCLUDED.payment_risk_score;

        GET DIAGNOSTICS v_this = ROW_COUNT;
        v_rows := v_rows + v_this;
    END LOOP;

    CLOSE c_payments;

    CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_PAYMENTS', v_start_ts, v_rows, 'SUCCESS', NULL);
EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_PAYMENTS', v_start_ts, v_rows, 'FAILED', SQLERRM);
        RAISE;
END;
$$;

-- prc_load_dim_deliveries
-- cursor variable again, but opened with OPEN ... FOR EXECUTE -- the
-- query text is built with format() at runtime.
CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_deliveries()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_ts   TIMESTAMP := clock_timestamp();
    c_deliveries refcursor;
    v_rec        RECORD;
    v_this       INTEGER;
    v_rows       INTEGER := 0;
    v_src_table  TEXT := 'bl_3nf.ce_delivery';
BEGIN
    OPEN c_deliveries FOR EXECUTE
        format('SELECT delivery_id, delivery_type, delivery_status, fulfillment_time FROM %s WHERE delivery_sk <> -1', v_src_table);

    LOOP
        FETCH c_deliveries INTO v_rec;
        EXIT WHEN NOT FOUND;

        INSERT INTO bl_dm.dim_deliveries (
            delivery_surr_id, delivery_src_id, delivery_type, delivery_status,
            delivery_fulfillment_time_num, insert_dt, update_dt, source_system, source_entity
        ) VALUES (
            nextval('bl_dm.seq_dim_deliveries'), v_rec.delivery_id, v_rec.delivery_type, v_rec.delivery_status,
            v_rec.fulfillment_time, CURRENT_DATE, CURRENT_DATE, 'BL_3NF', 'CE_DELIVERY'
        )
        ON CONFLICT (delivery_src_id) DO UPDATE SET
            delivery_type                  = EXCLUDED.delivery_type,
            delivery_status                = EXCLUDED.delivery_status,
            delivery_fulfillment_time_num  = EXCLUDED.delivery_fulfillment_time_num,
            update_dt                      = CURRENT_DATE
        WHERE dim_deliveries.delivery_type                 IS DISTINCT FROM EXCLUDED.delivery_type
           OR dim_deliveries.delivery_status               IS DISTINCT FROM EXCLUDED.delivery_status
           OR dim_deliveries.delivery_fulfillment_time_num IS DISTINCT FROM EXCLUDED.delivery_fulfillment_time_num;

        GET DIAGNOSTICS v_this = ROW_COUNT;
        v_rows := v_rows + v_this;
    END LOOP;

    CLOSE c_deliveries;

    CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_DELIVERIES', v_start_ts, v_rows, 'SUCCESS', NULL);
EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_DELIVERIES', v_start_ts, v_rows, 'FAILED', SQLERRM);
        RAISE;
END;
$$;

-- prc_load_dim_customers_scd
-- the SCD2 one. No ON CONFLICT -- has to keep every version, so I close
-- the old row and insert a new one by hand when something changed.
-- cursor FOR loop + t_customer_attrs to compare the tracked fields as
-- one value instead of five separate OR conditions.
CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_customers_scd()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_ts     TIMESTAMP := clock_timestamp();
    v_cur          RECORD;
    v_new_attrs    bl_cl.t_customer_attrs;
    v_old_attrs    bl_cl.t_customer_attrs;
    v_dm_active_id BIGINT;
    v_rows         INTEGER := 0;
BEGIN
    FOR v_cur IN
        SELECT customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group,
               source_system, source_entity
        FROM bl_3nf.ce_customer
        WHERE is_active = 'Y' AND customer_sk <> -1
    LOOP
        v_new_attrs := ROW(v_cur.customer_segment, v_cur.customer_type, v_cur.customer_city,
                            v_cur.loyalty_score, v_cur.age_group)::bl_cl.t_customer_attrs;

        v_dm_active_id := NULL;
        SELECT customer_surr_id INTO v_dm_active_id
        FROM bl_dm.dim_customers_scd
        WHERE customer_src_id = v_cur.customer_id::VARCHAR(50) AND is_active = 'Y';

        IF v_dm_active_id IS NULL THEN
            -- brand-new customer, first version
            INSERT INTO bl_dm.dim_customers_scd (
                customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
                customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active,
                insert_dt, update_dt, source_system, source_entity
            ) VALUES (
                nextval('bl_dm.seq_dim_customers'), v_cur.customer_id::VARCHAR(50),
                (v_new_attrs).customer_segment, (v_new_attrs).customer_type, (v_new_attrs).customer_city,
                (v_new_attrs).customer_loyalty_score, (v_new_attrs).customer_age_group,
                CURRENT_DATE, DATE '9999-12-31', 'Y',
                CURRENT_DATE, CURRENT_DATE, v_cur.source_system, v_cur.source_entity
            );
            v_rows := v_rows + 1;
        ELSE
            -- note: SELECT ROW(...)::type INTO doesn't unpack the fields
            -- correctly in plpgsql, so I assign it directly instead
            v_old_attrs := (
                SELECT ROW(customer_segment, customer_type, customer_city, customer_loyalty_score, customer_age_group)::bl_cl.t_customer_attrs
                FROM bl_dm.dim_customers_scd
                WHERE customer_surr_id = v_dm_active_id
            );

            IF v_old_attrs IS DISTINCT FROM v_new_attrs THEN
                UPDATE bl_dm.dim_customers_scd
                   SET end_dt = (CURRENT_DATE - INTERVAL '1 day')::DATE,
                       is_active = 'N',
                       update_dt = CURRENT_DATE
                 WHERE customer_surr_id = v_dm_active_id;

                INSERT INTO bl_dm.dim_customers_scd (
                    customer_surr_id, customer_src_id, customer_segment, customer_type, customer_city,
                    customer_loyalty_score, customer_age_group, start_dt, end_dt, is_active,
                    insert_dt, update_dt, source_system, source_entity
                ) VALUES (
                    nextval('bl_dm.seq_dim_customers'), v_cur.customer_id::VARCHAR(50),
                    (v_new_attrs).customer_segment, (v_new_attrs).customer_type, (v_new_attrs).customer_city,
                    (v_new_attrs).customer_loyalty_score, (v_new_attrs).customer_age_group,
                    CURRENT_DATE, DATE '9999-12-31', 'Y',
                    CURRENT_DATE, CURRENT_DATE, v_cur.source_system, v_cur.source_entity
                );
                v_rows := v_rows + 2; -- 1 row closed + 1 row opened
            END IF;
            -- else: nothing changed, do nothing
        END IF;
    END LOOP;

    CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_CUSTOMERS_SCD', v_start_ts, v_rows, 'SUCCESS', NULL);
EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_log_etl_event('PRC_LOAD_DIM_CUSTOMERS_SCD', v_start_ts, v_rows, 'FAILED', SQLERRM);
        RAISE;
END;
$$;

-- runs all 5 in one CALL, order doesn't matter since none of the
-- dimensions reference each other.
CREATE OR REPLACE PROCEDURE bl_cl.prc_run_all_dim_loads()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL bl_cl.prc_load_dim_products();
    CALL bl_cl.prc_load_dim_stores();
    CALL bl_cl.prc_load_dim_payments();
    CALL bl_cl.prc_load_dim_deliveries();
    CALL bl_cl.prc_load_dim_customers_scd();
END;
$$;

-- grants on the objects just created -- the earlier GRANT ... ALL TABLES
-- IN SCHEMA bl_cl ran before mta_etl_log existed, so it's repeated here
-- now that the table is actually there
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA bl_cl TO bl_cl_role;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA bl_cl TO bl_cl_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA bl_cl GRANT EXECUTE ON ROUTINES TO bl_cl_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA bl_cl GRANT SELECT, INSERT, UPDATE ON TABLES TO bl_cl_role;
