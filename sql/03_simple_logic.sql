-- =====================================================================
-- 03_simple_logic.sql   Views, one trigger, stored procedures
-- Run order: 01_schema -> 02_seed -> 03_rollback_old_logic -> 03_simple_logic
-- Safe to re-run (CREATE OR REPLACE). Tables and data are not changed.
--
-- Status workflow used by the procedures:
--   Pending -> Assigned          (admin assigns a technician)
--   Assigned -> In Progress      (technician starts)
--   In Progress <-> On Hold      (technician pauses / resumes, reason needed to pause)
--   In Progress -> Completed     (technician completes, repair details needed)
--   any open status -> Cancelled (admin; requester only while Pending)
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- 1. VIEWS
-- ---------------------------------------------------------------------

-- 1a. Every request with readable names instead of ids (used by all 3 tabs)
CREATE OR REPLACE VIEW v_request_details AS
SELECT m.request_id,
       m.title,
       m.description,
       m.reported_on,
       m.completed_on,
       m.repair_details,
       m.completion_notes,
       m.requester_id,
       rq.name            AS requester_name,
       rq.requester_type,
       m.category_id,
       c.category_name,
       t.team_id,
       t.team_name,
       m.priority_id,
       p.priority_name,
       p.sort_rank        AS priority_rank,
       m.location_id,
       l.building,
       l.floor,
       l.room_no,
       m.status_id,
       s.status_name,
       m.personnel_id,
       mp.name            AS technician_name,
       m.suggested_priority_id,
       suggested_p.priority_name AS suggested_priority_name
FROM maintenance_request m
JOIN requester rq                  ON rq.requester_id = m.requester_id
JOIN category c                    ON c.category_id   = m.category_id
JOIN maintenance_team t            ON t.team_id       = c.team_id
JOIN priority p                    ON p.priority_id   = m.priority_id
LEFT JOIN priority suggested_p     ON suggested_p.priority_id = m.suggested_priority_id
JOIN location l                    ON l.location_id   = m.location_id
JOIN status s                      ON s.status_id     = m.status_id
LEFT JOIN maintenance_personnel mp ON mp.personnel_id = m.personnel_id;

-- 1b. Status history with names (who changed what, when)
CREATE OR REPLACE VIEW v_request_history AS
SELECT h.history_id,
       h.request_id,
       m.title,
       h.changed_at,
       so.status_name AS old_status,
       sn.status_name AS new_status,
       COALESCE(mp.name, rq.name, u.email) AS changed_by_name,
       u.system_role  AS changed_by_role,
       h.remarks
FROM request_status_history h
JOIN maintenance_request m         ON m.request_id    = h.request_id
JOIN status sn                     ON sn.status_id    = h.new_status_id
LEFT JOIN status so                ON so.status_id    = h.old_status_id
JOIN app_user u                    ON u.user_id       = h.changed_by
LEFT JOIN maintenance_personnel mp ON mp.user_id      = u.user_id
LEFT JOIN requester rq             ON rq.user_id      = u.user_id;

-- 1c. Workload per technician
CREATE OR REPLACE VIEW v_technician_workload AS
SELECT mp.personnel_id,
       mp.name AS technician_name,
       t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Assigned')    AS assigned,
       count(*) FILTER (WHERE s.status_name = 'In Progress') AS in_progress,
       count(*) FILTER (WHERE s.status_name = 'On Hold')     AS on_hold,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open_total,
       count(*) FILTER (WHERE s.status_name = 'Completed')   AS completed
FROM maintenance_personnel mp
JOIN maintenance_team t          ON t.team_id = mp.team_id
LEFT JOIN maintenance_request m  ON m.personnel_id = mp.personnel_id
LEFT JOIN status s               ON s.status_id = m.status_id
GROUP BY mp.personnel_id, mp.name, t.team_name;

