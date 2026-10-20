-- ============================================================
-- 07_trigger_stress_tests.sql
-- Project: Digital Health Clinic & Diagnostic Lab Portal
-- Owner: Member 2
-- Purpose: Test appointment, billing and audit triggers
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

-- ============================================================
-- TESTS 4-7: further trigger stress tests (added by Member 3 in
-- Week 3 integration). Each test reads ids/slots from the data,
-- expects one error or one recalculation, and restores the data.
-- ============================================================

-- TEST 4: RESCHEDULE INTO A TAKEN SLOT  (trg_check_doctor_availability_upd)
-- Move appointment 12 onto appointment 11's doctor / date / time.
-- Expected: ERROR ERR_DOUBLE_BOOKING, appointment 12 unchanged.
SELECT doctor_id, appt_date, appt_time INTO @d11, @dt11, @tm11
FROM Appointments WHERE appt_id = 11;

UPDATE Appointments
SET doctor_id = @d11, appt_date = @dt11, appt_time = @tm11
WHERE appt_id = 12;

SELECT appt_id, doctor_id, appt_date, appt_time, status
FROM Appointments WHERE appt_id = 12;          -- still its original slot


-- TEST 5: UN-CANCEL INTO A SLOT THAT WAS RE-BOOKED
-- Appointment 8 is Cancelled, so its slot may be booked again (allowed).
-- Then trying to make appointment 8 'Scheduled' again must fail.
-- Expected: the INSERT succeeds; the UPDATE gives ERROR ERR_DOUBLE_BOOKING.
SELECT doctor_id, appt_date, appt_time INTO @d8, @dt8, @tm8
FROM Appointments WHERE appt_id = 8;

INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time, status, reason)
VALUES (12, @d8, @dt8, @tm8, 'Scheduled', 'Stress test: re-booked cancelled slot');
SET @rebooked = LAST_INSERT_ID();

UPDATE Appointments SET status = 'Scheduled' WHERE appt_id = 8;

SELECT appt_id, status FROM Appointments WHERE appt_id IN (8, @rebooked);   -- 8 stays Cancelled

DELETE FROM Appointments WHERE appt_id = @rebooked;                          -- clean up


-- TEST 6: LAB ORDER ON A PAID VISIT  (trg_block_lab_order_after_payment)
-- Appointment 1 is completed and its bill is Paid.
-- Expected: ERROR ERR_BILL_PAID, no new lab order.
SELECT COUNT(*) INTO @labs_before FROM Lab_Orders WHERE appt_id = 1;

INSERT INTO Lab_Orders (appt_id, test_id)
VALUES (1, (SELECT test_id FROM Diagnostic_Tests WHERE test_name = 'ESR'));

SELECT @labs_before AS labs_before,
       (SELECT COUNT(*) FROM Lab_Orders WHERE appt_id = 1) AS labs_after_same;


-- TEST 7: AUTOMATIC BILL RECALCULATION  (trg_update_bill_on_lab_order_ins / _del)
-- Appointment 10 has a 'Generated' bill. Ordering one more test must
-- re-price the bill and pull it back to 'Draft'; removing the test
-- must re-price it again.
SELECT status, lab_total, total_amount FROM Bills WHERE appt_id = 10;   -- before

INSERT INTO Lab_Orders (appt_id, test_id)
VALUES (10, (SELECT test_id FROM Diagnostic_Tests WHERE test_name = 'ESR'));
SET @extra_lab = LAST_INSERT_ID();

SELECT status AS status_now_draft, lab_total, total_amount
FROM Bills WHERE appt_id = 10;                                           -- Draft, +100.00

DELETE FROM Lab_Orders WHERE lab_order_id = @extra_lab;                  -- clean up

SELECT status, lab_total, total_amount
FROM Bills WHERE appt_id = 10;                                           -- total back to before

UPDATE Bills SET status = 'Generated' WHERE appt_id = 10 AND status = 'Draft';   -- restore demo state

-- END OF TESTS
