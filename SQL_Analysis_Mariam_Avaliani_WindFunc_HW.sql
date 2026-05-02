
/*task 1*/
/* 
We solve this using window functions because we need:
1. Ranking customers within each channel (Top 5 per channel)
2. Total sales per channel (for percentage calculation)

We avoid window frames as requested.
*/

WITH customer_channel_sales AS (
    -- Step 1: Calculate total sales per customer per channel
    SELECT
        ch.channel_desc,
        c.cust_id,
        c.cust_first_name,
        c.cust_last_name,
        SUM(s.amount_sold) AS total_sales
    FROM sh.sales s
    JOIN sh.customers c ON s.cust_id = c.cust_id
    JOIN sh.channels ch ON s.channel_id = ch.channel_id
    GROUP BY ch.channel_desc, c.cust_id, c.cust_first_name, c.cust_last_name
),

channel_totals AS (
    -- Step 2: Total sales per channel (needed for KPI calculation)
    SELECT
        channel_desc,
        SUM(total_sales) AS channel_total_sales
    FROM customer_channel_sales
    GROUP BY channel_desc
),

ranked_customers AS (
    -- Step 3: Rank customers within each channel
    SELECT
        ccs.*,
        ct.channel_total_sales,
        RANK() OVER (
            PARTITION BY ccs.channel_desc
            ORDER BY ccs.total_sales DESC
        ) AS rnk
    FROM customer_channel_sales ccs
    JOIN channel_totals ct
        ON ccs.channel_desc = ct.channel_desc
)

-- Final output
SELECT
    channel_desc,
    cust_id,
    cust_first_name,
    cust_last_name,

    -- format total sales with 2 decimal places
    TO_CHAR(total_sales, 'FM999999999.00') AS total_sales,

    -- KPI: sales percentage within channel
    TO_CHAR(
        (total_sales / channel_total_sales) * 100,
        'FM999999990.0000'
    ) || '%' AS sales_percentage

FROM ranked_customers
WHERE rnk <= 5
ORDER BY channel_desc, total_sales DESC;

/*task 2*/
/*
We use crosstab(text, text) as defined in PostgreSQL documentation.

Goal:
- Show sales per product (Photo category)
- Filter: Asia region, year 2000
- Break sales into quarters (Q1–Q4)
- Compute yearly total (YEAR_SUM)
- No window frames allowed → we use aggregation only
*/

SELECT
    product_name,

    -- Replace NULLs with 0 for cleaner output
    COALESCE(q1, 0) AS q1,
    COALESCE(q2, 0) AS q2,
    COALESCE(q3, 0) AS q3,
    COALESCE(q4, 0) AS q4,

    /*
    YEAR_SUM = total yearly sales per product
    We compute it manually (NOT using window functions)
    because window frames are not allowed.
    */
    COALESCE(q1,0)
  + COALESCE(q2,0)
  + COALESCE(q3,0)
  + COALESCE(q4,0) AS year_sum

FROM crosstab(

    /*
    ============================
    SOURCE QUERY (row source)
    ============================

    Must return exactly 3 columns:
    1. row_name   → product_name
    2. category   → quarter (1–4)
    3. value      → sales amount
    */
    $$
    SELECT
        p.prod_name AS product_name,

        /*
        We use calendar_quarter_number because:
        - SH schema already provides quarter logic
        - avoids incorrect date parsing errors
        - guarantees values 1–4
        */
        t.calendar_quarter_number AS quarter,

        -- total sales per product per quarter
        SUM(s.amount_sold) AS sales

    FROM sh.sales s

    -- join product dimension (to filter Photo category)
    JOIN sh.products p ON s.prod_id = p.prod_id

    -- join customers → countries (to filter Asia region)
    JOIN sh.customers c ON s.cust_id = c.cust_id
    JOIN sh.countries co ON c.country_id = co.country_id

    -- time dimension (for year and quarter filtering)
    JOIN sh.times t ON s.time_id = t.time_id

    WHERE
        -- filter only Photo products
        p.prod_category = 'Photo'

        -- filter only Asia region
        AND co.country_region = 'Asia'

        -- filter only year 2000
        AND t.calendar_year = 2000

    /*
    Grouping is required because we aggregate sales
    per product per quarter.
    */
    GROUP BY
        p.prod_name,
        t.calendar_quarter_number

    /*
    ORDER BY is REQUIRED by crosstab:
    ensures correct grouping of row_name and category
    */
    ORDER BY 1,2
    $$,

    /*
    ============================
    CATEGORY QUERY (columns)
    ============================

    Defines fixed output columns:
    Q1, Q2, Q3, Q4
    */
    $$
    SELECT generate_series(1,4)
    $$

)

