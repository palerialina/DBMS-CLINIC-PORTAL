# Form Validation Test Cases (Week 2)
Tested by: Member 3 · Date: 19–20 Oct 2026 · Database freshly loaded with `00_setup_all.sql` on 19 Oct 2026

Screenshots: see `Form_Test_Screenshots.pdf` (Fig 1–14, grouped by test case).

| No. | Test | Input | Expected result | Actual result | Pass/Fail |
|---|---|---|---|---|---|
| TC1 | Empty name | First name left blank, other fields filled | "First and last name are required." Nothing saved. | "First and last name are required." shown; patient not saved (Fig 1–2) | Pass |
| TC2 | 9-digit phone | Phone 432123456 | "Phone must be exactly 10 digits." | "Phone must be exactly 10 digits." shown; patient not saved (Fig 3–4) | Pass |
| TC3 | Duplicate phone | Phone 9840020001 (existing patient Ravi Kumar) | Rejected by the UNIQUE constraint on phone | "That value already exists (phone, email or another unique field is a duplicate)." (Fig 5–6) | Pass |
| TC4 | Invalid email | Email "sana @mail" | "Please enter a valid email address, like name@mail.com." | Same message shown; patient not saved (Fig 7–8) | Pass |
| TC5 | Slot already booked | Dr. Rahul Verma (Cardiology), 20 Oct 2026, 11:00 (booked) | "Doctor already has an appointment at this time" | Same message shown; no appointment created (Fig 9–10) | Pass |
| TC6 | Past date | Try to pick a date before today | Date picker does not allow it; the database also rejects it (`ERR_PAST_DATE`, backend test B5) | Calendar greys out past dates; only today and later can be picked (Fig 11) | Pass |
| TC7 | Bill with labs pending | Visit #16 (Ravi Kumar, Dr. Rahul Verma), 3 lab tests pending, Generate invoice | "Complete all lab tests before generating the invoice"; no bill created | Same message shown; invoice refused (Fig 12) | Pass |
| TC8 | Valid registration | All fields valid (Aarathy Nair, 9383449526, aarathy46@gmail.com) | "Patient registered. Patient ID = <new id>" | "Patient registered. Patient ID = 19" (Fig 13–14) | Pass |

**Result: 8 of 8 tests passed.**

Notes
- TC8 shows ID 19 because patients 16–18 were registered earlier in the same test session (used for TC5–TC6).
- TC1–TC4 are checked in the app before any SQL runs, except TC3, which reaches MySQL and is refused by `uq_patient_phone`.
- TC5 and TC7 are enforced in the database (`sp_book_appointment` / `trg_check_doctor_availability` and `sp_generate_or_finalize_bill`), so they cannot be bypassed from outside the app.
