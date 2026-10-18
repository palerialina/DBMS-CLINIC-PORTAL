"""
app/doctor_tab.py  --  Tab 2: Doctor Desk (Member 1 + Member 3).
View appointments, see patient details, write prescriptions, order lab tests.
"""
from datetime import date, datetime, timedelta

import pandas as pd
import streamlit as st
from mysql.connector import Error

from db_connection import friendly_error, run_query, run_write


def _t(v):
    return (datetime.min + v).time().strftime("%H:%M") if isinstance(v, timedelta) else str(v)[:5]


def _patient_panel(appt):
    st.markdown("#### Patient details")
    p = run_query("SELECT * FROM Patients WHERE patient_id = %s", (appt["patient_id"],))[0]
    c1, c2, c3 = st.columns(3)
    c1.write(f"**Name:** {p['first_name']} {p['last_name']}")
    c2.write(f"**DOB:** {p['dob']}  |  **Gender:** {p['gender']}")
    c3.write(f"**Blood group:** {p['blood_group'] or '-'}  |  **Phone:** {p['phone']}")
    st.write(f"**Reason for visit:** {appt['reason'] or '-'}")

    history = run_query(
        "SELECT a.appt_date, m.med_name, pr.dosage, pr.frequency, pr.duration_days "
        "FROM Prescriptions pr JOIN Appointments a ON a.appt_id = pr.appt_id "
        "JOIN Medications m ON m.med_id = pr.med_id "
        "WHERE a.patient_id = %s AND a.appt_id <> %s ORDER BY a.appt_date DESC",
        (appt["patient_id"], appt["appt_id"]))
    with st.expander(f"Previous prescriptions ({len(history)})"):
        if history:
            st.dataframe(pd.DataFrame(history), use_container_width=True, hide_index=True)
        else:
            st.write("None on record.")


def _prescription_section(appt_id):
    st.markdown("#### Prescription")
    meds = run_query("SELECT med_id, med_name, strength FROM Medications ORDER BY med_name")

    with st.expander("Medication not in the list? Add it"):
        n1, n2 = st.columns(2)
        new_name = n1.text_input("Medication name", key="dr_newmed_name")
        new_strength = n2.text_input("Strength (e.g. 500mg)", key="dr_newmed_strength")
        if st.button("Add medication", key="dr_newmed_btn"):
            if not new_name.strip():
                st.error("Medication name is required.")
            else:
                try:
                    run_write("INSERT INTO Medications (med_name, strength) VALUES (%s, %s)",
                              (new_name.strip(), new_strength.strip() or None))
                    st.success("Medication added.")
                    st.rerun()
                except Error as e:
                    st.error(friendly_error(e))

    if meds:
        with st.form("dr_prescribe", clear_on_submit=True):
            med = st.selectbox("Medicine", meds,
                               format_func=lambda m: f"{m['med_name']} {m['strength'] or ''}".strip())
            c1, c2, c3 = st.columns(3)
            dosage = c1.text_input("Dosage (e.g. 1 tablet)")
            freq = c2.text_input("Frequency (e.g. twice daily)")
            days = c3.number_input("Duration (days)", min_value=1, value=5, step=1)
            notes = st.text_input("Notes")
            if st.form_submit_button("Add to prescription"):
                if not dosage.strip() or not freq.strip():
                    st.error("Dosage and frequency are required.")
                else:
                    try:
                        run_write(
                            "INSERT INTO Prescriptions (appt_id, med_id, dosage, frequency, duration_days, notes) "
                            "VALUES (%s, %s, %s, %s, %s, %s)",
                            (appt_id, med["med_id"], dosage.strip(), freq.strip(), int(days), notes.strip() or None))
                        st.success("Medicine added to the prescription.")
                    except Error as e:
                        st.error(friendly_error(e))
    else:
        st.info("The medication list is empty. Add one above.")

    rows = run_query(
        "SELECT m.med_name AS medicine, pr.dosage, pr.frequency, pr.duration_days AS days, pr.notes "
        "FROM Prescriptions pr JOIN Medications m ON m.med_id = pr.med_id WHERE pr.appt_id = %s", (appt_id,))
    if rows:
        st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)


def _lab_section(appt_id):
    st.markdown("#### Order lab tests")
    tests = run_query("SELECT test_id, test_name, category, cost FROM Diagnostic_Tests ORDER BY category, test_name")
    if tests:
        with st.form("dr_laborder", clear_on_submit=True):
            chosen = st.multiselect("Tests", tests,
                                    format_func=lambda t: f"{t['test_name']} ({t['category']}, {t['cost']})")
            if st.form_submit_button("Order selected tests"):
                if not chosen:
                    st.warning("Select at least one test.")
                for t in chosen:
                    try:
                        run_write("INSERT INTO Lab_Orders (appt_id, test_id) VALUES (%s, %s)",
                                  (appt_id, t["test_id"]))
                        st.success(f"Ordered: {t['test_name']}")
                    except Error as e:
                        st.error(f"{t['test_name']}: {friendly_error(e)}")
    else:
        st.info("The test catalogue is empty. Load the sample data first.")

    rows = run_query(
        "SELECT t.test_name AS test, lo.status, lo.result_value AS result, t.unit, t.cost "
        "FROM Lab_Orders lo JOIN Diagnostic_Tests t ON t.test_id = lo.test_id WHERE lo.appt_id = %s", (appt_id,))
    if rows:
        st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)


def render_doctor_tab():
    try:
        doctors = run_query("SELECT doctor_id, doctor_name, specialization FROM Doctors ORDER BY doctor_name")
    except Error as e:
        st.error(friendly_error(e))
        return
    if not doctors:
        st.warning("No doctors found. Load the sample data first.")
        return

    c1, c2 = st.columns([2, 1])
    doctor = c1.selectbox("Doctor", doctors, key="dr_doctor",
                          format_func=lambda d: f"{d['doctor_name']} ({d['specialization'] or 'General'})")
    only_day = c2.checkbox("Only this date", value=True, key="dr_only_day")
    day = c2.date_input("Date", value=date.today(), key="dr_day", disabled=not only_day)

    sql = ("SELECT a.appt_id, a.patient_id, a.appt_date, a.appt_time, a.status, a.reason, "
           "CONCAT(p.first_name, ' ', p.last_name) AS patient "
           "FROM Appointments a JOIN Patients p ON p.patient_id = a.patient_id "
           "WHERE a.doctor_id = %s AND a.status <> 'Cancelled' ")
    params = [doctor["doctor_id"]]
    if only_day:
        sql += "AND a.appt_date = %s "
        params.append(day)
    sql += "ORDER BY a.appt_date, a.appt_time"
    appts = run_query(sql, tuple(params))

    if not appts:
        st.info("No appointments for this selection.")
        return
    table = [{"ID": a["appt_id"], "Date": a["appt_date"], "Time": _t(a["appt_time"]),
              "Patient": a["patient"], "Status": a["status"]} for a in appts]
    st.dataframe(pd.DataFrame(table), use_container_width=True, hide_index=True)

    appt = st.selectbox("Open consultation", appts, key="dr_appt",
                        format_func=lambda a: f"#{a['appt_id']} - {a['patient']} at {_t(a['appt_time'])} ({a['appt_date']})")
    st.divider()
    _patient_panel(appt)
    _prescription_section(appt["appt_id"])
    _lab_section(appt["appt_id"])
