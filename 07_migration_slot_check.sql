-- 07_migration_slot_check.sql | Member 1
-- Adds the 30-minute slot rule to an EXISTING clinic_portal database
-- (no need to rebuild). Then re-run 03_procedures_functions.sql.
USE clinic_portal;

-- 1. Existing rows that would break the rule (fix or delete these first)
SELECT appt_id, appt_date, appt_time FROM Appointments
WHERE NOT (appt_time BETWEEN '09:00:00' AND '16:30:00'
           AND MINUTE(appt_time) IN (0,30) AND SECOND(appt_time) = 0);

-- 2. Example fix for one bad row (edit the id):
-- UPDATE Appointments SET appt_time = '10:30:00' WHERE appt_id = 1;

-- 3. Add the rule (fails if step 1 still returns rows)
ALTER TABLE Appointments
  ADD CONSTRAINT chk_appt_slot
  CHECK (appt_time BETWEEN '09:00:00' AND '16:30:00'
         AND MINUTE(appt_time) IN (0,30) AND SECOND(appt_time) = 0);
