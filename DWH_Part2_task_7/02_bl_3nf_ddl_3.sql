\timing on
-- =====================================================================
-- BL_3NF DDL -- REVISION 3
-- Incorporates mentor feedback (Kseniya Lazarchik) on the Task
-- 3/6 PR, applied here because Task 7's BL_CL procedures load directly
-- into these tables:
--
--   (g) CE_DATE removed entirely -- date is not a business entity;
--       CE_TRANSACTION now carries a plain transaction_date column and
--       DIM_DATES continues to be built independently, directly at
--       BL_DM (as it already was, since Task 4).
--   (e) "source-based uniqueness must use the source triplet, not a
--       raw id assumed globally unique": CE_TRANSACTION, CE_PAYMENT and
--       CE_DELIVERY natural-key uniqueness is now composite
--       (source_system, <id>) instead of a bare id. PAYMENT_ID and
--       DELIVERY_ID are synthetic (both source systems number their own
--       transactions from 1 independently, so an unqualified id is not
--       actually safe to assume globally unique -- this is deliberately
--       demonstrated with overlapping id ranges in the test data, see
--       the Task 7 document). PRODUCT_ID / STORE_ID / CUSTOMER_ID are
--       kept as global natural keys -- they are a genuinely shared,
--       conformed catalog/customer-master by explicit design assumption
--       (stated here, not left implicit), checked in testing (Task 7,
--       section "Data-quality check").
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bl_3nf;

CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_category;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_subcategory;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_product;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_country;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_region;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_store;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_customer;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_payment;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_delivery;
CREATE SEQUENCE IF NOT EXISTS bl_3nf.seq_ce_transaction;
-- seq_ce_date dropped (CE_DATE removed, point g)

CREATE TABLE IF NOT EXISTS bl_3nf.ce_category (
    category_sk     BIGINT        NOT NULL,
    category_name   VARCHAR(100)  NOT NULL,
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
    subcategory_name  VARCHAR(100)  NOT NULL,
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
    product_id       BIGINT         NOT NULL,
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
    CONSTRAINT uq_ce_product_id UNIQUE (product_id),  -- global conformed catalog (explicit assumption, see header)
    CONSTRAINT fk_ce_product2subcategory FOREIGN KEY (subcategory_sk) REFERENCES bl_3nf.ce_subcategory (subcategory_sk)
);

CREATE TABLE IF NOT EXISTS bl_3nf.ce_country (
    country_sk      BIGINT        NOT NULL,
    country_name    VARCHAR(100)  NOT NULL,
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
    region_name     VARCHAR(100)  NOT NULL,
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
    store_id        BIGINT        NOT NULL,
    store_location  VARCHAR(255)  NOT NULL,
    store_type      VARCHAR(50)   NOT NULL,
    region_sk       BIGINT        NOT NULL,
    insert_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system   VARCHAR(30)   NOT NULL,
    source_entity   VARCHAR(50)   NOT NULL,
    source_id       VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_store PRIMARY KEY (store_sk),
    CONSTRAINT uq_ce_store_id UNIQUE (store_id),  -- global conformed store master (explicit assumption)
    CONSTRAINT fk_ce_store2region FOREIGN KEY (region_sk) REFERENCES bl_3nf.ce_region (region_sk)
);

-- CE_CUSTOMER (SCD Type 2). start_dt/end_dt are now driven by the actual
-- source transaction_date that revealed the change (point f), not by
-- CURRENT_DATE / load date -- see bl_cl.load_ce_customer().
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

-- CE_PAYMENT -- uniqueness now (source_system, payment_id): point (e)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_payment (
    payment_sk         BIGINT        NOT NULL,
    payment_id         BIGINT        NOT NULL,
    payment_method     VARCHAR(50)   NOT NULL,
    payment_status     VARCHAR(50)   NOT NULL,
    payment_risk_score INTEGER       NOT NULL,
    insert_dt          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system      VARCHAR(30)   NOT NULL,
    source_entity       VARCHAR(50)  NOT NULL,
    source_id          VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_payment PRIMARY KEY (payment_sk),
    CONSTRAINT uq_ce_payment_srctriplet UNIQUE (source_system, payment_id)
);

-- CE_DELIVERY -- uniqueness now (source_system, delivery_id): point (e)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_delivery (
    delivery_sk       BIGINT        NOT NULL,
    delivery_id       VARCHAR(50)   NOT NULL,
    delivery_type     VARCHAR(50)   NOT NULL,
    delivery_status   VARCHAR(50)   NOT NULL,
    fulfillment_time  INTEGER       NOT NULL,
    insert_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system     VARCHAR(30)   NOT NULL,
    source_entity      VARCHAR(50)  NOT NULL,
    source_id         VARCHAR(100)  NOT NULL,
    CONSTRAINT pk_ce_delivery PRIMARY KEY (delivery_sk),
    CONSTRAINT uq_ce_delivery_srctriplet UNIQUE (source_system, delivery_id)
);

-- CE_DATE removed entirely (point g) -- see header note.

-- CE_TRANSACTION (fact table). transaction_date now stored directly
-- (no date_sk / CE_DATE FK, point g). Uniqueness now
-- (source_system, transaction_id) instead of a bare transaction_id
-- (point e) -- see the Task 7 document for why this specific fix
-- matters (retail and online each number their own transactions from 1).
CREATE TABLE IF NOT EXISTS bl_3nf.ce_transaction (
    transaction_sk        BIGINT         NOT NULL,
    transaction_id        BIGINT         NOT NULL,
    customer_sk           BIGINT         NOT NULL,   -- logical FK -> ce_customer (SCD2, no DB constraint)
    product_sk             BIGINT         NOT NULL,
    store_sk                BIGINT         NOT NULL,
    payment_sk                BIGINT       NOT NULL,
    delivery_sk                BIGINT      NOT NULL,
    transaction_date            DATE       NOT NULL,
    quantity                  INTEGER,
    unit_price                DECIMAL(12,2),
    sales_value                DECIMAL(12,2),
    discount                    DECIMAL(12,2),
    cost_price                   DECIMAL(12,2),
    shipping_cost                  DECIMAL(12,2),
    total_cost                       DECIMAL(12,2),
    profit                             DECIMAL(12,2),
    transaction_channel     VARCHAR(20)     NOT NULL,
    insert_dt                TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_dt                 TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_system             VARCHAR(30)      NOT NULL,
    source_entity              VARCHAR(50)      NOT NULL,
    source_id                   VARCHAR(100)     NOT NULL,
    CONSTRAINT pk_ce_transaction PRIMARY KEY (transaction_sk),
    CONSTRAINT uq_ce_transaction_srctriplet UNIQUE (source_system, transaction_id),
    CONSTRAINT fk_ce_transaction2product  FOREIGN KEY (product_sk)  REFERENCES bl_3nf.ce_product  (product_sk),
    CONSTRAINT fk_ce_transaction2store    FOREIGN KEY (store_sk)    REFERENCES bl_3nf.ce_store    (store_sk),
    CONSTRAINT fk_ce_transaction2payment  FOREIGN KEY (payment_sk)  REFERENCES bl_3nf.ce_payment  (payment_sk),
    CONSTRAINT fk_ce_transaction2delivery FOREIGN KEY (delivery_sk) REFERENCES bl_3nf.ce_delivery (delivery_sk)
);
