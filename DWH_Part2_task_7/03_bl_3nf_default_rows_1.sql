\timing on
-- Default ("n. a.") row for every BL_3NF dimension. CE_DATE dropped
-- (point g). Rerunnable: every INSERT guarded by WHERE NOT EXISTS.

INSERT INTO bl_3nf.ce_category (category_sk, category_name, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, 'n. a.', TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_category WHERE category_sk = -1);

INSERT INTO bl_3nf.ce_subcategory (subcategory_sk, subcategory_name, category_sk, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_subcategory WHERE subcategory_sk = -1);

INSERT INTO bl_3nf.ce_product (product_sk, product_id, product_name, subcategory_sk, product_brand, product_price, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, -1, 'n. a.', -1, 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_product WHERE product_sk = -1);

INSERT INTO bl_3nf.ce_country (country_sk, country_name, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, 'n. a.', TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_country WHERE country_sk = -1);

INSERT INTO bl_3nf.ce_region (region_sk, region_name, country_sk, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_region WHERE region_sk = -1);

INSERT INTO bl_3nf.ce_store (store_sk, store_id, store_location, store_type, region_sk, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, -1, 'n. a.', 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_store WHERE store_sk = -1);

INSERT INTO bl_3nf.ce_customer (customer_sk, customer_id, customer_segment, customer_type, customer_city, loyalty_score, age_group, start_dt, end_dt, is_active, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, -1, 'n. a.', 'n. a.', 'n. a.', -1, 'n. a.', DATE '1900-01-01', DATE '9999-12-31', 'Y', TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_customer WHERE customer_sk = -1);

INSERT INTO bl_3nf.ce_payment (payment_sk, payment_id, payment_method, payment_status, payment_risk_score, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, -1, 'n. a.', 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_payment WHERE payment_sk = -1);

INSERT INTO bl_3nf.ce_delivery (delivery_sk, delivery_id, delivery_type, delivery_status, fulfillment_time, insert_dt, update_dt, source_system, source_entity, source_id)
SELECT -1, 'n. a.', 'n. a.', 'n. a.', -1, TIMESTAMP '1900-01-01', TIMESTAMP '1900-01-01', 'MANUAL', 'MANUAL', 'n. a.'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_delivery WHERE delivery_sk = -1);

COMMIT;

SELECT 'ce_category' t, count(*) FROM bl_3nf.ce_category
UNION ALL SELECT 'ce_subcategory', count(*) FROM bl_3nf.ce_subcategory
UNION ALL SELECT 'ce_product', count(*) FROM bl_3nf.ce_product
UNION ALL SELECT 'ce_country', count(*) FROM bl_3nf.ce_country
UNION ALL SELECT 'ce_region', count(*) FROM bl_3nf.ce_region
UNION ALL SELECT 'ce_store', count(*) FROM bl_3nf.ce_store
UNION ALL SELECT 'ce_customer', count(*) FROM bl_3nf.ce_customer
UNION ALL SELECT 'ce_payment', count(*) FROM bl_3nf.ce_payment
UNION ALL SELECT 'ce_delivery', count(*) FROM bl_3nf.ce_delivery
UNION ALL SELECT 'ce_transaction', count(*) FROM bl_3nf.ce_transaction;