-- 1d. Report: requests per category
CREATE OR REPLACE VIEW v_category_summary AS
SELECT c.category_name,
       t.team_name,
       count(m.request_id) AS total,
       count(*) FILTER (WHERE s.status_name = 'Pending')   AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       count(*) FILTER (WHERE s.status_name = 'Cancelled') AS cancelled
FROM category c
JOIN maintenance_team t         ON t.team_id = c.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s              ON s.status_id = m.status_id
GROUP BY c.category_name, t.team_name;

-- 1e. Report: pending / open work per team
CREATE OR REPLACE VIEW v_team_summary AS
SELECT t.team_name,
       count(*) FILTER (WHERE s.status_name = 'Pending') AS pending,
       count(*) FILTER (WHERE s.status_name IN ('Assigned','In Progress','On Hold')) AS open,
       count(*) FILTER (WHERE s.status_name = 'Completed') AS completed,
       round(avg(EXTRACT(EPOCH FROM (m.completed_on - m.reported_on)) / 3600)
             FILTER (WHERE s.status_name = 'Completed'), 1) AS avg_hours_to_complete
FROM maintenance_team t
LEFT JOIN category c            ON c.team_id = t.team_id
LEFT JOIN maintenance_request m ON m.category_id = c.category_id
LEFT JOIN status s              ON s.status_id = m.status_id
GROUP BY t.team_name;

-- ---------------------------------------------------------------------
-- 2. SMALL HELPER FUNCTIONS
-- ---------------------------------------------------------------------

-- Status id from its name, e.g. fn_status_id('Pending')
CREATE OR REPLACE FUNCTION fn_status_id(p_name text)
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT status_id FROM status WHERE status_name = p_name
$$;

CREATE OR REPLACE FUNCTION fn_priority_id(p_name text)
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT priority_id FROM priority WHERE priority_name = p_name AND is_active
$$;

-- Technicians who can take a request of this category (same team),
-- least busy first. Used by the admin's "assign" dropdown.
CREATE OR REPLACE FUNCTION fn_team_technicians(p_category_id bigint)
RETURNS TABLE (personnel_id bigint, technician_name text, open_jobs bigint)
LANGUAGE sql STABLE AS $$
    SELECT w.personnel_id, w.technician_name::text, w.open_total
    FROM v_technician_workload w
    JOIN maintenance_personnel mp ON mp.personnel_id = w.personnel_id
    JOIN category c               ON c.team_id = mp.team_id
    WHERE c.category_id = p_category_id
    ORDER BY w.open_total, w.technician_name
$$;

