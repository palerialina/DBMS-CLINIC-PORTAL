-- =====================================================================
-- 05_sample_data.sql | Owner: Member 2 | Seed data
-- Run on a FRESH database (after 01 and 02) so auto-increment ids start
-- at 1; the appointment/lab rows below refer to ids by position.
-- Dates are relative to CURDATE() so the demo never goes stale.
-- =====================================================================
USE clinic_portal;

-- 5 departments ------------------------------------------------------
INSERT INTO Departments (dept_name, location) VALUES
('General Medicine', 'Block A, Ground Floor'),
('Cardiology',       'Block B, 1st Floor'),
('Pediatrics',       'Block A, 1st Floor'),
('Orthopedics',      'Block C, Ground Floor'),
('Dermatology',      'Block C, 2nd Floor');

-- 10 doctors (ids 1-10, two per department in order) ------------------
INSERT INTO Doctors (doctor_name, dept_id, specialization, license_no, phone, email, consultation_fee) VALUES
('Dr. Arvind Menon',   1, 'General Physician',   'TNMC-10001', '9840010001', 'arvind.menon@clinic.in',   400.00),
('Dr. Sunita Rao',     1, 'Internal Medicine',   'TNMC-10002', '9840010002', 'sunita.rao@clinic.in',     500.00),
('Dr. Rahul Verma',    2, 'Interventional Cardiology', 'TNMC-10003', '9840010003', 'rahul.verma@clinic.in', 900.00),
('Dr. Meera Iyer',     2, 'Cardiac Electrophysiology', 'TNMC-10004', '9840010004', 'meera.iyer@clinic.in',  850.00),
('Dr. Karthik Subramanian', 3, 'General Pediatrics', 'TNMC-10005', '9840010005', 'karthik.s@clinic.in',  500.00),
('Dr. Anita Desai',    3, 'Neonatology',         'TNMC-10006', '9840010006', 'anita.desai@clinic.in',    600.00),
('Dr. Vikram Singh',   4, 'Joint Replacement',   'TNMC-10007', '9840010007', 'vikram.singh@clinic.in',   700.00),
('Dr. Priya Nair',     4, 'Sports Medicine',     'TNMC-10008', '9840010008', 'priya.nair@clinic.in',     650.00),
('Dr. Farhan Sheikh',  5, 'Dermatology',         'TNMC-10009', '9840010009', 'farhan.sheikh@clinic.in',  550.00),
('Dr. Lakshmi Pillai', 5, 'Cosmetic Dermatology','TNMC-10010', '9840010010', 'lakshmi.pillai@clinic.in',600.00);

-- 22 diagnostic tests (ids 1-22) --------------------------------------
INSERT INTO Diagnostic_Tests (test_name, category, unit, ref_range_low, ref_range_high, cost) VALUES
('Hemoglobin',              'Hematology',   'g/dL',     12.00,  17.00,  150.00),
('Platelet Count',          'Hematology',   '10^3/uL', 150.00, 450.00,  150.00),
('WBC Count',               'Hematology',   '10^3/uL',   4.00,  11.00,  150.00),
('ESR',                     'Hematology',   'mm/hr',     0.00,  20.00,  100.00),
('Fasting Blood Glucose',   'Biochemistry', 'mg/dL',    70.00, 100.00,   80.00),
('HbA1c',                   'Biochemistry', '%',         4.00,   5.60,  450.00),
('Total Cholesterol',       'Lipid Profile','mg/dL',     0.00, 200.00,  300.00),
('LDL Cholesterol',         'Lipid Profile','mg/dL',     0.00, 100.00,  350.00),
('HDL Cholesterol',         'Lipid Profile','mg/dL',    40.00,  60.00,  350.00),
('Triglycerides',           'Lipid Profile','mg/dL',     0.00, 150.00,  350.00),
('Serum Creatinine',        'Renal',        'mg/dL',     0.60,   1.30,  250.00),
('Blood Urea',              'Renal',        'mg/dL',    15.00,  40.00,  200.00),
('Uric Acid',               'Renal',        'mg/dL',     3.50,   7.20,  220.00),
('SGPT (ALT)',              'Liver',        'U/L',       7.00,  56.00,  250.00),
('TSH',                     'Endocrine',    'mIU/L',     0.40,   4.00,  400.00),
('Vitamin D (25-OH)',       'Vitamins',     'ng/mL',    30.00, 100.00,  900.00),
('Vitamin B12',             'Vitamins',     'pg/mL',   200.00, 900.00,  700.00),
('C-Reactive Protein',      'Inflammation', 'mg/L',      0.00,   5.00,  500.00),
('Urine Routine',           'Urine',         NULL,       NULL,   NULL,  120.00),
('Chest X-Ray',             'Imaging',       NULL,       NULL,   NULL,  600.00),
('ECG',                     'Cardiac',       NULL,       NULL,   NULL,  350.00),
('Ultrasound Abdomen',      'Imaging',       NULL,       NULL,   NULL, 1200.00);

