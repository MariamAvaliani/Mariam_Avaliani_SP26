-- =============================================
-- VIEW: sales_revenue_by_category_qtr
-- =============================================

CREATE OR REPLACE VIEW public.sales_revenue_by_category_qtr AS
SELECT
    c.name AS category_name,
    SUM(p.amount) AS total_revenue
FROM public.payment p
JOIN public.rental r
    ON p.rental_id = r.rental_id
JOIN public.inventory i
    ON r.inventory_id = i.inventory_id
JOIN public.film f
    ON i.film_id = f.film_id
JOIN public.film_category fc
    ON f.film_id = fc.film_id
JOIN public.category c
    ON fc.category_id = c.category_id
WHERE
    EXTRACT(YEAR FROM p.payment_date) = EXTRACT(YEAR FROM CURRENT_DATE)
    AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
GROUP BY c.name
HAVING SUM(p.amount) > 0;


-- Test view

SELECT *
FROM public.sales_revenue_by_category_qtr;


SELECT *
FROM public.sales_revenue_by_category_qtr
WHERE total_revenue > 1000000;


-- =============================================
-- FUNCTION 1:
-- get_sales_revenue_by_category_qtr
-- (FIXED: accepts one DATE parameter)
-- =============================================

CREATE OR REPLACE FUNCTION public.get_sales_revenue_by_category_qtr(
    p_date DATE
)
RETURNS TABLE (
    category_name TEXT,
    total_revenue NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN

    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Date must not be NULL';
    END IF;

    RETURN QUERY
    SELECT
        c.name::TEXT,
        SUM(p.amount)
    FROM public.payment p
    JOIN public.rental r
        ON p.rental_id = r.rental_id
    JOIN public.inventory i
        ON r.inventory_id = i.inventory_id
    JOIN public.film f
        ON i.film_id = f.film_id
    JOIN public.film_category fc
        ON f.film_id = fc.film_id
    JOIN public.category c
        ON fc.category_id = c.category_id
    WHERE
        EXTRACT(YEAR FROM p.payment_date) =
        EXTRACT(YEAR FROM p_date)

        AND

        EXTRACT(QUARTER FROM p.payment_date) =
        EXTRACT(QUARTER FROM p_date)

    GROUP BY c.name
    HAVING SUM(p.amount) > 0;

END;
$$;


-- Test function 1

SELECT *
FROM public.get_sales_revenue_by_category_qtr('2007-02-15');


SELECT *
FROM public.get_sales_revenue_by_category_qtr(NULL);


SELECT *
FROM public.get_sales_revenue_by_category_qtr('2099-01-01');


-- =============================================
-- FUNCTION 2:
-- most_popular_films_by_countries
-- =============================================

CREATE OR REPLACE FUNCTION public.most_popular_films_by_countries(
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
    FROM public.customer cu
    JOIN public.address a
        ON cu.address_id = a.address_id
    JOIN public.city ci
        ON a.city_id = ci.city_id
    JOIN public.country co
        ON ci.country_id = co.country_id
    JOIN public.rental r
        ON cu.customer_id = r.customer_id
    JOIN public.inventory i
        ON r.inventory_id = i.inventory_id
    JOIN public.film f
        ON i.film_id = f.film_id
    JOIN public.language l
        ON f.language_id = l.language_id
    WHERE co.country = ANY(p_countries)
    GROUP BY
        co.country,
        f.title,
        f.rating,
        l.name,
        f.length,
        f.release_year
),
ranked_films AS (
    SELECT *,
           RANK() OVER (
               PARTITION BY country_name
               ORDER BY rental_count DESC
           ) AS rnk
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


-- Test function 2

SELECT *
FROM public.most_popular_films_by_countries(
    ARRAY['Afghanistan', 'Brazil', 'United States']
);


-- =============================================
-- FUNCTION 3:
-- new_movie
-- =============================================

CREATE OR REPLACE FUNCTION public.new_movie(
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

    -- Check title

    IF p_title IS NULL OR TRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be empty';
    END IF;

    -- Prevent duplicates

    IF EXISTS (
        SELECT 1
        FROM public.film
        WHERE LOWER(title) = LOWER(p_title)
    ) THEN
        RAISE EXCEPTION 'Movie "%" already exists', p_title;
    END IF;

    -- Check language

    SELECT language_id
    INTO v_language_id
    FROM public.language
    WHERE LOWER(name) = LOWER(p_language_name)
    LIMIT 1;

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist', p_language_name;
    END IF;

    -- Generate new film_id

    SELECT nextval('public.film_film_id_seq')
    INTO v_film_id;

    -- Insert movie

    INSERT INTO public.film (
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

END;
$$;


-- Test function 3

SELECT public.new_movie('Interstellar');


SELECT public.new_movie(
    'New Film',
    2024,
    'UnknownLang'
);
