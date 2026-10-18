-- =====================================================================
-- 02_triggers.sql | Owner: Member 2 | Triggers
-- Load order: 01_schema_ddl.sql -> 02_triggers.sql -> 03_procedures_functions.sql
--             -> 04_views_queries.sql -> 05_sample_data.sql
-- (This file is self-contained: it does not depend on 03.)
-- =====================================================================
USE clinic_portal;

DROP TRIGGER IF EXISTS trg_check_doctor_availability;
DROP TRIGGER IF EXISTS trg_check_doctor_availability_upd;
DROP TRIGGER IF EXISTS trg_update_bill_on_lab_order_ins;
DROP TRIGGER IF EXISTS trg_update_bill_on_lab_order_upd;
DROP TRIGGER IF EXISTS trg_update_bill_on_lab_order_del;
DROP TRIGGER IF EXISTS trg_block_lab_order_after_payment;
DROP TRIGGER IF EXISTS trg_audit_appointment_cancellation;
DROP PROCEDURE IF EXISTS sp_recalc_bill;

DELIMITER //

-- ---------------------------------------------------------------------
-- Helper: recompute lab_total / total_amount of an UNPAID bill.
-- (MySQL triggers cannot be shared across events, so the three
--  Lab_Orders triggers all call this one routine.)
-- If a new unfinished lab order appears on a 'Generated' bill, the bill
-- is pulled back to 'Draft' because the invoice is no longer final.
-- Paid bills are never touched.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_recalc_bill(IN p_appt_id INT)
BEGIN
    DECLARE v_lab     DECIMAL(10,2);
    DECLARE v_pending INT;

    SELECT IFNULL(SUM(t.cost), 0) INTO v_lab
    FROM Lab_Orders lo
    JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
    WHERE lo.appt_id = p_appt_id;

    SELECT COUNT(*) INTO v_pending
    FROM Lab_Orders
    WHERE appt_id = p_appt_id AND status <> 'Completed';

    UPDATE Bills
    SET lab_total    = v_lab,
        total_amount = consultation_fee + v_lab,
        status       = IF(status = 'Generated' AND v_pending > 0, 'Draft', status)
    WHERE appt_id = p_appt_id
      AND status <> 'Paid';
END//

-- ---------------------------------------------------------------------
-- TRIGGER 1: trg_check_doctor_availability
-- BEFORE INSERT: reject a second live appointment for the same
-- doctor / date / time slot (Cancelled slots may be rebooked).
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_check_doctor_availability
BEFORE INSERT ON Appointments
FOR EACH ROW
BEGIN
    DECLARE v_cnt INT DEFAULT 0;

    IF NEW.status <> 'Cancelled' THEN
        SELECT COUNT(*) INTO v_cnt
        FROM Appointments
        WHERE doctor_id = NEW.doctor_id
          AND appt_date = NEW.appt_date
          AND appt_time = NEW.appt_time
          AND status <> 'Cancelled';

        IF v_cnt > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERR_DOUBLE_BOOKING: Doctor already has an appointment at this time';
        END IF;
    END IF;
END//

-- Same rule on UPDATE (rescheduling, changing doctor, or un-cancelling).
CREATE TRIGGER trg_check_doctor_availability_upd
BEFORE UPDATE ON Appointments
FOR EACH ROW
BEGIN
    DECLARE v_cnt INT DEFAULT 0;

    IF NEW.status <> 'Cancelled'
       AND (   OLD.doctor_id <> NEW.doctor_id
            OR OLD.appt_date <> NEW.appt_date
            OR OLD.appt_time <> NEW.appt_time
            OR OLD.status    =  'Cancelled') THEN

        SELECT COUNT(*) INTO v_cnt
        FROM Appointments
        WHERE doctor_id = NEW.doctor_id
          AND appt_date = NEW.appt_date
          AND appt_time = NEW.appt_time
          AND status <> 'Cancelled'
          AND appt_id <> NEW.appt_id;

        IF v_cnt > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERR_DOUBLE_BOOKING: Doctor already has an appointment at this time';
        END IF;
    END IF;
END//

-- ---------------------------------------------------------------------
-- TRIGGER 2: trg_update_bill_on_lab_order  (auto bill recalculation)
-- Fires after a lab order is added, changed or removed.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_update_bill_on_lab_order_ins
AFTER INSERT ON Lab_Orders
FOR EACH ROW
BEGIN
    CALL sp_recalc_bill(NEW.appt_id);
END//

CREATE TRIGGER trg_update_bill_on_lab_order_upd
AFTER UPDATE ON Lab_Orders
FOR EACH ROW
BEGIN
    CALL sp_recalc_bill(NEW.appt_id);
    IF OLD.appt_id <> NEW.appt_id THEN
        CALL sp_recalc_bill(OLD.appt_id);
    END IF;
END//

CREATE TRIGGER trg_update_bill_on_lab_order_del
AFTER DELETE ON Lab_Orders
FOR EACH ROW
BEGIN
    CALL sp_recalc_bill(OLD.appt_id);
END//

-- Guard: no new lab orders once the bill has been paid.
CREATE TRIGGER trg_block_lab_order_after_payment
BEFORE INSERT ON Lab_Orders
FOR EACH ROW
BEGIN
    DECLARE v_paid INT DEFAULT 0;
    SELECT COUNT(*) INTO v_paid
    FROM Bills WHERE appt_id = NEW.appt_id AND status = 'Paid';
    IF v_paid > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERR_BILL_PAID: Cannot add lab tests to an appointment whose bill is paid';
    END IF;
END//

-- ---------------------------------------------------------------------
-- TRIGGER 3: trg_audit_appointment_cancellation
-- Logs every appointment status transition into Audit_Logs
-- (cancellations are tagged action = 'CANCELLED').
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_audit_appointment_cancellation
AFTER UPDATE ON Appointments
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO Audit_Logs (table_name, record_id, action, old_status, new_status, details)
        VALUES ('Appointments',
                NEW.appt_id,
                IF(NEW.status = 'Cancelled', 'CANCELLED', 'STATUS_CHANGE'),
                OLD.status,
                NEW.status,
                CONCAT('Doctor ', NEW.doctor_id, ', patient ', NEW.patient_id,
                       ', slot ', NEW.appt_date, ' ', NEW.appt_time));
    END IF;
END//

DELIMITER ;
