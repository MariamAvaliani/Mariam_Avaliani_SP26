-- =====================================================================
-- Introduction to DWH and ETL -- Task 6 (3NF layer loading)
-- Script 1 of 3 : DDL -- physical structure of the BL_3NF layer
-- Target RDBMS: PostgreSQL
-- REVISION 2 -- updated to address mentor feedback on Task 3:
--   1. CE_STORE / CE_PRODUCT hierarchies normalized out into their own
--      entities (CE_COUNTRY -> CE_REGION -> CE_STORE,
--      CE_CATEGORY -> CE_SUBCATEGORY -> CE_PRODUCT) instead of storing
--      COUNTRY/REGION/CATEGORY/SUBCATEGORY as flat repeated text.
--   2. CE_DATE trimmed to surrogate key + natural key only -- calendar
--      breakdown (day/month/year/...) is generated later, at BL_DM.
--   3. CE_CUSTOMER (SCD2) key/versioning logic documented explicitly
--      below; see script 3 for how CE_TRANSACTION resolves the correct
--      customer version.
--
-- Run ONCE, at the very beginning (before script 2 and script 3).
-- Safe to re-run: every object is created with IF NOT EXISTS, so running
-- this script again on an already-built schema does nothing and raises
-- no errors. Unlike the staging (SA_) scripts from Task 5, this script
-- never DROPs a table -- BL_3NF holds accumulated SCD2 history for
-- CE_CUSTOMER, and a DROP would silently destroy that history on a
-- re-run.
--
-- Objects created (see "3nf_model_revised.png" for the full ER diagram):
--   Schema  : bl_3nf
--   Tables  : ce_category, ce_subcategory, ce_product
--             ce_country, ce_region, ce_store
--             ce_customer (SCD Type 2), ce_payment, ce_delivery, ce_date
--             ce_transaction (fact)
--   Sequences: one per table, per Naming_Conventions.docx ("Use only
--             SEQUENCES to generate IDs. New sequence for each table.")
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bl_3nf;

-- ---------------------------------------------------------------------
-- Sequences (one per table -- surrogate keys are never generated with
-- SERIAL/IDENTITY, per Naming_Conventions.docx)
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_category;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_subcategory;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_product;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_country;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_region;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_store;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_customer;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_payment;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_delivery;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_date;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_transaction;

-- =======================================================================
-- PRODUCT HIERARCHY: CE_CATEGORY -> CE_SUBCATEGORY -> CE_PRODUCT
-- Previously PRODUCT_CATEGORY / PRODUCT_SUBCATEGORY were flat text on
-- CE_PRODUCT. That is a transitive dependency (SUBCATEGORY depends on
-- CATEGORY, not directly on PRODUCT_ID) and is not proper 3NF. Splitting
-- them into their own entities removes the redundancy; the BL_DM layer
-- flattens the chain back into one denormalized DIM_PRODUCTS row, per
-- the hierarchy pattern in Naming_Conventions.docx.
-- =======================================================================

CREATE TABLE IF NOT EXISTS bl_3nf.ce_category (
    category_sk     BIGINT        NOT NULL,
    category_name   VARCHAR(100)  NOT NULL,   -- natural key
    insert_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system   VARCHAR(30)   NOT NULL,
    source_entity   VARCHAR(50)   NOT NULL,
    source_id       VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_category PRIMARY KEY (category_sk),
    CONSTRAINT uq_ce_category_name UNIQUE (category_name)
);

CREATE TABLE IF NOT EXISTS bl_3nf.ce_subcategory (
    subcategory_sk    BIGINT        NOT NULL,
    subcategory_name  VARCHAR(100)  NOT NULL,   -- natural key (composite with category_sk)
    category_sk       BIGINT        NOT NULL,
    insert_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system     VARCHAR(30)   NOT NULL,
    source_entity     VARCHAR(50)   NOT NULL,
    source_id         VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_subcategory PRIMARY KEY (subcategory_sk),
    CONSTRAINT uq_ce_subcategory_name UNIQUE (subcategory_name, category_sk),
    CONSTRAINT fk_ce_subcategory2category FOREIGN KEY (category_sk) REFERENCES bl_3nf.ce_category (category_sk)
);

CREATE TABLE IF NOT EXISTS bl_3nf.ce_product (
    product_sk       BIGINT         NOT NULL,
    product_id       BIGINT         NOT NULL,   -- natural key
    product_name     VARCHAR(255)   NOT NULL,
    subcategory_sk   BIGINT         NOT NULL,
    product_brand    VARCHAR(100)   NOT NULL,
    product_price    DECIMAL(12,2)  NOT NULL,
    insert_dt        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system    VARCHAR(30)    NOT NULL,
    source_entity    VARCHAR(50)    NOT NULL,
    source_id        VARCHAR(100)   NOT NULL,
    CONSTRAINT pk_ce_product PRIMARY KEY (product_sk),
    CONSTRAINT uq_ce_product_id UNIQUE (product_id),
    CONSTRAINT fk_ce_product2subcategory FOREIGN KEY (subcategory_sk) REFERENCES bl_3nf.ce_subcategory (subcategory_sk)
);

-- =======================================================================
-- LOCATION HIERARCHY: CE_COUNTRY -> CE_REGION -> CE_STORE
-- Previously REGION / COUNTRY were flat text on CE_STORE (same
-- transitive-dependency issue as above: COUNTRY depends on REGION, not
-- directly on STORE_ID). Split into their own entities; BL_DM flattens
-- them back into one denormalized DIM_STORES row.
-- =======================================================================

CREATE TABLE IF NOT EXISTS bl_3nf.ce_country (
    country_sk      BIGINT        NOT NULL,
    country_name    VARCHAR(100)  NOT NULL,   -- natural key
    insert_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system   VARCHAR(30)   NOT NULL,
    source_entity   VARCHAR(50)   NOT NULL,
    source_id       VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_country PRIMARY KEY (country_sk),
    CONSTRAINT uq_ce_country_name UNIQUE (country_name)
);

CREATE TABLE IF NOT EXISTS bl_3nf.ce_region (
    region_sk       BIGINT        NOT NULL,
    region_name     VARCHAR(100)  NOT NULL,   -- natural key (composite with country_sk)
    country_sk      BIGINT        NOT NULL,
    insert_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system   VARCHAR(30)   NOT NULL,
    source_entity   VARCHAR(50)   NOT NULL,
    source_id       VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_region PRIMARY KEY (region_sk),
    CONSTRAINT uq_ce_region_name UNIQUE (region_name, country_sk),
    CONSTRAINT fk_ce_region2country FOREIGN KEY (country_sk) REFERENCES bl_3nf.ce_country (country_sk)
);

CREATE TABLE IF NOT EXISTS bl_3nf.ce_store (
    store_sk        BIGINT        NOT NULL,
    store_id        BIGINT        NOT NULL,   -- natural key
    store_location  VARCHAR(255)  NOT NULL,
    store_type      VARCHAR(50)   NOT NULL,
    region_sk       BIGINT        NOT NULL,
    insert_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system   VARCHAR(30)   NOT NULL,
    source_entity   VARCHAR(50)   NOT NULL,
    source_id       VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_store PRIMARY KEY (store_sk),
    CONSTRAINT uq_ce_store_id UNIQUE (store_id),
    CONSTRAINT fk_ce_store2region FOREIGN KEY (region_sk) REFERENCES bl_3nf.ce_region (region_sk)
);

-- ---------------------------------------------------------------------
-- CE_CUSTOMER (SCD Type 2)
-- Tracked attributes: customer_segment, customer_type, customer_city,
-- loyalty_score, age_group.
--
-- Key / versioning logic (mentor feedback on Task 3, now made explicit):
--   - CUSTOMER_ID is the NATURAL key. It is stable and repeats across
--     every version of the same real-world customer.
--   - CUSTOMER_SK is the SURROGATE key and the table's PK. A NEW value
--     is generated (from seq_ce_customer) every time a tracked attribute
--     changes, so each row = one version of one customer.
--   - At any point in time, exactly one row per CUSTOMER_ID has
--     IS_ACTIVE = 'Y'; all prior versions have IS_ACTIVE = 'N' with
--     END_DT set to the day before the next version's START_DT.
--   - PK is CUSTOMER_SK alone (not a composite of CUSTOMER_ID + START_DT)
--     because CUSTOMER_SK is already unique per version -- see script 3
--     for the SCD2 load logic that maintains this invariant.
-- Per Naming_Conventions.docx, an SCD2 table on the 3NF layer must NEVER
-- have a real FK constraint pointing at it from the fact table -- the
-- relationship to CE_TRANSACTION is logical only, resolved "as of" the
-- transaction date (see script 3).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_3nf.ce_customer (
    customer_sk       BIGINT        NOT NULL,
    customer_id       BIGINT        NOT NULL,
    customer_segment  VARCHAR(50)   NOT NULL,
    customer_type     VARCHAR(50)   NOT NULL,
    customer_city     VARCHAR(100)  NOT NULL,
    loyalty_score     INTEGER       NOT NULL,
    age_group         VARCHAR(30)   NOT NULL,
    start_dt          DATE          NOT NULL,
    end_dt            DATE          NOT NULL,
    is_active         CHAR(1)       NOT NULL,
    insert_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system     VARCHAR(30)   NOT NULL,
    source_entity     VARCHAR(50)   NOT NULL,
    source_id         VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_customer PRIMARY KEY (customer_sk),
    CONSTRAINT ck_ce_customer_is_active CHECK (is_active IN ('Y', 'N'))
);

-- ---------------------------------------------------------------------
-- CE_PAYMENT
-- NOTE (assumption): neither source system provides a dedicated payment
-- business key. Because every transaction has exactly one payment event,
-- payment_id is derived from transaction_id -- the same globally-unique
-- assumption already implied by CE_TRANSACTION.transaction_id itself
-- being used, unqualified, as that table's own natural key.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_3nf.ce_payment (
    payment_sk         BIGINT        NOT NULL,
    payment_id         BIGINT        NOT NULL,
    payment_method     VARCHAR(50)   NOT NULL,
    payment_status     VARCHAR(50)   NOT NULL,
    payment_risk_score INTEGER       NOT NULL,
    insert_dt          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system      VARCHAR(30)   NOT NULL,
    source_entity      VARCHAR(50)   NOT NULL,
    source_id          VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_payment PRIMARY KEY (payment_sk),
    CONSTRAINT uq_ce_payment_id UNIQUE (payment_id)
);

