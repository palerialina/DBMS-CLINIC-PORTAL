"""
app/reception_tab.py  --  Tab 1: Receptionist Portal (Member 1 + Member 3).
Patient registration, appointment booking (via sp_book_appointment),
and viewing / cancelling appointments.
"""
from datetime import date, datetime, time, timedelta

import pandas as pd
import streamlit as st
from mysql.connector import Error

from db_connection import call_proc, friendly_error, run_query, run_write

SLOTS = [time(9, 0)]
while SLOTS[-1] < time(16, 30):                       # 09:00 .. 16:30, every 30 min
    SLOTS.append((datetime.combine(date.today(), SLOTS[-1]) + timedelta(minutes=30)).time())


def _to_time(v):
    """MySQL TIME columns arrive as timedelta; convert to datetime.time."""
    return (datetime.min + v).time() if isinstance(v, timedelta) else v


def _register_patient():
    st.subheader("Register new patient")
    with st.form("register_patient", clear_on_submit=True):
        c1, c2 = st.columns(2)
        first = c1.text_input("First name *")
        last = c2.text_input("Last name *")
        dob = c1.date_input("Date of birth *", value=date(2000, 1, 1),
                            min_value=date(1900, 1, 1), max_value=date.today())
        gender = c2.selectbox("Gender *", ["M", "F", "O"])
        phone = c1.text_input("Phone * (10 digits)")
        email = c2.text_input("Email")
        blood = c1.selectbox("Blood group", ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"])
        address = c2.text_input("Address")
        submitted = st.form_submit_button("Register patient")

    if submitted:
        if not first.strip() or not last.strip():
            st.error("First and last name are required.")
        elif not (phone.isdigit() and len(phone) == 10):
            st.error("Phone must be exactly 10 digits.")
        else:
            try:
                pid = run_write(
                    "INSERT INTO Patients (first_name, last_name, dob, gender, phone, email, address, blood_group) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (first.strip(), last.strip(), dob, gender, phone,
                     email.strip() or None, address.strip() or None, blood or None),
                )
                st.success(f"Patient registered. Patient ID = {pid}")
            except Error as e:
                st.error(friendly_error(e))


def _book_appointment():
    st.subheader("Book appointment")
    try:
        q = st.text_input("Search patient (name or phone)", key="rc_search")
        like = f"%{q.strip()}%"
        patients = run_query(
            "SELECT patient_id, first_name, last_name, phone FROM Patients "
            "WHERE first_name LIKE %s OR last_name LIKE %s OR phone LIKE %s "
            "ORDER BY last_name, first_name LIMIT 50", (like, like, like))
        departments = run_query("SELECT dept_id, dept_name FROM Departments ORDER BY dept_name")
    except Error as e:
        st.error(friendly_error(e))
        return
    if not patients:
        st.info("No matching patients. Register one first.")
        return
    if not departments:
        st.warning("No departments found. Load the sample data first.")
        return

    patient = st.selectbox(
        "Patient", patients, key="rc_patient",
        format_func=lambda p: f"{p['patient_id']} - {p['first_name']} {p['last_name']} ({p['phone']})")
    dept = st.selectbox("Department", departments, key="rc_dept", format_func=lambda d: d["dept_name"])
    doctors = run_query(
        "SELECT doctor_id, doctor_name, consultation_fee FROM Doctors WHERE dept_id = %s ORDER BY doctor_name",
        (dept["dept_id"],))
    if not doctors:
        st.warning("No doctors in this department.")
        return
    doctor = st.selectbox("Doctor", doctors, key="rc_doctor",
                          format_func=lambda d: f"{d['doctor_name']} (fee {d['consultation_fee']})")
    appt_date = st.date_input("Date", min_value=date.today(), key="rc_date")

    booked = {_to_time(r["appt_time"]) for r in run_query(
        "SELECT appt_time FROM Appointments WHERE doctor_id = %s AND appt_date = %s AND status <> 'Cancelled'",
        (doctor["doctor_id"], appt_date))}
    show_all = st.checkbox("Show booked slots too (to demonstrate the double-booking error)", key="rc_showall")
    options = SLOTS if show_all else [s for s in SLOTS if s not in booked]
    if not options:
        st.warning("This doctor is fully booked on that day.")
        return
    slot = st.selectbox("Time slot", options, key="rc_slot",
                        format_func=lambda s: s.strftime("%H:%M") + ("  (booked)" if s in booked else ""))
    reason = st.text_input("Reason for visit", key="rc_reason")

    if st.button("Book appointment", type="primary", key="rc_book"):
        try:
            result = call_proc("sp_book_appointment",
                               (patient["patient_id"], doctor["doctor_id"], appt_date, slot,
                                reason.strip() or None, 0))
            st.success(f"Appointment booked. Appointment ID = {result[5]}")
        except Error as e:
            st.error(friendly_error(e))         # e.g. 'Doctor already has an appointment at this time'


def _upcoming_and_cancel():
    st.subheader("Upcoming appointments")
    try:
        rows = run_query(
            "SELECT a.appt_id, a.appt_date, a.appt_time, CONCAT(p.first_name, ' ', p.last_name) AS patient, "
            "d.doctor_name AS doctor, a.status "
            "FROM Appointments a JOIN Patients p ON p.patient_id = a.patient_id "
            "JOIN Doctors d ON d.doctor_id = a.doctor_id "
            "WHERE a.appt_date >= CURDATE() ORDER BY a.appt_date, a.appt_time LIMIT 100")
    except Error as e:
        st.error(friendly_error(e))
        return
    if not rows:
        st.info("No upcoming appointments.")
        return
    for r in rows:
        r["appt_time"] = _to_time(r["appt_time"]).strftime("%H:%M")
    st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)

    scheduled = [r for r in rows if r["status"] == "Scheduled"]
    if scheduled:
        target = st.selectbox(
            "Cancel an appointment", scheduled, key="rc_cancel_sel",
            format_func=lambda r: f"#{r['appt_id']} - {r['patient']} with {r['doctor']} on {r['appt_date']} {r['appt_time']}")
        if st.button("Cancel selected appointment", key="rc_cancel_btn"):
            try:
                run_write("UPDATE Appointments SET status = 'Cancelled' WHERE appt_id = %s AND status = 'Scheduled'",
                          (target["appt_id"],))
                st.success("Appointment cancelled (the audit trigger logs this in Audit_Logs).")
            except Error as e:
                st.error(friendly_error(e))


def render_reception_tab():
    left, right = st.columns(2)
    with left:
        _register_patient()
    with right:
        _book_appointment()
    st.divider()
    _upcoming_and_cancel()