-- 15 patients (ids 1-15) -----------------------------------------------
INSERT INTO Patients (first_name, last_name, dob, gender, phone, email, address, blood_group) VALUES
('Ravi',    'Kumar',     '1985-03-12', 'M', '9840020001', 'ravi.kumar@mail.com',     'Anna Nagar, Chennai',   'B+'),
('Divya',   'Sharma',    '1992-07-25', 'F', '9840020002', 'divya.sharma@mail.com',   'T Nagar, Chennai',      'O+'),
('Suresh',  'Babu',      '1968-11-02', 'M', '9840020003', 'suresh.babu@mail.com',    'Adyar, Chennai',        'A+'),
('Lakshmi', 'Narayanan', '1959-01-18', 'F', '9840020004', 'lakshmi.n@mail.com',      'Mylapore, Chennai',     'AB+'),
('Aarav',   'Patel',     '2018-05-09', 'M', '9840020005', NULL,                      'Velachery, Chennai',    'O-'),
('Mohammed','Iqbal',     '1977-09-30', 'M', '9840020006', 'm.iqbal@mail.com',        'Tambaram, Chennai',     'B-'),
('Sneha',   'Reddy',     '1999-12-14', 'F', '9840020007', 'sneha.reddy@mail.com',    'Porur, Chennai',        'A-'),
('Arjun',   'Menon',     '1990-04-21', 'M', '9840020008', 'arjun.menon@mail.com',    'Guindy, Chennai',       'O+'),
('Kavitha', 'Raj',       '1982-08-08', 'F', '9840020009', 'kavitha.raj@mail.com',    'Chromepet, Chennai',    'B+'),
('Harish',  'Gupta',     '1973-02-27', 'M', '9840020010', 'harish.gupta@mail.com',   'Perambur, Chennai',     'A+'),
('Nisha',   'Joseph',    '1995-06-16', 'F', '9840020011', 'nisha.joseph@mail.com',   'Kodambakkam, Chennai',  'O+'),
('Vijay',   'Anand',     '1988-10-05', 'M', '9840020012', 'vijay.anand@mail.com',    'Saidapet, Chennai',     'AB-'),
('Pooja',   'Krishnan',  '2015-03-03', 'F', '9840020013', NULL,                      'Thiruvanmiyur, Chennai','B+'),
('Imran',   'Khan',      '1965-12-24', 'M', '9840020014', 'imran.khan@mail.com',     'Royapettah, Chennai',   'O+'),
('Deepa',   'Venkat',    '1993-01-11', 'F', '9840020015', 'deepa.venkat@mail.com',   'Besant Nagar, Chennai', 'A+');

-- 12 medications (ids 1-12) --------------------------------------------
INSERT INTO Medications (med_name, form, strength) VALUES
('Paracetamol',   'Tablet',  '500mg'),
('Amoxicillin',   'Capsule', '500mg'),
('Azithromycin',  'Tablet',  '500mg'),
('Metformin',     'Tablet',  '500mg'),
('Atorvastatin',  'Tablet',  '10mg'),
('Amlodipine',    'Tablet',  '5mg'),
('Cetirizine',    'Tablet',  '10mg'),
('Ibuprofen',     'Tablet',  '400mg'),
('Pantoprazole',  'Tablet',  '40mg'),
('Clotrimazole',  'Cream',   '1%'),
('ORS',           'Sachet',  '21g'),
('Vitamin D3',    'Capsule', '60000IU');