-- ---------------------------------------------------------------------
-- CE_DELIVERY
-- Online (e-commerce) transactions only -- the retail (in-store) channel
-- has no delivery leg. delivery_id is VARCHAR (per the approved 3NF
-- diagram) and, per the same assumption as CE_PAYMENT above, is derived
-- from the online transaction_id.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_3nf.ce_delivery (
    delivery_sk       BIGINT        NOT NULL,
    delivery_id       VARCHAR(50)   NOT NULL,
    delivery_type     VARCHAR(50)   NOT NULL,
    delivery_status   VARCHAR(50)   NOT NULL,
    fulfillment_time  INTEGER       NOT NULL,
    insert_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system     VARCHAR(30)   NOT NULL,
    source_entity     VARCHAR(50)   NOT NULL,
    source_id         VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_delivery PRIMARY KEY (delivery_sk),
    CONSTRAINT uq_ce_delivery_id UNIQUE (delivery_id)
);

-- ---------------------------------------------------------------------
-- CE_DATE
-- Trimmed per mentor feedback: DAY / MONTH / YEAR and any other calendar
-- breakdown are derived attributes and are generated later, only at the
-- BL_DM layer (consistent with how DIM_DATES was already built
-- independently of BL_3NF in Task 4). CE_DATE here holds only the
-- surrogate key and the natural key (FULL_DATE), and is populated with
-- whatever dates are actually observed in the staging data (see script 3).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_3nf.ce_date (
    date_sk     BIGINT     NOT NULL,
    full_date   DATE       NOT NULL,
    insert_dt   TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ce_date PRIMARY KEY (date_sk),
    CONSTRAINT uq_ce_date_full_date UNIQUE (full_date)
);

