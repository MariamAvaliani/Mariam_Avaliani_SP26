-- =====================================================================
-- Introduction to DWH and ETL — Task 4 (Business Layer Dimensional Model)
-- DIM_DATES : creation and one-time population script
-- Target RDBMS: PostgreSQL
--
-- Per the task requirements, the date dimension is NOT populated from
-- the BL_3NF layer like the other dimensions. It is created once and
-- populated for the full date range the project needs.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS bl_dm;

DROP TABLE IF EXISTS bl_dm.dim_dates;

CREATE TABLE bl_dm.dim_dates (
    date_surr_id        INTEGER      NOT NULL,   -- surrogate key, format YYYYMMDD
    full_date            DATE         NOT NULL,   -- natural date value
    day_of_month_num     SMALLINT     NOT NULL,
    day_of_week_num       SMALLINT     NOT NULL,   -- 1 = Monday ... 7 = Sunday (ISO)
    day_of_week_desc      VARCHAR(10)  NOT NULL,
    weekend_flag         VARCHAR(1)   NOT NULL,   -- 'Y' / 'N'
    month_num            SMALLINT     NOT NULL,
    month_desc           VARCHAR(10)  NOT NULL,
    quarter_num           SMALLINT     NOT NULL,
    quarter_desc          VARCHAR(2)   NOT NULL,   -- 'Q1'..'Q4'
    year_num              SMALLINT     NOT NULL,
    insert_dt            DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT pk_dim_dates PRIMARY KEY (date_surr_id)
);

-- One default "Not Applicable" row, per the project naming convention
-- (obligatory default row for cases where a date is not available).
INSERT INTO bl_dm.dim_dates
(date_surr_id, full_date, day_of_month_num, day_of_week_num, day_of_week_desc,
 weekend_flag, month_num, month_desc, quarter_num, quarter_desc, year_num, insert_dt)
VALUES
(-1, '1900-01-01', 1, 1, 'n.a.', 'N', 1, 'n.a.', 1, 'NA', 1900, CURRENT_DATE);

-- Populate the dimension for a fixed calendar range.
-- Adjust the two bounds below to match the actual span of your source data.
INSERT INTO bl_dm.dim_dates
(date_surr_id, full_date, day_of_month_num, day_of_week_num, day_of_week_desc,
 weekend_flag, month_num, month_desc, quarter_num, quarter_desc, year_num, insert_dt)
SELECT
    (EXTRACT(YEAR FROM d)::INT * 10000
        + EXTRACT(MONTH FROM d)::INT * 100
        + EXTRACT(DAY FROM d)::INT)                              AS date_surr_id,
    d::DATE                                                       AS full_date,
    EXTRACT(DAY FROM d)::SMALLINT                                 AS day_of_month_num,
    EXTRACT(ISODOW FROM d)::SMALLINT                              AS day_of_week_num,
    TO_CHAR(d, 'Dy')                                              AS day_of_week_desc,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'Y' ELSE 'N' END AS weekend_flag,
    EXTRACT(MONTH FROM d)::SMALLINT                               AS month_num,
    TO_CHAR(d, 'Mon')                                             AS month_desc,
    EXTRACT(QUARTER FROM d)::SMALLINT                             AS quarter_num,
    'Q' || EXTRACT(QUARTER FROM d)::INT                           AS quarter_desc,
    EXTRACT(YEAR FROM d)::SMALLINT                                AS year_num,
    CURRENT_DATE                                                  AS insert_dt
FROM generate_series('2015-01-01'::DATE, '2030-12-31'::DATE, INTERVAL '1 day') AS d;

-- Sanity checks -------------------------------------------------------
-- Row count should equal (number of calendar days in range) + 1 default row
SELECT COUNT(*) AS total_rows FROM bl_dm.dim_dates;

-- Grain check: date_surr_id must be unique
SELECT date_surr_id, COUNT(*)
FROM bl_dm.dim_dates
GROUP BY date_surr_id
HAVING COUNT(*) > 1;
