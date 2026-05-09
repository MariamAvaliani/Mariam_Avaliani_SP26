--task1
WITH sales_summary AS (
    SELECT
        co.country_region,
        t.calendar_year,
        ch.channel_desc,
        SUM(s.amount_sold) AS amount_sold
    FROM sh.sales s
    JOIN sh.times t
        ON s.time_id = t.time_id
    JOIN sh.customers cu
        ON s.cust_id = cu.cust_id
    JOIN sh.countries co
        ON cu.country_id = co.country_id
    JOIN sh.channels ch
        ON s.channel_id = ch.channel_id
    WHERE t.calendar_year BETWEEN 1999 AND 2001
      AND co.country_region IN ('Americas', 'Asia', 'Europe')
    GROUP BY
        co.country_region,
        t.calendar_year,
        ch.channel_desc
),

percentages AS (
    SELECT
        country_region,
        calendar_year,
        channel_desc,
        amount_sold,

        ROUND(
            100.0 * amount_sold
            / SUM(amount_sold) OVER (
                PARTITION BY country_region, calendar_year
            ),
            2
        ) AS pct_by_channels
    FROM sales_summary
)

SELECT
    country_region,
    calendar_year,
    channel_desc,
    amount_sold,

    pct_by_channels AS "% BY CHANNELS",

    LAG(pct_by_channels) OVER (
        PARTITION BY country_region, channel_desc
        ORDER BY calendar_year
    ) AS "% PREVIOUS PERIOD",

    ROUND(
        pct_by_channels -
        LAG(pct_by_channels) OVER (
            PARTITION BY country_region, channel_desc
            ORDER BY calendar_year
        ),
        2
    ) AS "% DIFF"

FROM percentages

ORDER BY
    country_region ASC,
    calendar_year ASC,
    channel_desc ASC;



--task2
WITH daily_sales AS (
    SELECT
        t.calendar_year,
        t.calendar_week_number,
        t.time_id,
        t.day_name,
        SUM(s.amount_sold) AS amount_sold
    FROM sh.sales s
    JOIN sh.times t
        ON s.time_id = t.time_id
    WHERE t.calendar_year = 1999
      AND t.calendar_week_number IN (49, 50, 51)
    GROUP BY
        t.calendar_year,
        t.calendar_week_number,
        t.time_id,
        t.day_name
),

sales_calc AS (
    SELECT
        calendar_year,
        calendar_week_number,
        time_id,
        day_name,
        amount_sold,

        -- cumulative weekly sum
        SUM(amount_sold) OVER (
            PARTITION BY calendar_week_number
            ORDER BY time_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cum_sum,

        -- centered moving average
        ROUND(
            CASE

                -- Monday: Sat + Sun + Mon + Tue
                WHEN day_name = 'Monday' THEN
                    AVG(amount_sold) OVER (
                        ORDER BY time_id
                        ROWS BETWEEN 2 PRECEDING AND 1 FOLLOWING
                    )

                -- Friday: Thu + Fri + Sat + Sun
                WHEN day_name = 'Friday' THEN
                    AVG(amount_sold) OVER (
                        ORDER BY time_id
                        ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING
                    )

                -- Standard centered 3-day average
                ELSE
                    AVG(amount_sold) OVER (
                        ORDER BY time_id
                        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
                    )
            END,
            2
        ) AS centered_3_day_avg

    FROM daily_sales
)

SELECT
    calendar_year,
    calendar_week_number,
    time_id,
    day_name,
    amount_sold,
    cum_sum AS CUM_SUM,
    centered_3_day_avg AS CENTERED_3_DAY_AVG

FROM sales_calc

ORDER BY
    calendar_week_number,
    time_id;

-- =========================================================
-- TASK 3
-- Examples of Window Functions Using:
-- 1. ROWS
-- 2. RANGE
-- 3. GROUPS
-- =========================================================



-- =========================================================
-- 1. ROWS FRAME
-- =========================================================
-- PURPOSE:
-- Calculate a running total of daily sales.
--
-- WHY ROWS?
-- ROWS works with the physical position of rows.
-- It is ideal for cumulative totals because we want
-- every previous row included up to the current row.
-- =========================================================

SELECT
    t.time_id,
    SUM(s.amount_sold) AS daily_sales,

    -- Running total from first row to current row
    SUM(SUM(s.amount_sold)) OVER (
        ORDER BY t.time_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total

FROM sh.sales s
JOIN sh.times t
    ON s.time_id = t.time_id

WHERE t.calendar_year = 1999

GROUP BY t.time_id

ORDER BY t.time_id;



-- =========================================================
-- 2. RANGE FRAME
-- =========================================================
-- PURPOSE:
-- Calculate sales totals within a logical sales range.
--
-- WHY RANGE?
-- RANGE uses values instead of physical rows.
-- Here, all rows within 1000 units of the current
-- sales amount are included in the frame.
--
-- Useful for:
-- - financial analysis
-- - price bands
-- - salary ranges
-- =========================================================

SELECT
    t.time_id,
    SUM(s.amount_sold) AS daily_sales,

    -- Sum sales for rows within a value range
    SUM(SUM(s.amount_sold)) OVER (
        ORDER BY SUM(s.amount_sold)
        RANGE BETWEEN 1000 PRECEDING AND CURRENT ROW
    ) AS range_based_total

FROM sh.sales s
JOIN sh.times t
    ON s.time_id = t.time_id

WHERE t.calendar_year = 1999

GROUP BY t.time_id

ORDER BY daily_sales;



-- =========================================================
-- 3. GROUPS FRAME
-- =========================================================
-- PURPOSE:
-- Calculate average weekly sales using neighboring groups.
--
-- WHY GROUPS?
-- GROUPS operates on peer groups instead of rows.
-- Here each calendar week represents one group.
--
-- The calculation includes:
-- - previous week
-- - current week
-- - next week
--
-- Useful when multiple rows can share the same
-- ORDER BY value and should be treated together.
-- =========================================================

SELECT
    t.calendar_week_number,
    SUM(s.amount_sold) AS weekly_sales,

    -- Average sales across neighboring week groups
    AVG(SUM(s.amount_sold)) OVER (
        ORDER BY t.calendar_week_number
        GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS avg_neighbor_weeks

FROM sh.sales s
JOIN sh.times t
    ON s.time_id = t.time_id

WHERE t.calendar_year = 1999

GROUP BY t.calendar_week_number

ORDER BY t.calendar_week_number;