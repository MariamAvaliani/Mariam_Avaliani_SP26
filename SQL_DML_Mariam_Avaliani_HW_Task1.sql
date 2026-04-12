-- =======================
-- TASK 1: INSERT FILMS
-- =======================
BEGIN;

INSERT INTO public.film (title, rental_rate, rental_duration, language_id, last_update)
SELECT title, rental_rate, rental_duration, l.language_id, CURRENT_DATE
FROM (
    SELECT 'Pirates of the Caribbean: On Stranger Tides' AS title, 4.99, 7
    UNION ALL
    SELECT 'Interstellar', 9.99, 14
    UNION ALL
    SELECT 'The Devil Wears Prada', 19.99, 21
) AS new_films(title, rental_rate, rental_duration)
CROSS JOIN (
    SELECT language_id FROM public.language WHERE name = 'English'
) l
WHERE NOT EXISTS (
    SELECT 1 FROM public.film f WHERE f.title = new_films.title
)
RETURNING film_id, title;

COMMIT;


-- =======================
-- INSERT ACTORS
-- =======================
BEGIN;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT *
FROM (
    SELECT 'Matthew', 'McConaughey', CURRENT_DATE
    UNION ALL
    SELECT 'Anne', 'Hathaway', CURRENT_DATE
    UNION ALL
    SELECT 'Meryl', 'Streep', CURRENT_DATE
    UNION ALL
    SELECT 'Johnny', 'Depp', CURRENT_DATE
    UNION ALL
    SELECT 'Emily', 'Blunt', CURRENT_DATE
    UNION ALL
    SELECT 'Orlando', 'Bloom', CURRENT_DATE
) AS new_actors (first_name, last_name, last_update)
WHERE NOT EXISTS (
    SELECT 1 FROM public.actor a
    WHERE a.first_name = new_actors.first_name
      AND a.last_name = new_actors.last_name
)
RETURNING actor_id;

COMMIT;


-- =======================
-- LINK ACTORS TO FILMS (FIXED)
-- =======================
BEGIN;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM public.actor a
JOIN public.film f ON (
    (a.first_name = 'Matthew' AND a.last_name = 'McConaughey' AND f.title = 'Interstellar') OR
    (a.first_name = 'Anne' AND a.last_name = 'Hathaway' AND f.title = 'Interstellar') OR
    (a.first_name = 'Meryl' AND a.last_name = 'Streep' AND f.title = 'The Devil Wears Prada') OR
    (a.first_name = 'Emily' AND a.last_name = 'Blunt' AND f.title = 'The Devil Wears Prada') OR
    (a.first_name = 'Johnny' AND a.last_name = 'Depp' AND f.title = 'Pirates of the Caribbean: On Stranger Tides') OR
    (a.first_name = 'Orlando' AND a.last_name = 'Bloom' AND f.title = 'Pirates of the Caribbean: On Stranger Tides')
)
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor fa
    WHERE fa.actor_id = a.actor_id
      AND fa.film_id = f.film_id
);

COMMIT;


-- =======================
-- INSERT INVENTORY (FIXED store_id)
-- =======================
BEGIN;

INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id,
       (SELECT store_id FROM store ORDER BY store_id LIMIT 1),
       CURRENT_DATE
FROM public.film f
WHERE f.title IN (
    'Interstellar',
    'The Devil Wears Prada',
    'Pirates of the Caribbean: On Stranger Tides'
)
AND NOT EXISTS (
    SELECT 1 FROM public.inventory i
    WHERE i.film_id = f.film_id
      AND i.store_id = (SELECT store_id FROM store ORDER BY store_id LIMIT 1)
)
RETURNING inventory_id;

COMMIT;


-- =======================
-- UPDATE CUSTOMER (FIXED store_id & address_id)
-- =======================
BEGIN;

WITH eligible_customer AS (
    SELECT c.customer_id
    FROM customer c
    JOIN rental r ON c.customer_id = r.customer_id
    JOIN payment p ON c.customer_id = p.customer_id
    GROUP BY c.customer_id
    HAVING COUNT(DISTINCT r.rental_id) >= 43
       AND COUNT(DISTINCT p.payment_id) >= 43
    LIMIT 1
)

UPDATE customer
SET
    first_name = 'Mariam',
    last_name = 'Avaliani',
    email = 'mariamavaliani0217@gmail.com',
    store_id = (SELECT store_id FROM store ORDER BY store_id LIMIT 1),
    address_id = (SELECT address_id FROM address ORDER BY address_id LIMIT 1),
    active = 1,
    last_update = CURRENT_DATE
