\timing on
-- =====================================================================
-- BL_CL -- ETL objects: logging + one load procedure per BL_3NF table.
-- Task 7 (PostgreSQL_DB_for_DWH_and_ETL). Addresses mentor feedback
-- (Kseniya Lazarchik) throughout -- see inline notes tagged (a)-(h)
-- matching the review comment list in the Task 7 document.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bl_cl;
CREATE SEQUENCE IF NOT EXISTS bl_cl.seq_log_table;

-- ---------------------------------------------------------------------
-- Centralized logging table + logging procedure
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_cl.log_table (
    log_id          BIGINT        NOT NULL DEFAULT nextval('bl_cl.seq_log_table'),
    log_dt          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    procedure_name  VARCHAR(100)  NOT NULL,
    rows_affected   INTEGER       NOT NULL,
    status          VARCHAR(10)   NOT NULL,
    log_message     VARCHAR(4000) NOT NULL,
    CONSTRAINT pk_log_table PRIMARY KEY (log_id),
    CONSTRAINT ck_log_table_status CHECK (status IN ('SUCCESS', 'ERROR'))
);
CREATE INDEX IF NOT EXISTS ix_log_table_proc_dt ON bl_cl.log_table (procedure_name, log_dt DESC);

CREATE OR REPLACE PROCEDURE bl_cl.sp_write_log(
    p_procedure_name VARCHAR,
    p_rows_affected  INTEGER,
    p_status         VARCHAR,
    p_message        VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO bl_cl.log_table (log_id, log_dt, procedure_name, rows_affected, status, log_message)
    VALUES (nextval('bl_cl.seq_log_table'), CURRENT_TIMESTAMP, p_procedure_name, p_rows_affected, p_status, p_message);
END;
$$;

-- ---------------------------------------------------------------------
-- Explicit conformed-dimension crosswalks (point d): CE_CATEGORY and
-- CE_COUNTRY are conformed (same business meaning regardless of which
-- source system reported them). Rather than an implicit DISTINCT ON +
-- ORDER BY priority pick that silently drops the "losing" source's row,
-- every (name, source_system) combination this project has ever seen is
-- recorded here, cross-referenced to the one canonical BL_3NF row. The
-- matching rule is explicit and documented: exact name match; SA_RETAIL
-- is system-of-record when both sources report the same name (creates
-- the canonical row first); SA_ONLINE's row for the same name is
-- matched to it, not discarded -- its lineage survives in this table.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_cl.wk_category_xref (
    category_name  VARCHAR(100)  NOT NULL,
    source_system  VARCHAR(30)   NOT NULL,
    source_entity  VARCHAR(50)   NOT NULL,
    source_id      VARCHAR(100)  NOT NULL,
    category_sk    BIGINT        NOT NULL,
    matched_dt     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_wk_category_xref PRIMARY KEY (category_name, source_system)
);

CREATE TABLE IF NOT EXISTS bl_cl.wk_country_xref (
    country_name   VARCHAR(100)  NOT NULL,
    source_system  VARCHAR(30)   NOT NULL,
    source_entity  VARCHAR(50)   NOT NULL,
    source_id      VARCHAR(100)  NOT NULL,
    country_sk     BIGINT        NOT NULL,
    matched_dt     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_wk_country_xref PRIMARY KEY (country_name, source_system)
);


-- =======================================================================
-- 1. CE_CATEGORY -- FUNCTION, RETURNS TABLE, uses a FOR loop over the
--    query result (rubric requirements: "Function returns table" and
--    "Use For Loop over query result"). This loop body IS the explicit
--    matching/dedup logic BL_CL now owns (point d), instead of an
--    implicit DISTINCT ON in a single INSERT...SELECT.
-- =======================================================================
CREATE OR REPLACE FUNCTION bl_cl.fn_load_ce_category()
RETURNS TABLE(out_category_sk BIGINT, out_category_name VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    rec   RECORD;
    v_sk  BIGINT;
BEGIN
    FOR rec IN
        SELECT DISTINCT u.category_name, u.source_system, u.source_entity, u.source_id, u.src_priority
        FROM (
            SELECT product_category AS category_name, 'SA_RETAIL' AS source_system,
                   'SRC_RETAIL_SALES' AS source_entity, product_category AS source_id, 1 AS src_priority
            FROM sa_retail.src_retail_sales
            UNION ALL
            SELECT product_category, 'SA_ONLINE', 'SRC_ONLINE_SALES', product_category, 2
            FROM sa_online.src_online_sales
        ) u
        ORDER BY u.category_name, u.src_priority
    LOOP
        SELECT c.category_sk INTO v_sk FROM bl_3nf.ce_category c WHERE c.category_name = rec.category_name;

        IF v_sk IS NULL THEN
            v_sk := nextval('bl_3nf.seq_ce_category');
            INSERT INTO bl_3nf.ce_category (category_sk, category_name, insert_dt, update_dt, source_system, source_entity, source_id)
            VALUES (v_sk, rec.category_name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, rec.source_system, rec.source_entity, rec.source_id);
            out_category_sk := v_sk; out_category_name := rec.category_name;
            RETURN NEXT;
        END IF;

        -- record this source's lineage regardless of who created the canonical row
        INSERT INTO bl_cl.wk_category_xref (category_name, source_system, source_entity, source_id, category_sk, matched_dt)
        VALUES (rec.category_name, rec.source_system, rec.source_entity, rec.source_id, v_sk, CURRENT_TIMESTAMP)
        ON CONFLICT (category_name, source_system) DO UPDATE SET category_sk = EXCLUDED.category_sk, matched_dt = EXCLUDED.matched_dt;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE bl_cl.load_ce_category()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        SELECT count(*) INTO v_rows FROM bl_cl.fn_load_ce_category();
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_category', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_category failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 2. CE_SUBCATEGORY (FK -> CE_CATEGORY). LEFT JOIN + COALESCE(-1)
--    instead of INNER JOIN (points b, c): an unresolvable parent no
--    longer silently drops the child row -- it degrades to the
--    default category instead, exactly like the fact table already did.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_subcategory()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_subcategory (
            subcategory_sk, subcategory_name, category_sk, insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT
            nextval('bl_3nf.seq_ce_subcategory'),
            dedup.subcategory_name, COALESCE(cat.category_sk, -1), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
            dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT DISTINCT ON (subcategory_name, category_name)
                COALESCE(subcategory_name, 'n. a.') AS subcategory_name, COALESCE(category_name, 'n. a.') AS category_name,
                source_system, source_entity, source_id
            FROM (
                SELECT product_subcategory AS subcategory_name, product_category AS category_name,
                       'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                       product_subcategory AS source_id, 1 AS src_priority
                FROM sa_retail.src_retail_sales
                UNION ALL
                SELECT product_subcategory, product_category, 'SA_ONLINE', 'SRC_ONLINE_SALES', product_subcategory, 2
                FROM sa_online.src_online_sales
            ) u
            ORDER BY subcategory_name, category_name, src_priority
        ) dedup
        LEFT JOIN bl_3nf.ce_category cat ON cat.category_name = dedup.category_name
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_subcategory s
            WHERE s.subcategory_name = dedup.subcategory_name AND s.category_sk = COALESCE(cat.category_sk, -1)
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_subcategory', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_subcategory failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 3. CE_PRODUCT (FK -> CE_SUBCATEGORY). Same LEFT JOIN + COALESCE fix.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_product()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_product (
            product_sk, product_id, product_name, subcategory_sk, product_brand, product_price,
            insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT
            nextval('bl_3nf.seq_ce_product'),
            dedup.product_id, COALESCE(dedup.product_name, 'n. a.'), COALESCE(sub.subcategory_sk, -1),
            COALESCE(dedup.product_brand, 'n. a.'), COALESCE(dedup.product_price, -1),
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
                       'SA_ONLINE', 'SRC_ONLINE_SALES', product_id::VARCHAR(100), 2
                FROM sa_online.src_online_sales
            ) u
            ORDER BY product_id, src_priority
        ) dedup
        LEFT JOIN bl_3nf.ce_category cat    ON cat.category_name = dedup.product_category
        LEFT JOIN bl_3nf.ce_subcategory sub ON sub.subcategory_name = dedup.product_subcategory
                                             AND sub.category_sk = COALESCE(cat.category_sk, -1)
        WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_product p WHERE p.product_id = dedup.product_id);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_product', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_product failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 4. CE_COUNTRY -- explicit crosswalk, same rationale as CE_CATEGORY
