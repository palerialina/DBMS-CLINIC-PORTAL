-- =====================================================================
-- 06_backend_tests.sql | Owner: Member 1 | Week 3-4 test evidence
-- Run with:  mysql -u root -p --force --table clinic_portal < 06_backend_tests.sql
-- (--force keeps going after the INTENTIONAL errors marked EXPECT ERROR)
-- Uses its own fixtures (ZZ_ prefix) and removes them at the end, so it
-- is safe to run on top of Member 2's sample data.
-- Requires 01, 03 (and 02 if you want the triggers active) to be loaded.
-- =====================================================================
USE clinic_portal;

-- ---------------------------------------------------------------------
-- FIXTURES
-- ---------------------------------------------------------------------
INSERT INTO Departments(dept_name) VALUES ('ZZ_Dept');
SET @dept = LAST_INSERT_ID();
INSERT INTO Doctors(doctor_name, dept_id, license_no, phone, consultation_fee)
VALUES ('ZZ_Doctor', @dept, 'ZZ-LIC-1', '9000000001', 500.00);
SET @doc = LAST_INSERT_ID();
INSERT INTO Patients(first_name,last_name,dob,gender,phone)
VALUES ('ZZ','Patient','1995-05-05','M','9000000002');
SET @pat = LAST_INSERT_ID();
INSERT INTO Medications(med_name,strength) VALUES ('ZZ_Med','500mg');
SET @med = LAST_INSERT_ID();
INSERT INTO Diagnostic_Tests(test_name,category,unit,ref_range_low,ref_range_high,cost)
VALUES ('ZZ_Test','Blood','mg/dL',70,110,300.00);
SET @test = LAST_INSERT_ID();

SELECT '=== A. CONSTRAINT TESTS ===' AS section;

SELECT 'A1 UNIQUE: duplicate patient phone -- EXPECT ERROR 1062' AS test;
INSERT INTO Patients(first_name,last_name,dob,gender,phone)
VALUES ('Dup','Phone','1990-01-01','F','9000000002');

SELECT 'A2 CHECK: negative consultation fee -- EXPECT ERROR 3819' AS test;
INSERT INTO Doctors(doctor_name,dept_id,license_no,phone,consultation_fee)
VALUES ('Bad Fee',@dept,'ZZ-LIC-2','9000000003',-10);

SELECT 'A3 CHECK: invalid gender -- EXPECT ERROR 3819' AS test;
INSERT INTO Patients(first_name,last_name,dob,gender,phone)
VALUES ('Bad','Gender','1990-01-01','X','9000000004');

SELECT 'A4 FK: appointment for nonexistent doctor -- EXPECT ERROR 1452' AS test;
INSERT INTO Appointments(patient_id,doctor_id,appt_date,appt_time)
VALUES (@pat, 999999, CURDATE() + INTERVAL 30 DAY, '10:00:00');

SELECT 'A5 CHECK: invalid appointment status -- EXPECT ERROR 3819' AS test;
INSERT INTO Appointments(patient_id,doctor_id,appt_date,appt_time,status)
VALUES (@pat,@doc,CURDATE() + INTERVAL 30 DAY,'10:00:00','Pending');

SELECT 'A6 NOT NULL: patient without phone -- EXPECT ERROR 1364/1048' AS test;
INSERT INTO Patients(first_name,last_name,dob,gender) VALUES ('No','Phone','1990-01-01','M');

SELECT 'A7 CHECK: reversed reference range -- EXPECT ERROR 3819' AS test;
INSERT INTO Diagnostic_Tests(test_name,category,ref_range_low,ref_range_high,cost)
VALUES ('ZZ_BadRange','Blood',200,100,50);

-- ---------------------------------------------------------------------
SELECT '=== B. PROCEDURE + TRANSACTION TESTS ===' AS section;

SET @day = CURDATE() + INTERVAL 7 DAY;

SELECT 'B1 booking succeeds -- EXPECT appt id returned' AS test;
CALL sp_book_appointment(@pat, @doc, @day, '10:00:00', 'Checkup', @appt1);
SELECT @appt1 AS appt1, status FROM Appointments WHERE appt_id = @appt1;

SELECT 'B2 double booking -- EXPECT ERR_DOUBLE_BOOKING' AS test;
SELECT COUNT(*) AS rows_before FROM Appointments WHERE doctor_id=@doc;
CALL sp_book_appointment(@pat, @doc, @day, '10:00:00', 'Duplicate', @x);
SELECT COUNT(*) AS rows_after_unchanged FROM Appointments WHERE doctor_id=@doc;

SELECT 'B3 unknown patient -- EXPECT ERR_PATIENT_NOT_FOUND' AS test;
CALL sp_book_appointment(999999, @doc, @day, '11:00:00', NULL, @x);

SELECT 'B4 unknown doctor -- EXPECT ERR_DOCTOR_NOT_FOUND' AS test;
CALL sp_book_appointment(@pat, 999999, @day, '11:00:00', NULL, @x);

SELECT 'B5 past date -- EXPECT ERR_PAST_DATE' AS test;
CALL sp_book_appointment(@pat, @doc, CURDATE() - INTERVAL 1 DAY, '11:00:00', NULL, @x);

