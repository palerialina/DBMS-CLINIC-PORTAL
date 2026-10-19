-- ============================================================
-- 07_trigger_stress_tests.sql
-- Project: Digital Health Clinic & Diagnostic Lab Portal
-- Owner: Member 2
-- Purpose: Test appointment and audit triggers
-- Run with:  mysql -u root -p --force --table clinic_portal < 07_trigger_stress_tests.sql
-- (Test 1 fixed by Member 3: slot read from appointment 10 instead of a hard-coded date)
-- ============================================================

USE clinic_portal;

-- TEST 1: DOUBLE-BOOKING PREVENTION
-- Take the exact doctor / date / time of existing appointment 10 and try
-- to book a second patient into it. The slot is read from the table, so
-- this works on whatever day the database was loaded (05 uses CURDATE()).
-- Expected: ERROR ERR_DOUBLE_BOOKING.
-- Run with --force (or run this INSERT on its own) because an error is expected.

SELECT doctor_id, appt_date, appt_time INTO @d, @dt, @tm
FROM Appointments WHERE appt_id = 10;

INSERT INTO Appointments
    (doctor_id, patient_id, appt_date, appt_time, status)
VALUES
    (@d, 11, @dt, @tm, 'Scheduled');


-- TEST 2: VERIFY CANCELLATION AUDIT TRIGGER
-- Appointment 16 (today, Scheduled) comes from 05_sample_data.sql.
-- First cancel it, then check Audit_Logs.

UPDATE Appointments
SET status = 'Cancelled'
WHERE appt_id = 16
  AND status = 'Scheduled';

-- Verify that the cancellation was recorded.
SELECT log_id, table_name, record_id, action,
       old_status, new_status, details, logged_at
FROM Audit_Logs
WHERE table_name = 'Appointments'
  AND record_id = 16
ORDER BY log_id DESC;


-- TEST 3: RESTORE APPOINTMENT 16
-- Restore the original status after the demonstration.
-- This creates another STATUS_CHANGE audit record.

UPDATE Appointments
SET status = 'Scheduled'
WHERE appt_id = 16
  AND status = 'Cancelled';

-- Verify the final appointment status.
SELECT appt_id, doctor_id, patient_id,
       appt_date, appt_time, status
FROM Appointments
WHERE appt_id = 16;

-- Verify both audit entries for appointment 16.
SELECT log_id, record_id, action,
       old_status, new_status, logged_at
FROM Audit_Logs
WHERE table_name = 'Appointments'
  AND record_id = 16
ORDER BY log_id DESC;

-- END OF TESTS
