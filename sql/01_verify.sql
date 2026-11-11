-- =====================================================================
-- 01_verify.sql   Read-only check that 01_schema.sql was applied fully.
-- Every row should say PASS. Safe to run any time (SELECT only).
-- =====================================================================
WITH s AS (SELECT oid FROM pg_namespace WHERE nspname = 'public'),
c AS (
  SELECT 'tables'                 AS check_name, 10 AS expected,
         (SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tablename IN
            ('app_user','requester','maintenance_team','maintenance_personnel','category',
             'status','priority','location','maintenance_request','request_status_history'))::int AS actual
  UNION ALL SELECT 'columns (all 10 tables)', 57,
         (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN
            ('app_user','requester','maintenance_team','maintenance_personnel','category',
             'status','priority','location','maintenance_request','request_status_history'))::int
  UNION ALL SELECT 'primary keys', 10,
         (SELECT count(*) FROM pg_constraint, s WHERE contype = 'p' AND connamespace = s.oid)::int
  UNION ALL SELECT 'foreign keys', 15,
         (SELECT count(*) FROM pg_constraint, s WHERE contype = 'f' AND connamespace = s.oid)::int
  UNION ALL SELECT 'foreign keys with ON DELETE RESTRICT', 15,
         (SELECT count(*) FROM pg_constraint, s WHERE contype = 'f' AND confdeltype = 'r' AND connamespace = s.oid)::int
  UNION ALL SELECT 'unique constraints', 8,
         (SELECT count(*) FROM pg_constraint, s WHERE contype = 'u' AND connamespace = s.oid)::int
  UNION ALL SELECT 'check constraints', 19,
         (SELECT count(*) FROM pg_constraint, s WHERE contype = 'c' AND connamespace = s.oid)::int
  UNION ALL SELECT 'extra indexes', 11,
         (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
            AND (indexname LIKE 'ix\_%' OR indexname = 'uq_app_user_email_lower'))::int
)
SELECT check_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM c;