-- ---------------------------------------------------------------------
-- 3. TRIGGER: log every status change into request_status_history
--    Who made the change is passed in by the procedures below through
--    the transaction setting 'app.user_id' (and 'app.remarks').
--    New requests fall back to the requester.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_log_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user    bigint := NULLIF(current_setting('app.user_id', true), '')::bigint;
    v_remarks text   := NULLIF(current_setting('app.remarks', true), '');
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_user := COALESCE(v_user,
                  (SELECT user_id FROM requester WHERE requester_id = NEW.requester_id));
        INSERT INTO request_status_history (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES (NEW.request_id, NULL, NEW.status_id, v_user, COALESCE(v_remarks, 'Request submitted'));

    ELSIF NEW.status_id <> OLD.status_id THEN
        IF v_user IS NULL THEN
            RAISE EXCEPTION 'Change status through the procedures (who made the change is unknown)';
        END IF;
        INSERT INTO request_status_history (request_id, old_status_id, new_status_id, changed_by, remarks)
        VALUES (NEW.request_id, OLD.status_id, NEW.status_id, v_user, v_remarks);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_status_change ON maintenance_request;
CREATE TRIGGER trg_log_status_change
    AFTER INSERT OR UPDATE OF status_id ON maintenance_request
    FOR EACH ROW EXECUTE FUNCTION trg_log_status_change();

-- ---------------------------------------------------------------------
-- 4. STORED PROCEDURES (call with CALL ...)
-- ---------------------------------------------------------------------

-- 4a. Requester submits a request (always starts as Pending)
CREATE OR REPLACE PROCEDURE sp_submit_request(
    p_requester_id bigint, p_title text, p_description text,
    p_category_id bigint, p_priority_id bigint, p_location_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    -- the trigger will record the requester as the person who made the change
    PERFORM set_config('app.user_id', '', true);
    PERFORM set_config('app.remarks', '', true);

    IF NOT EXISTS (
        SELECT 1 FROM requester r JOIN app_user u ON u.user_id = r.user_id
        WHERE r.requester_id = p_requester_id AND u.system_role = 'requester' AND u.is_active
    ) THEN
        RAISE EXCEPTION 'An active requester profile is required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM priority WHERE priority_id = p_priority_id AND is_active) THEN
        RAISE EXCEPTION 'Choose an active suggested urgency';
    END IF;

    INSERT INTO maintenance_request
        (title, description, requester_id, category_id, priority_id,
         suggested_priority_id, location_id, status_id)
    VALUES
        (p_title, p_description, p_requester_id, p_category_id,
         COALESCE(fn_priority_id('Medium'), p_priority_id), p_priority_id, p_location_id,
         fn_status_id('Pending'));
END;
$$;

-- 4b. Admin assigns a Pending request to a technician of the right team
CREATE OR REPLACE PROCEDURE sp_assign_request(
    p_request_id bigint, p_personnel_id bigint, p_admin_user_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_ok     boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_user WHERE user_id = p_admin_user_id AND system_role = 'admin' AND is_active) THEN
        RAISE EXCEPTION 'An active admin account is required to assign requests';
    END IF;

    SELECT s.status_name INTO v_status
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    ELSIF v_status <> 'Pending' THEN
        RAISE EXCEPTION 'Only Pending requests can be assigned (this one is %)', v_status;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM maintenance_request m
        JOIN category c ON c.category_id = m.category_id
        JOIN maintenance_personnel mp ON mp.team_id = c.team_id
        JOIN app_user u ON u.user_id = mp.user_id
        WHERE m.request_id = p_request_id AND mp.personnel_id = p_personnel_id
          AND u.system_role = 'technician' AND u.is_active
    ) INTO v_ok;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'This technician is not in the team that handles this category';
    END IF;

    PERFORM set_config('app.user_id', p_admin_user_id::text, true);
    PERFORM set_config('app.remarks',
        'Assigned to ' || (SELECT name FROM maintenance_personnel WHERE personnel_id = p_personnel_id), true);

    UPDATE maintenance_request
    SET personnel_id = p_personnel_id, status_id = fn_status_id('Assigned')
    WHERE request_id = p_request_id;
END;
$$;

-- 4c. Technician moves his own request: Assigned -> In Progress,
--     In Progress -> On Hold (reason needed), On Hold -> In Progress
CREATE OR REPLACE PROCEDURE sp_update_status(
    p_request_id bigint, p_personnel_id bigint, p_new_status text, p_remarks text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM maintenance_personnel mp JOIN app_user u ON u.user_id = mp.user_id
        WHERE mp.personnel_id = p_personnel_id AND u.system_role = 'technician' AND u.is_active
    ) THEN
        RAISE EXCEPTION 'An active technician account is required';
    END IF;
    IF NOT ((v_status = 'Assigned'    AND p_new_status = 'In Progress') OR
            (v_status = 'In Progress' AND p_new_status = 'On Hold')     OR
            (v_status = 'On Hold'     AND p_new_status = 'In Progress')) THEN
        RAISE EXCEPTION 'Cannot move from % to %', v_status, p_new_status;
    END IF;
    IF p_new_status = 'On Hold' AND coalesce(btrim(p_remarks), '') = '' THEN
        RAISE EXCEPTION 'Give a reason for putting the request On Hold';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(p_remarks, ''), true);

    UPDATE maintenance_request SET status_id = fn_status_id(p_new_status)
    WHERE request_id = p_request_id;
END;
$$;

