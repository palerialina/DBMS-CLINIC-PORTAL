-- =====================================================================
-- 01_schema_ddl.sql  |  Digital Health Clinic & Diagnostic Lab Portal
-- Owner: Member 1 (Database Architect)   |   Target: MySQL 8.0.16+
-- (CHECK constraints are only enforced from 8.0.16 onwards)
-- Run order for a clean setup: 01 -> 02 -> 03 -> 04 -> 05 -> 05b
-- (simplest: run 00_setup_all.sql, which loads them in this order)
-- =====================================================================

DROP DATABASE IF EXISTS clinic_portal;
CREATE DATABASE clinic_portal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE clinic_portal;

-- ---------------------------------------------------------------------
-- 1. Departments
-- ---------------------------------------------------------------------
CREATE TABLE Departments (
    dept_id     INT AUTO_INCREMENT PRIMARY KEY,
    dept_name   VARCHAR(80)  NOT NULL,
    location    VARCHAR(80),
    CONSTRAINT uq_dept_name UNIQUE (dept_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Doctors  (N:1 Departments)
-- ---------------------------------------------------------------------
CREATE TABLE Doctors (
    doctor_id        INT AUTO_INCREMENT PRIMARY KEY,
    doctor_name      VARCHAR(100) NOT NULL,
    dept_id          INT          NOT NULL,
    specialization   VARCHAR(100),
    license_no       VARCHAR(30)  NOT NULL,
    phone            VARCHAR(15)  NOT NULL,
    email            VARCHAR(100),
    consultation_fee DECIMAL(8,2) NOT NULL,
    CONSTRAINT uq_doctor_license UNIQUE (license_no),
    CONSTRAINT uq_doctor_phone   UNIQUE (phone),
    CONSTRAINT uq_doctor_email   UNIQUE (email),
    CONSTRAINT chk_doctor_fee    CHECK (consultation_fee >= 0),
    CONSTRAINT fk_doctor_dept FOREIGN KEY (dept_id)
        REFERENCES Departments(dept_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Patients
-- ---------------------------------------------------------------------
CREATE TABLE Patients (
    patient_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    dob            DATE         NOT NULL,
    gender         CHAR(1)      NOT NULL,
    phone          VARCHAR(15)  NOT NULL,
    email          VARCHAR(100),
    address        VARCHAR(200),
    blood_group    VARCHAR(3),
    registered_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_patient_phone UNIQUE (phone),
    CONSTRAINT uq_patient_email UNIQUE (email),
    CONSTRAINT chk_patient_gender CHECK (gender IN ('M','F','O')),
    CONSTRAINT chk_patient_blood  CHECK (blood_group IS NULL OR
        blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-'))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Appointments  (N:1 Patients, N:1 Doctors)
--    Double-booking is blocked by (a) sp_book_appointment, which checks
--    for an active booking under a row lock, and (b) Member 2's trigger
--    trg_check_doctor_availability as a second line of defence.
--    A plain UNIQUE(doctor, date, time) is deliberately NOT used: it
--    would stop a slot being re-booked after a cancellation.
-- ---------------------------------------------------------------------
CREATE TABLE Appointments (
    appt_id      INT AUTO_INCREMENT PRIMARY KEY,
    patient_id   INT         NOT NULL,
    doctor_id    INT         NOT NULL,
    appt_date    DATE        NOT NULL,
    appt_time    TIME        NOT NULL,
    status       VARCHAR(15) NOT NULL DEFAULT 'Scheduled',
    reason       VARCHAR(200),
    created_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_appt_status CHECK (status IN ('Scheduled','Completed','Cancelled')),
    -- clinic hours 09:00-16:30 (last slot), 30-minute slots only
    CONSTRAINT chk_appt_slot CHECK (appt_time BETWEEN '09:00:00' AND '16:30:00'
                                    AND MINUTE(appt_time) IN (0, 30) AND SECOND(appt_time) = 0),
    CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id)
        REFERENCES Patients(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_doctor FOREIGN KEY (doctor_id)
        REFERENCES Doctors(doctor_id)   ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_appt_slot (doctor_id, appt_date, appt_time),
    INDEX idx_appt_patient (patient_id),
    INDEX idx_appt_date (appt_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Medications (master list)
-- ---------------------------------------------------------------------
CREATE TABLE Medications (
    med_id        INT AUTO_INCREMENT PRIMARY KEY,
    med_name      VARCHAR(100) NOT NULL,
    form          VARCHAR(30),            -- tablet, syrup, injection ...
    strength      VARCHAR(30),
    CONSTRAINT uq_medication UNIQUE (med_name, strength)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Prescriptions  (one row per prescribed medicine line)
--    Child of Appointments: CASCADE (a line has no meaning without its
--    appointment). Medication is RESTRICTed so history is never lost.
-- ---------------------------------------------------------------------
CREATE TABLE Prescriptions (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    appt_id         INT         NOT NULL,
    med_id          INT         NOT NULL,
    dosage          VARCHAR(50) NOT NULL,
    frequency       VARCHAR(50) NOT NULL,
    duration_days   INT         NOT NULL,
    notes           VARCHAR(200),
    CONSTRAINT chk_presc_duration CHECK (duration_days > 0),
    CONSTRAINT uq_presc_line UNIQUE (appt_id, med_id),
    CONSTRAINT fk_presc_appt FOREIGN KEY (appt_id)
        REFERENCES Appointments(appt_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_presc_med FOREIGN KEY (med_id)
        REFERENCES Medications(med_id)   ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. Diagnostic_Tests (catalogue)
-- ---------------------------------------------------------------------
CREATE TABLE Diagnostic_Tests (
    test_id         INT AUTO_INCREMENT PRIMARY KEY,
    test_name       VARCHAR(100) NOT NULL,
    category        VARCHAR(50)  NOT NULL,
    unit            VARCHAR(20),
    ref_range_low   DECIMAL(10,2),
    ref_range_high  DECIMAL(10,2),
    cost            DECIMAL(8,2) NOT NULL,
    CONSTRAINT uq_test_name UNIQUE (test_name),
    CONSTRAINT chk_test_cost CHECK (cost >= 0),
    CONSTRAINT chk_test_range CHECK (ref_range_low IS NULL OR ref_range_high IS NULL
                                     OR ref_range_low <= ref_range_high)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. Lab_Orders  (a test ordered during an appointment)
--    Workflow: Ordered -> Sample Collected -> Completed
-- ---------------------------------------------------------------------
CREATE TABLE Lab_Orders (
    lab_order_id         INT AUTO_INCREMENT PRIMARY KEY,
    appt_id              INT         NOT NULL,
    test_id              INT         NOT NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'Ordered',
    ordered_at           DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sample_collected_at  DATETIME,
    result_value         DECIMAL(10,2),
    result_notes         VARCHAR(200),
    completed_at         DATETIME,
    CONSTRAINT chk_lab_status CHECK (status IN ('Ordered','Sample Collected','Completed')),
    CONSTRAINT uq_lab_order UNIQUE (appt_id, test_id),
    CONSTRAINT fk_lab_appt FOREIGN KEY (appt_id)
        REFERENCES Appointments(appt_id)  ON DELETE CASCADE  ON UPDATE CASCADE,
    CONSTRAINT fk_lab_test FOREIGN KEY (test_id)
        REFERENCES Diagnostic_Tests(test_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_lab_status (status)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. Bills  (exactly one bill per appointment)
--    RESTRICT: financial records must not vanish with an appointment.
-- ---------------------------------------------------------------------
CREATE TABLE Bills (
    bill_id          INT AUTO_INCREMENT PRIMARY KEY,
    appt_id          INT          NOT NULL,
    consultation_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    lab_total        DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amount     DECIMAL(10,2) NOT NULL DEFAULT 0,
    status           VARCHAR(15)  NOT NULL DEFAULT 'Draft',
    generated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at          DATETIME,
    payment_mode     VARCHAR(20),
    CONSTRAINT uq_bill_appt UNIQUE (appt_id),
    CONSTRAINT chk_bill_status CHECK (status IN ('Draft','Generated','Paid')),
    CONSTRAINT chk_bill_amounts CHECK (consultation_fee >= 0 AND lab_total >= 0 AND total_amount >= 0),
    CONSTRAINT fk_bill_appt FOREIGN KEY (appt_id)
        REFERENCES Appointments(appt_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 10. Audit_Logs  (no FKs on purpose: a log must survive deletions)
-- ---------------------------------------------------------------------
CREATE TABLE Audit_Logs (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    table_name  VARCHAR(50) NOT NULL,
    record_id   INT         NOT NULL,
    action      VARCHAR(30) NOT NULL,
    old_status  VARCHAR(20),
    new_status  VARCHAR(20),
    details     VARCHAR(255),
    logged_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_record (table_name, record_id)
) ENGINE=InnoDB;
