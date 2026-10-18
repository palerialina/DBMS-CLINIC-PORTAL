# Integration review (Week 3)

Everything below was run on MySQL 8.0.46 with the scripts loaded through `00_setup_all.sql`,
and the app was driven through a full patient journey in all four tabs.

## Status

| Item | Owner | Status |
|---|---|---|
| 01_schema_ddl.sql | Riya | ✅ loads cleanly, all constraints behave |
| 03_procedures_functions.sql | Riya | ✅ both procedures + function work |
| 06_backend_tests.sql | Riya | ✅ all 26 checks give the expected result (21 intentional errors) |
| reception_tab.py, doctor_tab.py | Riya | ✅ work end to end |
| ER diagram (drawio) | Riya | ⚠ see note 3 |
| lab_tab.py | Kanishka | ✅ works inside the app (now passed a pooled connection) |
| 02_triggers.sql | Kanishka | ✅ received 16 Oct; all triggers work |
| 04_views_queries.sql | Kanishka | ✅ received 16 Oct; 3 views + Q1–Q10 run, lab tab columns match |
| 05_sample_data.sql | Kanishka | ✅ received 16 Oct; meets the counts, but see note 1 |
| Trigger stress tests | Kanishka | ❌ not received |
| db_connection.py, app.py, billing_tab.py | Member 3 | ✅ done |

Verified on 16 Oct with Kanishka's files loaded: Riya's 26 backend tests still pass, all four
tabs load without errors, ordering a test on an invoiced visit reprices the bill and sends it
back to Draft (₹1,200 → ₹1,550), and ordering a test on a paid visit is refused.

## For Kanishka

1. **Seed data is too thin for the dashboard.** The counts match the brief (5 / 10 / 22 / 15),
   but there are only 16 appointments and 8 paid bills, and every `paid_at` falls on the last
   one or two days (`NOW() - INTERVAL 1 DAY - appt_id HOURS`). So "revenue per day" is one or two
   points and "top lab tests" has very few tests ordered twice. Week 3 asks for data that
   "supports meaningful dashboard results". Suggest 80–150 past appointments spread over
   60–90 days, with `paid_at` on the appointment date.
2. **Audit log starts empty.** Appointment 8 is inserted already `Cancelled`, so
   `trg_audit_appointment_cancellation` never fires. Insert it as `Scheduled`, then
   `UPDATE ... SET status = 'Cancelled'`, so the audit trail has a row to show in the demo.
3. **Trigger stress tests are missing** (Week 2 deliverable and roadmap step 3.5). A short
   `07_trigger_tests.sql` in the style of Riya's `06` would do: conflicting inserts on the same
   slot, rescheduling into a taken slot, un-cancelling into a taken slot, test order on a paid
   bill, and a cancellation that writes Audit_Logs.
4. Be ready to explain in the viva why `trg_update_bill_on_lab_order` became three triggers
   (`_ins`, `_upd`, `_del`) plus the helper `sp_recalc_bill`: a MySQL trigger fires on one
   event only. That is a good design choice, but it differs from the roadmap's name.
5. Small one: `lab_tab.py` shows `e.msg` directly, so a trigger error would appear as
   `ERR_...: ...`. Switching to `from db_connection import friendly_error` fixes that.

## For Riya

0. **Normalization proof (1NF → 2NF → 3NF/BCNF) not received.** It was a Week 1 deliverable and
   goes into the report; a short write-up of the design decisions (why each CASCADE/RESTRICT)
   is also still owed.
1. **Slot-range CHECK missing.** The roadmap lists "CHECK constraints (gender, fees, slot ranges)";
   the schema has no slot rule. This works on MySQL 8 and all sample data passes it (tested):
   ```sql
   CONSTRAINT chk_appt_slot CHECK (appt_time BETWEEN '09:00:00' AND '16:30:00'
       AND MINUTE(appt_time) IN (0, 30) AND SECOND(appt_time) = 0)
   ```
2. **Likely viva question on 3NF:** `Bills.total_amount = consultation_fee + lab_total` is a
   derived value (a non-key → non-key dependency). Either make it a generated column
   (`total_amount DECIMAL(10,2) GENERATED ALWAYS AS (consultation_fee + lab_total) STORED`, and stop
   the procedure writing it) or be ready to defend it as a frozen invoice snapshot. Same defence for
   copying `consultation_fee` into Bills: the doctor's fee can change later, the invoice must not.
3. **ER diagram:** it is a plain ERD generated from Mermaid. The roadmap asks for ER/EER with weak
   entities. Prescriptions and Lab_Orders are natural weak entities of Appointments
   (identified by `appt_id + med_id` / `appt_id + test_id`, ON DELETE CASCADE). Marking them as weak,
   and showing the key attributes for every table, would match the brief.
4. Good viva point to keep: "appointment date must be today or later" cannot be a CHECK in MySQL
   because `CURDATE()` is non-deterministic, which is why it lives in `sp_book_appointment`.

## What changed in shared files

- `db_connection.py`: now uses a **connection pool** (the roadmap asks for pooling); same four
  functions, plus `get_connection()` for the lab tab and clearer messages for missing tables/procedures.
- `app.py`: passes `get_connection` to `render_lab_tab()` (the skeleton called it with no
  arguments, which crashed the tab). A real error inside one tab no longer shows up as
  "not integrated yet", and a sidebar shows today's visits, lab queue and unpaid bills.
- `reception_tab.py`, `doctor_tab.py`, `lab_tab.py`: **unchanged**.