-- Appointments (ids 1-16) ----------------------------------------------
-- 1-7, 9 completed & paid | 8 cancelled | 10 awaiting payment
-- 11-15 upcoming | 16 today, labs in progress
INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time, status, reason, created_at) VALUES
( 1, 1, CURDATE() - INTERVAL 30 DAY, '09:00:00', 'Completed', 'Fever and body ache',        NOW() - INTERVAL 32 DAY),
( 2, 1, CURDATE() - INTERVAL 30 DAY, '09:30:00', 'Completed', 'Seasonal allergy',           NOW() - INTERVAL 31 DAY),
( 3, 3, CURDATE() - INTERVAL 21 DAY, '10:00:00', 'Completed', 'Chest discomfort',           NOW() - INTERVAL 24 DAY),
( 4, 3, CURDATE() - INTERVAL 21 DAY, '10:30:00', 'Completed', 'Diabetes follow-up',         NOW() - INTERVAL 23 DAY),
( 5, 5, CURDATE() - INTERVAL 14 DAY, '11:00:00', 'Completed', 'Loose motions',              NOW() - INTERVAL 15 DAY),
( 6, 7, CURDATE() - INTERVAL 14 DAY, '14:00:00', 'Completed', 'Knee pain',                  NOW() - INTERVAL 16 DAY),
( 7, 9, CURDATE() - INTERVAL 10 DAY, '15:00:00', 'Completed', 'Fungal rash',                NOW() - INTERVAL 12 DAY),
( 8, 2, CURDATE() - INTERVAL 7 DAY,  '09:00:00', 'Scheduled', 'Routine checkup',            NOW() - INTERVAL 9 DAY),
( 9, 2, CURDATE() - INTERVAL 7 DAY,  '09:30:00', 'Completed', 'Fatigue, thyroid check',     NOW() - INTERVAL 8 DAY),
(10, 4, CURDATE() - INTERVAL 3 DAY,  '10:00:00', 'Scheduled', 'Cholesterol review',         NOW() - INTERVAL 5 DAY),
(11, 1, CURDATE() + INTERVAL 1 DAY,  '10:00:00', 'Scheduled', 'Headache',                   NOW() - INTERVAL 1 DAY),
(12, 3, CURDATE() + INTERVAL 1 DAY,  '11:00:00', 'Scheduled', 'Palpitations',               NOW() - INTERVAL 1 DAY),
(13, 6, CURDATE() + INTERVAL 2 DAY,  '09:00:00', 'Scheduled', 'Vaccination follow-up',      NOW()),
(14, 8, CURDATE() + INTERVAL 2 DAY,  '16:00:00', 'Scheduled', 'Sports injury',              NOW()),
(15,10, CURDATE() + INTERVAL 3 DAY,  '12:00:00', 'Scheduled', 'Acne consultation',          NOW()),
( 1, 3, CURDATE(),                   '10:00:00', 'Scheduled', 'Cardiac screening',          NOW() - INTERVAL 2 DAY);

-- Appointment 8 is cancelled with an UPDATE (not inserted as 'Cancelled'), so
-- trg_audit_appointment_cancellation writes a real row into Audit_Logs.
UPDATE Appointments SET status = 'Cancelled' WHERE appt_id = 8;

-- Prescriptions --------------------------------------------------------
INSERT INTO Prescriptions (appt_id, med_id, dosage, frequency, duration_days, notes) VALUES
( 1,  1, '1 tablet',  'three times daily', 5,  'After food'),
( 1,  2, '1 capsule', 'twice daily',       5,  NULL),
( 2,  7, '1 tablet',  'once daily',        7,  'At bedtime'),
( 3,  5, '1 tablet',  'once daily',        30, 'At night'),
( 3,  6, '1 tablet',  'once daily',        30, 'Morning'),
( 4,  4, '1 tablet',  'twice daily',       30, 'After meals'),
( 5,  1, '1/2 tablet','as needed',         3,  'Fever only'),
( 5, 11, '1 sachet',  'after each stool',  3,  'Dissolve in 1 L water'),
( 6,  8, '1 tablet',  'twice daily',       5,  'After food'),
( 6, 12, '1 capsule', 'once weekly',       8,  NULL),
( 7, 10, 'Apply thin layer', 'twice daily',14, 'Affected area only'),
( 9,  9, '1 tablet',  'once daily',        14, 'Before breakfast'),
(10,  5, '1 tablet',  'once daily',        30, 'At night');

