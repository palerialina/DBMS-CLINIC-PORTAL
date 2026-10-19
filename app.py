"""
app/app.py  --  main entry point (SKELETON by Member 1; Member 3 owns this file).
Run from the project root:   streamlit run app/app.py

Each tab lives in its own file and exposes ONE function. A tab that has not
been integrated yet shows a placeholder instead of crashing the whole app.
Rules for every tab file: wrap the UI in a function, use db_connection.py,
and do NOT call st.set_page_config() (only app.py does).
"""
import importlib

import streamlit as st

from db_connection import DB_CONFIG, friendly_error, run_query

st.set_page_config(page_title="Digital Health Clinic Portal", page_icon="🏥", layout="wide")
st.title("🏥 Digital Health Clinic & Diagnostic Lab Portal")

try:
    run_query("SELECT 1 AS ok")
    st.sidebar.success(f"Connected to {DB_CONFIG['database']}")
except Exception as e:                                   # noqa: BLE001 - show any connection problem
    st.sidebar.error(friendly_error(e))
    st.error("Cannot reach the database. Start MySQL and check DB_HOST / DB_USER / DB_PASSWORD.")
    st.stop()

TABS = [                       # (tab title, module, function)
    ("Reception",          "reception_tab", "render_reception_tab"),
    ("Doctor Desk",        "doctor_tab",    "render_doctor_tab"),
    ("Diagnostic Lab",     "lab_tab",       "render_lab_tab"),         # Member 2
    ("Billing & Analytics", "billing_tab",  "render_billing_tab"),     # Member 3
]

for container, (title, module, func) in zip(st.tabs([t[0] for t in TABS]), TABS):
    with container:
        try:
            getattr(importlib.import_module(module), func)()
        except (ModuleNotFoundError, AttributeError) as e:
            st.info(f"'{title}' is not integrated yet ({module}.{func} not found).")
            st.caption(str(e))
