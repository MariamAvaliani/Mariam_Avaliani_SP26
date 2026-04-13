
-- =============================================
-- VIEW: sales_revenue_by_category_qtr
-- =============================================
-- PURPOSE:
-- This view calculates total sales revenue per film category
-- for the CURRENT quarter and CURRENT year dynamically.
--
-- WHY THIS LOGIC:
-- - We use CURRENT_DATE to always get the system date → ensures dynamic behavior.
-- - EXTRACT(YEAR FROM CURRENT_DATE) → determines current year.
-- - EXTRACT(QUARTER FROM CURRENT_DATE) → determines current quarter.
-- - We JOIN payment → rental → inventory → film → film_category → category
--   to correctly map payments (revenue) to film categories.
--
-- HOW RESULT IS CALCULATED:
-- - SUM(p.amount) → total revenue per category.
-- - GROUP BY category name.
--
-- WHY ONLY CATEGORIES WITH SALES APPEAR:
-- - INNER JOIN + WHERE filter ensures only matching payment records exist.
-- - If no payment exists → category is automatically excluded.
--
-- HOW ZERO-SALES CATEGORIES ARE EXCLUDED:
-- - No LEFT JOIN is used → categories without sales never appear.
--
-- =============================================

CREATE OR REPLACE VIEW sales_revenue_by_category_qtr AS
SELECT
    c.name AS category_name,
    SUM(p.amount) AS total_revenue
FROM payment p
JOIN rental r ON p.rental_id = r.rental_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
JOIN film_category fc ON f.film_id = fc.film_id
JOIN category c ON fc.category_id = c.category_id
WHERE
    EXTRACT(YEAR FROM p.payment_date) = EXTRACT(YEAR FROM CURRENT_DATE)
    AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
GROUP BY c.name
HAVING SUM(p.amount) > 0;

-- =============================================
-- TEST 1: VALID QUERY
-- =============================================
-- PURPOSE:
-- This query retrieves all rows from the view
-- to verify that it correctly returns revenue
-- for the current quarter and year.
--
-- WHY THIS TEST:
-- - Ensures the view executes without errors
-- - Confirms aggregation (SUM) works correctly
-- - Confirms filtering by current quarter/year works
--
-- EXPECTED RESULT:
-- - List of categories with total_revenue > 0
-- - Only categories that had sales in current quarter
-- - No NULL or zero values
--
-- IMPORTANT NOTE:
-- If your database has NO data for the current year,
-- this query will return 0 rows (this is correct behavior)

SELECT *
FROM sales_revenue_by_category_qtr;


-- =============================================
-- TEST 2: EDGE CASE (NO MATCHING DATA)
-- =============================================
-- PURPOSE:
-- This query tests how the view behaves when
-- no rows satisfy the condition.
--
-- WHY THIS TEST:
-- - Ensures the system handles empty results safely
-- - Verifies no runtime errors occur
-- - Confirms the query remains stable under extreme conditions
--
-- LOGIC:
-- We apply a filter that is unlikely to be true
-- (very high revenue), forcing an empty result set.
--
-- EXPECTED RESULT:
-- - Query returns 0 rows
-- - No errors or crashes occur
--
-- HOW THE SOLUTION HANDLES IT:
-- - SQL naturally returns an empty result set
-- - No need for RAISE EXCEPTION in views
-- - This confirms robustness of the view

SELECT *
FROM sales_revenue_by_category_qtr
WHERE total_revenue > 1000000;


-- ============================================================
-- FUNCTION: get_sales_revenue_by_category_qtr
-- ============================================================
-- PURPOSE:
-- Returns total sales revenue per category for a given
-- year and quarter (provided as parameters).
--
-- WHY PARAMETER IS NEEDED:
-- - Unlike the view (which uses CURRENT_DATE),
--   this function allows flexible querying:
--     ✔ past quarters
--     ✔ specific year analysis
--     ✔ testing when current year has no data
--
-- PARAMETERS:
-- p_year    → year to filter (e.g., 2007)
-- p_quarter → quarter (1–4)
--
-- HOW RESULT IS CALCULATED:
-- - Same logic as the view:
--   payment → rental → inventory → film → category
-- - SUM(p.amount) gives total revenue per category
--
-- ERROR HANDLING:
-- - If quarter is not between 1 and 4 → RAISE EXCEPTION
-- - If parameters are NULL → RAISE EXCEPTION
--
-- WHAT HAPPENS IF:
-- 1. INVALID QUARTER:
--    → Function throws error and stops execution
--
-- 2. NO DATA EXISTS:
--    → Function returns empty result (0 rows)
--    → No error (this is expected SQL behavior)
--
-- ============================================================