-- 4d. Technician completes his own In Progress request
CREATE OR REPLACE PROCEDURE sp_complete_request(
    p_request_id bigint, p_personnel_id bigint, p_repair_details text, p_notes text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
    v_owner  bigint;
BEGIN
    SELECT s.status_name, m.personnel_id INTO v_status, v_owner
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF v_owner IS DISTINCT FROM p_personnel_id THEN
        RAISE EXCEPTION 'Request % is not assigned to you', p_request_id;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM maintenance_personnel mp JOIN app_user u ON u.user_id = mp.user_id
        WHERE mp.personnel_id = p_personnel_id AND u.system_role = 'technician' AND u.is_active
    ) THEN
        RAISE EXCEPTION 'An active technician account is required';
    END IF;
    IF v_status <> 'In Progress' THEN
        RAISE EXCEPTION 'Only In Progress requests can be completed (this one is %)', v_status;
    END IF;
    IF coalesce(btrim(p_repair_details), '') = '' THEN
        RAISE EXCEPTION 'Repair details are required';
    END IF;

    PERFORM set_config('app.user_id',
        (SELECT user_id FROM maintenance_personnel WHERE personnel_id = p_personnel_id)::text, true);
    PERFORM set_config('app.remarks', coalesce(nullif(btrim(p_notes), ''), 'Work completed'), true);

    UPDATE maintenance_request
    SET status_id        = fn_status_id('Completed'),
        repair_details   = p_repair_details,
        completion_notes = p_notes,
        completed_on     = now()
    WHERE request_id = p_request_id;
END;
$$;

-- 4e. Cancel: admin can cancel any open request,
--     a requester only his own and only while it is Pending
CREATE OR REPLACE PROCEDURE sp_cancel_request(
    p_request_id bigint, p_user_id bigint, p_reason text)
LANGUAGE plpgsql AS $$
DECLARE
    v_role      text;
    v_status    text;
    v_requester bigint;
BEGIN
    SELECT system_role INTO v_role FROM app_user WHERE user_id = p_user_id AND is_active;
    SELECT s.status_name, m.requester_id INTO v_status, v_requester
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel';
    END IF;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_status IN ('Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Request is already %', v_status;
    END IF;
    IF v_role = 'requester' THEN
        IF v_requester <> (SELECT requester_id FROM requester WHERE user_id = p_user_id) THEN
            RAISE EXCEPTION 'You can only cancel your own requests';
        END IF;
        IF v_status <> 'Pending' THEN
            RAISE EXCEPTION 'Work has started; ask the admin to cancel';
        END IF;
    ELSIF v_role IS DISTINCT FROM 'admin' THEN
        RAISE EXCEPTION 'Only the requester or an admin can cancel';
    END IF;

    PERFORM set_config('app.user_id', p_user_id::text, true);
    PERFORM set_config('app.remarks', 'Cancelled: ' || p_reason, true);

    UPDATE maintenance_request SET status_id = fn_status_id('Cancelled')
    WHERE request_id = p_request_id;
END;
$$;

-- 4f. Admin confirms or changes the official priority during triage.
CREATE OR REPLACE PROCEDURE sp_set_priority(
    p_request_id bigint, p_priority_id bigint, p_admin_user_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_status text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_user WHERE user_id = p_admin_user_id AND system_role = 'admin' AND is_active) THEN
        RAISE EXCEPTION 'An active admin account is required to set priority';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM priority WHERE priority_id = p_priority_id AND is_active) THEN
        RAISE EXCEPTION 'Choose an active official priority';
    END IF;

    SELECT s.status_name INTO v_status
    FROM maintenance_request m JOIN status s ON s.status_id = m.status_id
    WHERE m.request_id = p_request_id
    FOR UPDATE OF m;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    ELSIF v_status IN ('Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'Priority cannot be changed on a % request', v_status;
    END IF;

    UPDATE maintenance_request SET priority_id = p_priority_id
    WHERE request_id = p_request_id;
END;
$$;

COMMIT;
