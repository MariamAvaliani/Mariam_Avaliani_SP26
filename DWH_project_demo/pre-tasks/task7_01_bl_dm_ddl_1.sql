-- =====================================================================
-- Introduction to DWH and ETL -- Task 7 (Dimensional Model creation)
-- Script 1 of 2 : DDL -- physical structure of the BL_DM layer
-- Target RDBMS: PostgreSQL
--
-- Implements the star schema defined in Chapter 3 ("Dimension and Fact
-- Table Definitions") of the main business document: each BL_3NF core
-- entity is flattened into one denormalized BL_DM dimension, plus the
-- FCT_TRANSACTIONS_DD fact table at the center.
--
-- REVISION 2 -- per mentor feedback on the PR: the UNIQUE constraint on
-- each Type 0/1 dimension (DIM_PRODUCTS, DIM_STORES, DIM_PAYMENTS,
-- DIM_DELIVERIES) now covers the full source context
-- (source_system, source_entity, *_src_id), not just the src id alone --
-- so a natural key from a future second source system can never be
-- silently merged with an unrelated row that happens to reuse the same
-- src id. The load procedures' ON CONFLICT targets were updated to match
-- (see task8_01_bl_cl_load_procedures.sql / bl_cl_procedures 04-07).
--
-- Run ONCE, at the very beginning (before script 2,
-- task7_02_bl_dm_default_rows.sql). Safe to re-run: every object is
-- created with IF NOT EXISTS, so running this script again on an
-- already-built schema does nothing and raises no errors. This script
-- never DROPs a table -- DIM_CUSTOMERS_SCD holds accumulated SCD2
-- history, and a DROP would silently destroy that history on a re-run.
--
-- Objects created (see Chapter 3, Figure 3.1 "Business Layer Dimensional
-- Model (Star Schema)" for the full diagram):
--   Schema  : bl_dm
--   Tables  : dim_customers_scd (SCD Type 2), dim_products, dim_stores,
--             dim_payments, dim_deliveries, dim_dates,
--             fct_transactions_dd (fact)
--   Sequences: one per Type 0/1 dimension, per Naming_Conventions.docx
--             ("Use only SEQUENCES to generate IDs. New sequence for
--             each table.") DIM_DATES uses a deterministic YYYYMMDD
--             surrogate key instead, so it needs no sequence.
--
-- Note on DIM_DATES: this table and its one-time population were already
-- delivered independently in Task 4 (DIM_DATES_create_and_populate.sql),
-- per the task requirement that the date dimension is NOT sourced from
-- BL_3NF like the other five. It is included below (IF NOT EXISTS only,
-- no data touched) purely so this script is a complete, self-contained
-- DDL for "all BL_DM objects"; running it after Task 4's script is a
-- no-op for dim_dates, and running it before is equally safe.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bl_dm;

-- ---------------------------------------------------------------------
-- Sequences (one per Type 0/1 dimension -- surrogate keys are never
-- generated with SERIAL/IDENTITY, per Naming_Conventions.docx)
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS bl_dm.seq_dim_customers;
CREATE SEQUENCE IF NOT EXISTS bl_dm.seq_dim_products;
CREATE SEQUENCE IF NOT EXISTS bl_dm.seq_dim_stores;
CREATE SEQUENCE IF NOT EXISTS bl_dm.seq_dim_payments;
CREATE SEQUENCE IF NOT EXISTS bl_dm.seq_dim_deliveries;

-- =======================================================================
-- DIM_CUSTOMERS_SCD  (from CE_CUSTOMER, SCD Type 2)
-- Tracked attributes: customer_segment, customer_type, customer_city,
-- customer_loyalty_score, customer_age_group. Same key/versioning logic
-- as CE_CUSTOMER: CUSTOMER_SRC_ID is the stable natural key,
-- CUSTOMER_SURR_ID is the surrogate PK and gets a new value every time a
-- tracked attribute changes. Per Naming_Conventions.docx, an SCD2 table
-- must NEVER have a real FK constraint pointing at it from the fact
-- table -- FCT_TRANSACTIONS_DD.CUSTOMER_SURR_ID is a logical reference
-- only, resolved "as of" the transaction date at load time.
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_customers_scd (
    customer_surr_id        BIGINT        NOT NULL,
    customer_src_id          VARCHAR(50)   NOT NULL,   -- natural key, from CE_CUSTOMER.customer_id
    customer_segment         VARCHAR(50)   NOT NULL,
    customer_type            VARCHAR(50)   NOT NULL,
    customer_city            VARCHAR(100)  NOT NULL,
    customer_loyalty_score   INTEGER       NOT NULL,
    customer_age_group       VARCHAR(30)   NOT NULL,
    start_dt                 DATE          NOT NULL,
    end_dt                   DATE          NOT NULL,
    is_active                VARCHAR(1)    NOT NULL,
    insert_dt                DATE          NOT NULL DEFAULT CURRENT_DATE,
    update_dt                DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system            VARCHAR(30)   NOT NULL,
    source_entity             VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_dim_customers_scd PRIMARY KEY (customer_surr_id),
    CONSTRAINT ck_dim_customers_scd_is_active CHECK (is_active IN ('Y', 'N'))
);

-- =======================================================================
-- DIM_PRODUCTS  (from CE_PRODUCT + CE_SUBCATEGORY + CE_CATEGORY,
-- flattened -- Type 0/1, latest known values only)
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_products (
    product_surr_id     BIGINT         NOT NULL,
    product_src_id       VARCHAR(50)    NOT NULL,   -- natural key, from CE_PRODUCT.product_id
    product_name        VARCHAR(255)   NOT NULL,
    product_category     VARCHAR(100)   NOT NULL,   -- denormalized hierarchy attribute
    product_subcategory  VARCHAR(100)   NOT NULL,   -- denormalized hierarchy attribute
    product_brand        VARCHAR(100)   NOT NULL,
    product_price_amt     DECIMAL(12,2)  NOT NULL,
    insert_dt            DATE           NOT NULL DEFAULT CURRENT_DATE,
    update_dt            DATE           NOT NULL DEFAULT CURRENT_DATE,
    source_system        VARCHAR(30)    NOT NULL,
    source_entity         VARCHAR(50)    NOT NULL,
    CONSTRAINT pk_dim_products PRIMARY KEY (product_surr_id),
    -- per mentor feedback on Task 7: keyed on the full source context
    -- (source_system, source_entity, product_src_id), not product_src_id
    -- alone, so a future second source system can never collide with an
    -- unrelated product that happens to reuse the same src id
    CONSTRAINT uq_dim_products_src_id UNIQUE (source_system, source_entity, product_src_id)
);

-- =======================================================================
-- DIM_STORES  (from CE_STORE + CE_REGION + CE_COUNTRY, flattened --
-- Type 0/1, latest known values only)
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_stores (
    store_surr_id    BIGINT        NOT NULL,
    store_src_id      VARCHAR(50)   NOT NULL,   -- natural key, from CE_STORE.store_id
    store_location   VARCHAR(255)  NOT NULL,
    store_type       VARCHAR(50)   NOT NULL,
    store_region      VARCHAR(100)  NOT NULL,   -- denormalized hierarchy attribute
    store_country     VARCHAR(100)  NOT NULL,   -- denormalized hierarchy attribute
    insert_dt        DATE          NOT NULL DEFAULT CURRENT_DATE,
    update_dt        DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system    VARCHAR(30)   NOT NULL,
    source_entity     VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_dim_stores PRIMARY KEY (store_surr_id),
    -- per mentor feedback on Task 7: full source context, same reasoning
    -- as DIM_PRODUCTS above
    CONSTRAINT uq_dim_stores_src_id UNIQUE (source_system, source_entity, store_src_id)
);

-- =======================================================================
-- DIM_PAYMENTS  (from CE_PAYMENT -- Type 0/1, latest known values only)
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_payments (
    payment_surr_id     BIGINT        NOT NULL,
    payment_src_id       VARCHAR(50)   NOT NULL,   -- natural key, from CE_PAYMENT.payment_id
    payment_method      VARCHAR(50)   NOT NULL,
    payment_status      VARCHAR(50)   NOT NULL,
    payment_risk_score   NUMERIC(5,2)  NOT NULL,
    insert_dt           DATE          NOT NULL DEFAULT CURRENT_DATE,
    update_dt           DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system       VARCHAR(30)   NOT NULL,
    source_entity        VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_dim_payments PRIMARY KEY (payment_surr_id),
    -- per mentor feedback on Task 7: full source context, same reasoning
    -- as DIM_PRODUCTS above
    CONSTRAINT uq_dim_payments_src_id UNIQUE (source_system, source_entity, payment_src_id)
);

-- =======================================================================
-- DIM_DELIVERIES  (from CE_DELIVERY -- Type 0/1, latest known values
-- only. Online transactions only; retail transactions link to the -1
-- 'n.a.' default row -- see task7_02_bl_dm_default_rows.sql)
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_deliveries (
    delivery_surr_id             BIGINT        NOT NULL,
    delivery_src_id               VARCHAR(50)   NOT NULL,   -- natural key, from CE_DELIVERY.delivery_id
    delivery_type                VARCHAR(50)   NOT NULL,
    delivery_status              VARCHAR(50)   NOT NULL,
    delivery_fulfillment_time_num INTEGER      NOT NULL,
    insert_dt                    DATE          NOT NULL DEFAULT CURRENT_DATE,
    update_dt                    DATE          NOT NULL DEFAULT CURRENT_DATE,
    source_system                VARCHAR(30)   NOT NULL,
    source_entity                 VARCHAR(50)   NOT NULL,
    CONSTRAINT pk_dim_deliveries PRIMARY KEY (delivery_surr_id),
    -- per mentor feedback on Task 7: full source context, same reasoning
    -- as DIM_PRODUCTS above
    CONSTRAINT uq_dim_deliveries_src_id UNIQUE (source_system, source_entity, delivery_src_id)
);

-- =======================================================================
-- DIM_DATES  (standalone calendar dimension -- see note at the top of
-- this script. Included here, IF NOT EXISTS only, so the DDL for all
-- BL_DM objects lives in one place; population remains the job of
-- DIM_DATES_create_and_populate.sql, run once at warehouse setup.)
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.dim_dates (
    date_surr_id        INTEGER      NOT NULL,   -- deterministic surrogate key, format YYYYMMDD
    full_date            DATE         NOT NULL,   -- natural key
    day_of_month_num     SMALLINT     NOT NULL,
    day_of_week_num       SMALLINT     NOT NULL,   -- 1 = Monday ... 7 = Sunday (ISO)
    day_of_week_desc      VARCHAR(10)  NOT NULL,
    weekend_flag         VARCHAR(1)   NOT NULL,
    month_num            SMALLINT     NOT NULL,
    month_desc           VARCHAR(10)  NOT NULL,
    quarter_num           SMALLINT     NOT NULL,
    quarter_desc          VARCHAR(2)   NOT NULL,
    year_num              SMALLINT     NOT NULL,
    insert_dt            DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT pk_dim_dates PRIMARY KEY (date_surr_id)
);

-- =======================================================================
-- FCT_TRANSACTIONS_DD  (fact table, from CE_TRANSACTION)
-- Grain: one row per transaction/product line (TRANSACTION_SRC_ID), from
-- either source system -- unchanged from the 3NF-layer grain.
-- TRANSACTION_SRC_ID has no descriptive attributes of its own, so per
-- the degenerate-dimension pattern it is kept directly on the fact table
-- rather than given its own dimension, and doubles as this table's PK.
-- Per Naming_Conventions.docx, "All columns ARE NOT NULL, except KPI
-- (Metrics)" -- the FCT_ measure columns below are intentionally
-- nullable; every other column is NOT NULL.
-- No FK constraint on customer_surr_id -- DIM_CUSTOMERS_SCD is SCD2 (see
-- note above); the reference is logical only, resolved "as of"
-- EVENT_DT at load time.
-- =======================================================================
CREATE TABLE IF NOT EXISTS bl_dm.fct_transactions_dd (
    transaction_src_id     VARCHAR(50)    NOT NULL,   -- degenerate dimension / grain key
    event_dt               DATE           NOT NULL,
    customer_surr_id       BIGINT         NOT NULL,   -- logical FK -> dim_customers_scd (SCD2, no DB constraint)
    product_surr_id        BIGINT         NOT NULL,
    store_surr_id          BIGINT         NOT NULL,
    payment_surr_id        BIGINT         NOT NULL,
    delivery_surr_id       BIGINT         NOT NULL,
    date_surr_id           INTEGER        NOT NULL,
    transaction_channel_cd VARCHAR(20)    NOT NULL,
    fct_quantity_num       INTEGER,                   -- KPI / metric: nullable
    fct_unit_price_amt     DECIMAL(12,2),              -- KPI / metric: nullable
    fct_sales_value_amt    DECIMAL(12,2),              -- KPI / metric: nullable
    fct_discount_amt       DECIMAL(12,2),              -- KPI / metric: nullable
    fct_cost_price_amt     DECIMAL(12,2),              -- KPI / metric: nullable
    fct_shipping_cost_amt  DECIMAL(12,2),              -- KPI / metric: nullable
    fct_total_cost_amt     DECIMAL(12,2),              -- KPI / metric: nullable
    fct_profit_amt         DECIMAL(12,2),              -- KPI / metric: nullable
    fct_avg_unit_cost_amt  DECIMAL(12,2),              -- KPI / metric: nullable, calculated at load
    insert_dt              DATE           NOT NULL DEFAULT CURRENT_DATE,
    update_dt               DATE           NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT pk_fct_transactions_dd PRIMARY KEY (transaction_src_id),
    CONSTRAINT fk_fct2dim_products    FOREIGN KEY (product_surr_id)  REFERENCES bl_dm.dim_products    (product_surr_id),
    CONSTRAINT fk_fct2dim_stores      FOREIGN KEY (store_surr_id)    REFERENCES bl_dm.dim_stores      (store_surr_id),
    CONSTRAINT fk_fct2dim_payments    FOREIGN KEY (payment_surr_id)  REFERENCES bl_dm.dim_payments    (payment_surr_id),
    CONSTRAINT fk_fct2dim_deliveries  FOREIGN KEY (delivery_surr_id) REFERENCES bl_dm.dim_deliveries  (delivery_surr_id),
    CONSTRAINT fk_fct2dim_dates       FOREIGN KEY (date_surr_id)     REFERENCES bl_dm.dim_dates       (date_surr_id)
);
