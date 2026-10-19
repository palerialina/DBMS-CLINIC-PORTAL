# Integration and Error Test Cases (Week 3)

Member 3 · Digital Health Clinic & Diagnostic Lab Portal

**How these were run:** the full app (`streamlit run app/app.py`) was driven through a real browser by an
automated script (Playwright), against MySQL 8.0.46 freshly loaded with `00_setup_all.sql`
(01 → 05 plus `05b_dashboard_history.sql`). Every message below was read from the screen, and the
database was queried afterwards to confirm what was actually stored. Run date: 19 Oct 2026.

Screenshots: `Integration_Test_Screenshots.pdf` (Fig 1–15).

| No. | Test | Steps | Expected result | Actual result | Pass/Fail |
|---|---|---|---|---|---|
| IT1 | SQL injection blocked | Reception → *Search patient* = `x' OR '1'='1` | No patients listed. The input is sent as a `%s` parameter, so it's treated as text, not SQL. | "No matching patients. Register one first."; no rows returned (Fig 1) | Pass |
| IT2 | Full patient journey | Register *Test Journey* → book Dr. Meera Iyer today → prescribe Amlodipine → order Total Cholesterol + Hemoglobin → collect both samples → enter results → generate invoice → pay by UPI | Every step succeeds; bill **Paid**; visit **Completed** | Patient ID 36; appointment 171; "Medicine added…"; both tests ordered; invoice ₹1,300 (850 + 300 + 150); after IT3 the paid total is ₹1,650 by UPI. Database: `Bills.status = Paid`, `Appointments.status = Completed` (Fig 2–7) | Pass |
| IT2b | Invoice refused while labs pending | Press *Generate invoice* before the lab finishes (part of IT2) | "Complete all lab tests before generating the invoice"; no bill created | Same message (`ERR_LABS_PENDING`); no row in `Bills` (Fig 5) | Pass |
| IT3 | Bill updates itself (trigger) | After the ₹1,300 invoice, order HDL Cholesterol (₹350) at Doctor Desk, then open Billing Desk | Bill goes back to **Draft** with total ₹1,650; payment blocked until regenerated | "A test was ordered after the invoice was made, so the bill went back to Draft…"; provisional ₹1,650; after the lab finished, *Regenerate* → ₹1,650 (Fig 8) | Pass |
| IT4 | No tests on a paid visit (trigger) | Doctor Desk → paid visit 171 → order ESR | "Cannot add lab tests to an appointment whose bill is paid" | "ESR: Cannot add lab tests to an appointment whose bill is paid" (`trg_block_lab_order_after_payment`) (Fig 9) | Pass |
| IT5 | Cancellation is audited (trigger) | Reception → cancel appointment 16 → Analytics → *Audit trail* | New `CANCELLED` row in `Audit_Logs` | "Appointment cancelled…"; `Audit_Logs` row: appt 16, CANCELLED, Scheduled → Cancelled, "Doctor 3, patient 1, slot … 10:00" (Fig 10–11) | Pass |
| IT6 | Abnormal result flagged | Diagnostic Lab → Total Cholesterol (range 0–200) = 250 | "Result is HIGH"; listed under Abnormal results | "Order #229 (Total Cholesterol) completed. Result is HIGH." (Fig 12) | Pass |
| IT7 | Payment without an invoice | (a) Billing Desk on a visit with no invoice. (b) `CALL sp_generate_or_finalize_bill(11,'PAY','Cash',@b,@t);` | (a) *Mark as paid* is not offered. (b) Database refuses with `ERR_NO_BILL`. | (a) No *Mark as paid* button (Fig 13). (b) `ERROR 1644 (45000): ERR_NO_BILL: Generate the invoice before taking payment`; still no bill for visit 11 | Pass |
| IT8 | Paid invoice can be downloaded | After payment, *Recently paid* → *Download paid invoice* | Text invoice with all items, the total, and "PAID on … by UPI" | `invoice_000157.txt`: consultation ₹850 + 3 tests (₹300, ₹150, ₹350) = **₹1,650**, "PAID on 19 Oct 2026 … by UPI" (Fig 14) | Pass |
| IT9 | Analytics with realistic data | Billing & Analytics → *Analytics* → *Last 90 days* | KPIs and all charts populated | Revenue ₹1,59,640 from 149 paid bills; 150 visits; 5 charts drawn; busy-hours peak 10:00 (Fig 15) | Pass |

**Result: 10 of 10 checks passed.**

## Backend scripts re-run on the same database
Run after adding `05b_dashboard_history.sql`, to confirm the extra data broke nothing:

| Script | Result |
|---|---|
| `06_backend_tests.sql` (Member 1) | All checks behave as labelled: exactly **24** intentional `ERROR` lines, fixtures removed |
| `07_trigger_stress_tests.sql` (Member 2, Test 1 fixed) | Test 1 → `ERR_DOUBLE_BOOKING`; Tests 2–3 → `CANCELLED` and `STATUS_CHANGE` rows in `Audit_Logs` |
| Data checks on `05b` | 0 bookings outside 09:00–16:30 slots; 0 double bookings; every bill's total = consultation fee + lab total |

## Changes made in Week 3 (Member 3)
- `app/billing_tab.py`: paid invoices are now downloadable from *Recently paid*. Previously the
  download disappeared once a bill was paid. Every invoice is built from the bill row, so the consultation fee printed is the one
  frozen on the bill.
- `app/lab_tab.py`: database errors are shown through `friendly_error()` (for example "Cannot add…"
  instead of `ERR_BILL_PAID: …`), the same as the other tabs. Small change to Member 2's file; Member 2 to confirm.
- `database/05b_dashboard_history.sql`: about 150 past visits over 90 days, paid on the visit day, with lab results and
  cancellations made through `UPDATE`, so the dashboard and audit trail show real data. Loaded by `00_setup_all.sql`.
- `database/07_trigger_stress_tests.sql`: Member 2's script added to the repo. Test 1 now reads appointment 10's slot
  instead of a hard-coded date, so it works on any day.
