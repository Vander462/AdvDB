-- =====================================================================
-- 03_simple_test.sql   Walks one request through the whole workflow.
-- Everything is ROLLED BACK at the end, so no data is left behind.
-- Watch the NOTICE lines: every one should start with PASS.
-- =====================================================================
BEGIN;

DO $$
DECLARE
    v_requester bigint := (SELECT r.requester_id FROM requester r JOIN app_user u USING (user_id)
                           WHERE u.email = 'pema.ece@cst.edu.bt');
    v_cat       bigint := (SELECT category_id FROM category WHERE category_name = 'Scientific & Test Equipment');
    v_pri       bigint := (SELECT priority_id FROM priority WHERE priority_name = 'Medium');
    v_loc       bigint := (SELECT location_id FROM location WHERE room_no = 'ECE-LAB1');
    v_admin     bigint := (SELECT user_id FROM app_user WHERE email = 'admin.estate@cst.edu.bt');
    v_tech      bigint := (SELECT personnel_id FROM maintenance_personnel WHERE name = 'Jamyang Tenzin');
    v_wrongtech bigint := (SELECT personnel_id FROM maintenance_personnel WHERE name = 'Karma Thinley');
    v_pema_user bigint := (SELECT user_id FROM app_user WHERE email = 'pema.ece@cst.edu.bt');
    v_req       bigint;
    v_status    text;
    v_hist      int;
BEGIN
    -- 1. Requester submits -> Pending + 1 history row (by the trigger)
    CALL sp_submit_request(v_requester, 'TEST: Multimeter display faulty', 'LCD shows random digits',
                           v_cat, v_pri, v_loc);
    SELECT max(request_id) INTO v_req FROM maintenance_request;
    SELECT status_name INTO v_status FROM v_request_details WHERE request_id = v_req;
    RAISE NOTICE '% T1 new request starts as Pending (%)', CASE WHEN v_status = 'Pending' THEN 'PASS' ELSE 'FAIL' END, v_status;

    -- 2. Wrong-team technician is rejected
    BEGIN
        CALL sp_assign_request(v_req, v_wrongtech, v_admin);
        RAISE NOTICE 'FAIL T2 wrong-team technician was accepted';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS T2 wrong team blocked: %', SQLERRM;
    END;

    -- 3. Admin assigns to the right technician
    CALL sp_assign_request(v_req, v_tech, v_admin);

    -- 4. Cannot complete straight from Assigned
    BEGIN
        CALL sp_complete_request(v_req, v_tech, 'x');
        RAISE NOTICE 'FAIL T4 completed from Assigned';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS T4 blocked: %', SQLERRM;
    END;

    -- 5. On Hold needs a reason
    CALL sp_update_status(v_req, v_tech, 'In Progress', 'Opened the casing');
    BEGIN
        CALL sp_update_status(v_req, v_tech, 'On Hold');
        RAISE NOTICE 'FAIL T5 On Hold without reason';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS T5 blocked: %', SQLERRM;
    END;

    -- 6. Hold, resume, complete
    CALL sp_update_status(v_req, v_tech, 'On Hold', 'Waiting for LCD module');
    CALL sp_update_status(v_req, v_tech, 'In Progress', 'Part arrived');
    CALL sp_complete_request(v_req, v_tech, 'Replaced LCD module', 'Tested on all ranges');
    SELECT status_name INTO v_status FROM v_request_details WHERE request_id = v_req;
    SELECT count(*) INTO v_hist FROM request_status_history WHERE request_id = v_req;
    RAISE NOTICE '% T6 completed with 6 history rows (status %, rows %)',
        CASE WHEN v_status = 'Completed' AND v_hist = 6 THEN 'PASS' ELSE 'FAIL' END, v_status, v_hist;

    -- 7. Completed request cannot be cancelled
    BEGIN
        CALL sp_cancel_request(v_req, v_admin, 'test');
        RAISE NOTICE 'FAIL T7 cancel was allowed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS T7 blocked: %', SQLERRM;
    END;

    -- 8. Requester cannot cancel someone else's request
    BEGIN
        SELECT request_id INTO v_req FROM maintenance_request
        WHERE title = 'IT Lab 205 Ethernet Wall Jack Loose';      -- belongs to Dechen
        CALL sp_cancel_request(v_req, v_pema_user, 'not mine');
        RAISE NOTICE 'FAIL T8 cancelled another person''s request';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS T8 blocked: %', SQLERRM;
    END;
END $$;

-- The history the trigger wrote for the test request
SELECT old_status, new_status, changed_by_name, changed_by_role, remarks
FROM v_request_history
WHERE title = 'TEST: Multimeter display faulty'
ORDER BY history_id;

ROLLBACK;