SELECT 'B6 cancelled slot can be rebooked -- EXPECT success' AS test;
UPDATE Appointments SET status='Cancelled' WHERE appt_id=@appt1;
CALL sp_book_appointment(@pat, @doc, @day, '10:00:00', 'Rebook', @appt2);
SELECT @appt2 AS appt2, status FROM Appointments WHERE appt_id=@appt2;

SELECT 'B7 bill for cancelled appointment -- EXPECT ERR_APPT_CANCELLED' AS test;
CALL sp_generate_or_finalize_bill(@appt1, 'GENERATE', NULL, @b, @t);

-- order a lab test for appt2
INSERT INTO Lab_Orders(appt_id,test_id) VALUES (@appt2,@test);
SET @lab = LAST_INSERT_ID();

SELECT 'B8 bill while lab pending -- EXPECT ERR_LABS_PENDING' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'GENERATE', NULL, @b, @t);
SELECT COUNT(*) AS bills_created_should_be_0 FROM Bills WHERE appt_id=@appt2;

UPDATE Lab_Orders SET status='Completed', result_value=95, completed_at=NOW() WHERE lab_order_id=@lab;

SELECT 'B9 generate invoice -- EXPECT total = 500 + 300 = 800' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'GENERATE', NULL, @bill, @total);
SELECT @bill AS bill_id, @total AS total;
SELECT * FROM Bills WHERE bill_id=@bill;

SELECT 'B10 pay without payment mode -- EXPECT ERR_NO_PAYMENT_MODE, bill stays Generated' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'PAY', NULL, @b, @t);
SELECT status AS bill_status_unchanged FROM Bills WHERE bill_id=@bill;

SELECT 'B11 pay -- EXPECT bill Paid, appointment Completed' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'PAY', 'UPI', @b, @t);
SELECT b.status AS bill_status, a.status AS appt_status
FROM Bills b JOIN Appointments a ON a.appt_id=b.appt_id WHERE b.bill_id=@bill;

SELECT 'B12 pay twice -- EXPECT ERR_ALREADY_PAID' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'PAY', 'UPI', @b, @t);

SELECT 'B13 bad action -- EXPECT ERR_BAD_ACTION' AS test;
CALL sp_generate_or_finalize_bill(@appt2, 'REFUND', NULL, @b, @t);

-- ---------------------------------------------------------------------
SELECT '=== C. CASCADE / RESTRICT TESTS ===' AS section;

SELECT 'C1 RESTRICT: delete doctor who has appointments -- EXPECT ERROR 1451' AS test;
DELETE FROM Doctors WHERE doctor_id=@doc;

SELECT 'C2 RESTRICT: delete department that has doctors -- EXPECT ERROR 1451' AS test;
DELETE FROM Departments WHERE dept_id=@dept;

SELECT 'C3 RESTRICT: delete patient who has appointments -- EXPECT ERROR 1451' AS test;
DELETE FROM Patients WHERE patient_id=@pat;

SELECT 'C4 RESTRICT: delete appointment that has a bill -- EXPECT ERROR 1451' AS test;
DELETE FROM Appointments WHERE appt_id=@appt2;

SELECT 'C5 RESTRICT: delete medication used in a prescription -- EXPECT ERROR 1451' AS test;
CALL sp_book_appointment(@pat, @doc, @day, '12:00:00', 'Cascade test', @appt3);
INSERT INTO Prescriptions(appt_id,med_id,dosage,frequency,duration_days)
VALUES (@appt3,@med,'1 tablet','twice daily',5);
INSERT INTO Lab_Orders(appt_id,test_id) VALUES (@appt3,@test);
DELETE FROM Medications WHERE med_id=@med;

SELECT 'C6 CASCADE: delete appointment with no bill -- children must vanish' AS test;
SELECT (SELECT COUNT(*) FROM Prescriptions WHERE appt_id=@appt3) AS presc_before,
       (SELECT COUNT(*) FROM Lab_Orders    WHERE appt_id=@appt3) AS labs_before;
DELETE FROM Appointments WHERE appt_id=@appt3;
SELECT (SELECT COUNT(*) FROM Prescriptions WHERE appt_id=@appt3) AS presc_after_should_be_0,
       (SELECT COUNT(*) FROM Lab_Orders    WHERE appt_id=@appt3) AS labs_after_should_be_0;

-- ---------------------------------------------------------------------
-- CLEANUP (children first)
-- ---------------------------------------------------------------------
DELETE FROM Bills          WHERE appt_id IN (@appt1,@appt2);
DELETE FROM Appointments   WHERE patient_id=@pat;   -- cascades to prescriptions / lab orders
DELETE FROM Audit_Logs     WHERE table_name='Appointments' AND record_id IN (@appt1,@appt2,@appt3);
DELETE FROM Patients       WHERE patient_id=@pat;
DELETE FROM Doctors        WHERE doctor_id=@doc;
DELETE FROM Departments    WHERE dept_id=@dept;
DELETE FROM Medications    WHERE med_id=@med;
DELETE FROM Diagnostic_Tests WHERE test_id=@test;
SELECT '=== DONE: fixtures removed ===' AS section;
