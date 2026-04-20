-- =========================================
-- TASK 2.1: Create user with limited access
-- =========================================

-- Create user
CREATE USER rentaluser WITH PASSWORD 'rentalpassword';

-- Allow only connection to database
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;


-- =========================================
-- TASK 2.2: Verify NO access initially (should FAIL)
-- =========================================

SET ROLE rentaluser;

-- This should fail because no SELECT permission yet
SELECT * FROM customer;

-- Expected:
-- ERROR: permission denied for table customer


-- =========================================
-- TASK 2.3: Grant SELECT on customer table
-- =========================================

RESET ROLE;

GRANT SELECT ON TABLE customer TO rentaluser;


-- =========================================
-- TASK 2.4: Verify SELECT works (should SUCCESS)
-- =========================================

SET ROLE rentaluser;

SELECT * FROM customer;

-- Expected:
-- Table data is returned successfully


-- =========================================
-- TASK 2.5: Create group role and assign user
-- =========================================

RESET ROLE;

-- Create role (group)
CREATE ROLE rental;

-- Add user to group
GRANT rental TO rentaluser;


-- =========================================
-- TASK 2.6: Grant INSERT and UPDATE on rental table
-- =========================================

GRANT INSERT, UPDATE ON TABLE rental TO rental;

-- =========================================
-- =========================================
-- TASK 2.7: Test INSERT (should SUCCESS)
-- =========================================

-- Switch to user (ONLY works if your system allows it)
-- If SET ROLE fails, log in directly as rentaluser instead
SET ROLE rentaluser;


-- Correct INSERT (DO NOT include rental_id)
INSERT INTO public.rental(
    rental_id, rental_date, inventory_id, customer_id, return_date, staff_id, last_update
)
VALUES (
    123456,
    NOW(),
    1,
    1,
    NULL,
    1,
    NOW()
);
-- Expected:
-- INSERT 0 1


-- =========================================
-- TASK 2.8: Test UPDATE (should SUCCESS)
-- =========================================

UPDATE rental
SET return_date = NOW()
WHERE rental_id = 1;

-- Expected:
-- UPDATE 1


-- =========================================
-- TASK 2.9: Revoke INSERT permission
-- =========================================

RESET ROLE;

REVOKE INSERT ON TABLE rental FROM rental;


-- =========================================
-- TASK 2.10: Test INSERT again (should FAIL)
-- =========================================

SET ROLE rentaluser;

-- TASK: Insert new rental record (correct version)

INSERT INTO public.rental (
    rental_id,
    rental_date,
    inventory_id,
    customer_id,
    return_date,
    staff_id,
    last_update
)
VALUES (
    123457,             
    1,
    1,
    NULL,
    1,
    NOW()
);

-- Expected:
-- ERROR: permission denied for table rental


-- =========================================
-- TASK 2.11: Find customer with rental + payment history
-- =========================================

RESET ROLE;

SELECT c.first_name, c.last_name, c.customer_id
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN payment p ON c.customer_id = p.customer_id
LIMIT 1;

/*
"Tommy"	"Collazo" - customer_id	 = 459
*/


-- =========================================
-- TASK 2.12: Create personalized role
-- Customer: Tommy Collazo (customer_id = 459)
-- =========================================

CREATE ROLE client_tommy_collazo;


-- =========================================
-- TASK 2.13: Grant access to rental & payment tables
-- =========================================

GRANT SELECT ON rental TO client_tommy_collazo;
GRANT SELECT ON payment TO client_tommy_collazo;


-- =========================================
-- TASK 2.14: Enable Row-Level Security (RLS)
-- =========================================

-- Enable RLS on rental table
ALTER TABLE rental ENABLE ROW LEVEL SECURITY;

-- Drop old policy if exists (avoids conflict)
DROP POLICY IF EXISTS rental_policy_tommy ON rental;


-- Create policy: allow ONLY Tommy Collazo data

CREATE POLICY rental_policy_tommy
ON rental
FOR SELECT
TO client_tommy_collazo
USING (customer_id = 459);