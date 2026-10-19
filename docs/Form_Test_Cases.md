# Form Validation Test Cases (Week 2)
Tested by: Member 3 · Date: 19 Oct 2026 · Database freshly loaded with 00_setup_all.sql

| No. | Test | Input | Expected result | Actual result | Pass/Fail |
|---|---|---|---|---|---|
| TC1 | Empty name | First name blank | "First and last name are required." | | |
| TC2 | 9-digit phone | 984002000 | "Phone must be exactly 10 digits." | | |
| TC3 | Duplicate phone | 9840020001 (existing patient) | "That value already exists…" (UNIQUE constraint) | | |
| TC4 | Invalid email | ravi@mail | "Please enter a valid email address…" | | |
| TC5 | Slot already booked | Dr. Rahul Verma, today, 10:00 | "Doctor already has an appointment at this time" | | |
| TC6 | Past date | Yesterday's date | Date picker does not allow it; DB also rejects (ERR_PAST_DATE) | | |
| TC7 | Bill with labs pending | Visit #16, Generate invoice | "Complete all lab tests before generating the invoice" | | |
| TC8 | Valid registration | All fields valid | "Patient registered. Patient ID = 16" | | |