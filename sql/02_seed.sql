-- =====================================================================
-- 02_seed.sql   Sample data for the College Maintenance Request Database
-- Run order : 01_schema.sql  ->  02_seed.sql  ->  03_triggers.sql ...
--             Run this BEFORE the triggers: it loads finished requests
--             (Completed, On Hold ...) and their history directly.
-- Safe to re-run: every insert skips rows that already exist, nothing is
--   deleted or updated, and it runs as ONE transaction (all or nothing).
-- No hard-coded ids: rows are linked by natural keys (email, name, room code),
--   so it works even when identity values are not 1, 2, 3 ... (they are not
--   after a failed run or a rolled-back transaction).
-- Needs the pgcrypto extension (supported by Neon) for real bcrypt hashes.
-- DEMO ONLY: every account gets the same password, 'ChangeMe@2026'.
-- =====================================================================
BEGIN;
SET LOCAL lock_timeout = '10s';

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Status (workflow: Pending, Assigned, In Progress, On Hold, Completed, Cancelled)
-- ---------------------------------------------------------------------
INSERT INTO status (status_name, description, is_active) VALUES
  ('Pending',     'Request logged and awaiting triage or team assignment', TRUE),
  ('Assigned',    'Assigned to a maintenance technician for assessment', TRUE),
  ('In Progress', 'Active repair, troubleshooting, or maintenance underway', TRUE),
  ('On Hold',     'Work suspended pending spare parts, vendor support, or safety clearance', TRUE),
  ('Completed',   'Repair work successfully completed and verified', TRUE),
  ('Cancelled',   'Request cancelled by user or marked invalid by administration', TRUE)