WHERE customer_id = (SELECT customer_id FROM eligible_customer)
RETURNING customer_id;

COMMIT;


-- =======================
-- DELETE OLD PAYMENTS & RENTALS
-- =======================
BEGIN;

DELETE FROM payment
WHERE customer_id = (
    SELECT customer_id
    FROM customer
    WHERE first_name = 'Mariam'
      AND last_name = 'Avaliani'
    LIMIT 1
);

DELETE FROM rental
WHERE customer_id = (
    SELECT customer_id
    FROM customer
    WHERE first_name = 'Mariam'
      AND last_name = 'Avaliani'
    LIMIT 1
);

COMMIT;


-- =======================
-- RENT MOVIES + PAYMENTS (FIXED staff_id)
-- =======================
BEGIN;

INSERT INTO rental (inventory_id, customer_id, rental_date, staff_id, last_update)
SELECT i.inventory_id,
       c.customer_id,
       '2017-01-10'::date,
       (SELECT staff_id FROM staff ORDER BY staff_id LIMIT 1),
       CURRENT_DATE
FROM inventory i
JOIN film f ON f.film_id = i.film_id
JOIN customer c ON c.first_name = 'Mariam' AND c.last_name = 'Avaliani'
WHERE f.title IN (
    'Pirates of the Caribbean: On Stranger Tides',
    'Interstellar',
    'The Devil Wears Prada'
)
AND NOT EXISTS (
    SELECT 1 FROM rental r
    WHERE r.inventory_id = i.inventory_id
      AND r.customer_id = c.customer_id
);

-- PAYMENTS
INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT c.customer_id,
       (SELECT staff_id FROM staff ORDER BY staff_id LIMIT 1),
       r.rental_id,
       v.rate,
       '2017-01-15'::date
FROM rental r
JOIN inventory i ON i.inventory_id = r.inventory_id
JOIN film f ON f.film_id = i.film_id
JOIN customer c ON c.customer_id = r.customer_id
JOIN (VALUES 
    ('Pirates of the Caribbean: On Stranger Tides', 4.99),
    ('Interstellar', 9.99),
    ('The Devil Wears Prada', 19.99)
) AS v(title, rate) ON f.title = v.title
WHERE c.first_name = 'Mariam'
  AND c.last_name = 'Avaliani'
  AND NOT EXISTS (
      SELECT 1 FROM payment p WHERE p.rental_id = r.rental_id
);

COMMIT;
/*
Why a separate transaction is used

Each BEGIN ... COMMIT block isolates a logical subtask:

Inserting films
Inserting actors
Adding inventories
Updating the customer
Deleting old rentals/payments
Inserting new rentals and payments

Reason: If one subtask fails, it does not affect other subtasks. For example, if inserting actors fails, your films and inventory remain intact. This makes the script safe and modular.
*/
 

/*What would happen if the transaction fails
If any error occurs inside a BEGIN ... COMMIT block, all changes within that block are rolled back automatically.
For example, if the payment insert fails, no partial payments are stored, and the database remains consistent.
Other transactions already committed (like films or actors) are not affected, because each subtask is in its own transaction.*/


/*Rollback is possible for each transaction.

If a transaction fails, all changes made within that transaction are undone, but changes in other transactions are not affected.

Insert films → only film table is affected
Insert actors → only actor table is affected
Insert inventory → only inventory table is affected
Update customer → only customer table is affected
Delete rentals/payments → only rental and payment tables are affected
Rent movies & insert payments → only rental and payment tables are affected

All other tables stay unchanged, so the script can be safely run again without risk of data loss.*/


/*How referential integrity is preserved
Rental → inventory, customer: Rentals are only inserted for existing inventory_id and customer_id.
Payment → rental, customer: Payments reference existing rental_id and customer_id.
Inventory → film: Inventories are only added for existing film_id.
Actors → film_actor (not shown here but done elsewhere): Only valid actor_id and film_id would be linked.

All foreign keys are respected, so there are no orphan records.*/



/*How the script avoids duplicates
WHERE NOT EXISTS checks before inserting:
Films: avoids inserting the same title twice
Actors: avoids inserting the same first + last name combination
Inventory: avoids duplicating inventory for the same film_id in the same store
Rentals: avoids renting the same movie to the same customer on the same date
Payments: avoids creating multiple payments for the same rental
Using RETURNING allows you to capture IDs dynamically instead of hardcoding them, which further prevents mismatched inserts.*/

/*Actors → film_actor: Actors are explicitly linked to films in this script using valid actor_id and film_id.*/
    



