# Integration review (Week 3)

Everything below was run on MySQL 8.0.46 with the scripts loaded through `00_setup_all.sql`,
and the app was driven through a full patient journey in all four tabs.

## Status

| Item | Owner | Status |
|---|---|---|
| 01_schema_ddl.sql | Riya | ✅ updated 18 Oct with `chk_appt_slot`; loads cleanly, all sample data passes it |
| 03_procedures_functions.sql | Riya | ✅ updated 18 Oct; `sp_book_appointment` now raises `ERR_BAD_SLOT` |
| 06_backend_tests.sql | Riya | ✅ updated 18 Oct; all 29 checks give the expected result (24 intentional errors) |
| reception_tab.py, doctor_tab.py | Riya | ✅ work end to end |
| ER diagram | Riya | ✅ `docs/ER_Diagram_Chen.drawio` (18 Oct): weak entities + all attributes; see note 3 |
| Normalization proof + design decisions | Riya | ✅ `docs/Normalization_and_Design_Decisions.md` (18 Oct) |
| lab_tab.py | Kanishka | ✅ works inside the app (now passed a pooled connection) |
| 02_triggers.sql | Kanishka | ✅ received 16 Oct; all triggers work |
| 04_views_queries.sql | Kanishka | ✅ received 16 Oct; 3 views + Q1–Q10 run, lab tab columns match |
| 05_sample_data.sql | Kanishka | ✅ received 16 Oct; 20 Oct: bill dates and audited cancellation fixed (notes 1–2) |
| 07_trigger_stress_tests.sql | Kanishka | ✅ received; Test 1 fixed and Tests 4–7 added by Member 3 (20 Oct) |
| db_connection.py, app.py, billing_tab.py | Member 3 | ✅ done; 20 Oct: paid invoices downloadable |
| 05b_dashboard_history.sql | Member 3 | ✅ 20 Oct: ~150 past visits over 90 days for the dashboard (answers note 1 and 2 below) |
| Integration tests (Week 3) | Member 3 | ✅ `docs/Integration_Test_Cases.md`: 10/10 pass |

Verified on 16 Oct with Kanishka's files loaded: Riya's 26 backend tests still pass, all four
tabs load without errors, ordering a test on an invoiced visit reprices the bill and sends it
back to Draft (₹1,200 → ₹1,550), and ordering a test on a paid visit is refused.

Re-verified on 18 Oct with Riya's updated 01, 03 and 06: the database loads through
`00_setup_all.sql`, all 29 backend checks pass (24 expected errors, fixtures cleaned up), all four
tabs load without errors, and a 10:15 booking shows the clean message
"Slots run 09:00-16:30 in 30-minute steps". `billing_tab.py`, `db_connection.py` and `app.py`
needed no change: the bill procedure kept its five parameters.

## For Kanishka

Update 20 Oct: all notes below are handled except 4, which is for the viva.
- `05b_dashboard_history.sql` adds about 150 past visits (please review it).
- `05_sample_data.sql`: appointment 8 is now cancelled with an `UPDATE`, so the audit trigger writes a row,
  and paid bills are dated after each visit's last lab result instead of all on yesterday. This removes the
  spike on the *Revenue per day* chart.
- `07_trigger_stress_tests.sql`: Test 1 fixed. Tests 4–7 added: reschedule into a taken slot, un-cancel into a
  re-booked slot, test order on a paid bill, and bill re-pricing. It is self-cleaning, so it can be run again.
- `lab_tab.py` uses `friendly_error`. The old copy uploaded as `database/lab_tab.py` was removed; the app uses `app/lab_tab.py`.
- `database/00_run_all.sql` was removed: it had paths for one laptop only (`C:/clinic_project/...`) and duplicated
  `00_setup_all.sql`. `database/session_log.txt` was removed, as already done on the `member-2` branch.
- `Member2_Test_Evidence.docx` moved to `docs/`: placeholder lines removed, a note on Test 1's date added, and
  sections 4 (Tests 4–7) and 5 (where the lab tab is tested) added.

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

Done on 18 Oct (no longer outstanding):
- ✅ **Normalization proof** UNF → 1NF → 2NF → 3NF → BCNF with anomalies and FDs, plus the
  **design-decisions note** (every CASCADE/RESTRICT explained):
  `docs/Normalization_and_Design_Decisions.md`.
- ✅ **Slot-range CHECK** `chk_appt_slot` added to `Appointments`; `sp_book_appointment` checks it
  first so the UI shows `ERR_BAD_SLOT` instead of a raw constraint error. New tests A8, A9, B5b.
- ✅ **3NF question on `Bills.total_amount`** answered in the proof (A5): kept on purpose as a
  frozen invoice snapshot.
- ✅ **ER diagram** redrawn in Chen notation (`docs/ER_Diagram_Chen.drawio`): Prescriptions and
  Lab_Orders are weak entities with identifying relationships, every table shows all attributes.

Week 3 clean-up, done 20 Oct (by Member 3, for Riya to review):
- ✅ **Crow's Foot:** both notations are now in `docs/`: Chen (`ER_Diagram_Chen.drawio` / `.svg`) and
  Crow's Foot (`dbms_proj.drawio` / `dbms_proj_drawio.png`, plus the Mermaid version in `Member1_Documentation.md`).
- ✅ **Partial keys:** the dashed underline now marks `med_id` and `test_id`; `prescription_id` and
  `lab_order_id` are shown as plain surrogate keys (drawio, SVG and the normalization note all match).
- ✅ **drawio file repaired:** the old `ER_Diagram_Chen.drawio` was not valid XML (unescaped quotes in two
  labels), so draw.io could refuse to open it. Fixed; the file now parses cleanly.
- ✅ **Run order** in `01_schema_ddl.sql` and `Member1_Documentation.md` is now 01 → 02 → 03 → 04 → 05 → 05b
  (same as `00_setup_all.sql`); the obsolete `07_migration_slot_check.sql` reference was removed.
- ✅ **Index review (Day 15):** checked with `EXPLAIN`; existing indexes are used by the hot queries, and no new
  index was worth adding (details in the normalization note, B3.6).
- ✅ `ER_Diagram_Chen.svg` and `Member1_Documentation.md` added to `docs/` (from Riya's upload).


Viva point to keep: "appointment date must be today or later" cannot be a CHECK in MySQL
   because `CURDATE()` is non-deterministic, which is why it lives in `sp_book_appointment`.

## What changed in shared files

- `db_connection.py`: now uses a **connection pool** (the roadmap asks for pooling); same four
  functions, plus `get_connection()` for the lab tab and clearer messages for missing tables/procedures.
- `app.py`: passes `get_connection` to `render_lab_tab()` (the skeleton called it with no
  arguments, which crashed the tab). A real error inside one tab no longer shows up as
  "not integrated yet", and a sidebar shows today's visits, lab queue and unpaid bills.
- `reception_tab.py`: email-format check added (Week 2). `doctor_tab.py`: unchanged.
- `lab_tab.py`: 20 Oct, errors now shown through `friendly_error()` like every other tab (2 lines + import).
- `billing_tab.py`: 20 Oct, *Recently paid* has a *Download paid invoice* button.
- 18 Oct: Riya's updated `01`, `03`, `06` replaced the old ones; no app code had to change.
  Every slot the Reception tab offers (09:00–16:30, every 30 min) already satisfies the new CHECK,
  and all of Kanishka's sample appointments use valid slot times.
