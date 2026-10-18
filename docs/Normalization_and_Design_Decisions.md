# Normalization Proof and Design Decisions
Digital Health Clinic & Diagnostic Lab Portal | BACSE202 | Member 1

## Part A. Normalization proof (UNF → 1NF → 2NF → 3NF → BCNF)

### A1. Starting point: the clinic's paper "visit sheet" (UNF)

`VISIT(visit_id, patient_name, patient_phone, patient_dob, doctor_name, doctor_license, dept_name, doctor_fee, appt_date, appt_time, {medicine, dosage}, {test_name, test_cost}, bill_total)`

`{ }` marks a repeating group. Sample data:

| visit_id | patient_name | patient_phone | doctor_name | dept_name | doctor_fee | medicines | tests | bill_total |
|---|---|---|---|---|---|---|---|---|
| 1 | Asha Rao | 9000000011 | Dr. Mehta | Cardiology | 600 | Aspirin 75mg, Atorvastatin 10mg | ECG (400), Lipid Profile (350) | 1350 |
| 2 | Asha Rao | 9000000011 | Dr. Mehta | Cardiology | 600 | Aspirin 75mg | none | 600 |

**Anomalies this causes**
- **Update anomaly:** if Dr. Mehta's fee changes, every visit row must change, and missing one leaves the data inconsistent.
- **Insertion anomaly:** a new doctor or department cannot be stored until a visit exists for it.
- **Deletion anomaly:** deleting Asha's only visit also deletes her contact details.
- **Redundancy:** patient and doctor details repeat on every visit.

### A2. Functional dependencies (FDs) identified
- `visit_id → patient_phone, doctor_license, appt_date, appt_time, bill_total`
- `patient_phone → patient_name, patient_dob`
- `doctor_license → doctor_name, dept_name, doctor_fee`
- `test_name → test_cost`
- `medicine → (strength, form)` (a property of the medicine alone)
- `(visit_id, medicine) → dosage`

### A3. First Normal Form (1NF): atomic values, no repeating groups
Each repeating group becomes its own table, with one value per cell:
- `VISIT(visit_id PK, patient_*, doctor_*, dept_name, doctor_fee, appt_date, appt_time, bill_total)`
- `VISIT_MEDICINE(visit_id, medicine, dosage)` with PK (visit_id, medicine)
- `VISIT_TEST(visit_id, test_name, test_cost)` with PK (visit_id, test_name)

### A4. Second Normal Form (2NF): no partial dependency on part of a composite key
2NF only concerns tables with composite keys.
- In `VISIT_TEST`, `test_name → test_cost` depends on only part of the key (visit_id, test_name). **Partial dependency.** Move it out: `DIAGNOSTIC_TESTS(test_id PK, test_name, cost, ...)`, and keep `LAB_ORDERS(appt_id, test_id)`.
- In `VISIT_MEDICINE`, the medicine's own properties depend only on `medicine`. Move them out: `MEDICATIONS(med_id PK, med_name, form, strength)`, and keep `PRESCRIPTIONS(appt_id, med_id, dosage, ...)`. Here `dosage` depends on the whole key, so this table is in 2NF.
- `VISIT` has a single-column key, so it is in 2NF automatically.

### A5. Third Normal Form (3NF): no transitive dependency
In `VISIT`:
- `visit_id → doctor_license → doctor_name, dept_name, doctor_fee`: non-key attributes determined through another non-key attribute. **Transitive.** Extract `DOCTORS`, and then `DEPARTMENTS`, because `doctor → dept`.
- `visit_id → patient_phone → patient_name, patient_dob`: **Transitive.** Extract `PATIENTS`.

After extraction, `APPOINTMENTS` keeps only `appt_id`, `patient_id`, `doctor_id`, `appt_date`, `appt_time`, `status` and `reason`.

`bill_total` is derivable (doctor fee plus test costs). It is kept in `BILLS` on purpose, as a **snapshot of what the patient was charged**. If a doctor's fee changes next year, old invoices must not change. This is a documented, deliberate denormalization, and the bill is still in 3NF because every non-key column depends on `bill_id`.