-- Lab orders (inserted BEFORE the bills so trigger recalculation is harmless)
-- Completed
INSERT INTO Lab_Orders (appt_id, test_id, status, ordered_at, sample_collected_at, result_value, result_notes, completed_at) VALUES
( 1,  1, 'Completed', NOW() - INTERVAL 30 DAY, NOW() - INTERVAL 30 DAY + INTERVAL 1 HOUR, 13.80, NULL, NOW() - INTERVAL 29 DAY),
( 1,  3, 'Completed', NOW() - INTERVAL 30 DAY, NOW() - INTERVAL 30 DAY + INTERVAL 1 HOUR, 12.40, 'Mild leukocytosis', NOW() - INTERVAL 29 DAY),
( 3,  7, 'Completed', NOW() - INTERVAL 21 DAY, NOW() - INTERVAL 21 DAY + INTERVAL 1 HOUR, 225.00, 'Borderline high', NOW() - INTERVAL 20 DAY),
( 3,  8, 'Completed', NOW() - INTERVAL 21 DAY, NOW() - INTERVAL 21 DAY + INTERVAL 1 HOUR, 140.00, 'Elevated', NOW() - INTERVAL 20 DAY),
( 3, 21, 'Completed', NOW() - INTERVAL 21 DAY, NOW() - INTERVAL 21 DAY + INTERVAL 1 HOUR, NULL, 'Normal sinus rhythm', NOW() - INTERVAL 21 DAY),
( 4,  5, 'Completed', NOW() - INTERVAL 21 DAY, NOW() - INTERVAL 21 DAY + INTERVAL 1 HOUR, 98.00, NULL, NOW() - INTERVAL 20 DAY),
( 4,  6, 'Completed', NOW() - INTERVAL 21 DAY, NOW() - INTERVAL 21 DAY + INTERVAL 1 HOUR, 6.10, 'Above target', NOW() - INTERVAL 20 DAY),
( 5,  1, 'Completed', NOW() - INTERVAL 14 DAY, NOW() - INTERVAL 14 DAY + INTERVAL 1 HOUR, 11.20, 'Mild anemia', NOW() - INTERVAL 13 DAY),
( 6, 16, 'Completed', NOW() - INTERVAL 14 DAY, NOW() - INTERVAL 14 DAY + INTERVAL 1 HOUR, 18.50, 'Deficient', NOW() - INTERVAL 12 DAY),
( 9, 15, 'Completed', NOW() - INTERVAL 7 DAY,  NOW() - INTERVAL 7 DAY + INTERVAL 1 HOUR, 5.20, 'Slightly high', NOW() - INTERVAL 6 DAY),
(10, 10, 'Completed', NOW() - INTERVAL 3 DAY,  NOW() - INTERVAL 3 DAY + INTERVAL 1 HOUR, 180.00, 'Elevated', NOW() - INTERVAL 2 DAY);
-- Pending (feeds vw_pending_lab_reports / lab desk)
INSERT INTO Lab_Orders (appt_id, test_id, status, ordered_at, sample_collected_at) VALUES
(16,  5, 'Ordered',          NOW() - INTERVAL 3 HOUR, NULL),
(16,  7, 'Sample Collected', NOW() - INTERVAL 3 HOUR, NOW() - INTERVAL 2 HOUR),
(16,  9, 'Ordered',          NOW() - INTERVAL 3 HOUR, NULL),
(12, 21, 'Ordered',          NOW() - INTERVAL 1 HOUR, NULL);

-- Bills for completed appointments: paid, amounts computed from the data.
-- Dated after the visit and its last lab result (not all on 'yesterday'),
-- so the Revenue-per-day chart shows real days.
INSERT INTO Bills (appt_id, consultation_fee, lab_total, total_amount, status, generated_at, paid_at, payment_mode)
SELECT x.appt_id, x.fee, x.lab, x.fee + x.lab, 'Paid',
       x.ready + INTERVAL 1 HOUR,                      -- invoiced 1 h after the visit / last lab result
       x.ready + INTERVAL 1 HOUR + INTERVAL 10 MINUTE, -- paid 10 min later
       ELT(x.appt_id % 3 + 1, 'Cash', 'UPI', 'Card')
FROM (
    SELECT a.appt_id, a.appt_date, a.appt_time,
           d.consultation_fee AS fee,
           IFNULL((SELECT SUM(t.cost) FROM Lab_Orders lo
                   JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
                   WHERE lo.appt_id = a.appt_id), 0) AS lab,
           GREATEST(TIMESTAMP(a.appt_date, a.appt_time),
                    IFNULL((SELECT MAX(lo.completed_at) FROM Lab_Orders lo WHERE lo.appt_id = a.appt_id),
                           TIMESTAMP(a.appt_date, a.appt_time))) AS ready
    FROM Appointments a
    JOIN Doctors d ON d.doctor_id = a.doctor_id
    WHERE a.status = 'Completed'
) x;

-- Appointment 10: invoice generated, awaiting payment
INSERT INTO Bills (appt_id, consultation_fee, lab_total, total_amount, status, generated_at)
SELECT 10, d.consultation_fee, 350.00, d.consultation_fee + 350.00, 'Generated',
       (SELECT MAX(completed_at) FROM Lab_Orders WHERE appt_id = 10) + INTERVAL 1 HOUR
FROM Doctors d WHERE d.doctor_id = 4;

-- Quick sanity checks
SELECT 'departments' AS tbl, COUNT(*) AS n FROM Departments UNION ALL
SELECT 'doctors', COUNT(*) FROM Doctors UNION ALL
SELECT 'tests', COUNT(*) FROM Diagnostic_Tests UNION ALL
SELECT 'patients', COUNT(*) FROM Patients UNION ALL
SELECT 'appointments', COUNT(*) FROM Appointments UNION ALL
SELECT 'lab_orders', COUNT(*) FROM Lab_Orders UNION ALL
SELECT 'bills', COUNT(*) FROM Bills;

-- LIVE DEMO (run during viva): double-booking is rejected by the trigger
-- INSERT INTO Appointments (patient_id, doctor_id, appt_date, appt_time)
-- VALUES (2, 1, CURDATE() + INTERVAL 1 DAY, '10:00:00');   -- ERR_DOUBLE_BOOKING