--    (point d), implemented set-based this time (the FOR-loop
--    requirement is already covered by fn_load_ce_category above).
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_country()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
    v_new    INTEGER := 0;
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_country (country_sk, country_name, insert_dt, update_dt, source_system, source_entity, source_id)
        SELECT nextval('bl_3nf.seq_ce_country'), dedup.country_name, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
               dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT DISTINCT ON (country_name)
                COALESCE(country_name, 'n. a.') AS country_name, source_system, source_entity, source_id
            FROM (
                SELECT country AS country_name, 'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                       country AS source_id, 1 AS src_priority
                FROM sa_retail.src_retail_sales
                UNION ALL
                SELECT country, 'SA_ONLINE', 'SRC_ONLINE_SALES', country, 2
                FROM sa_online.src_online_sales
            ) u
            ORDER BY country_name, src_priority
        ) dedup
        WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_country c WHERE c.country_name = dedup.country_name);
        GET DIAGNOSTICS v_new = ROW_COUNT;
        v_rows := v_new;

        -- explicit crosswalk: every (country_name, source_system) combo, both sources
        INSERT INTO bl_cl.wk_country_xref (country_name, source_system, source_entity, source_id, country_sk, matched_dt)
        SELECT u.country_name, u.source_system, u.source_entity, u.source_id, c.country_sk, CURRENT_TIMESTAMP
        FROM (
            SELECT DISTINCT COALESCE(country, 'n. a.') AS country_name, 'SA_RETAIL' AS source_system,
                   'SRC_RETAIL_SALES' AS source_entity, country AS source_id
            FROM sa_retail.src_retail_sales
            UNION
            SELECT DISTINCT COALESCE(country, 'n. a.'), 'SA_ONLINE', 'SRC_ONLINE_SALES', country
            FROM sa_online.src_online_sales
        ) u
        JOIN bl_3nf.ce_country c ON c.country_name = u.country_name
        ON CONFLICT (country_name, source_system) DO UPDATE SET country_sk = EXCLUDED.country_sk, matched_dt = EXCLUDED.matched_dt;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_country', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_country failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 5. CE_REGION (FK -> CE_COUNTRY). LEFT JOIN + COALESCE fix. Online has
