-- =====================================================================
-- 03_rollback_old_logic.sql
-- Removes everything that PART A of the old 03_logic.sql created
-- (5 triggers + 15 functions). Tables and data are NOT touched.
-- Safe to re-run (IF EXISTS everywhere). One transaction: all or nothing.
-- =====================================================================
BEGIN;

-- Triggers first (they depend on the trigger functions)
DROP TRIGGER IF EXISTS trg_request_validate     ON maintenance_request;
DROP TRIGGER IF EXISTS trg_request_log_status   ON maintenance_request;
DROP TRIGGER IF EXISTS trg_history_no_change    ON request_status_history;
DROP TRIGGER IF EXISTS trg_history_no_truncate  ON request_status_history;
DROP TRIGGER IF EXISTS trg_history_check_insert ON request_status_history;

-- Workflow functions
DROP FUNCTION IF EXISTS submit_request(text, text, bigint, bigint, bigint);
DROP FUNCTION IF EXISTS assign_request(bigint, bigint, text);
DROP FUNCTION IF EXISTS change_status(bigint, text, text);
DROP FUNCTION IF EXISTS complete_request(bigint, text, text);
DROP FUNCTION IF EXISTS cancel_request(bigint, text);
DROP FUNCTION IF EXISTS pick_technician(bigint);

-- Trigger functions
DROP FUNCTION IF EXISTS trg_request_validate();
DROP FUNCTION IF EXISTS trg_request_log_status();
DROP FUNCTION IF EXISTS trg_history_append_only();
DROP FUNCTION IF EXISTS trg_history_check_insert();

-- Helpers
DROP FUNCTION IF EXISTS require_actor(text[]);
DROP FUNCTION IF EXISTS is_valid_transition(text, text);
DROP FUNCTION IF EXISTS status_name_of(bigint);
DROP FUNCTION IF EXISTS status_id_of(text);
DROP FUNCTION IF EXISTS current_app_user();

COMMIT;

-- Check: both counts should be 0
SELECT
  (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal
      AND c.relname IN ('maintenance_request', 'request_status_history')) AS user_triggers_left,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('current_app_user','status_id_of','status_name_of','is_valid_transition',
                        'require_actor','trg_request_validate','trg_request_log_status',
                        'trg_history_append_only','trg_history_check_insert','pick_technician',
                        'submit_request','assign_request','change_status','complete_request',
                        'cancel_request')) AS old_functions_left;
