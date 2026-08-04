\timing on
-- =====================================================================
-- Grant required privileges to BL_CL (Task 7 requirement, mentor
-- feedback item "documentation"/explicitness in general): a dedicated
-- role runs the BL_CL objects, with exactly the privileges the load
-- actually needs -- read on the SA_ staging schemas, read/write on
-- BL_3NF, and EXECUTE on the BL_CL functions/procedures themselves.
-- =====================================================================

DROP ROLE IF EXISTS etl_bl_cl;
CREATE ROLE etl_bl_cl LOGIN PASSWORD 'etl_bl_cl_pw';

GRANT USAGE ON SCHEMA sa_retail TO etl_bl_cl;
GRANT USAGE ON SCHEMA sa_online TO etl_bl_cl;
GRANT SELECT ON ALL TABLES IN SCHEMA sa_retail TO etl_bl_cl;
GRANT SELECT ON ALL TABLES IN SCHEMA sa_online TO etl_bl_cl;

GRANT USAGE ON SCHEMA bl_3nf TO etl_bl_cl;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA bl_3nf TO etl_bl_cl;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA bl_3nf TO etl_bl_cl;

GRANT USAGE ON SCHEMA bl_cl TO etl_bl_cl;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA bl_cl TO etl_bl_cl;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA bl_cl TO etl_bl_cl;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA bl_cl TO etl_bl_cl;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA bl_cl TO etl_bl_cl;

-- keep future objects covered too
ALTER DEFAULT PRIVILEGES IN SCHEMA bl_3nf GRANT SELECT, INSERT, UPDATE ON TABLES TO etl_bl_cl;
ALTER DEFAULT PRIVILEGES IN SCHEMA bl_cl GRANT SELECT, INSERT, UPDATE ON TABLES TO etl_bl_cl;
ALTER DEFAULT PRIVILEGES IN SCHEMA bl_cl GRANT EXECUTE ON FUNCTIONS TO etl_bl_cl;

SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'etl_bl_cl' AND table_schema IN ('sa_retail','sa_online','bl_3nf','bl_cl')
ORDER BY table_schema, table_name, privilege_type;
