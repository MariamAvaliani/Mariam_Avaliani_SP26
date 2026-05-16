
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





	/* =========================
   TASK 3 — UPDATED VERSION
   =========================

Goal:
- Find customers who ranked in the TOP 300
  for EACH year:
      1998, 1999, 2001

- Categorize results by sales channel

- Include only purchases made in the
  corresponding channel

- Use window functions

- Format total sales with 2 decimals
*/
/* =========================
   TASK 3
   =========================

Goal:
- Find TOP 300 customers based on TOTAL sales
  across the years:
      1998, 1999, 2001

- Customers are ranked using the COMBINED
  sales of these years together
  (NOT separately per year)

- After selecting TOP 300 customers,
  show their sales categorized by channel

- Include only purchases made through
  the corresponding channel

- Use window functions

- Format sales with 2 decimal places
*/

WITH customer_channel_sales AS (

    /*---------------------------------
      Step 1:
      Calculate sales per customer
      per channel for required years
    ----------------------------------*/
    SELECT
        s.cust_id,
        c.cust_first_name,
        c.cust_last_name,
        ch.channel_desc,

        SUM(s.amount_sold) AS channel_sales

    FROM sh.sales s

    JOIN sh.customers c
        ON s.cust_id = c.cust_id

    JOIN sh.channels ch
        ON s.channel_id = ch.channel_id

    JOIN sh.times t
        ON s.time_id = t.time_id

    WHERE t.calendar_year IN (1998, 1999, 2001)

    GROUP BY
        s.cust_id,
        c.cust_first_name,
        c.cust_last_name,
        ch.channel_desc
),

customer_total_sales AS (

    /*---------------------------------
      Step 2:
      Calculate TOTAL sales per customer
      across all channels and years
    ----------------------------------*/
    SELECT
        cust_id,

        SUM(channel_sales) AS total_sales

    FROM customer_channel_sales

    GROUP BY cust_id
),

ranked_customers AS (

    /*---------------------------------
      Step 3:
      Rank customers by total sales

      Highest sales = rank 1
    ----------------------------------*/
    SELECT
        cust_id,
        total_sales,

        RANK() OVER (
            ORDER BY total_sales DESC
        ) AS sales_rank

    FROM customer_total_sales
)

-- ===================================
-- Final Report
-- ===================================

SELECT
    ccs.channel_desc,
    ccs.cust_id,
    ccs.cust_first_name,
    ccs.cust_last_name,

    /*
      Show sales only for the
      corresponding channel
    */
    TO_CHAR(
        ccs.channel_sales,
        'FM999999999.00'
    ) AS amount_sold

FROM customer_channel_sales ccs

JOIN ranked_customers rc
    ON ccs.cust_id = rc.cust_id

/*
  Keep only TOP 300 customers
*/
WHERE rc.sales_rank <= 300

ORDER BY
    ccs.channel_desc,
    ccs.channel_sales DESC;



/* =========================
   TASK 4 — WINDOW FUNCTION 
   =========================

Goal:
- Generate sales report for:
    January, February, March 2000
- Regions:
    Europe and Americas
- Display results:
    by month and product category
- Sort alphabetically
- Use window functions
- No crosstab needed

Approach:
- Use conditional aggregation with
  window functions
- Calculate regional sales separately
  for Americas and Europe
*/

WITH sales_data AS (

    /*---------------------------------
      Step 1:
      Collect sales data
    ----------------------------------*/
    SELECT
        t.calendar_month_desc,
        p.prod_category,
        co.country_region,
        s.amount_sold

    FROM sh.sales s

    JOIN sh.products p
        ON s.prod_id = p.prod_id

    JOIN sh.customers c
        ON s.cust_id = c.cust_id

    JOIN sh.countries co
        ON c.country_id = co.country_id

    JOIN sh.times t
        ON s.time_id = t.time_id

    WHERE
        t.calendar_year = 2000
        AND t.calendar_month_number IN (1,2,3)
        AND co.country_region IN ('Americas', 'Europe')
),

regional_sales AS (

    /*---------------------------------
      Step 2:
      Calculate sales per region using
      window functions
    ----------------------------------*/
    SELECT DISTINCT
        calendar_month_desc,
        prod_category,

        SUM(
            CASE
                WHEN country_region = 'Americas'
                THEN amount_sold
                ELSE 0
            END
        ) OVER (
            PARTITION BY
                calendar_month_desc,
                prod_category
        ) AS "Americas SALES",

        SUM(
            CASE
                WHEN country_region = 'Europe'
                THEN amount_sold
                ELSE 0
            END
        ) OVER (
            PARTITION BY
                calendar_month_desc,
                prod_category
        ) AS "Europe SALES"

    FROM sales_data
)

-- ===================================
-- Final Report
-- ===================================

SELECT
    calendar_month_desc,
    prod_category,

    ROUND("Americas SALES", 2)
        AS "Americas SALES",

    ROUND("Europe SALES", 2)
        AS "Europe SALES"

FROM regional_sales

ORDER BY
    calendar_month_desc ASC,
    prod_category ASC;