ON CONFLICT (status_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Priority (higher sort_rank = more urgent)
-- ---------------------------------------------------------------------
INSERT INTO priority (priority_name, sort_rank, is_active) VALUES
  ('Low', 1, TRUE), ('Medium', 2, TRUE), ('High', 3, TRUE), ('Urgent', 4, TRUE), ('Critical', 5, TRUE)
ON CONFLICT (priority_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Maintenance teams
-- ---------------------------------------------------------------------
INSERT INTO maintenance_team (team_name, description) VALUES
  ('Electrical & Power Systems',      'Handles electrical distribution, lab power rigs, generators, and lighting'),
  ('IT & Network Infrastructure',     'Manages server rooms, campus backbone, lab workstations, and AV equipment'),
  ('Mechanical & Workshop Support',   'Maintains heavy machinery, hydraulic labs, HVAC, and workshop tools'),
  ('Civil & Campus Facilities',       'Maintains building structures, masonry, plumbing, roof leaks, and water supply'),
  ('Lab & Precision Instruments Unit','Specialist support for electronics, surveying gear, and scientific lab instruments')
ON CONFLICT (team_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Categories (each handled by one team)
-- ---------------------------------------------------------------------
INSERT INTO category (category_name, description, team_id, is_active)
SELECT v.category_name, v.description, t.team_id, TRUE
FROM (VALUES
  ('Electrical Supply & Lighting', 'Circuit breakers, power outlets, lab bench supply, three-phase power',            'Electrical & Power Systems'),
  ('Backup Power & UPS',           'Diesel generator, battery backups, high-voltage transformers',                   'Electrical & Power Systems'),
  ('Network Infrastructure',       'Fiber backbone, network switches, Wi-Fi access points, Ethernet jacks',          'IT & Network Infrastructure'),
  ('Workstations & Hardware',      'Lab PCs, servers, GPU clusters, display monitors, lab printers',                 'IT & Network Infrastructure'),
  ('AV & Smart Classroom',         'Projectors, audio amplifiers, interactive displays, podium systems',             'IT & Network Infrastructure'),
  ('Heavy Equipment & CNC',        'Lathes, milling machines, CNC routers, welding stations, air compressors',       'Mechanical & Workshop Support'),
  ('HVAC & Ventilation',           'Air conditioning units, chemical fume hoods, exhaust systems',                   'Mechanical & Workshop Support'),
  ('Plumbing & Water Supply',      'Lab sinks, water supply lines, hydraulic benches, drainage systems',             'Civil & Campus Facilities'),
  ('Building Repair & Structural', 'Doors, windows, roofing leaks, ceiling tiles, wall masonry repairs',             'Civil & Campus Facilities'),
  ('Scientific & Test Equipment',  'Oscilloscopes, total stations, concrete compression testers, optical gear',      'Lab & Precision Instruments Unit')
) AS v(category_name, description, team_name)
JOIN maintenance_team t ON t.team_name = v.team_name
ON CONFLICT (category_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 5. Accounts (2 admins, 8 technicians, 16 requesters)
-- ---------------------------------------------------------------------
INSERT INTO app_user (email, password_hash, system_role, is_active)
SELECT v.email, crypt('ChangeMe@2026', gen_salt('bf', 10)), v.system_role, TRUE
FROM (VALUES
  ('admin.estate@cst.edu.bt',     'admin'),
  ('head.maintenance@cst.edu.bt', 'admin'),
  ('tech.kinley@cst.edu.bt',      'technician'),
  ('tech.tashi@cst.edu.bt',       'technician'),
  ('tech.karma@cst.edu.bt',       'technician'),
  ('tech.sangay@cst.edu.bt',      'technician'),
  ('tech.dorji@cst.edu.bt',       'technician'),
  ('tech.sonam@cst.edu.bt',       'technician'),
  ('tech.jamyang@cst.edu.bt',     'technician'),
  ('tech.choki@cst.edu.bt',       'technician'),
  ('pema.ece@cst.edu.bt',         'requester'),
  ('dechen.it@cst.edu.bt',        'requester'),
  ('ugyen.civil@cst.edu.bt',      'requester'),
  ('tshering.ee@cst.edu.bt',      'requester'),
  ('choden.chem@cst.edu.bt',      'requester'),
  ('dawa.lib@cst.edu.bt',         'requester'),
  ('yeshey.admin@cst.edu.bt',     'requester'),
  ('kidu.mech@cst.edu.bt',        'requester'),
  ('std0219001@cst.edu.bt',       'requester'),
  ('std0219015@cst.edu.bt',       'requester'),
  ('std0219032@cst.edu.bt',       'requester'),
  ('std0219044@cst.edu.bt',       'requester'),
  ('std0219058@cst.edu.bt',       'requester'),
  ('std0219070@cst.edu.bt',       'requester'),
  ('std0219083@cst.edu.bt',       'requester'),
  ('std0219095@cst.edu.bt',       'requester')
) AS v(email, system_role)
WHERE NOT EXISTS (SELECT 1 FROM app_user u WHERE lower(u.email) = lower(v.email));

-- ---------------------------------------------------------------------
-- 6. Technicians (every team has at least two)
-- ---------------------------------------------------------------------
INSERT INTO maintenance_personnel (name, phone, team_id, user_id)
SELECT v.name, v.phone, t.team_id, u.user_id
FROM (VALUES
  ('Kinley Dorji',    '+975-17654321', 'Electrical & Power Systems',       'tech.kinley@cst.edu.bt'),
  ('Tashi Phuntsho',  '+975-17654322', 'Electrical & Power Systems',       'tech.tashi@cst.edu.bt'),
  ('Karma Thinley',   '+975-17654323', 'IT & Network Infrastructure',      'tech.karma@cst.edu.bt'),
  ('Sangay Wangdi',   '+975-17654324', 'IT & Network Infrastructure',      'tech.sangay@cst.edu.bt'),
  ('Dorji Gyeltshen', '+975-17654325', 'Mechanical & Workshop Support',    'tech.dorji@cst.edu.bt'),
  ('Sonam Tobgay',    '+975-17654326', 'Civil & Campus Facilities',        'tech.sonam@cst.edu.bt'),
  ('Jamyang Tenzin',  '+975-17654327', 'Lab & Precision Instruments Unit', 'tech.jamyang@cst.edu.bt'),
  ('Choki Wangmo',    '+975-17654328', 'Lab & Precision Instruments Unit', 'tech.choki@cst.edu.bt')
) AS v(name, phone, team_name, email)
JOIN maintenance_team t ON t.team_name = v.team_name
JOIN app_user u ON lower(u.email) = lower(v.email)
WHERE NOT EXISTS (SELECT 1 FROM maintenance_personnel p WHERE p.user_id = u.user_id);

-- ---------------------------------------------------------------------
-- 7. Requesters (8 staff, 8 students)
-- ---------------------------------------------------------------------
INSERT INTO requester (name, phone, requester_type, user_id)
SELECT v.name, v.phone, v.requester_type, u.user_id
FROM (VALUES
  ('Dr. Pema Choden',  '+975-17112233', 'staff',   'pema.ece@cst.edu.bt'),
  ('Dechen Wangmo',    '+975-17112234', 'staff',   'dechen.it@cst.edu.bt'),
  ('Ugyen Tshering',   '+975-17112235', 'staff',   'ugyen.civil@cst.edu.bt'),
  ('Tshering Nidup',   '+975-17112236', 'staff',   'tshering.ee@cst.edu.bt'),
  ('Dr. Choden Lhamo', '+975-17112237', 'staff',   'choden.chem@cst.edu.bt'),
  ('Dawa Norbu',       '+975-17112238', 'staff',   'dawa.lib@cst.edu.bt'),
  ('Yeshey Zangmo',    '+975-17112239', 'staff',   'yeshey.admin@cst.edu.bt'),
  ('Kidu Tobden',      '+975-17112240', 'staff',   'kidu.mech@cst.edu.bt'),
  ('Jigme Singye',     '+975-77223341', 'student', 'std0219001@cst.edu.bt'),
  ('Sonam Yangchen',   '+975-77223342', 'student', 'std0219015@cst.edu.bt'),
  ('Karma Dechen',     '+975-77223343', 'student', 'std0219032@cst.edu.bt'),
  ('Tashi Rabten',     '+975-77223344', 'student', 'std0219044@cst.edu.bt'),
  ('Kinley Penjor',    '+975-77223345', 'student', 'std0219058@cst.edu.bt'),
  ('Pema Samdrup',     '+975-77223346', 'student', 'std0219070@cst.edu.bt'),
  ('Dechen Pem',       '+975-77223347', 'student', 'std0219083@cst.edu.bt'),
  ('Sangay Lhendup',   '+975-77223348', 'student', 'std0219095@cst.edu.bt')
) AS v(name, phone, requester_type, email)
JOIN app_user u ON lower(u.email) = lower(v.email)
WHERE NOT EXISTS (SELECT 1 FROM requester r WHERE r.user_id = u.user_id);

-- ---------------------------------------------------------------------
-- 8. Locations (the room code is unique within this seed data)
-- ---------------------------------------------------------------------
INSERT INTO location (building, floor, room_no) VALUES
  ('IT Block (Department of Information Technology)',           0, 'IT-G01'),
  ('IT Block (Department of Information Technology)',           1, 'IT-102'),
  ('IT Block (Department of Information Technology)',           2, 'IT-205'),
  ('Electronic and Communication Department Workshop',          0, 'ECE-LAB1'),
  ('Electronic and Communication Department Workshop',          1, 'ECE-LAB3'),
  ('Electrical Department Workshop',                            0, 'ELE-WS01'),
  ('Electrical Engineering Workshop',                           0, 'ELE-HV02'),
  ('Civil Engineering Lab (Geology and Concrete)',              0, 'CIV-CONC'),
  ('Civil Engineering Lab (Survey, Highway and Geotechnical)',  0, 'CIV-SURV'),
  ('Hydraulics Lab',                                            0, 'HYD-MAIN'),
  ('Chemistry Lab (Old)',                                       0, 'CHEM-L01'),
  ('Carpenter''s Workshop',                                     0, 'CARP-W01'),
  ('Academic Building',                                         1, 'AB-101'),
  ('Academic Building',                                         2, 'AB-204'),
  ('Administrative Building CST',                               0, 'ADM-05'),
  ('Library',                                                   0, 'LIB-REF'),
  ('Library',                                                   1, 'LIB-SERVER'),
  ('LH2 (Lecture Hall 2)',                                      0, 'LH2-AUD'),
  ('LH3 (Lecture Hall 3)',                                      0, 'LH3-MAIN'),
  ('Old Lecture Hall (LH1)',                                    0, 'LH1-01'),
  ('Block AB (Hostel)',                                         1, 'HAB-112'),
  ('Block CD (Hostel)',                                         2, 'HCD-204'),
  ('Block E (Hostel)',                                          0, 'HE-008'),
  ('Hostel F',                                                  1, 'HF-115'),
  ('NK Hostel',                                                 2, 'HNK-210'),
  ('RK Hostel',                                                 1, 'HRK-105'),
  ('Gymnasium Hall',                                            0, 'GYM-MAIN'),
  ('Yangsel Cafeteria',                                         0, 'CAF-KIT')
ON CONFLICT (building, floor, room_no) DO NOTHING;

-- ---------------------------------------------------------------------
-- 9. Requests (42). Staged in a temp table so every row is linked by names,
--    never by numeric ids. work_note / end_note become history remarks.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE seed_request (
  seq int, title text, description text, reported_on timestamptz, completed_on timestamptz,
  repair_details text, completion_notes text, requester_email text, tech_email text,
  category_name text, priority_name text, room_no text, status_name text,
  work_note text, end_note text
) ON COMMIT DROP;

INSERT INTO seed_request VALUES
  (1, 'Oscilloscope Channel 2 Calib Failure', 'Tektronix DSO Channel 2 shows significant voltage offset and signal attenuation during micro-controller lab experiments.', '2026-10-01 09:15:00+06', '2026-10-02 14:30:00+06', 'Replaced input BNC connector attenuator stage and recalibrated frequency response.', 'Tested with function generator signal. Both channels reading accurately.', 'pema.ece@cst.edu.bt', 'tech.jamyang@cst.edu.bt', 'Scientific & Test Equipment', 'High', 'ECE-LAB1', 'Completed', 'Started bench test and diagnostics', 'Recalibrated and verified operational'),
  (2, 'Core Switch Port Flapping on VLAN 20', 'Cisco 3850 core switch in IT server rack experiences intermittent packet drops affecting Software Engineering Lab.', '2026-10-02 10:00:00+06', '2026-10-02 16:45:00+06', 'Cleaned patch panel optical transceiver and replaced damaged Cat6 patch cable.', 'Link stability restored; zero dropped packets over 2-hour ping test.', 'dechen.it@cst.edu.bt', 'tech.karma@cst.edu.bt', 'Network Infrastructure', 'Urgent', 'IT-G01', 'Completed', 'Inspecting switch optical ports', 'Replaced patch cable and verified line'),
  (3, 'Hydraulic Bench Pump Pressure Failure', 'Armfield hydraulic bench pump trips main breaker immediately upon turning motor switch ON.', '2026-10-03 11:20:00+06', '2026-10-05 11:00:00+06', 'Replaced shorted motor capacitor and thermal overload relay unit.', 'Flow rate calibrated to 40 L/min standard operational spec.', 'ugyen.civil@cst.edu.bt', 'tech.choki@cst.edu.bt', 'Scientific & Test Equipment', 'Urgent', 'HYD-MAIN', 'Completed', 'Replacing motor start capacitor', 'Pump motor operational under full load'),
  (4, 'Three-Phase Variable Transformer Sparking', 'Variac auto-transformer emitting high acoustic hum and blue sparking around carbon brush wiper.', '2026-10-04 14:00:00+06', '2026-10-06 17:00:00+06', 'Dismantled variac assembly, polished copper winding surface, replaced worn carbon brush.', 'Voltage sweep tested smooth output from 0V to 415V AC without arcing.', 'tshering.ee@cst.edu.bt', 'tech.tashi@cst.edu.bt', 'Electrical Supply & Lighting', 'Critical', 'ELE-HV02', 'Completed', NULL, NULL),
  (5, 'Fume Hood Face Velocity Alarm Tripped', 'Fume hood airflow sensor triggering continuous low-flow audible alarm; chemical vapor venting compromised.', '2026-10-05 08:30:00+06', '2026-10-05 13:15:00+06', 'Unblocked roof exhaust duct dampers and replaced broken drive V-belt on extraction fan.', 'Face velocity re-measured at 0.51 m/s (passes OSHA/ISO standards).', 'choden.chem@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'HVAC & Ventilation', 'Critical', 'CHEM-L01', 'Completed', NULL, NULL),
  (6, 'Library Digital Catalogue Server Battery Fault', 'APC Smart-UPS battery warning LED flashing red; backup time degraded to under 1 minute during load test.', '2026-10-06 09:45:00+06', '2026-10-07 10:30:00+06', 'Installed replacement 12V 9Ah AGM battery cartridge module.', 'UPS self-test passed successfully. Runtime estimated at 42 minutes under full load.', 'dawa.lib@cst.edu.bt', 'tech.tashi@cst.edu.bt', 'Backup Power & UPS', 'High', 'LIB-SERVER', 'Completed', NULL, NULL),
  (7, 'Smart Classroom Projector HDMI Port Dead', 'HDMI Input 1 on ceiling-mounted Panasonic laser projector lost signal sync with lecturer console.', '2026-10-07 13:00:00+06', '2026-10-08 11:20:00+06', 'Replaced wall plate HDMI transmitter and crimped new shield connector.', 'Video output tested at 1080p 60Hz without distortion.', 'yeshey.admin@cst.edu.bt', 'tech.karma@cst.edu.bt', 'AV & Smart Classroom', 'Medium', 'LH2-AUD', 'Completed', NULL, NULL),
  (8, 'Concrete Compression Machine Pressure Gauge Leak', 'Hydraulic oil weeping from analogue pressure gauge coupling during 200 kN cube testing.', '2026-10-08 15:10:00+06', '2026-10-10 16:00:00+06', 'Replaced high-pressure copper sealing washer and re-bled hydraulic oil lines.', 'Pressurized to 300 kN static load; no leaks observed.', 'ugyen.civil@cst.edu.bt', 'tech.jamyang@cst.edu.bt', 'Scientific & Test Equipment', 'Urgent', 'CIV-CONC', 'Completed', NULL, NULL),
  (9, 'Electronic Soldering Station Fume Extractor Damaged', 'Flexible arm hood broken at pivot joint; solder smoke not exhausting from workbenches 4 and 5.', '2026-10-09 10:05:00+06', '2026-10-09 16:30:00+06', 'Fitted new flexible suction arm and renewed HEPA carbon filter cartridge.', 'Extraction suction tested positive on both workbench arms.', 'pema.ece@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'HVAC & Ventilation', 'Medium', 'ECE-LAB1', 'Completed', NULL, NULL),
  (10, 'Total Station Laser Rangefinder Calibration Out', 'Leica TS06 Total Station distance measurement off by +4.2 cm across 50m baseline.', '2026-10-10 11:30:00+06', '2026-10-12 15:00:00+06', 'Recalibrated optical EDM offset using internal service menu calibration routines.', 'Verified on 100m calibration baseline; error within +-1.5mm standard spec.', 'ugyen.civil@cst.edu.bt', 'tech.choki@cst.edu.bt', 'Scientific & Test Equipment', 'High', 'CIV-SURV', 'Completed', NULL, NULL),
  (11, 'GIS Workstation GPU Driver Crash & Artifacts', 'NVIDIA RTX 4080 GPU rendering corrupt textures and crashing during ArcGIS 3D map rendering.', '2026-10-11 16:00:00+06', '2026-10-12 11:45:00+06', 'Cleaned heavy dust accumulation from GPU heatsink fan and re-applied thermal compound.', 'FurMark stress test run for 1 hour; max temp stable at 68C.', 'dechen.it@cst.edu.bt', 'tech.sangay@cst.edu.bt', 'Workstations & Hardware', 'High', 'IT-205', 'Completed', NULL, NULL),
  (12, 'Wood Planer Machine Emergency Stop Button Stuck', 'Safety emergency stop button on industrial surface planer latched closed and mechanism broken.', '2026-10-12 08:50:00+06', '2026-10-12 14:10:00+06', 'Replaced latching mushroom head switch contact block assembly.', 'Safety trip function tested 5 times; machine restarts cleanly.', 'kidu.mech@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'Heavy Equipment & CNC', 'Critical', 'CARP-W01', 'Completed', NULL, NULL),
  (13, 'Computer Network Cable Cut during Wall Drilling', 'Masonry drill punctured main Cat6 trunk bundle connecting Floor 1 to Floor 2 in IT Block.', '2026-10-13 14:20:00+06', '2026-10-14 18:00:00+06', 'Pulled new 4-run Cat6 cable link through conduit and re-punched patch panel ports.', 'All cable runs verified using Fluke Network Cable Analyzer.', 'dechen.it@cst.edu.bt', 'tech.karma@cst.edu.bt', 'Network Infrastructure', 'Urgent', 'IT-102', 'Completed', NULL, NULL),
  (14, 'Roof Leak Above High-Voltage Switchgear', 'Monsoon rainwater dripping onto top cover of distribution panel during heavy rain downpour.', '2026-10-15 07:45:00+06', '2026-10-16 12:00:00+06', 'Applied silicone sealant to roof sheet laps and covered switchgear with waterproof canopy.', 'Roof tested with water hose; interior completely dry.', 'tshering.ee@cst.edu.bt', 'tech.sonam@cst.edu.bt', 'Building Repair & Structural', 'Critical', 'ELE-WS01', 'Completed', NULL, NULL),
  (15, 'Spectrum Analyzer Display Backlight Dark', 'Anritsu RF Spectrum Analyzer LCD backlight failed, text barely visible under bright light.', '2026-10-16 10:10:00+06', '2026-10-18 15:30:00+06', 'Replaced backlight inverter board and LED backlight ribbon strip.', 'Screen brightness restored and adjustable.', 'pema.ece@cst.edu.bt', 'tech.jamyang@cst.edu.bt', 'Scientific & Test Equipment', 'Medium', 'ECE-LAB3', 'Completed', NULL, NULL),
  (16, 'Main Water Pipe Burst Near Block AB Hostel', '3-inch galvanized iron water main cracked, causing water logging around hostel entrance.', '2026-10-17 06:30:00+06', '2026-10-17 13:00:00+06', 'Isolated supply valve, cut damaged pipe section, welded HDPE replacement coupling.', 'Pressure restored to 4 bar; ground area backfilled and cleared.', 'std0219001@cst.edu.bt', 'tech.sonam@cst.edu.bt', 'Plumbing & Water Supply', 'Critical', 'HAB-112', 'Completed', NULL, NULL),
  (17, 'CNC Router Z-Axis Stepper Motor Stalling', '3-Axis CNC router losing steps on vertical axis during aluminium plate milling operations.', '2026-10-18 13:40:00+06', '2026-10-20 16:20:00+06', 'Cleaned lead screw debris, lubricated ball nut, adjusted stepper drive current potentiometer.', 'Milled test block; dimensional tolerance within +-0.05mm.', 'kidu.mech@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'Heavy Equipment & CNC', 'High', 'CARP-W01', 'Completed', NULL, NULL),
  (18, 'Lecture Hall Audio System Loud Feedback & Hum', 'LH3 sound system emitting low 50Hz mains hum and intermittent squealing during lectures.', '2026-10-19 15:00:00+06', '2026-10-20 10:15:00+06', 'Installed ground loop isolator between mixer and power amplifier; replaced unshielded mic cable.', 'Audio output clean; ground hum eliminated.', 'yeshey.admin@cst.edu.bt', 'tech.karma@cst.edu.bt', 'AV & Smart Classroom', 'Medium', 'LH3-MAIN', 'Completed', NULL, NULL),
  (19, 'Water Distillation Apparatus Heater Element Burnout', 'Chemistry lab glass water still not boiling due to burned out heating element coil.', '2026-10-20 09:00:00+06', '2026-10-21 14:00:00+06', 'Fitted new 3kW nichrome heating coil and replaced corroded terminal post.', 'Distillation rate measured at 4 Litres per hour.', 'choden.chem@cst.edu.bt', 'tech.choki@cst.edu.bt', 'Scientific & Test Equipment', 'High', 'CHEM-L01', 'Completed', NULL, NULL),
  (20, 'Hostel CD Second Floor Washroom Tap Broken', 'Brass sink tap sheared off at thread junction, water spraying continuously.', '2026-10-21 07:15:00+06', '2026-10-21 09:30:00+06', 'Extracted broken thread stub with EZ-out tool and installed heavy-duty brass pillar tap.', 'No leakage under full system head pressure.', 'std0219015@cst.edu.bt', 'tech.sonam@cst.edu.bt', 'Plumbing & Water Supply', 'Urgent', 'HCD-204', 'Completed', NULL, NULL),
  (21, 'Distribution Transformer Oil Level Low', '250 kVA campus transformer sight glass shows oil level below minimum line mark.', '2026-10-22 08:30:00+06', NULL, NULL, NULL, 'tshering.ee@cst.edu.bt', 'tech.tashi@cst.edu.bt', 'Backup Power & UPS', 'Urgent', 'ELE-HV02', 'In Progress', 'Drawn oil sample for breakdown voltage testing. Top-up dielectric oil scheduled.', NULL),
  (22, 'Wi-Fi Access Point Offline in Block E Hostel', 'Aruba AP-505 in ground floor hallway unreachable via SNMP monitoring console.', '2026-10-23 11:15:00+06', NULL, NULL, NULL, 'std0219032@cst.edu.bt', 'tech.sangay@cst.edu.bt', 'Network Infrastructure', 'High', 'HE-008', 'In Progress', 'PoE injector checked. Tracing network cable run for physical line break.', NULL),
  (23, 'Surveying Laboratory Theodolite Reticle Misaligned', 'Crosshair reticle inside optical telescope shifted vertically after tripod impact.', '2026-10-24 14:10:00+06', NULL, NULL, NULL, 'ugyen.civil@cst.edu.bt', 'tech.choki@cst.edu.bt', 'Scientific & Test Equipment', 'High', 'CIV-SURV', 'In Progress', 'Eyepiece diaphragm assembly disassembled for precision reticle realigning.', NULL),
  (24, 'High Performance Computing Cluster Node 04 Overheating', 'Supermicro rack node 04 shutting down automatically due to CPU thermal throttle threshold (95C).', '2026-10-25 16:45:00+06', NULL, NULL, NULL, 'dechen.it@cst.edu.bt', 'tech.sangay@cst.edu.bt', 'Workstations & Hardware', 'Urgent', 'IT-G01', 'In Progress', 'Replaced dual cooling fan module; monitoring liquid cooling loop pump flow.', NULL),
  (25, 'Old Lecture Hall LH1 Ceiling Fan Motor Burnt', 'Ceiling fan emitting burning electrical odor and spinning at very low speed.', '2026-10-26 10:00:00+06', NULL, NULL, NULL, 'yeshey.admin@cst.edu.bt', 'tech.kinley@cst.edu.bt', 'Electrical Supply & Lighting', 'Medium', 'LH1-01', 'In Progress', 'Removed stator assembly for coil rewinding.', NULL),
  (26, 'Geotechnical Triaxial Testing Cell Leakage', 'Perspex chamber cell losing confining pressure during soil shear stress test.', '2026-10-27 13:30:00+06', NULL, NULL, NULL, 'ugyen.civil@cst.edu.bt', 'tech.jamyang@cst.edu.bt', 'Scientific & Test Equipment', 'High', 'CIV-SURV', 'In Progress', 'Replacing internal O-ring seal sets and high-pressure nylon tubes.', NULL),
  (27, 'Hostel F Ground Floor Main Door Lock Jammed', 'Mortise door lock cylinder key broken inside mechanism; students unable to secure block entry.', '2026-10-28 19:20:00+06', NULL, NULL, NULL, 'std0219044@cst.edu.bt', 'tech.sonam@cst.edu.bt', 'Building Repair & Structural', 'High', 'HF-115', 'In Progress', 'Extracted broken key fragment; replacing master lock cylinder.', NULL),
  (28, 'Cafeteria Commercial Refrigerator Cooling Failure', 'Walk-in cooler temperature risen to +14C; compressor short-cycling.', '2026-10-29 08:00:00+06', NULL, NULL, NULL, 'std0219083@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'HVAC & Ventilation', 'Urgent', 'CAF-KIT', 'In Progress', 'Recharged R404A refrigerant gas and sealed minor leak on suction line valve.', NULL),
  (29, 'Function Generator Frequency Drift', 'GW Instek 2MHz function generator outputting 1.15MHz when set to 1.00MHz Sine wave.', '2026-10-30 09:30:00+06', NULL, NULL, NULL, 'pema.ece@cst.edu.bt', 'tech.jamyang@cst.edu.bt', 'Scientific & Test Equipment', 'Medium', 'ECE-LAB1', 'Assigned', NULL, NULL),
  (30, 'Library Quiet Study Area AC Unit Dripping', 'Split air conditioner wall unit leaking condensed water onto study table 04.', '2026-10-31 11:00:00+06', NULL, NULL, NULL, 'dawa.lib@cst.edu.bt', 'tech.dorji@cst.edu.bt', 'HVAC & Ventilation', 'Medium', 'LIB-REF', 'Assigned', NULL, NULL),
  (31, 'Digital Logic Trainer Board Power Supply Short', 'Workbench trainer board +5V rail shorted to ground, tripping internal polyfuse.', '2026-11-01 14:15:00+06', NULL, NULL, NULL, 'pema.ece@cst.edu.bt', 'tech.kinley@cst.edu.bt', 'Electrical Supply & Lighting', 'High', 'ECE-LAB3', 'Assigned', NULL, NULL),
  (32, 'Hostel NK Room 210 Window Glass Cracked', 'Pane cracked during heavy wind storm; window frame cannot close properly.', '2026-11-02 16:30:00+06', NULL, NULL, NULL, 'std0219058@cst.edu.bt', 'tech.sonam@cst.edu.bt', 'Building Repair & Structural', 'Medium', 'HNK-210', 'Assigned', NULL, NULL),
  (33, 'Gymnasium Lighting Fixture High Bay LED Out', 'Two 150W industrial LED high-bay luminaires flickering dark on basketball court.', '2026-11-03 17:45:00+06', NULL, NULL, NULL, 'std0219070@cst.edu.bt', 'tech.tashi@cst.edu.bt', 'Electrical Supply & Lighting', 'Medium', 'GYM-MAIN', 'Assigned', NULL, NULL),
  (34, 'Academic Building Room 101 Smart Board Touch Unresponsive', 'Interactive optical whiteboard touch response offset by 10cm to right.', '2026-11-04 10:20:00+06', NULL, NULL, NULL, 'yeshey.admin@cst.edu.bt', 'tech.karma@cst.edu.bt', 'AV & Smart Classroom', 'Medium', 'AB-101', 'Assigned', NULL, NULL),
  (35, 'Universal Testing Machine (UTM) Tensile Grip Slippage', 'Mechanical wedge grips slipping on high-tensile steel rebar specimens during tension test.', '2026-11-05 09:00:00+06', NULL, NULL, NULL, 'ugyen.civil@cst.edu.bt', NULL, 'Scientific & Test Equipment', 'High', 'CIV-CONC', 'Pending', NULL, NULL),
  (36, 'Hostel RK Room 105 Water Heater (Geyser) Not Heating', '25L electric storage water heater indicator light stays off; no hot water.', '2026-11-06 07:30:00+06', NULL, NULL, NULL, 'std0219095@cst.edu.bt', NULL, 'Electrical Supply & Lighting', 'High', 'HRK-105', 'Pending', NULL, NULL),
  (37, 'IT Lab 205 Ethernet Wall Jack Loose', 'RJ45 wall outlet faceplate detached from wall channel, bare wires exposed.', '2026-11-07 11:40:00+06', NULL, NULL, NULL, 'dechen.it@cst.edu.bt', NULL, 'Network Infrastructure', 'Low', 'IT-205', 'Pending', NULL, NULL),
  (38, 'Carpenter Workshop Lathe Machine Belt Slippage', 'V-belt driving wood lathe spindle slipping under cutting tool force.', '2026-11-08 13:10:00+06', NULL, NULL, NULL, 'kidu.mech@cst.edu.bt', NULL, 'Heavy Equipment & CNC', 'Medium', 'CARP-W01', 'Pending', NULL, NULL),
  (39, 'Administrative Office Room 05 Door Closer Broken', 'Hydraulic overhead door closer leaking fluid and slamming door violently.', '2026-11-09 15:25:00+06', NULL, NULL, NULL, 'yeshey.admin@cst.edu.bt', NULL, 'Building Repair & Structural', 'Low', 'ADM-05', 'Pending', NULL, NULL),
  (40, 'High Voltage Surge Generator Spark Gap Electrode Pitted', 'Sphere spark gap electrodes heavily pitted; requires specialized imported tungsten replacement.', '2026-10-25 09:10:00+06', NULL, NULL, NULL, 'tshering.ee@cst.edu.bt', 'tech.tashi@cst.edu.bt', 'Electrical Supply & Lighting', 'Urgent', 'ELE-HV02', 'On Hold', 'Inspected spark gap sphere surface damage', 'Order placed with OEM supplier for replacement sphere set. Awaiting international shipment arrival from vendor.'),
  (41, 'Request duplicate - Ethernet connectivity in IT-102', 'Duplicate entry submitted accidentally.', '2026-10-26 11:00:00+06', NULL, NULL, NULL, 'dechen.it@cst.edu.bt', NULL, 'Network Infrastructure', 'Low', 'IT-102', 'Cancelled', NULL, 'Cancelled: duplicate of "Computer Network Cable Cut during Wall Drilling"'),
  (42, 'Fiber Optic Splicing Machine Arc Calibration Error', 'Fujikura fusion splicer displaying electrode wear warning and arc power error during core alignment.', '2026-11-10 09:30:00+06', NULL, NULL, NULL, 'pema.ece@cst.edu.bt', NULL, 'Scientific & Test Equipment', 'High', 'ECE-LAB3', 'Pending', NULL, NULL);

DO $$
DECLARE expected int; inserted int;
BEGIN
  SELECT count(*) INTO expected FROM seed_request s
  WHERE NOT EXISTS (SELECT 1 FROM maintenance_request m WHERE m.title = s.title AND m.reported_on = s.reported_on);

  INSERT INTO maintenance_request
    (title, description, reported_on, completed_on, repair_details, completion_notes,
     requester_id, personnel_id, category_id, priority_id, location_id, status_id)
  SELECT s.title, s.description, s.reported_on, s.completed_on, s.repair_details, s.completion_notes,
         rq.requester_id, p.personnel_id, c.category_id, pr.priority_id, l.location_id, st.status_id
  FROM seed_request s
  JOIN app_user ru            ON lower(ru.email) = lower(s.requester_email)
  JOIN requester rq           ON rq.user_id = ru.user_id
  LEFT JOIN app_user tu       ON lower(tu.email) = lower(s.tech_email)
  LEFT JOIN maintenance_personnel p ON p.user_id = tu.user_id
  JOIN category c             ON c.category_name = s.category_name
  JOIN priority pr            ON pr.priority_name = s.priority_name
  JOIN location l             ON l.room_no = s.room_no
  JOIN status st              ON st.status_name = s.status_name
  WHERE NOT EXISTS (SELECT 1 FROM maintenance_request m WHERE m.title = s.title AND m.reported_on = s.reported_on)
  ORDER BY s.seq;

  GET DIAGNOSTICS inserted = ROW_COUNT;
  IF inserted <> expected THEN
    RAISE EXCEPTION 'Seed requests: expected % new rows but inserted % (a lookup value did not match)', expected, inserted;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 10. Status history, derived from each request's final status.
--     Only for seeded requests that have no history yet, so re-runs (and
--     runs after the history trigger exists) never create duplicates.
--     Path: Pending -> Assigned -> In Progress -> (On Hold | Completed);
--           Pending -> Cancelled.
-- ---------------------------------------------------------------------
WITH adm AS (
  SELECT (SELECT user_id FROM app_user WHERE lower(email) = 'admin.estate@cst.edu.bt')     AS a0,
         (SELECT user_id FROM app_user WHERE lower(email) = 'head.maintenance@cst.edu.bt') AS a1
),
r AS (
  SELECT m.request_id, m.reported_on, m.completed_on, s.status_name, s.work_note, s.end_note,
         rq.name AS requester_name, rq.user_id AS requester_user,
         pe.name AS tech_name, pe.user_id AS tech_user,
         CASE WHEN m.request_id % 2 = 0 THEN adm.a0 ELSE adm.a1 END AS admin_user,
         m.reported_on + make_interval(mins => (15 + (m.request_id % 4) * 10)::int) AS assigned_at
  FROM maintenance_request m
  JOIN seed_request s ON s.title = m.title AND s.reported_on = m.reported_on
  JOIN requester rq   ON rq.requester_id = m.requester_id
  LEFT JOIN maintenance_personnel pe ON pe.personnel_id = m.personnel_id
  CROSS JOIN adm
  WHERE NOT EXISTS (SELECT 1 FROM request_status_history h WHERE h.request_id = m.request_id)
),
steps AS (
  SELECT request_id, NULL::text AS old_name, 'Pending'::text AS new_name, requester_user AS by_user,
         reported_on AS at, ('Request submitted by ' || requester_name) AS remarks
  FROM r
  UNION ALL
  SELECT request_id, 'Pending', 'Assigned', admin_user, assigned_at, 'Assigned to ' || tech_name
  FROM r WHERE status_name IN ('Assigned', 'In Progress', 'On Hold', 'Completed')
  UNION ALL
  SELECT request_id, 'Assigned', 'In Progress', tech_user, assigned_at + interval '20 minutes',
         COALESCE(work_note, 'Technician started work')
  FROM r WHERE status_name IN ('In Progress', 'On Hold', 'Completed')
  UNION ALL
  SELECT request_id, 'In Progress', 'On Hold', tech_user, assigned_at + interval '20 minutes' + interval '1 day',
         COALESCE(end_note, 'Work placed on hold')
  FROM r WHERE status_name = 'On Hold'
  UNION ALL
  SELECT request_id, 'In Progress', 'Completed', tech_user, completed_on,
         COALESCE(end_note, 'Work completed and verified')
  FROM r WHERE status_name = 'Completed'
  UNION ALL
  SELECT request_id, 'Pending', 'Cancelled', admin_user, reported_on + interval '30 minutes',
         COALESCE(end_note, 'Request cancelled')
  FROM r WHERE status_name = 'Cancelled'
)
INSERT INTO request_status_history (request_id, old_status_id, new_status_id, changed_by, changed_at, remarks)
SELECT st.request_id, so.status_id, sn.status_id, st.by_user, st.at, st.remarks
FROM steps st
LEFT JOIN status so ON so.status_name = st.old_name
JOIN status sn      ON sn.status_name = st.new_name
ORDER BY st.request_id, st.at;

COMMIT;
