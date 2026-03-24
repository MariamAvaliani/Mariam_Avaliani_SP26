/*
Task:
The marketing team needs a list of animation movies between 2017 and 2019 
with rental_rate > 1, sorted alphabetically.
*/

/*
Assumptions:
- schema name is public
- Animation category is identified by category.name = 'Animation'
- rental_rate represents "rate"
*/

/*
Business Logic:
- Filter films by category = Animation
- Filter by release_year between 2017 and 2019
- Filter by rental_rate > 1
- Sort results alphabetically by title
*/

/*
Solution Type: INNER JOIN

JOIN explanation:
- INNER JOIN ensures only matching records across film, film_category, and category
- Non-matching rows are excluded
*/

SELECT 
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film AS f
INNER JOIN public.film_category AS fc 
    ON f.film_id = fc.film_id
INNER JOIN public.category AS c 
    ON fc.category_id = c.category_id
WHERE 
    c.name = 'Animation'
    AND f.release_year BETWEEN 2017 AND 2019
    AND f.rental_rate > 1
ORDER BY f.title ASC;


/*
Task:
Get all Animation movies released between 2017 and 2019 
with rental_rate > 1, sorted alphabetically.
*/

/*
Assumptions:
- Schema name is public
- "Animation" is identified by category.name
- rental_rate represents the "rate"
*/

/*
Business Logic:
- Filter films by release year (2017–2019)
- Filter films with rental_rate > 1
- Keep only films that belong to Animation category
- Sort results alphabetically by title
*/

/*
Subquery Explanation:
- Inner subquery retrieves category_id for 'Animation'
- Middle subquery retrieves film_ids belonging to that category
- Outer query filters films using those film_ids
*/

SELECT 
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film AS f
WHERE 
    f.release_year BETWEEN 2017 AND 2019
    AND f.rental_rate > 1
    AND f.film_id IN (
        SELECT fc.film_id
        FROM public.film_category AS fc
        WHERE fc.category_id = (
            SELECT c.category_id
            FROM public.category AS c
            WHERE c.name = 'Animation'
        )
    )
ORDER BY f.title ASC;

/*
Task:
Get all Animation movies released between 2017 and 2019 
with rental_rate > 1, sorted alphabetically.
*/

/*
Assumptions:
- Schema name is public
- "Animation" is identified by category.name
- rental_rate represents the "rate"
*/

/*
Business Logic:
- First isolate Animation films
- Then filter by year and rental_rate
- Sort alphabetically
*/

/*
CTE Explanation:
- CTE creates a temporary result set (animation_films)
- INNER JOIN ensures only matching records are included
- Improves readability by separating logic into steps
*/

WITH animation_films AS (
    SELECT 
        f.film_id,
        f.title,
        f.release_year,
        f.rental_rate
    FROM public.film AS f
    INNER JOIN public.film_category AS fc 
        ON f.film_id = fc.film_id
    INNER JOIN public.category AS c 
        ON fc.category_id = c.category_id
    WHERE c.name = 'Animation'
)

SELECT 
    title,
    release_year,
    rental_rate
FROM animation_films
WHERE 
    release_year BETWEEN 2017 AND 2019
    AND rental_rate > 1
ORDER BY title ASC;


/*
Task:
Calculate the revenue earned by each store after March 2017 (since April).
Include columns:
- full address (address + address2 as one column)
- revenue
*/

/*
Assumptions:
- Schema name is public
- Revenue is calculated as SUM(payment.amount)
- Payment date determines the time filter
- Stores are linked via staff → store
- Address is built from address.address + address.address2
*/

/*
Business Logic:
- Filter payments from April 1, 2017 onwards
- Map payments → staff → store → address
- Aggregate revenue per store
- Combine address fields into one column
*/

/*
Subquery Explanation:
- Inner subquery filters payments after March 2017
- Outer query aggregates revenue per store
*/

