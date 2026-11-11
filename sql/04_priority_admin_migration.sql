-- Install or update the admin-only official-priority procedure.
-- Run after 01_schema.sql and 03_simple_logic.sql in the Neon SQL editor.
-- Safe to re-run; it changes no request data.

CREATE OR REPLACE PROCEDURE sp_set_priority(
    p_request_id bigint,
    p_priority_id bigint,
    p_admin_user_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM app_user
        WHERE user_id = p_admin_user_id
          AND system_role = 'admin'
          AND is_active
    ) THEN
        RAISE EXCEPTION 'An active admin account is required to set priority';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM priority
        WHERE priority_id = p_priority_id AND is_active
    ) THEN
        RAISE EXCEPTION 'Choose an active official priority';
    END IF;

    SELECT s.status_name INTO v_status
    FROM maintenance_request m
    JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    ELSIF v_status IN ('Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Priority cannot be changed on a % request', v_status;
    END IF;

    UPDATE maintenance_request
    SET priority_id = p_priority_id
    WHERE request_id = p_request_id;
END;
$$;
