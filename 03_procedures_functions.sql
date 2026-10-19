-- =====================================================================
-- 03_procedures_functions.sql | Owner: Member 1
-- Atomic booking + billing procedures with START TRANSACTION / COMMIT /
-- ROLLBACK.  Run AFTER 01_schema_ddl.sql.
--
-- ERROR CONVENTION (agreed with Members 2 & 3)
--   Every business-rule failure is SQLSTATE '45000' and MESSAGE_TEXT
--   starts with a code:  ERR_<CODE>: human readable text
--   Streamlit shows the text after the first ': ' to the user.
-- =====================================================================
USE clinic_portal;

DROP FUNCTION  IF EXISTS fn_lab_total;
DROP PROCEDURE IF EXISTS sp_book_appointment;
DROP PROCEDURE IF EXISTS sp_generate_or_finalize_bill;

DELIMITER //

-- ---------------------------------------------------------------------
-- fn_lab_total: sum of test costs ordered for an appointment.
-- Reusable by the bill procedure and by Member 2's trigger.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_lab_total(p_appt_id INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2);
    SELECT IFNULL(SUM(t.cost), 0) INTO v_total
    FROM Lab_Orders lo
    JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
    WHERE lo.appt_id = p_appt_id;
    RETURN v_total;
END//

-- ---------------------------------------------------------------------
-- sp_book_appointment
--   Atomically books a slot.
--   Atomicity  : any error -> ROLLBACK, nothing is inserted.
--   Isolation  : SELECT ... FOR UPDATE on the doctor row serialises
--                concurrent bookings for the same doctor, so two users
--                cannot both pass the availability check.
--   Consistency: patient/doctor must exist, date not in the past,
--                slot must be free (cancelled bookings do not block).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_book_appointment(
    IN  p_patient_id INT,
    IN  p_doctor_id  INT,
    IN  p_appt_date  DATE,
    IN  p_appt_time  TIME,
    IN  p_reason     VARCHAR(200),
    OUT p_appt_id    INT
)
BEGIN
    DECLARE v_cnt INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;          -- re-raise original error (incl. Member 2's trigger)
    END;

    SET p_appt_id = NULL;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_cnt FROM Patients WHERE patient_id = p_patient_id;
    IF v_cnt = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_PATIENT_NOT_FOUND: Patient does not exist';
    END IF;

    -- Lock the doctor row: concurrent bookings for this doctor queue up here
    SELECT COUNT(*) INTO v_cnt FROM Doctors WHERE doctor_id = p_doctor_id FOR UPDATE;
    IF v_cnt = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DOCTOR_NOT_FOUND: Doctor does not exist';
    END IF;

    IF p_appt_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_PAST_DATE: Cannot book an appointment in the past';
    END IF;

    IF p_appt_time < '09:00:00' OR p_appt_time > '16:30:00'
       OR MINUTE(p_appt_time) NOT IN (0, 30) OR SECOND(p_appt_time) <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_BAD_SLOT: Slots run 09:00-16:30 in 30-minute steps';
    END IF;

    SELECT COUNT(*) INTO v_cnt
    FROM Appointments
    WHERE doctor_id = p_doctor_id
      AND appt_date = p_appt_date
      AND appt_time = p_appt_time
      AND status <> 'Cancelled';
    IF v_cnt > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_DOUBLE_BOOKING: Doctor already has an appointment at this time';
    END IF;

    INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time, reason)
    VALUES (p_patient_id, p_doctor_id, p_appt_date, p_appt_time, p_reason);

    SET p_appt_id = LAST_INSERT_ID();

    COMMIT;
END//