### A6. Boyce-Codd Normal Form (BCNF): every determinant is a candidate key

| Table | Determinants (candidate keys) | Result |
|---|---|---|
| Departments | dept_id, dept_name | BCNF |
| Doctors | doctor_id, license_no, phone | BCNF |
| Patients | patient_id, phone, email | BCNF |
| Appointments | appt_id | BCNF (doctor/date/time is not a key, since cancelled slots can be reused) |
| Medications | med_id, (med_name, strength) | BCNF |
| Prescriptions | prescription_id, (appt_id, med_id) | BCNF |
| Diagnostic_Tests | test_id, test_name | BCNF |
| Lab_Orders | lab_order_id, (appt_id, test_id) | BCNF |
| Bills | bill_id, appt_id | BCNF |
| Audit_Logs | log_id | BCNF |

All 10 tables are in BCNF.

**Result:** the three anomalies are gone. A doctor's fee is stored once (update anomaly), doctors and departments exist without visits (insertion anomaly), and deleting a visit no longer removes patient data (deletion anomaly).

---

## Part B. Design decisions

### B1. Why each delete rule is CASCADE or RESTRICT

**Principle:** if a child row has no meaning without its parent, CASCADE. If the parent is a master record or legal and financial history, RESTRICT, so it can never be lost by accident.

| Foreign key (child → parent) | Rule | Reason |
|---|---|---|
| Doctors → Departments | RESTRICT | A department with doctors must not vanish and orphan them. |
| Appointments → Patients | RESTRICT | Medical history must never be lost by deleting a patient. |
| Appointments → Doctors | RESTRICT | Past consultations must keep their doctor. |
| Prescriptions → Appointments | CASCADE | A prescription line is meaningless without its consultation. |
| Prescriptions → Medications | RESTRICT | A medicine used in any prescription must stay in the master list. |
| Lab_Orders → Appointments | CASCADE | A lab order belongs to one consultation. |
| Lab_Orders → Diagnostic_Tests | RESTRICT | A catalogue test used in orders must not disappear. |
| Bills → Appointments | RESTRICT | Financial records must outlive any clean-up of appointments. |
| Audit_Logs | no FK | A log must survive the deletion of the rows it describes. |

All **ON UPDATE** rules are CASCADE (or the default for Audit_Logs, which has no FK), so a changed key value propagates to child rows.

### B2. Weak entities
**Prescriptions** and **Lab_Orders** are the weak entities. A prescription line or lab order cannot exist without an Appointment, so it is identified through its owner. In the ER diagram they are double rectangles linked by identifying relationships (`has`, `triggers`, double diamonds). The tables also use a surrogate key (`prescription_id`, `lab_order_id`) for easier joins. `UNIQUE (appt_id, med_id)` and `UNIQUE (appt_id, test_id)` keep the owner-plus-item uniqueness that a pure weak-entity key would give.

### B3. Other key decisions
1. **Double-booking:** there is no `UNIQUE(doctor, date, time)`, because it would block re-booking a cancelled slot. Instead `sp_book_appointment` checks under a row lock (`SELECT ... FOR UPDATE`), and Member 2's trigger is a second line of defence.
2. **Slot-time CHECK:** `chk_appt_slot` limits `appt_time` to 09:00-16:30 in 30-minute steps. The procedure also checks this first, so the user sees `ERR_BAD_SLOT` instead of a raw constraint error. All sample data must use valid slot times.
3. **Bill snapshot:** see A5.
4. **Surrogate keys:** integer auto-increment PKs are short and stable. Natural identifiers (phone, license, email) are kept as UNIQUE.
5. **Error codes:** every business-rule failure raises SQLSTATE 45000 with a message starting `ERR_CODE:`, so the UI shows one consistent format.
6. **Indexes:** on `appt_date`, `patient_id`, `(doctor_id, appt_date, appt_time)` and `Lab_Orders.status`, for the schedule and pending-lab queries.