--    no REGION column -- every online row maps to the 'n. a.' region
--    under its real country (unchanged from the original design).
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_region()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_region (region_sk, region_name, country_sk, insert_dt, update_dt, source_system, source_entity, source_id)
        SELECT nextval('bl_3nf.seq_ce_region'), dedup.region_name, COALESCE(ctry.country_sk, -1), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
               dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT DISTINCT ON (region_name, country_name)
                region_name, country_name, source_system, source_entity, source_id
            FROM (
                SELECT COALESCE(region, 'n. a.') AS region_name, COALESCE(country, 'n. a.') AS country_name,
                       'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                       COALESCE(region, 'n. a.') AS source_id, 1 AS src_priority
                FROM sa_retail.src_retail_sales
                UNION ALL
                SELECT 'n. a.', COALESCE(country, 'n. a.'), 'SA_ONLINE', 'SRC_ONLINE_SALES', 'n. a.', 2
                FROM sa_online.src_online_sales
            ) u
            ORDER BY region_name, country_name, src_priority
        ) dedup
        LEFT JOIN bl_3nf.ce_country ctry ON ctry.country_name = dedup.country_name
        WHERE NOT EXISTS (
            SELECT 1 FROM bl_3nf.ce_region r
            WHERE r.region_name = dedup.region_name AND r.country_sk = COALESCE(ctry.country_sk, -1)
        );
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_region', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_region failed: %', v_msg;
    END IF;
END;
$$;


-- =======================================================================
-- 6. CE_STORE (FK -> CE_REGION). LEFT JOIN + COALESCE fix.
-- =======================================================================
CREATE OR REPLACE PROCEDURE bl_cl.load_ce_store()
LANGUAGE plpgsql
AS $$
DECLARE
    v_rows   INTEGER := 0;
    v_status VARCHAR := 'SUCCESS';
    v_msg    VARCHAR := 'OK';
BEGIN
    BEGIN
        INSERT INTO bl_3nf.ce_store (
            store_sk, store_id, store_location, store_type, region_sk,
            insert_dt, update_dt, source_system, source_entity, source_id
        )
        SELECT nextval('bl_3nf.seq_ce_store'), dedup.store_id, COALESCE(dedup.store_location, 'n. a.'),
               COALESCE(dedup.store_type, 'n. a.'), COALESCE(reg.region_sk, -1),
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, dedup.source_system, dedup.source_entity, dedup.source_id
        FROM (
            SELECT DISTINCT ON (store_id)
                store_id, store_location, store_type, region_name, country_name,
                source_system, source_entity, source_id
            FROM (
                SELECT store_id, store_location, store_type,
                       COALESCE(region, 'n. a.') AS region_name, COALESCE(country, 'n. a.') AS country_name,
                       'SA_RETAIL' AS source_system, 'SRC_RETAIL_SALES' AS source_entity,
                       store_id::VARCHAR(100) AS source_id, 1 AS src_priority
                FROM sa_retail.src_retail_sales
                UNION ALL
                SELECT store_id, store_location, store_type,
                       'n. a.', COALESCE(country, 'n. a.'),
                       'SA_ONLINE', 'SRC_ONLINE_SALES', store_id::VARCHAR(100), 2
                FROM sa_online.src_online_sales
            ) u
            ORDER BY store_id, src_priority
        ) dedup
        LEFT JOIN bl_3nf.ce_country ctry ON ctry.country_name = dedup.country_name
        LEFT JOIN bl_3nf.ce_region  reg  ON reg.region_name = dedup.region_name AND reg.country_sk = COALESCE(ctry.country_sk, -1)
        WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_store st WHERE st.store_id = dedup.store_id);
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
        v_status := 'ERROR'; v_msg := SQLERRM; v_rows := 0;
    END;
    CALL bl_cl.sp_write_log('load_ce_store', v_rows, v_status, v_msg);
    COMMIT;
    IF v_status = 'ERROR' THEN
        RAISE EXCEPTION 'load_ce_store failed: %', v_msg;
    END IF;
END;
$$;