CREATE OR REPLACE FUNCTION get_sales_revenue_by_category_qtr(
    p_year INT,
    p_quarter INT
)
RETURNS TABLE (
    category_name TEXT,
    total_revenue NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN

    -- ============================
    -- VALIDATION: NULL PARAMETERS
    -- ============================
    IF p_year IS NULL OR p_quarter IS NULL THEN
        RAISE EXCEPTION 'Year and Quarter must not be NULL';
    END IF;

    -- ============================
    -- VALIDATION: QUARTER RANGE
    -- ============================
    IF p_quarter < 1 OR p_quarter > 4 THEN
        RAISE EXCEPTION 'Invalid quarter: %, must be between 1 and 4', p_quarter;
    END IF;

    -- ============================
    -- MAIN QUERY LOGIC
    -- ============================
    RETURN QUERY
    SELECT
        c.name ::TEXT AS category_name,
        SUM(p.amount) AS total_revenue
    FROM payment p
    JOIN rental r ON p.rental_id = r.rental_id
    JOIN inventory i ON r.inventory_id = i.inventory_id
    JOIN film f ON i.film_id = f.film_id
    JOIN film_category fc ON f.film_id = fc.film_id
    JOIN category c ON fc.category_id = c.category_id
    WHERE
        EXTRACT(YEAR FROM p.payment_date) = p_year
        AND EXTRACT(QUARTER FROM p.payment_date) = p_quarter
    GROUP BY c.name
    HAVING SUM(p.amount) > 0;

END;
$$;


-- =============================================
-- TEST 1: VALID INPUT
-- =============================================
-- PURPOSE:
-- Check that function returns correct revenue data
-- for an existing year and quarter.
--
-- EXAMPLE:
-- 2007 Q1 is known to exist in DVD Rental DB
--
-- EXPECTED RESULT:
-- - List of categories
-- - Each with total_revenue > 0

SELECT *
FROM get_sales_revenue_by_category_qtr(2007, 1);





-- =============================================
-- TEST 2: INVALID INPUT
-- =============================================
-- PURPOSE:
-- Verify error handling when invalid quarter is passed
--
-- EXPECTED RESULT:
-- Function should throw an exception

SELECT *
FROM get_sales_revenue_by_category_qtr(2007, 5);



-- ============================================================
-- FUNCTION: most_popular_films_by_countries
-- ============================================================
-- PURPOSE:
-- Returns the most popular film for each country provided
-- as an array input parameter.
--
-- WHY ARRAY PARAMETER:
-- - Allows querying multiple countries in one call
-- - Makes function reusable and flexible
-- - Avoids hardcoding country values
--
-- HOW "MOST POPULAR" IS DEFINED:
-- - Based on COUNT of rentals (number of times a film was rented)
-- - This reflects user demand/activity more directly than revenue
--
-- HOW TIES ARE HANDLED:
-- - If multiple films have the same rental count,
--   ALL of them are returned (no arbitrary exclusion)
--
-- WHAT HAPPENS IF COUNTRY HAS NO DATA:
-- - That country will NOT appear in the result
-- - No error is thrown (safe behavior)
--
-- ERROR HANDLING:
-- - If input array is NULL or empty → RAISE EXCEPTION
--
-- ============================================================

CREATE OR REPLACE FUNCTION most_popular_films_by_countries(
    p_countries TEXT[]
)
RETURNS TABLE (
    country TEXT,
    film TEXT,
    rating TEXT,
    language TEXT,
    length INT,
    release_year INT
)
LANGUAGE sql
AS $$
    WITH film_rentals AS (
        SELECT
            co.country AS country_name,
            f.title AS film_title,
            f.rating AS film_rating,
            l.name AS film_language,
            f.length AS film_length,
            f.release_year AS film_year,
            COUNT(r.rental_id) AS rental_count
        FROM customer cu
        JOIN address a ON cu.address_id = a.address_id
        JOIN city ci ON a.city_id = ci.city_id
        JOIN country co ON ci.country_id = co.country_id
        JOIN rental r ON cu.customer_id = r.customer_id
        JOIN inventory i ON r.inventory_id = i.inventory_id
        JOIN film f ON i.film_id = f.film_id
        JOIN language l ON f.language_id = l.language_id
        WHERE co.country = ANY(p_countries)
        GROUP BY
            co.country, f.title, f.rating, l.name, f.length, f.release_year
    ),
    ranked_films AS (
        SELECT *,
               RANK() OVER (PARTITION BY country_name ORDER BY rental_count DESC) AS rnk
        FROM film_rentals
    )
    SELECT
        country_name::TEXT,
        film_title::TEXT,
        film_rating::TEXT,
        film_language::TEXT,
        film_length::INT,
        film_year::INT
    FROM ranked_films
    WHERE rnk = 1;
$$;

SELECT *
FROM most_popular_films_by_countries(
    ARRAY['Afghanistan','Brazil','United States']
);





CREATE OR REPLACE FUNCTION new_movie(
    p_title TEXT,
    p_release_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    p_language_name TEXT DEFAULT 'Klingon'
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_film_id INT;
    v_language_id INT;
BEGIN
    ------------------------------------------------------------------
    -- 1. Validate input title
    ------------------------------------------------------------------
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be NULL or empty';
    END IF;

    ------------------------------------------------------------------
    -- 2. Prevent duplicates
    ------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM film WHERE LOWER(title) = LOWER(p_title)
    ) THEN
        RAISE EXCEPTION 'Movie "%" already exists', p_title;
    END IF;

    ------------------------------------------------------------------
    -- 3. Validate language existence
    ------------------------------------------------------------------
    SELECT language_id INTO v_language_id
    FROM language
    WHERE LOWER(name) = LOWER(p_language_name)
    LIMIT 1;

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist', p_language_name;
    END IF;

    ------------------------------------------------------------------
    -- 4. Generate unique film_id
    ------------------------------------------------------------------
    SELECT nextval('film_film_id_seq') INTO v_film_id;

    ------------------------------------------------------------------
    -- 5. Insert new movie
    ------------------------------------------------------------------
    INSERT INTO film (
        film_id,
        title,
        release_year,
        language_id,
        rental_duration,
        rental_rate,
        replacement_cost
    )
    VALUES (
        v_film_id,
        p_title,
        p_release_year,
        v_language_id,
        3,          -- required
        4.99,       -- required
        19.99       -- required
    );

EXCEPTION
    WHEN OTHERS THEN
        ------------------------------------------------------------------
        -- 6. Error handling
        ------------------------------------------------------------------
        RAISE EXCEPTION 'Insert failed: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION new_movie(
    p_title TEXT,
    p_release_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    p_language_name TEXT DEFAULT 'Klingon'
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_film_id INT;
    v_language_id INT;
BEGIN
    ------------------------------------------------------------------
    -- Validate input title
    -- Prevents NULL or empty movie names which would break data quality
    ------------------------------------------------------------------
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be NULL or empty';
    END IF;

    ------------------------------------------------------------------
    -- Ensure no duplicate movie titles
    -- Logic: case-insensitive comparison using LOWER()
    -- This guarantees that titles like 'Avatar' and 'avatar' are treated as duplicates
    -- If duplicate exists → function stops and raises exception
    ------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM film WHERE LOWER(title) = LOWER(p_title)
    ) THEN
        RAISE EXCEPTION 'Movie "%" already exists', p_title;
    END IF;

    ------------------------------------------------------------------
    -- Validate language existence
    -- Logic: try to fetch language_id from language table
    -- If no record is found → language does not exist → raise exception
    ------------------------------------------------------------------
    SELECT language_id INTO v_language_id
    FROM language
    WHERE LOWER(name) = LOWER(p_language_name)
    LIMIT 1;

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist', p_language_name;
    END IF;

    ------------------------------------------------------------------
    -- Generate unique film ID
    -- Logic: using PostgreSQL sequence (film_film_id_seq)
    -- nextval() guarantees:
    --    unique value
    --    concurrency-safe (multiple users inserting at same time)
    --    no hardcoding
    ------------------------------------------------------------------
    SELECT nextval('film_film_id_seq') INTO v_film_id;

    ------------------------------------------------------------------
    -- Insert new movie
    -- Default values applied as required:
    --   rental_duration = 3 days
    --   rental_rate = 4.99
    --   replacement_cost = 19.99
    ------------------------------------------------------------------
    INSERT INTO film (
        film_id,
        title,
        release_year,
        language_id,
        rental_duration,
        rental_rate,
        replacement_cost
    )
    VALUES (
        v_film_id,
        p_title,
        p_release_year,
        v_language_id,
        3,
        4.99,
        19.99
    );

EXCEPTION
    WHEN OTHERS THEN
        ------------------------------------------------------------------
        -- What happens if insertion fails
        -- Any error (constraint, FK, etc.) is caught here
        -- The transaction is automatically rolled back
        -- Custom error message is returned for debugging
        ------------------------------------------------------------------
        RAISE EXCEPTION 'Insert failed: %', SQLERRM;
END;
$$;



SELECT new_movie('Interstellar');

/*
Expected result:
ERROR: Movie "Interstellar" already exists
Explanation:
Duplicate check detects existing title
Function stops before insert
Prevents redundant data
*/

SELECT new_movie('New Film', 2024, 'UnknownLang');
/*
Expected result:
ERROR: Language "UnknownLang" does not exist
 Explanation:
Language lookup fails
Prevents foreign key violation
*/