SELECT 
    (a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
    SUM(p.amount) AS revenue
FROM (
    SELECT *
    FROM public.payment
    WHERE payment_date >= '2017-04-01'
) AS p
INNER JOIN public.staff AS s 
    ON p.staff_id = s.staff_id
INNER JOIN public.store AS st 
    ON s.store_id = st.store_id
INNER JOIN public.address AS a 
    ON st.address_id = a.address_id
GROUP BY 
    a.address, a.address2
ORDER BY full_address;


/*
Task:
Calculate the revenue earned by each store after March 2017 (since April).
Include columns:
- full address (address + address2 as one column)
- revenue
*/

/*
Assumptions:
- Schema name is public
- Revenue is calculated as SUM(payment.amount)
- Payment date determines the time filter
- Stores are linked via staff → store
*/

/*
Business Logic:
- First isolate payments after March 2017
- Then join with store and address
- Aggregate revenue per store
*/

/*
CTE Explanation:
- CTE filters relevant payments
- Improves readability by separating filtering step
- INNER JOIN ensures only matching records are included
*/

WITH filtered_payments AS (
    SELECT 
        payment_id,
        amount,
        staff_id
    FROM public.payment
    WHERE payment_date >= '2017-04-01'
)

SELECT 
    (a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
    SUM(fp.amount) AS revenue
FROM filtered_payments AS fp
INNER JOIN public.staff AS s 
    ON fp.staff_id = s.staff_id
INNER JOIN public.store AS st 
    ON s.store_id = st.store_id
INNER JOIN public.address AS a 
    ON st.address_id = a.address_id
GROUP BY 
    a.address, a.address2
ORDER BY full_address;

/*
Task:
Calculate the revenue earned by each store after March 2017 (since April).
Include columns:
- full address (address + address2 as one column)
- revenue
*/

/*
Assumptions:
- Schema name is public
- Revenue = SUM(payment.amount)
- Payment date >= '2017-04-01'
- Store linked via staff → store → address
*/

/*
Business Logic:
- Join payments → staff → store → address
- Filter payments after March 2017
- Aggregate revenue per store
- Concatenate address + address2
*/

/*
JOIN Explanation:
- INNER JOIN ensures only records with matching staff, store, and address are included
- LEFT JOIN not needed, since payments must have staff/store for revenue calculation
- CROSS JOIN not relevant here
*/

SELECT 
    (a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
    SUM(p.amount) AS revenue
FROM public.payment AS p
INNER JOIN public.staff AS s 
    ON p.staff_id = s.staff_id
INNER JOIN public.store AS st 
    ON s.store_id = st.store_id
INNER JOIN public.address AS a 
    ON st.address_id = a.address_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY a.address, a.address2
ORDER BY full_address;

/*
Task:
Show top-5 actors by number of movies (released since 2015) they acted in.
Columns: first_name, last_name, number_of_movies
Sorted by number_of_movies descending
*/

/*
Assumptions:
- Schema name is public
- Only films with release_year >= 2015 are considered
- Actors linked to films via film_actor table
*/

/*
Business Logic:
- Count the number of films per actor
- Filter only films since 2015
- Order by count descending
- Limit to top 5
*/

SELECT 
    a.first_name,
    a.last_name,
    COUNT(f.film_id) AS number_of_movies
FROM public.actor AS a
INNER JOIN public.film_actor AS fa
    ON a.actor_id = fa.actor_id
INNER JOIN public.film AS f
    ON fa.film_id = f.film_id
WHERE f.release_year >= 2015
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY number_of_movies DESC
LIMIT 5;

/*
Task:
Top-5 actors by number of movies since 2015 using subquery
*/

/*
Subquery Explanation:
- Inner subquery counts films per actor
- Outer query selects top 5 ordered by number_of_movies
*/

SELECT 
    first_name,
    last_name,
    number_of_movies
FROM (
    SELECT 
        a.first_name,
        a.last_name,
        COUNT(f.film_id) AS number_of_movies
    FROM public.actor AS a
    INNER JOIN public.film_actor AS fa
        ON a.actor_id = fa.actor_id
    INNER JOIN public.film AS f
        ON fa.film_id = f.film_id
    WHERE f.release_year >= 2015
    GROUP BY a.actor_id, a.first_name, a.last_name
) AS actor_counts
ORDER BY number_of_movies DESC
LIMIT 5;

/*
Task:
Top-5 actors by number of movies since 2015 using CTE
*/

/*
CTE Explanation:
- CTE calculates movie counts per actor
- Main query selects top 5 sorted by number_of_movies
- Improves readability by separating aggregation
*/

WITH actor_movie_counts AS (
    SELECT 
        a.actor_id,
        a.first_name,
        a.last_name,
        COUNT(f.film_id) AS number_of_movies
    FROM public.actor AS a
    INNER JOIN public.film_actor AS fa
        ON a.actor_id = fa.actor_id
    INNER JOIN public.film AS f
        ON fa.film_id = f.film_id
    WHERE f.release_year >= 2015
    GROUP BY a.actor_id, a.first_name, a.last_name
)

SELECT 
    first_name,
    last_name,
    number_of_movies
FROM actor_movie_counts
ORDER BY number_of_movies DESC
LIMIT 5;

/*
Task:
Show number of Drama, Travel, Documentary movies per year

Limitation Explanation:
- Using only JOINs, it is not possible to pivot data into separate columns
- This query returns counts per genre per year as separate rows instead
*/

/*
Task:
Show number of Drama, Travel, Documentary movies per year
Columns:
- release_year
- number_of_drama_movies
- number_of_travel_movies
- number_of_documentary_movies
Sorted by release_year descending
*/

/*
Assumptions:
- Schema name is public
- Genres are identified by category.name
- A film can belong to multiple categories
*/

/*
Business Logic:
- Each film is linked to categories via film_category table
- We join film → film_category → category to identify genre per film
- We filter only Drama, Travel, Documentary categories
- We count number of films per release_year and per genre

- The result represents how many films of each genre were produced each year
- This helps marketing analyze trends and plan genre-specific campaigns
*/

/*
JOIN Explanation:
- INNER JOIN is used to connect film, film_category, and category tables
- INNER JOIN ensures that only films with valid category mappings are included
- Each row in the result represents a film-category combination
*/

/*
Limitation Explanation:
- This JOIN-only solution returns data in row format (one row per genre per year)
- The required output format (separate columns for each genre) is a pivot operation
- SQL JOIN operations cannot transform row values into separate columns

- To achieve the required column format, conditional logic (CASE),
  subqueries, or CTEs would be required

- Therefore, this solution provides correct aggregation but not the exact requested format
*/

SELECT 
    f.release_year,
    c.name AS genre,
    COUNT(f.film_id) AS number_of_movies
FROM public.film AS f
INNER JOIN public.film_category AS fc
    ON f.film_id = fc.film_id
INNER JOIN public.category AS c
    ON fc.category_id = c.category_id
WHERE c.name IN ('Drama','Travel','Documentary')
GROUP BY f.release_year, c.name
ORDER BY f.release_year DESC;

/*
Task:
Show number of Drama, Travel, Documentary movies per year
Columns:
- release_year
- number_of_drama_movies
- number_of_travel_movies
- number_of_documentary_movies
Sorted by release_year descending
*/

/*
Assumptions:
- Schema name is public
- Genres identified by category.name
- A film can belong to multiple categories
*/

/*
Business Logic:
- For each release_year, count number of films in each genre separately
- Use subqueries to calculate counts per genre
- Combine results into one row per year
- Replace NULL values with 0 using COALESCE
*/

/*
Subquery Explanation:
- Each subquery calculates count for a specific genre per year
- Outer query groups by release_year and combines results
- This approach simulates pivoting without using CASE
*/

SELECT 
    f.release_year,

    COALESCE((
        SELECT COUNT(*)
        FROM public.film AS f1
        INNER JOIN public.film_category AS fc1 
            ON f1.film_id = fc1.film_id
        INNER JOIN public.category AS c1 
            ON fc1.category_id = c1.category_id
        WHERE c1.name = 'Drama'
          AND f1.release_year = f.release_year
    ), 0) AS number_of_drama_movies,

    COALESCE((
        SELECT COUNT(*)
        FROM public.film AS f2
        INNER JOIN public.film_category AS fc2 
            ON f2.film_id = fc2.film_id
        INNER JOIN public.category AS c2 
            ON fc2.category_id = c2.category_id
        WHERE c2.name = 'Travel'
          AND f2.release_year = f.release_year
    ), 0) AS number_of_travel_movies,

    COALESCE((
        SELECT COUNT(*)
        FROM public.film AS f3
        INNER JOIN public.film_category AS fc3 
            ON f3.film_id = fc3.film_id
        INNER JOIN public.category AS c3 
            ON fc3.category_id = c3.category_id
        WHERE c3.name = 'Documentary'
          AND f3.release_year = f.release_year
    ), 0) AS number_of_documentary_movies

FROM public.film AS f
GROUP BY f.release_year
ORDER BY f.release_year DESC;

/*
Task:
Show number of Drama, Travel, Documentary movies per year
Columns:
- release_year
- number_of_drama_movies
- number_of_travel_movies
- number_of_documentary_movies
Sorted by release_year descending
*/

/*
Assumptions:
- Schema name is public
- Genres identified by category.name
*/

/*
Business Logic:
- Create separate CTEs for each genre
- Each CTE calculates movie count per year
- Join all CTEs by release_year
- Replace NULL values with 0
*/

/*
CTE Explanation:
- drama_cte, travel_cte, documentary_cte calculate counts independently
- LEFT JOIN combines them into one row per year
- This avoids using CASE while still achieving pivot-like structure
*/

WITH drama_cte AS (
    SELECT 
        f.release_year,
        COUNT(*) AS drama_count
    FROM public.film AS f
    INNER JOIN public.film_category AS fc 
        ON f.film_id = fc.film_id
    INNER JOIN public.category AS c 
        ON fc.category_id = c.category_id
    WHERE c.name = 'Drama'
    GROUP BY f.release_year
),
travel_cte AS (
    SELECT 
        f.release_year,
        COUNT(*) AS travel_count
    FROM public.film AS f
    INNER JOIN public.film_category AS fc 
        ON f.film_id = fc.film_id
    INNER JOIN public.category AS c 
        ON fc.category_id = c.category_id
    WHERE c.name = 'Travel'
    GROUP BY f.release_year
),
documentary_cte AS (
    SELECT 
        f.release_year,
        COUNT(*) AS documentary_count
    FROM public.film AS f
    INNER JOIN public.film_category AS fc 
        ON f.film_id = fc.film_id
    INNER JOIN public.category AS c 
        ON fc.category_id = c.category_id
    WHERE c.name = 'Documentary'
    GROUP BY f.release_year
)

/*
Main query:
- Use all years from film table
- LEFT JOIN each CTE to ensure missing genres appear as NULL
*/

SELECT 
    y.release_year,
    COALESCE(d.drama_count, 0) AS number_of_drama_movies,
    COALESCE(t.travel_count, 0) AS number_of_travel_movies,
    COALESCE(doc.documentary_count, 0) AS number_of_documentary_movies
FROM (
    SELECT DISTINCT release_year
    FROM public.film
) AS y
LEFT JOIN drama_cte AS d 
    ON y.release_year = d.release_year
LEFT JOIN travel_cte AS t 
    ON y.release_year = t.release_year
LEFT JOIN documentary_cte AS doc 
    ON y.release_year = doc.release_year
ORDER BY y.release_year DESC;


/*
Task:
Show top 3 employees who generated the most revenue in 2017
*/

/*
Business Logic:
- Calculate revenue per staff
- Determine last store using MAX(payment_date)
*/

/*
Task:
Show top 3 employees who generated the most revenue in 2017
*/

/*
Business Logic:
- Calculate total revenue per staff in 2017
- Identify the last store based on latest payment_date
- Ensure only one row per staff

CTE:
*/

WITH staff_revenue AS (
    SELECT 
        p.staff_id,
        SUM(p.amount) AS total_revenue
    FROM public.payment AS p
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2007
    GROUP BY p.staff_id
)

SELECT 
    st.first_name,
    st.last_name,

    (
        SELECT s.store_id
        FROM public.payment AS p2
        INNER JOIN public.staff AS s 
            ON p2.staff_id = s.staff_id
        WHERE p2.staff_id = st.staff_id
          AND EXTRACT(YEAR FROM p2.payment_date) = 2007
        ORDER BY p2.payment_date DESC
        LIMIT 1
    ) AS store_id,

    sr.total_revenue

FROM staff_revenue AS sr
INNER JOIN public.staff AS st 
    ON sr.staff_id = st.staff_id

ORDER BY sr.total_revenue DESC
LIMIT 3;


/*
This JOIN-only version can produce duplicates if staff made multiple payments on the same last date
*/

WITH staff_revenue AS (
    SELECT 
        p.staff_id,
        SUM(p.amount) AS total_revenue
    FROM public.payment AS p
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
    GROUP BY p.staff_id
),
last_payment AS (
    SELECT 
        staff_id,
        MAX(payment_date) AS last_payment_date
    FROM public.payment
    WHERE EXTRACT(YEAR FROM payment_date) = 2017
    GROUP BY staff_id
)

SELECT 
    st.first_name,
    st.last_name,
    s.store_id,
    sr.total_revenue
FROM staff_revenue AS sr
INNER JOIN public.staff AS st
    ON sr.staff_id = st.staff_id
INNER JOIN last_payment AS lp
    ON sr.staff_id = lp.staff_id
INNER JOIN public.payment AS p
    ON lp.staff_id = p.staff_id
    AND lp.last_payment_date = p.payment_date   -- problem: multiple payments on same date → duplicates
INNER JOIN public.staff AS s
    ON p.staff_id = s.staff_id
ORDER BY sr.total_revenue DESC
LIMIT 3;



/* subquery */

SELECT
    staff_id,
    (
        SELECT store_id
        FROM inventory i
        WHERE i.inventory_id = (
            SELECT r.inventory_id
            FROM rental r
            WHERE r.rental_id = (
                SELECT p2.rental_id
                FROM payment p2
                WHERE p2.staff_id = p1.staff_id
                  AND p2.payment_date >= '2017-01-01'
                  AND p2.payment_date <  '2018-01-01'
                ORDER BY p2.payment_date DESC
                LIMIT 1
            )
        )
    ) AS last_store_id,
    total_revenue
FROM (
    SELECT
        staff_id,
        SUM(amount) AS total_revenue
    FROM payment
    WHERE payment_date >= '2017-01-01'
      AND payment_date < '2018-01-01'
    GROUP BY staff_id
) p1
ORDER BY total_revenue DESC
LIMIT 3;



/*
Task:
Top 5 most rented movies and expected audience age
Subquery-only,
PostgreSQL-safe
*/

SELECT 
    f.title,

    -- Number of rentals per film
    (
        SELECT COUNT(*)
        FROM public.rental AS r
        INNER JOIN public.inventory AS i
            ON r.inventory_id = i.inventory_id
        WHERE i.film_id = f.film_id
    ) AS number_of_rentals,

    -- Expected audience age using VALUES mapping
    (
        SELECT age_group
        FROM (
            VALUES
                ('G'::mpaa_rating, 'All ages'),
                ('PG'::mpaa_rating, 'Parental guidance suggested'),
                ('PG-13'::mpaa_rating, '13+'),
                ('R'::mpaa_rating, '17+'),
                ('NC-17'::mpaa_rating, '18+')
        ) AS rating_map(rating_code, age_group)
        WHERE rating_map.rating_code = f.rating
        LIMIT 1
    ) AS expected_audience_age

FROM public.film AS f
ORDER BY number_of_rentals DESC NULLS LAST
LIMIT 5;


/*
Task 2: Top 5 most rented movies and expected audience age
CTE solution
- Rentals and rating mapping done in separate CTEs
- NULL-safe
*/

WITH rental_count AS (
    SELECT i.film_id, COUNT(*) AS number_of_rentals
    FROM public.rental AS r
    INNER JOIN public.inventory AS i ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
),
rating_map AS (
    SELECT * FROM (VALUES
        ('G'::mpaa_rating, 'All ages'),
        ('PG'::mpaa_rating, 'Parental guidance suggested'),
        ('PG-13'::mpaa_rating, '13+'),
        ('R'::mpaa_rating, '17+'),
        ('NC-17'::mpaa_rating, '18+')
    ) AS t(rating_code, age_group)
)

SELECT 
    f.title,
    rc.number_of_rentals,
    rm.age_group AS expected_audience_age
FROM public.film AS f
LEFT JOIN rental_count AS rc ON f.film_id = rc.film_id
LEFT JOIN rating_map AS rm ON f.rating = rm.rating_code
ORDER BY rc.number_of_rentals DESC NULLS LAST
LIMIT 5;

/*
Comments:
- rental_count CTE sums number of rentals per film
- rating_map CTE maps MPAA rating to audience age
- LEFT JOIN preserves films with no rentals (number_of_rentals = NULL)
- Top 5 sorted by number_of_rentals DESC
*/

/*
Task 2: Top 5 most rented movies and expected audience age
JOIN-only solution
- No CTE
- Uses LEFT JOINs to calculate rentals and map rating
- NULL-safe
*/

SELECT 
    f.title,
    COUNT(r.rental_id) AS number_of_rentals,
    rm.age_group AS expected_audience_age
FROM public.film AS f
LEFT JOIN public.inventory AS i ON i.film_id = f.film_id
LEFT JOIN public.rental AS r ON r.inventory_id = i.inventory_id
LEFT JOIN (
    VALUES
        ('G'::mpaa_rating, 'All ages'),
        ('PG'::mpaa_rating, 'Parental guidance suggested'),
        ('PG-13'::mpaa_rating, '13+'),
        ('R'::mpaa_rating, '17+'),
        ('NC-17'::mpaa_rating, '18+')
) AS rm(rating_code, age_group) ON f.rating = rm.rating_code
GROUP BY f.film_id, f.title, rm.age_group
ORDER BY number_of_rentals DESC NULLS LAST
LIMIT 5;

/*
Comments:
- LEFT JOIN inventory + rental counts number of rentals per film
- LEFT JOIN rating_map maps film rating to expected audience age
- GROUP BY ensures one row per film
- NULLs preserved if film was never rented or rating is missing
- ORDER BY + LIMIT 5 → Top 5 most rented movies
*/


/*
Task 3 V1: Actor inactivity as gap between latest film and current year
Subquery-only, no CTE
*/

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,

    -- Gap in years between actor's latest film and current year
    EXTRACT(YEAR FROM CURRENT_DATE) - (
        SELECT MAX(f.release_year)
        FROM public.film AS f
        INNER JOIN public.film_actor AS fa
            ON f.film_id = fa.film_id
        WHERE fa.actor_id = a.actor_id
    ) AS inactivity_years

FROM public.actor AS a
ORDER BY inactivity_years DESC NULLS LAST;

/*
Comments:
- Subquery calculates latest release_year for each actor
- EXTRACT(YEAR FROM CURRENT_DATE) - MAX(release_year) gives gap
- NULLs occur if actor never acted in any film
- ORDER BY DESC → actors with longest inactivity first
*/


/*
Task 3 V1: Actor inactivity gap using CTE
*/

WITH latest_film AS (
    SELECT fa.actor_id, MAX(f.release_year) AS latest_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f ON fa.film_id = f.film_id
    GROUP BY fa.actor_id
)

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,
    EXTRACT(YEAR FROM CURRENT_DATE) - lf.latest_year AS inactivity_years
FROM public.actor AS a
LEFT JOIN latest_film AS lf ON a.actor_id = lf.actor_id
ORDER BY inactivity_years DESC NULLS LAST;

/*
Comments:
- latest_film CTE computes latest film release per actor
- LEFT JOIN preserves actors with no films (inactivity_years = NULL)
- Clear, modular structure
*/

/*
Task 3 V1: Actor inactivity using JOIN-only
*/

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,
    EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year) AS inactivity_years
FROM public.actor AS a
LEFT JOIN public.film_actor AS fa ON a.actor_id = fa.actor_id
LEFT JOIN public.film AS f ON fa.film_id = f.film_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY inactivity_years DESC NULLS LAST;

/*
Comments:
- MAX(f.release_year) per actor gives last film
- LEFT JOIN ensures actors with no films are included
- One row per actor
*/

/*
Task 3 V2: Max gap between sequential films per actor
Subquery-only
COALESCE used to replace NULL with 0 for actors with <2 films
*/

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,

    -- Max gap in years between consecutive films; 0 if no or single film
    COALESCE(
        (
            SELECT MAX(f2.release_year - f1.release_year)
            FROM public.film_actor AS fa1
            JOIN public.film_actor AS fa2 
                ON fa1.actor_id = fa2.actor_id
            JOIN public.film AS f1 ON fa1.film_id = f1.film_id
            JOIN public.film AS f2 ON fa2.film_id = f2.film_id
            WHERE fa1.actor_id = a.actor_id
              AND f2.release_year > f1.release_year
        ), 0
    ) AS max_gap_years

FROM public.actor AS a
ORDER BY max_gap_years DESC;

/*
Task 3 V2: Max gap between sequential films per actor
CTE version with COALESCE
*/

WITH actor_films AS (
    SELECT fa.actor_id, f.release_year
    FROM public.film_actor AS fa
    JOIN public.film AS f ON fa.film_id = f.film_id
),
film_gaps AS (
    SELECT af1.actor_id, af2.release_year - af1.release_year AS gap_years
    FROM actor_films AS af1
    JOIN actor_films AS af2
      ON af1.actor_id = af2.actor_id
     AND af2.release_year > af1.release_year
)

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,
    COALESCE(MAX(fg.gap_years), 0) AS max_gap_years
FROM public.actor AS a
LEFT JOIN film_gaps AS fg ON a.actor_id = fg.actor_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY max_gap_years DESC;

/*
Task 3 V2: Max gap between sequential films per actor
JOIN-only version with COALESCE
*/

SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,
    COALESCE(MAX(f2.release_year - f1.release_year), 0) AS max_gap_years
FROM public.actor AS a
LEFT JOIN public.film_actor AS fa1 ON a.actor_id = fa1.actor_id
LEFT JOIN public.film_actor AS fa2 ON a.actor_id = fa2.actor_id
LEFT JOIN public.film AS f1 ON fa1.film_id = f1.film_id
LEFT JOIN public.film AS f2 ON fa2.film_id = f2.film_id AND f2.release_year > f1.release_year
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY max_gap_years DESC;
