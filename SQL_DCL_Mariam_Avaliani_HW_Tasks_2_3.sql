-- =========================================================
-- TASK 2.1 Create user with limited access
-- =========================================================

CREATE USER rentaluser WITH PASSWORD 'rentalpassword';

-- Only allow connection to database
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;


-- =========================================================
-- TASK 2.2 Verify NO access initially (should FAIL)
-- =========================================================

SET ROLE rentaluser;

-- Should fail because SELECT was not granted yet
SELECT * FROM customer;

-- Expected:
-- ERROR: permission denied for table customer


-- =========================================================
-- TASK 2.3 Grant SELECT on customer table
-- =========================================================

RESET ROLE;

GRANT SELECT ON TABLE customer TO rentaluser;


-- =========================================================
-- TASK 2.4 Verify SELECT works (should SUCCESS)
-- =========================================================

SET ROLE rentaluser;

SELECT * FROM customer;

-- Expected:
-- Customers are returned successfully


-- =========================================================
-- TASK 2.5 Create group role and assign user
-- =========================================================

RESET ROLE;

-- Group role
CREATE ROLE rental;

-- Add user to group
GRANT rental TO rentaluser;


-- =========================================================
-- TASK 2.6 Grant INSERT and UPDATE on rental table
-- =========================================================

GRANT INSERT, UPDATE ON TABLE rental TO rental;

-- Needed because rental_id uses sequence
GRANT USAGE, SELECT ON SEQUENCE rental_rental_id_seq TO rental;


-- =========================================================
-- TASK 2.7 Test INSERT (should SUCCESS)
-- IMPORTANT:
-- NO hardcoded IDs → use SELECT dynamically
-- =========================================================

SET ROLE rentaluser;

INSERT INTO rental (
    rental_date,
    inventory_id,
    customer_id,
    return_date,
    staff_id,
    last_update
)
VALUES (
    NOW(),

    -- dynamically get available inventory item
    (
        SELECT inventory_id
        FROM inventory
        ORDER BY inventory_id
        LIMIT 1
    ),

    -- dynamically get existing customer
    (
        SELECT customer_id
        FROM customer
        ORDER BY customer_id
        LIMIT 1
    ),

    NULL,

    -- dynamically get existing staff
    (
        SELECT staff_id
        FROM staff
        ORDER BY staff_id
        LIMIT 1
    ),

    NOW()
);

-- Expected:
-- INSERT 0 1


-- =========================================================
-- TASK 2.8 Test UPDATE (should SUCCESS)
-- =========================================================

UPDATE rental
SET return_date = NOW(),
    last_update = NOW()
WHERE rental_id = (
    SELECT rental_id
    FROM rental
    ORDER BY rental_id
    LIMIT 1
);

-- Expected:
-- UPDATE 1


-- =========================================================
-- TASK 2.9 Revoke INSERT permission
-- =========================================================

RESET ROLE;

REVOKE INSERT ON TABLE rental FROM rental;


-- =========================================================
-- TASK 2.10 Test INSERT again (should FAIL)
-- =========================================================

SET ROLE rentaluser;

INSERT INTO rental (
    rental_date,
    inventory_id,
    customer_id,
    return_date,
    staff_id,
    last_update
)
VALUES (
    NOW(),

    (
        SELECT inventory_id
        FROM inventory
        ORDER BY inventory_id
        LIMIT 1
    ),

    (
        SELECT customer_id
        FROM customer
        ORDER BY customer_id
        LIMIT 1
    ),

    NULL,

    (
        SELECT staff_id
        FROM staff
        ORDER BY staff_id
        LIMIT 1
    ),

    NOW()
);

-- Expected:
-- ERROR: permission denied for table rental


-- =========================================================
-- TASK 2.11 Find customer with rental + payment history
-- =========================================================

RESET ROLE;

SELECT DISTINCT
    c.customer_id,
    c.first_name,
    c.last_name
FROM customer c
JOIN rental r
    ON c.customer_id = r.customer_id
JOIN payment p
    ON c.customer_id = p.customer_id
LIMIT 1;

/*
Example result:

customer_id | first_name | last_name
----------- | ---------- | ----------
459         | Tommy      | Collazo
*/


-- =========================================================
-- TASK 2.12 Create personalized role
-- =========================================================

CREATE ROLE client_tommy_collazo;


-- =========================================================
-- TASK 2.13 Grant SELECT access
-- =========================================================

GRANT SELECT ON rental TO client_tommy_collazo;
GRANT SELECT ON payment TO client_tommy_collazo;


-- =========================================================
-- TASK 2.14 Enable Row-Level Security (RLS)
-- =========================================================

ALTER TABLE rental ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rental_policy_tommy ON rental;

CREATE POLICY rental_policy_tommy
ON rental
FOR SELECT
TO client_tommy_collazo
USING (customer_id = 459);


-- =========================================================
-- OPTIONAL CHECK: Successful access for personalized role
-- =========================================================

SET ROLE client_tommy_collazo;

SELECT *
FROM rental;

-- Expected:
-- Only rows where customer_id = 459 are visible


-- =========================================================
-- OPTIONAL CHECK: Access restriction example
-- =========================================================

SELECT *
FROM rental
WHERE customer_id <> 459;

-- Expected:
-- Returns 0 rows because RLS restricts access
