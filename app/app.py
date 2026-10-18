"""
app/app.py  --  main entry point (Member 3). Built on Member 1's skeleton.
Run from the project root:   streamlit run app/app.py

Each tab lives in its own file and exposes ONE render function.
Rules for every tab file: wrap the UI in a function, use db_connection.py,
and do NOT call st.set_page_config() (only app.py does).

Integration fixes over the skeleton:
  * lab_tab.render_lab_tab(get_conn) takes a connection factory; the skeleton
    called it with no arguments, which crashed. Each tab now declares its args.
  * The skeleton caught AttributeError around the whole tab, so a real bug
    inside a tab looked like "not integrated yet". Now only a missing module or
    function shows that note; database errors inside a tab are shown with
    friendly_error() and the other tabs keep working.
"""
import importlib
from datetime import date

import streamlit as st
from mysql.connector import Error

from db_connection import DB_CONFIG, friendly_error, get_connection, run_query

st.set_page_config(page_title="Digital Health Clinic Portal", page_icon="🏥", layout="wide")
st.title("🏥 Digital Health Clinic & Diagnostic Lab Portal")

# ------------------------------------------------------------- sidebar
try:
    run_query("SELECT 1 AS ok")
    st.sidebar.success(f"Connected to **{DB_CONFIG['database']}** on {DB_CONFIG['host']}")
except Exception as e:                                   # noqa: BLE001 - show any connection problem
    st.sidebar.error(friendly_error(e))
    st.error("Cannot reach the database. Start MySQL and check DB_HOST / DB_USER / DB_PASSWORD.")
    st.stop()

try:
    today = run_query(
        "SELECT "
        " (SELECT COUNT(*) FROM Appointments WHERE appt_date = CURDATE() AND status <> 'Cancelled') AS visits,"
        " (SELECT COUNT(*) FROM Lab_Orders lo JOIN Appointments a ON a.appt_id = lo.appt_id"
        "   WHERE lo.status <> 'Completed' AND a.status <> 'Cancelled') AS pending_labs,"
        " (SELECT COUNT(*) FROM Bills WHERE status <> 'Paid') AS unpaid_bills")[0]
    st.sidebar.markdown(f"**Today, {date.today():%d %b %Y}**")
    s1, s2, s3 = st.sidebar.columns(3)
    s1.metric("Visits", today["visits"])
    s2.metric("Lab queue", today["pending_labs"])
    s3.metric("Unpaid", today["unpaid_bills"])
except Error as e:
    st.sidebar.warning(friendly_error(e))

st.sidebar.divider()
st.sidebar.caption(
    "Demo flow: Reception → Doctor Desk → Diagnostic Lab → Billing.\n\n"
    "All SQL from this app uses parameterized queries (%s placeholders).")

# ---------------------------------------------------------------- tabs
TABS = [  # (tab title, module, function, positional args)
    ("Reception",           "reception_tab", "render_reception_tab", ()),
    ("Doctor Desk",         "doctor_tab",    "render_doctor_tab",    ()),
    ("Diagnostic Lab",      "lab_tab",       "render_lab_tab",       (get_connection,)),   # Member 2
    ("Billing & Analytics", "billing_tab",   "render_billing_tab",   ()),                  # Member 3
]

for container, (title, module, func, args) in zip(st.tabs([t[0] for t in TABS]), TABS):
    with container:
        try:
            render = getattr(importlib.import_module(module), func)
        except (ModuleNotFoundError, AttributeError) as e:
            st.info(f"'{title}' is not integrated yet ({module}.{func} not found).")
            st.caption(str(e))
            continue
        try:
            render(*args)
        except Error as e:                    # database problem inside one tab
            st.error(f"{title}: {friendly_error(e)}")