-- Define output structure (required by PostgreSQL)
AS ct (
    product_name TEXT,
    q1 NUMERIC,
    q2 NUMERIC,
    q3 NUMERIC,
    q4 NUMERIC
)

-- Final sorting: highest yearly sales first
ORDER BY year_sum DESC;


/*task 3*/
/*
We avoid window functions completely (requirement).
Instead we:
1. compute total sales per customer per year per channel
2. find top 300 customers using ORDER BY + LIMIT logic
3. join back to original data for final reporting
*/

WITH base_sales AS (
    /*
    Step 1: raw sales aggregated per customer, channel, year
    */
    SELECT
        s.cust_id,
        c.cust_last_name,
        c.cust_first_name,
        ch.channel_desc,
        t.calendar_year,
        SUM(s.amount_sold) AS amount_sold
    FROM sh.sales s
    JOIN sh.customers c ON s.cust_id = c.cust_id
    JOIN sh.channels ch ON s.channel_id = ch.channel_id
    JOIN sh.times t ON s.time_id = t.time_id
    WHERE t.calendar_year IN (1998, 1999, 2001)
    GROUP BY
        s.cust_id,
        c.cust_last_name,
        c.cust_first_name,
        ch.channel_desc,
        t.calendar_year
),

top_customers AS (
    /*
    Step 2: select TOP 300 customers per year based on total sales
    (no window functions → we use aggregation + ordering trick)
    */
    SELECT DISTINCT cust_id, calendar_year
    FROM (
        SELECT
            cust_id,
            calendar_year,
            SUM(amount_sold) AS total_year_sales
        FROM base_sales
        GROUP BY cust_id, calendar_year
        ORDER BY total_year_sales DESC
        LIMIT 300
    ) ranked
)

-- Step 3: final report
SELECT
    b.channel_desc,
    b.cust_id,
    b.cust_last_name,
    b.cust_first_name,

    -- formatted sales per channel
    TO_CHAR(SUM(b.amount_sold), 'FM999999999.00') AS amount_sold

FROM base_sales b
JOIN top_customers tc
    ON b.cust_id = tc.cust_id
    AND b.calendar_year = tc.calendar_year

GROUP BY
    b.channel_desc,
    b.cust_id,
    b.cust_last_name,
    b.cust_first_name

ORDER BY
    b.channel_desc,
    amount_sold DESC;


/*task 4*/
/*
Goal:
- Months: Jan, Feb, Mar 2000
- Regions: Europe + Americas
- Group by: month + product category
- Pivot regions into columns (Americas, Europe)

We use crosstab because we need:
row → month + category
columns → regions
values → sales
*/

SELECT
    calendar_month_desc,
    prod_category,

    COALESCE("Americas", 0) AS "Americas SALES",
    COALESCE("Europe", 0) AS "Europe SALES"

FROM crosstab(

$$
/*
SOURCE QUERY:
Must return 3 columns:
1) row identifier (month + category)
2) category (region)
3) value (sales)
*/
SELECT
    t.calendar_month_desc AS row_name,
    p.prod_category,
    co.country_region AS region,
    SUM(s.amount_sold) AS sales

FROM sh.sales s
JOIN sh.products p ON s.prod_id = p.prod_id
JOIN sh.customers c ON s.cust_id = c.cust_id
JOIN sh.countries co ON c.country_id = co.country_id
JOIN sh.times t ON s.time_id = t.time_id

WHERE
    t.calendar_year = 2000
    AND t.calendar_month_number IN (1,2,3)
    AND co.country_region IN ('Americas', 'Europe')

GROUP BY
    t.calendar_month_desc,
    p.prod_category,
    co.country_region

ORDER BY 1,2,3
$$,

$$
-- CATEGORY QUERY defines output columns order
SELECT unnest(ARRAY['Americas','Europe'])
$$

) AS ct (
    calendar_month_desc TEXT,
    prod_category TEXT,
    "Americas" NUMERIC,
    "Europe" NUMERIC
)

ORDER BY
    calendar_month_desc ASC,
    prod_category ASC;