-- ---------------------------------------------------------------------
-- sp_generate_or_finalize_bill
--   p_action = 'GENERATE' : create (or recompute) the bill, status
--                           'Generated'. All lab orders must be Completed.
--   p_action = 'PAY'      : mark the bill 'Paid' (totals recomputed one
--                           last time), appointment -> 'Completed'.
--   Everything runs in ONE transaction: a failure at any step leaves the
--   bill and appointment exactly as they were.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_generate_or_finalize_bill(
    IN  p_appt_id       INT,
    IN  p_action        VARCHAR(10),
    IN  p_payment_mode  VARCHAR(20),
    OUT p_bill_id       INT,
    OUT p_total         DECIMAL(10,2)
)
BEGIN
    DECLARE v_appt_status  VARCHAR(15);
    DECLARE v_doctor_id    INT;
    DECLARE v_fee          DECIMAL(10,2);
    DECLARE v_lab          DECIMAL(10,2);
    DECLARE v_bill_status  VARCHAR(15);
    DECLARE v_pending      INT DEFAULT 0;
    DECLARE v_cnt          INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_bill_id = NULL;
    SET p_total   = NULL;
    SET p_action  = UPPER(p_action);

    START TRANSACTION;

    IF p_action NOT IN ('GENERATE','PAY') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_BAD_ACTION: Action must be GENERATE or PAY';
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM Appointments WHERE appt_id = p_appt_id;
    IF v_cnt = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_APPT_NOT_FOUND: Appointment does not exist';
    END IF;

    -- lock the appointment so two clerks cannot bill it at the same time
    SELECT status, doctor_id INTO v_appt_status, v_doctor_id
    FROM Appointments WHERE appt_id = p_appt_id FOR UPDATE;

    IF v_appt_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_APPT_CANCELLED: Cannot bill a cancelled appointment';
    END IF;

    SELECT consultation_fee INTO v_fee FROM Doctors WHERE doctor_id = v_doctor_id;
    SET v_lab = fn_lab_total(p_appt_id);

    SELECT COUNT(*) INTO v_pending
    FROM Lab_Orders WHERE appt_id = p_appt_id AND status <> 'Completed';

    SELECT COUNT(*) INTO v_cnt FROM Bills WHERE appt_id = p_appt_id;
    IF v_cnt = 1 THEN
        SELECT bill_id, status INTO p_bill_id, v_bill_status
        FROM Bills WHERE appt_id = p_appt_id FOR UPDATE;
        IF v_bill_status = 'Paid' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_ALREADY_PAID: Bill is already paid';
        END IF;
    END IF;

    IF p_action = 'GENERATE' THEN
        IF v_pending > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_LABS_PENDING: Complete all lab tests before generating the invoice';
        END IF;

        IF v_cnt = 0 THEN
            INSERT INTO Bills (appt_id, consultation_fee, lab_total, total_amount, status)
            VALUES (p_appt_id, v_fee, v_lab, v_fee + v_lab, 'Generated');
            SET p_bill_id = LAST_INSERT_ID();
        ELSE
            UPDATE Bills
            SET consultation_fee = v_fee, lab_total = v_lab,
                total_amount = v_fee + v_lab, status = 'Generated',
                generated_at = NOW()
            WHERE bill_id = p_bill_id;
        END IF;

    ELSE  -- PAY
        IF v_cnt = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_NO_BILL: Generate the invoice before taking payment';
        END IF;
        IF v_pending > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_LABS_PENDING: Complete all lab tests before payment';
        END IF;
        IF p_payment_mode IS NULL OR p_payment_mode = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERR_NO_PAYMENT_MODE: Payment mode is required';
        END IF;

        UPDATE Bills
        SET consultation_fee = v_fee, lab_total = v_lab,
            total_amount = v_fee + v_lab, status = 'Paid',
            paid_at = NOW(), payment_mode = p_payment_mode
        WHERE bill_id = p_bill_id;

        UPDATE Appointments SET status = 'Completed' WHERE appt_id = p_appt_id;
    END IF;

    SELECT total_amount INTO p_total FROM Bills WHERE bill_id = p_bill_id;

    COMMIT;
END//

DELIMITER ;