-- ---------------------------------------------------------------------
-- CE_TRANSACTION (fact table on the 3NF layer)
-- Grain: one row per transaction_id (one retail sale or one online
-- order line), from either source system.
-- Per Naming_Conventions.docx, "All columns ARE NOT NULL, except KPI
-- (Metrics)" -- so the measure columns below are intentionally left
-- nullable; every other column is NOT NULL.
-- No FK constraint on customer_sk -- CE_CUSTOMER is SCD2 (see note on
-- CE_CUSTOMER above). Script 3 resolves it "as of" transaction_date.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bl_3nf.ce_transaction (
    transaction_sk        BIGINT         NOT NULL,
    transaction_id        BIGINT         NOT NULL,
    customer_sk            BIGINT         NOT NULL,   -- logical FK -> ce_customer (SCD2, no DB constraint)
    product_sk             BIGINT         NOT NULL,
    store_sk                BIGINT         NOT NULL,
    payment_sk               BIGINT         NOT NULL,
    delivery_sk               BIGINT         NOT NULL,
    date_sk                   BIGINT         NOT NULL,
    quantity                  INTEGER,        -- KPI / metric: nullable
    unit_price                DECIMAL(12,2),  -- KPI / metric: nullable
    sales_value                DECIMAL(12,2),  -- KPI / metric: nullable
    discount                    DECIMAL(12,2),  -- KPI / metric: nullable
    cost_price                   DECIMAL(12,2),  -- KPI / metric: nullable
    shipping_cost                  DECIMAL(12,2),  -- KPI / metric: nullable
    total_cost                       DECIMAL(12,2),  -- KPI / metric: nullable
    profit                             DECIMAL(12,2),  -- KPI / metric: nullable
    transaction_channel     VARCHAR(20)     NOT NULL,
    insert_dt                TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt                 TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system             VARCHAR(30)      NOT NULL,
    source_entity              VARCHAR(50)      NOT NULL,
    source_id                   VARCHAR(100)     NOT NULL,
    CONSTRAINT pk_ce_transaction PRIMARY KEY (transaction_sk),
    CONSTRAINT uq_ce_transaction_id UNIQUE (transaction_id),
    CONSTRAINT fk_ce_transaction2product  FOREIGN KEY (product_sk)  REFERENCES bl_3nf.ce_product  (product_sk),
    CONSTRAINT fk_ce_transaction2store    FOREIGN KEY (store_sk)    REFERENCES bl_3nf.ce_store    (store_sk),
    CONSTRAINT fk_ce_transaction2payment  FOREIGN KEY (payment_sk)  REFERENCES bl_3nf.ce_payment  (payment_sk),
    CONSTRAINT fk_ce_transaction2delivery FOREIGN KEY (delivery_sk) REFERENCES bl_3nf.ce_delivery (delivery_sk),
    CONSTRAINT fk_ce_transaction2date     FOREIGN KEY (date_sk)     REFERENCES bl_3nf.ce_date     (date_sk)
);
