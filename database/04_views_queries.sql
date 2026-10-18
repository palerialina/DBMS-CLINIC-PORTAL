-- =====================================================================
-- 04_views_queries.sql | Owner: Member 2 | Views + analytical queries
-- =====================================================================
USE clinic_portal;

-- ---------------------------------------------------------------------
-- VIEW 1: doctor's schedule (filter by doctor and date in the app)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_doctor_daily_schedule AS
SELECT a.appt_date,
       a.appt_time,
       a.appt_id,
       d.doctor_id,
       d.doctor_name,
       dep.dept_name,
       p.patient_id,
       CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
       p.phone  AS patient_phone,
       a.status,
       a.reason
FROM Appointments a
JOIN Doctors     d   ON d.doctor_id = a.doctor_id
JOIN Departments dep ON dep.dept_id = d.dept_id
JOIN Patients    p   ON p.patient_id = a.patient_id;

-- ---------------------------------------------------------------------
-- VIEW 2: lab worklist, every test not yet Completed
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pending_lab_reports AS
SELECT lo.lab_order_id,
       lo.appt_id,
       CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
       d.doctor_name   AS ordered_by,
       t.test_id,
       t.test_name,
       t.category,
       t.unit,
       lo.status,
       lo.ordered_at,
       lo.sample_collected_at,
       TIMESTAMPDIFF(HOUR, lo.ordered_at, NOW()) AS hours_waiting
FROM Lab_Orders lo
JOIN Diagnostic_Tests t ON t.test_id   = lo.test_id
JOIN Appointments a     ON a.appt_id   = lo.appt_id
JOIN Patients p         ON p.patient_id = a.patient_id
JOIN Doctors d          ON d.doctor_id = a.doctor_id
WHERE lo.status <> 'Completed'
  AND a.status  <> 'Cancelled';

-- ---------------------------------------------------------------------
-- VIEW 3: per-department KPIs
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_department_analytics AS
SELECT dep.dept_id,
       dep.dept_name,
       COUNT(DISTINCT d.doctor_id)                                   AS doctors,
       COUNT(a.appt_id)                                              AS total_appointments,
       IFNULL(SUM(a.status = 'Completed'), 0)                        AS completed,
       IFNULL(SUM(a.status = 'Scheduled'), 0)                        AS scheduled,
       IFNULL(SUM(a.status = 'Cancelled'), 0)                        AS cancelled,
       ROUND(100 * IFNULL(SUM(a.status = 'Cancelled'), 0)
             / NULLIF(COUNT(a.appt_id), 0), 1)                       AS cancellation_pct,
       IFNULL(SUM(CASE WHEN b.status = 'Paid' THEN b.consultation_fee END), 0) AS consultation_revenue,
       IFNULL(SUM(CASE WHEN b.status = 'Paid' THEN b.lab_total        END), 0) AS lab_revenue,
       IFNULL(SUM(CASE WHEN b.status = 'Paid' THEN b.total_amount     END), 0) AS total_revenue
FROM Departments dep
LEFT JOIN Doctors      d ON d.dept_id   = dep.dept_id
LEFT JOIN Appointments a ON a.doctor_id = d.doctor_id
LEFT JOIN Bills        b ON b.appt_id   = a.appt_id
GROUP BY dep.dept_id, dep.dept_name;

-- =====================================================================
-- ANALYTICAL QUERIES (used by the Streamlit dashboard / viva demo)
-- =====================================================================

-- Q1. Today's schedule for one doctor
-- SELECT * FROM vw_doctor_daily_schedule
-- WHERE doctor_id = 3 AND appt_date = CURDATE() ORDER BY appt_time;

-- Q2. Revenue by department (bar chart)
SELECT dept_name, total_revenue FROM vw_department_analytics ORDER BY total_revenue DESC;

-- Q3. Top prescribed (ordered) lab tests
SELECT t.test_name, t.category, COUNT(*) AS times_ordered, SUM(t.cost) AS revenue
FROM Lab_Orders lo
JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
GROUP BY t.test_id, t.test_name, t.category
ORDER BY times_ordered DESC, revenue DESC
LIMIT 10;

-- Q4. Busy hours (appointments per hour of day)
SELECT HOUR(appt_time) AS hour_of_day, COUNT(*) AS appointments
FROM Appointments
WHERE status <> 'Cancelled'
GROUP BY HOUR(appt_time)
ORDER BY hour_of_day;

-- Q5. Monthly paid revenue
SELECT DATE_FORMAT(paid_at, '%Y-%m') AS month, SUM(total_amount) AS revenue, COUNT(*) AS bills
FROM Bills
WHERE status = 'Paid'
GROUP BY DATE_FORMAT(paid_at, '%Y-%m')
ORDER BY month;

-- Q6. Doctors ranked by revenue within their department (window function)
SELECT dep.dept_name, d.doctor_name,
       IFNULL(SUM(b.total_amount), 0) AS revenue,
       RANK() OVER (PARTITION BY dep.dept_id ORDER BY IFNULL(SUM(b.total_amount), 0) DESC) AS dept_rank
FROM Doctors d
JOIN Departments dep ON dep.dept_id = d.dept_id
LEFT JOIN Appointments a ON a.doctor_id = d.doctor_id
LEFT JOIN Bills b ON b.appt_id = a.appt_id AND b.status = 'Paid'
GROUP BY dep.dept_id, dep.dept_name, d.doctor_id, d.doctor_name;

-- Q7. Outstanding (unpaid) bills with patient names
SELECT b.bill_id, CONCAT(p.first_name,' ',p.last_name) AS patient_name,
       b.total_amount, b.status, b.generated_at
FROM Bills b
JOIN Appointments a ON a.appt_id = b.appt_id
JOIN Patients p ON p.patient_id = a.patient_id
WHERE b.status <> 'Paid';

-- Q8. Abnormal lab results (outside reference range)
SELECT CONCAT(p.first_name,' ',p.last_name) AS patient_name, t.test_name, lo.result_value,
       t.ref_range_low, t.ref_range_high, t.unit,
       CASE WHEN lo.result_value < t.ref_range_low  THEN 'LOW'
            WHEN lo.result_value > t.ref_range_high THEN 'HIGH' END AS flag
FROM Lab_Orders lo
JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
JOIN Appointments a ON a.appt_id = lo.appt_id
JOIN Patients p ON p.patient_id = a.patient_id
WHERE lo.status = 'Completed' AND lo.result_value IS NOT NULL
  AND (lo.result_value < t.ref_range_low OR lo.result_value > t.ref_range_high);

-- Q9. Patients with more than one visit (subquery)
SELECT patient_id, CONCAT(first_name,' ',last_name) AS patient_name
FROM Patients
WHERE patient_id IN (SELECT patient_id FROM Appointments GROUP BY patient_id HAVING COUNT(*) > 1);

-- Q10. Cancellation audit trail
SELECT * FROM Audit_Logs WHERE table_name = 'Appointments' ORDER BY logged_at DESC;
