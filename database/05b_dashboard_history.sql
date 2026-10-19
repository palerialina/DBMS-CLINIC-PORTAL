-- =====================================================================
-- 05b_dashboard_history.sql | Member 3 (for review by Member 2)
-- Adds ~3 months of PAST clinic activity on top of 05_sample_data.sql so
-- the Analytics dashboard shows real trends (Week 3: "realistic data that
-- supports meaningful dashboard results").
--
--   * 20 more patients
--   * ~150 completed visits spread over the last 90 days (Mon-Sat),
--     busier in the morning, every department represented
--   * completed lab orders (some results HIGH / LOW), prescriptions
--   * one PAID bill per visit, paid on the visit day (Cash/UPI/Card/Insurance)
--   * a few cancellations made with UPDATE, so the audit trigger writes
--     real rows into Audit_Logs
--
-- Run AFTER 01-05 on a fresh database (00_setup_all.sql does this).
-- Deterministic: the same rows are produced every time (no RAND()).
-- Every row passes the schema CHECKs and the triggers in 02_triggers.sql.
-- =====================================================================
USE clinic_portal;

-- 20 more patients (ids 16-35 on a fresh load) --------------------------
INSERT INTO Patients (first_name, last_name, dob, gender, phone, email, address, blood_group) VALUES
('Anjali',  'Menon',      '1987-02-14', 'F', '9840030001', 'anjali.menon@mail.com',  'Nungambakkam, Chennai', 'O+'),
('Karthik', 'Raman',      '1979-06-03', 'M', '9840030002', 'karthik.raman@mail.com', 'Ashok Nagar, Chennai',  'B+'),
('Fathima', 'Begum',      '1990-11-21', 'F', '9840030003', 'fathima.b@mail.com',     'Triplicane, Chennai',   'A+'),
('Rohit',   'Sharma',     '1996-08-30', 'M', '9840030004', 'rohit.sharma@mail.com',  'Vadapalani, Chennai',   'O-'),
('Meena',   'Sundaram',   '1962-04-09', 'F', '9840030005', NULL,                     'West Mambalam, Chennai','AB+'),
('Joseph',  'Thomas',     '1984-12-17', 'M', '9840030006', 'joseph.t@mail.com',      'Egmore, Chennai',       'B-'),
('Priya',   'Ganesh',     '2001-03-25', 'F', '9840030007', 'priya.ganesh@mail.com',  'Pallavaram, Chennai',   'A-'),
('Sanjay',  'Kumar',      '1970-07-12', 'M', '9840030008', 'sanjay.k@mail.com',      'Ambattur, Chennai',     'O+'),
('Revathi', 'Iyer',       '1958-10-01', 'F', '9840030009', 'revathi.iyer@mail.com',  'Alwarpet, Chennai',     'B+'),
('Aditya',  'Rao',        '2012-01-19', 'M', '9840030010', NULL,                     'Medavakkam, Chennai',   'A+'),
('Lavanya', 'Srinivasan', '1993-05-28', 'F', '9840030011', 'lavanya.s@mail.com',     'Kilpauk, Chennai',      'O+'),
('Mohan',   'Das',        '1966-09-14', 'M', '9840030012', 'mohan.das@mail.com',     'Washermanpet, Chennai', 'AB-'),
('Shalini', 'Nair',       '1989-12-05', 'F', '9840030013', 'shalini.nair@mail.com',  'Sholinganallur, Chennai','B+'),
('Ganesh',  'Pillai',     '1975-03-08', 'M', '9840030014', 'ganesh.p@mail.com',      'Avadi, Chennai',        'O+'),
('Asha',    'Varghese',   '1998-07-22', 'F', '9840030015', 'asha.v@mail.com',        'Teynampet, Chennai',    'A+'),
('Naveen',  'Reddy',      '1983-11-11', 'M', '9840030016', 'naveen.reddy@mail.com',  'Perungudi, Chennai',    'B+'),
('Keerthi', 'Suresh',     '2016-06-15', 'F', '9840030017', NULL,                     'Madipakkam, Chennai',   'O+'),
('Abdul',   'Rahman',     '1961-02-02', 'M', '9840030018', 'abdul.rahman@mail.com',  'Mannady, Chennai',      'A-'),
('Bhavana', 'Krishna',    '1994-09-09', 'F', '9840030019', 'bhavana.k@mail.com',     'Choolaimedu, Chennai',  'AB+'),
('Ramesh',  'Babu',       '1972-05-31', 'M', '9840030020', 'ramesh.babu@mail.com',   'Kodungaiyur, Chennai',  'O-');

DROP PROCEDURE IF EXISTS sp_seed_dashboard_history;

DELIMITER //
CREATE PROCEDURE sp_seed_dashboard_history()
BEGIN
    DECLARE d, i, j, n_day, n_tests, k INT;
    DECLARE v_seq      INT DEFAULT 0;
    DECLARE v_date     DATE;
    DECLARE v_time     TIME;
    DECLARE v_doctor, v_patient, v_test, v_appt, v_cnt INT;
    DECLARE v_low, v_high, v_val DECIMAL(10,2);
    DECLARE v_fee, v_lab DECIMAL(10,2);
    DECLARE v_pmax INT;

    SELECT MAX(patient_id) INTO v_pmax FROM Patients;

    SET d = 90;
    WHILE d >= 1 DO
        SET v_date = CURDATE() - INTERVAL d DAY;
        IF DAYOFWEEK(v_date) <> 1 THEN                       -- clinic closed on Sunday
            SET n_day = 1 + ((d * 7) MOD 3);                 -- 1-3 visits per day
            SET i = 0;
            WHILE i < n_day DO
                SET v_seq    = v_seq + 1;
                SET v_doctor = ((d + i * 3) MOD 10) + 1;     -- distinct doctors within a day
                SET v_patient = ((d * 7 + i * 13) MOD v_pmax) + 1;
                -- weighted slots: mornings are busiest (10:00-11:30 peak)
                SET v_time = ELT(1 + ((d * 5 + i * 11) MOD 24),
                    '09:00:00','09:30:00','10:00:00','10:00:00','10:30:00','10:30:00',
                    '11:00:00','11:00:00','11:30:00','09:30:00','10:00:00','11:00:00',
                    '12:00:00','12:30:00','14:00:00','14:30:00','15:00:00','15:30:00',
                    '16:00:00','16:30:00','10:30:00','11:30:00','09:00:00','15:00:00');

                -- never collide with an existing live booking (05_sample_data rows)
                SELECT COUNT(*) INTO v_cnt FROM Appointments
                 WHERE doctor_id = v_doctor AND appt_date = v_date
                   AND appt_time = v_time AND status <> 'Cancelled';

                IF v_cnt = 0 THEN
                    IF v_seq MOD 11 = 0 THEN
                        -- cancelled visit: booked, then cancelled with UPDATE so
                        -- trg_audit_appointment_cancellation writes Audit_Logs
                        INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time, status, reason, created_at)
                        VALUES (v_patient, v_doctor, v_date, v_time, 'Scheduled', 'Follow-up visit',
                                TIMESTAMP(v_date - INTERVAL 3 DAY, '12:00:00'));
                        UPDATE Appointments SET status = 'Cancelled' WHERE appt_id = LAST_INSERT_ID();
                    ELSE
                        INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time, status, reason, created_at)
                        VALUES (v_patient, v_doctor, v_date, v_time, 'Completed',
                                ELT(1 + (v_seq MOD 8), 'Fever', 'Routine checkup', 'Follow-up visit',
                                    'Chest pain', 'Joint pain', 'Skin rash', 'Fatigue', 'Diabetes review'),
                                TIMESTAMP(v_date - INTERVAL 2 DAY, '11:00:00'));
                        SET v_appt = LAST_INSERT_ID();

                        -- one prescription line for most visits
                        IF v_seq MOD 4 <> 0 THEN
                            INSERT INTO Prescriptions (appt_id, med_id, dosage, frequency, duration_days)
                            VALUES (v_appt, (v_seq MOD 12) + 1, '1 tablet', 'twice daily', 5 + (v_seq MOD 3) * 5);
                        END IF;

                        -- 0-3 completed lab tests, common tests ordered most often
                        SET n_tests = (d + i) MOD 4;
                        SET j = 0;
                        WHILE j < n_tests DO
                            SET v_test = ELT(1 + ((d * 3 + i * 7 + j * 5) MOD 16),
                                             1, 5, 7, 1, 5, 8, 3, 21, 6, 15, 2, 1, 9, 11, 19, 16);
                            SELECT COUNT(*) INTO v_cnt FROM Lab_Orders WHERE appt_id = v_appt AND test_id = v_test;
                            IF v_cnt = 0 THEN
                                SELECT ref_range_low, ref_range_high INTO v_low, v_high
                                  FROM Diagnostic_Tests WHERE test_id = v_test;
                                SET k = (d * 13 + j * 17 + i) MOD 10;
                                IF v_low IS NULL THEN
                                    SET v_val = NULL;                                  -- report-type test
                                ELSEIF k = 9 THEN
                                    SET v_val = ROUND(v_high * 1.2, 2);                -- HIGH
                                ELSEIF k = 0 AND v_low > 0 THEN
                                    SET v_val = ROUND(v_low * 0.85, 2);                -- LOW
                                ELSE
                                    SET v_val = ROUND(v_low + (v_high - v_low) * (0.15 + k * 0.08), 2);  -- normal
                                END IF;
                                INSERT INTO Lab_Orders (appt_id, test_id, status, ordered_at,
                                                        sample_collected_at, result_value, result_notes, completed_at)
                                VALUES (v_appt, v_test, 'Completed',
                                        TIMESTAMP(v_date, v_time),
                                        TIMESTAMP(v_date, v_time) + INTERVAL 30 MINUTE,
                                        v_val, IF(v_val IS NULL, 'Normal study', NULL),
                                        TIMESTAMP(v_date, v_time) + INTERVAL 4 HOUR);
                            END IF;
                            SET j = j + 1;
                        END WHILE;

                        -- paid bill on the visit day (lab orders exist first, so the
                        -- block-after-payment trigger is never hit)
                        SELECT consultation_fee INTO v_fee FROM Doctors WHERE doctor_id = v_doctor;
                        SELECT IFNULL(SUM(t.cost), 0) INTO v_lab
                          FROM Lab_Orders lo JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
                         WHERE lo.appt_id = v_appt;
                        INSERT INTO Bills (appt_id, consultation_fee, lab_total, total_amount, status,
                                           generated_at, paid_at, payment_mode)
                        VALUES (v_appt, v_fee, v_lab, v_fee + v_lab, 'Paid',
                                TIMESTAMP(v_date, v_time) + INTERVAL 5 HOUR,
                                TIMESTAMP(v_date, v_time) + INTERVAL 5 HOUR + INTERVAL 10 MINUTE,
                                ELT(1 + (v_seq MOD 4), 'Cash', 'UPI', 'Card', 'Insurance'));
                    END IF;
                END IF;
                SET i = i + 1;
            END WHILE;
        END IF;
        SET d = d - 1;
    END WHILE;
END//
DELIMITER ;

CALL sp_seed_dashboard_history();
DROP PROCEDURE sp_seed_dashboard_history;

-- Quick check
SELECT 'history visits' AS item, COUNT(*) AS n FROM Appointments WHERE appt_id > 16 UNION ALL
SELECT 'paid bills',  COUNT(*) FROM Bills WHERE status = 'Paid' UNION ALL
SELECT 'lab orders',  COUNT(*) FROM Lab_Orders UNION ALL
SELECT 'audit rows',  COUNT(*) FROM Audit_Logs;
