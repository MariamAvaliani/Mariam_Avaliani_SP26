--task2

/*
1. Create table ‘table_to_delete’ and fill it with the following query:
*/

CREATE TABLE table_to_delete1 AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;  -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)

/*
2. Lookup how much space this table consumes with the following query:
*/

SELECT *, pg_size_pretty(total_bytes) AS total,
             pg_size_pretty(index_bytes) AS INDEX,
             pg_size_pretty(toast_bytes) AS toast,
             pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
       FROM (SELECT c.oid,nspname AS table_schema,
                    relname AS TABLE_NAME,
                    c.reltuples AS row_estimate,
                    pg_total_relation_size(c.oid) AS total_bytes,
                    pg_indexes_size(c.oid) AS index_bytes,
                    pg_total_relation_size(reltoastrelid) AS toast_bytes
             FROM pg_class c
             LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE relkind = 'r') a
     ) a
WHERE table_name LIKE '%table_to_delete%';

/*
3. Issue the following DELETE operation on ‘table_to_delete’:
*/

DELETE FROM table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0;

/*
DELETE Operation on table_to_delete

a) Execution time:

DELETE 1/3 of rows took 28.887 seconds.
DELETE is slower because PostgreSQL removes rows individually and marks them as deleted in the table file.

b) Table space after DELETE:

Table size: 575 MB
Total bytes: 602,611,712
Observation: DELETE does not immediately free disk space, the table file remains almost the same size.*/
 VACUUM FULL VERBOSE table_to_delete;
/*
c) VACUUM FULL:

Running VACUUM FULL VERBOSE table_to_delete took 12.985 seconds.
VACUUM FULL physically rewrites the table and reclaims disk space used by deleted rows.

d) Table space after VACUUM FULL:

Table size: 383 MB
Total bytes: 401,580,032
Conclusion: After VACUUM FULL, disk space is significantly reduced. DELETE alone does not reduce file size, VACUUM FULL is required to reclaim it.

e) Recreate table_to_delete table:

The table is recreated with the same 10 million rows to continue further experiments.
This ensures that subsequent operations (e.g., TRUNCATE) work on a full table.

*/


--truncate

CREATE TABLE table_to_delete2 AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x;

SELECT *, pg_size_pretty(total_bytes) AS total,
             pg_size_pretty(index_bytes) AS INDEX,
             pg_size_pretty(toast_bytes) AS toast,
             pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
       FROM (SELECT c.oid,nspname AS table_schema,
                    relname AS TABLE_NAME,
                    c.reltuples AS row_estimate,
                    pg_total_relation_size(c.oid) AS total_bytes,
                    pg_indexes_size(c.oid) AS index_bytes,
                    pg_total_relation_size(reltoastrelid) AS toast_bytes
             FROM pg_class c
             LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE relkind = 'r') a
     ) a
WHERE table_name LIKE '%table_to_delete%';


TRUNCATE table_to_delete2;

/*
Step 4: TRUNCATE table_to_delete

a) Execution time:

TRUNCATE operation took 1.218 seconds.
TRUNCATE is extremely fast because it removes all rows at once, without processing each row individually like DELETE.

b) Comparison with previous results:

DELETE 1/3 of rows: 28.887 seconds
DELETE + VACUUM FULL: 12.985 seconds
TRUNCATE: 1.218 seconds
Conclusion: TRUNCATE is much faster than DELETE, even with VACUUM FULL, because it resets the table instantly instead of handling individual rows.

c) Table space after TRUNCATE:

Table size: 0 MB
Total bytes: 8 KB (minimal overhead)
Conclusion: TRUNCATE frees almost all disk space immediately, unlike DELETE which requires VACUUM FULL to reclaim space.

Overall observations:

TRUNCATE is optimal for clearing large tables quickly.
DELETE is slower and does not free space automatically.
VACUUM FULL is needed after DELETE to reclaim disk space.
*/



/*

Step 5: Investigation Results – table_to_delete

a) Space Consumption Before and After Each Operation

Initial table:

Table size: 575 MB
Total bytes: 602,505,216
Notes: Full table of 10 million rows

After DELETE 1/3 of rows:

Table size: 575 MB
Total bytes: 602,611,712
Notes: DELETE alone does not reduce file size

After VACUUM FULL:

Table size: 383 MB
Total bytes: 401,580,032
Notes: VACUUM FULL reclaims space, reduces table size

After TRUNCATE:

Table size: 0 MB
Total bytes: 8 KB
Notes: TRUNCATE clears table completely, almost all space freed

b) DELETE vs TRUNCATE Comparison

Execution Time:

DELETE 1/3 rows: 28.887 sec
DELETE + VACUUM FULL: 12.985 sec
TRUNCATE: 1.218 sec

Disk Space Usage:

DELETE: Table file remains large until VACUUM FULL
TRUNCATE: Table space freed immediately

Transaction Behavior:

DELETE: Row-by-row, transactional, rollback possible
TRUNCATE: Table cleared instantly, rollback usually not possible

c) Explanations

Why DELETE does not free space immediately: DELETE marks rows as deleted but does not reduce the table file. Space is still allocated until VACUUM FULL runs.
Why VACUUM FULL changes table size: VACUUM FULL rewrites the table, removes dead tuples, and releases disk space, reducing the physical file size.
Why TRUNCATE behaves differently: TRUNCATE resets the table structure, deallocates all data pages instantly, and frees space immediately.
How these operations affect performance and storage:
DELETE on large tables: slow, heavy on transaction logs, needs VACUUM for space.
VACUUM FULL: moderate time, reduces file size, improves storage efficiency.
TRUNCATE: very fast, minimal overhead, space freed immediately.

Conclusion:

Use DELETE + VACUUM FULL for selective row deletion.
Use TRUNCATE for clearing entire tables efficiently.
Knowing these differences helps optimize performance and disk space in PostgreSQL.


*/