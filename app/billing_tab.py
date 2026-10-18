"""
app/billing_tab.py  --  Tab 4: Billing Desk & Analytics (Member 3).

Billing Desk
  Pick a visit -> preview the line items -> GENERATE the invoice ->
  take payment (PAY). Both steps call Member 1's stored procedure
  sp_generate_or_finalize_bill, which runs as ONE transaction: it sums the
  consultation fee and every lab test, writes the bill, and on payment also
  marks the appointment Completed -- all or nothing.

Analytics
  Revenue by department, daily revenue, top lab tests, busy hours, doctor
  workload and payment modes, all from GROUP BY / JOIN / HAVING queries.
  Each chart has a "Show SQL" expander for the viva.
"""
from datetime import date, datetime, timedelta

import altair as alt
import pandas as pd
import streamlit as st
from mysql.connector import Error

from db_connection import call_proc, friendly_error, run_query

BLUE = "#2a78d6"                     # one hue for every single-series chart
PAYMENT_MODES = ["Cash", "UPI", "Card", "Insurance"]


def _money(v) -> str:
    return f"₹{float(v or 0):,.2f}"


def _hhmm(v) -> str:
    """MySQL TIME arrives as timedelta."""
    return (datetime.min + v).strftime("%H:%M") if isinstance(v, timedelta) else str(v)[:5]


# =========================================================== BILLING DESK
VISITS_SQL = """
    SELECT a.appt_id, a.appt_date, a.appt_time, a.status AS appt_status,
           CONCAT(p.first_name, ' ', p.last_name) AS patient, p.phone,
           d.doctor_name, dep.dept_name, d.consultation_fee,
           b.bill_id, b.status AS bill_status, b.total_amount,
           (SELECT COUNT(*) FROM Lab_Orders lo
             WHERE lo.appt_id = a.appt_id AND lo.status <> 'Completed') AS labs_pending
    FROM Appointments a
    JOIN Patients p      ON p.patient_id = a.patient_id
    JOIN Doctors d       ON d.doctor_id  = a.doctor_id
    JOIN Departments dep ON dep.dept_id  = d.dept_id
    LEFT JOIN Bills b    ON b.appt_id    = a.appt_id
    WHERE a.status <> 'Cancelled'
      AND (b.status IS NULL OR b.status <> 'Paid')
      AND a.appt_date <= CURDATE()
    ORDER BY a.appt_date DESC, a.appt_time DESC
"""


def _visit_label(v) -> str:
    state = v["bill_status"] or "Not billed"
    if v["labs_pending"]:
        state += f", {v['labs_pending']} lab pending"
    return (f"#{v['appt_id']}  {v['patient']}  with {v['doctor_name']}  "
            f"({v['appt_date']:%d %b} {_hhmm(v['appt_time'])})  [{state}]")


def _invoice_text(v, lines, bill) -> str:
    rows = "\n".join(f"  {name:<44}{_money(amt):>14}" for name, amt in lines)
    paid = (f"PAID on {bill['paid_at']:%d %b %Y %H:%M} by {bill['payment_mode']}"
            if bill["status"] == "Paid" else f"Status: {bill['status']} (unpaid)")
    return (
        "DIGITAL HEALTH CLINIC & DIAGNOSTIC LAB\n"
        f"Invoice #{bill['bill_id']:06d}        Date: {bill['generated_at']:%d %b %Y}\n"
        f"{'-' * 60}\n"
        f"Patient : {v['patient']}  ({v['phone']})\n"
        f"Doctor  : {v['doctor_name']}, {v['dept_name']}\n"
        f"Visit   : #{v['appt_id']} on {v['appt_date']:%d %b %Y} at {_hhmm(v['appt_time'])}\n"
        f"{'-' * 60}\n{rows}\n{'-' * 60}\n"
        f"  {'TOTAL':<44}{_money(bill['total_amount']):>14}\n\n{paid}\n")


def _billing_desk():
    flash = st.session_state.pop("bill_msg", None)
    if flash:
        st.success(flash)

    visits = run_query(VISITS_SQL)
    if not visits:
        st.info("No visits are waiting for billing. Every visit up to today is paid.")
        _recent_paid()
        return

    c1, c2 = st.columns([3, 1])
    only_ready = c2.toggle("Only visits ready to bill", value=False, key="bl_ready",
                           help="Hide visits that still have lab tests pending")
    shown = [v for v in visits if not (only_ready and v["labs_pending"])]
    if not shown:
        st.info("Every unbilled visit still has lab tests pending.")
        return
    # Options are appointment IDs (stable), not the row dicts: the label changes
    # when a bill is generated, and a changed option list would reset the choice.
    by_id = {v["appt_id"]: v for v in shown}
    if st.session_state.get("bl_visit") not in by_id:
        st.session_state.pop("bl_visit", None)
    appt_id = c1.selectbox("Visit to bill", list(by_id), key="bl_visit",
                           format_func=lambda i: _visit_label(by_id[i]))
    v = by_id[appt_id]

    labs = run_query(
        "SELECT t.test_name, t.cost, lo.status FROM Lab_Orders lo "
        "JOIN Diagnostic_Tests t ON t.test_id = lo.test_id "
        "WHERE lo.appt_id = %s ORDER BY lo.lab_order_id", (appt_id,))
    lines = [(f"Consultation - {v['doctor_name']}", v["consultation_fee"])]
    lines += [(f"Lab - {r['test_name']}", r["cost"]) for r in labs]

    left, right = st.columns([3, 2])
    with left:
        st.markdown(f"#### {v['patient']}")
        st.caption(f"{v['dept_name']} · {v['doctor_name']} · visit #{appt_id} on "
                   f"{v['appt_date']:%d %b %Y} at {_hhmm(v['appt_time'])}")
        table = pd.DataFrame({
            "Item": [n for n, _ in lines],
            "Status": ["-"] + [r["status"] for r in labs],
            "Amount (₹)": [float(a) for _, a in lines],
        })
        st.dataframe(table, hide_index=True, use_container_width=True,
                     column_config={"Amount (₹)": st.column_config.NumberColumn(format="%.2f")})
        st.markdown(f"**Expected total: {_money(sum(float(a) for _, a in lines))}**")
        if v["labs_pending"]:
            st.warning(f"{v['labs_pending']} lab test(s) are not completed yet. The procedure will refuse "
                       "to invoice this visit until the lab finishes. You can press Generate to show this.")

    with right:
        st.markdown("#### Invoice")
        bill_status = v["bill_status"]
        if bill_status == "Draft":
            st.info("A test was ordered after the invoice was made, so the bill went back to Draft. "
                    "Regenerate it to pick up the new total.")
        gen_label = "Generate invoice" if bill_status is None else "Regenerate invoice"
        if st.button(gen_label, type="primary" if bill_status is None else "secondary",
                     key=f"bl_gen_{appt_id}", use_container_width=True):
            try:
                out = call_proc("sp_generate_or_finalize_bill", (appt_id, "GENERATE", None, 0, 0))
                st.session_state["bill_msg"] = (f"Invoice #{out[3]} generated for {v['patient']}: "
                                                f"{_money(out[4])}")
                st.rerun()
            except Error as e:
                st.error(friendly_error(e))     # e.g. 'Complete all lab tests before generating the invoice'

        if bill_status == "Draft":
            st.metric("Amount due (provisional)", _money(v["total_amount"]))
            st.caption("Payment opens once the invoice is regenerated.")
        elif bill_status == "Generated":
            st.metric("Amount due", _money(v["total_amount"]))
            mode = st.selectbox("Payment mode", PAYMENT_MODES, key=f"bl_mode_{appt_id}")
            if st.button("Mark as paid", type="primary", key=f"bl_pay_{appt_id}", use_container_width=True):
                try:
                    out = call_proc("sp_generate_or_finalize_bill", (appt_id, "PAY", mode, 0, 0))
                    st.session_state["bill_msg"] = (f"Payment of {_money(out[4])} received by {mode}. "
                                                    f"Bill #{out[3]} is Paid and visit #{appt_id} is Completed.")
                    st.rerun()
                except Error as e:
                    st.error(friendly_error(e))
            bill = run_query("SELECT * FROM Bills WHERE appt_id = %s", (appt_id,))[0]
            st.download_button("Download invoice (.txt)", _invoice_text(v, lines, bill),
                               file_name=f"invoice_{bill['bill_id']:06d}.txt", key=f"bl_dl_{appt_id}",
                               use_container_width=True)
        elif bill_status is None:
            st.caption("No invoice yet. Generating one sums the consultation fee and all lab tests "
                       "in a single transaction.")

    st.divider()
    _recent_paid()


def _recent_paid():
    st.markdown("#### Recently paid")
    rows = run_query(
        "SELECT b.bill_id AS bill, b.paid_at, CONCAT(p.first_name, ' ', p.last_name) AS patient, "
        "       d.doctor_name AS doctor, b.consultation_fee, b.lab_total, b.total_amount, b.payment_mode "
        "FROM Bills b JOIN Appointments a ON a.appt_id = b.appt_id "
        "JOIN Patients p ON p.patient_id = a.patient_id JOIN Doctors d ON d.doctor_id = a.doctor_id "
        "WHERE b.status = 'Paid' ORDER BY b.paid_at DESC LIMIT 15")
    if not rows:
        st.caption("No payments yet.")
        return
    df = pd.DataFrame(rows)
    for c in ("consultation_fee", "lab_total", "total_amount"):
        df[c] = df[c].astype(float)
    st.dataframe(df, hide_index=True, use_container_width=True, column_config={
        "paid_at": st.column_config.DatetimeColumn("Paid at", format="DD MMM, HH:mm"),
        "consultation_fee": st.column_config.NumberColumn("Consultation ₹", format="%.2f"),
        "lab_total": st.column_config.NumberColumn("Labs ₹", format="%.2f"),
        "total_amount": st.column_config.NumberColumn("Total ₹", format="%.2f"),
    })


# ============================================================== ANALYTICS
Q_DEPT_REVENUE = """
SELECT dep.dept_name AS department,
       COUNT(b.bill_id)    AS paid_visits,
       SUM(b.total_amount) AS revenue
FROM Bills b
JOIN Appointments a  ON a.appt_id   = b.appt_id
JOIN Doctors d       ON d.doctor_id = a.doctor_id
JOIN Departments dep ON dep.dept_id = d.dept_id
WHERE b.status = 'Paid' AND b.paid_at >= %s
GROUP BY dep.dept_name
ORDER BY revenue DESC"""

Q_DAILY_REVENUE = """
SELECT DATE(b.paid_at) AS day, SUM(b.total_amount) AS revenue
FROM Bills b
WHERE b.status = 'Paid' AND b.paid_at >= %s
GROUP BY DATE(b.paid_at)
ORDER BY day"""

Q_TOP_TESTS = """
SELECT t.test_name, t.category,
       COUNT(*)    AS times_ordered,
       SUM(t.cost) AS lab_revenue
FROM Lab_Orders lo
JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
JOIN Appointments a     ON a.appt_id = lo.appt_id
WHERE a.status <> 'Cancelled' AND lo.ordered_at >= %s
GROUP BY t.test_id, t.test_name, t.category
HAVING COUNT(*) >= 2               -- ignore one-off tests
ORDER BY times_ordered DESC
LIMIT 10"""

Q_BUSY_HOURS = """
SELECT HOUR(a.appt_time) AS hour, COUNT(*) AS appointments
FROM Appointments a
WHERE a.status <> 'Cancelled' AND a.appt_date >= %s
GROUP BY HOUR(a.appt_time)
ORDER BY hour"""

Q_DOCTORS = """
SELECT d.doctor_name AS doctor, dep.dept_name AS department,
       COUNT(a.appt_id) AS visits,
       COALESCE(SUM(CASE WHEN b.status = 'Paid' THEN b.total_amount END), 0) AS revenue,
       ROUND(COALESCE(SUM(CASE WHEN b.status = 'Paid' THEN b.total_amount END), 0)
             / NULLIF(COUNT(a.appt_id), 0), 2) AS revenue_per_visit
FROM Doctors d
JOIN Departments dep     ON dep.dept_id = d.dept_id
LEFT JOIN Appointments a ON a.doctor_id = d.doctor_id
                        AND a.status <> 'Cancelled' AND a.appt_date >= %s
LEFT JOIN Bills b        ON b.appt_id = a.appt_id
GROUP BY d.doctor_id, d.doctor_name, dep.dept_name
ORDER BY revenue DESC"""

Q_PAYMENT_MODES = """
SELECT payment_mode, COUNT(*) AS bills, SUM(total_amount) AS amount
FROM Bills
WHERE status = 'Paid' AND paid_at >= %s
GROUP BY payment_mode
ORDER BY amount DESC"""

Q_KPIS = """
SELECT
  (SELECT COALESCE(SUM(total_amount), 0) FROM Bills
    WHERE status = 'Paid' AND paid_at >= %s)                              AS revenue,
  (SELECT COUNT(*) FROM Bills WHERE status = 'Paid' AND paid_at >= %s)    AS paid_bills,
  (SELECT COUNT(*) FROM Appointments
    WHERE status <> 'Cancelled' AND appt_date >= %s AND appt_date <= CURDATE()) AS visits,
  (SELECT COUNT(*) FROM Appointments
    WHERE status = 'Cancelled' AND appt_date >= %s)                       AS cancelled,
  (SELECT COALESCE(SUM(total_amount), 0) FROM Bills WHERE status <> 'Paid') AS outstanding"""


def _df(sql, since, money_cols=()):
    df = pd.DataFrame(run_query(sql, (since,)))
    for c in money_cols:
        if c in df:
            df[c] = df[c].astype(float)
    return df


def _show_sql(sql):
    with st.expander("Show SQL"):
        st.code(sql.strip(), language="sql")


def _bar(df, cat, val, cat_title, val_title, money=False, horizontal=True, sort="-x"):
    fmt = ",.0f"
    tip = [alt.Tooltip(cat, title=cat_title),
           alt.Tooltip(val, title=val_title, format=",.2f" if money else ",d")]
    if horizontal:
        enc = dict(y=alt.Y(f"{cat}:N", sort=sort, title=None, scale=alt.Scale(paddingInner=0.3)),
                   x=alt.X(f"{val}:Q", title=val_title, axis=alt.Axis(format=fmt)))
    else:
        enc = dict(x=alt.X(f"{cat}:O", title=cat_title, axis=alt.Axis(labelAngle=0),
                           scale=alt.Scale(paddingInner=0.3)),
                   y=alt.Y(f"{val}:Q", title=val_title, axis=alt.Axis(format=fmt)))
    chart = alt.Chart(df).mark_bar(color=BLUE, cornerRadiusEnd=4).encode(**enc, tooltip=tip)
    return chart.properties(height=max(200, 34 * len(df)) if horizontal else 280)


def _analytics():
    periods = {"Last 7 days": 7, "Last 30 days": 30, "Last 90 days": 90, "Last 365 days": 365}
    label = st.segmented_control("Period", list(periods), default="Last 30 days", key="an_period") or "Last 30 days"
    since = date.today() - timedelta(days=periods[label])

    k = run_query(Q_KPIS, (since, since, since, since))[0]
    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Revenue collected", _money(k["revenue"]))
    c2.metric("Paid bills", k["paid_bills"])
    c3.metric("Average bill", _money(float(k["revenue"]) / k["paid_bills"]) if k["paid_bills"] else "-")
    c4.metric("Visits", k["visits"], help="Non-cancelled appointments up to today")
    c5.metric("Outstanding (unpaid)", _money(k["outstanding"]),
              help=f"{k['cancelled']} appointment(s) were cancelled in this period")

    # -- revenue by department + daily trend
    left, right = st.columns(2)
    with left:
        st.markdown("##### Revenue by department")
        df = _df(Q_DEPT_REVENUE, since, ["revenue"])
        if df.empty:
            st.caption("No paid bills in this period.")
        else:
            st.altair_chart(_bar(df, "department", "revenue", "Department", "Revenue (₹)", money=True),
                            use_container_width=True)
        _show_sql(Q_DEPT_REVENUE)
    with right:
        st.markdown("##### Revenue per day")
        df = _df(Q_DAILY_REVENUE, since, ["revenue"])
        if df.empty:
            st.caption("No paid bills in this period.")
        else:
            df["day"] = pd.to_datetime(df["day"])
            base = alt.Chart(df).encode(
                x=alt.X("day:T", title=None, axis=alt.Axis(format="%d %b", grid=False)),
                y=alt.Y("revenue:Q", title="Revenue (₹)", axis=alt.Axis(format=",.0f")))
            hover = alt.selection_point(fields=["day"], nearest=True, on="pointerover", empty=False)
            line = base.mark_line(color=BLUE, strokeWidth=2)
            pts = base.mark_point(color=BLUE, filled=True, size=70).encode(
                opacity=alt.condition(hover, alt.value(1), alt.value(0)),
                tooltip=[alt.Tooltip("day:T", title="Day", format="%a %d %b"),
                         alt.Tooltip("revenue:Q", title="Revenue (₹)", format=",.2f")]
            ).add_params(hover)
            rule = base.mark_rule(color="gray", strokeDash=[3, 3]).encode(
                opacity=alt.condition(hover, alt.value(0.6), alt.value(0))).transform_filter(hover)
            st.altair_chart((line + rule + pts).properties(height=280), use_container_width=True)
        _show_sql(Q_DAILY_REVENUE)

    # -- top lab tests + busy hours
    left, right = st.columns(2)
    with left:
        st.markdown("##### Most ordered lab tests")
        df = _df(Q_TOP_TESTS, since, ["lab_revenue"])
        if df.empty:
            st.caption("No test was ordered twice or more in this period.")
        else:
            df["times_ordered"] = df["times_ordered"].astype(int)
            st.altair_chart(_bar(df, "test_name", "times_ordered", "Test", "Times ordered"),
                            use_container_width=True)
        _show_sql(Q_TOP_TESTS)
    with right:
        st.markdown("##### Busy hours")
        df = _df(Q_BUSY_HOURS, since)
        if df.empty:
            st.caption("No appointments in this period.")
        else:
            df["hour"] = df["hour"].astype(int)
            df["slot"] = df["hour"].map(lambda h: f"{h:02d}:00")
            df["appointments"] = df["appointments"].astype(int)
            st.altair_chart(_bar(df, "slot", "appointments", "Hour of day", "Appointments",
                                 horizontal=False), use_container_width=True)
            peak = df.loc[df["appointments"].idxmax()]
            st.caption(f"Peak hour: **{peak['slot']}** with {peak['appointments']} appointments.")
        _show_sql(Q_BUSY_HOURS)

    # -- doctors + payment modes
    left, right = st.columns([3, 2])
    with left:
        st.markdown("##### Doctor workload and revenue")
        df = _df(Q_DOCTORS, since, ["revenue", "revenue_per_visit"])
        st.dataframe(df, hide_index=True, use_container_width=True, column_config={
            "revenue": st.column_config.NumberColumn("Revenue ₹", format="%.0f"),
            "revenue_per_visit": st.column_config.NumberColumn("₹ per visit", format="%.0f"),
        })
        _show_sql(Q_DOCTORS)
    with right:
        st.markdown("##### Payment modes")
        df = _df(Q_PAYMENT_MODES, since, ["amount"])
        if df.empty:
            st.caption("No payments in this period.")
        else:
            st.altair_chart(_bar(df, "payment_mode", "amount", "Mode", "Amount (₹)", money=True),
                            use_container_width=True)
        _show_sql(Q_PAYMENT_MODES)

    # -- trigger evidence
    with st.expander("Audit trail (written by trg_audit_appointment_cancellation)"):
        logs = run_query("SELECT log_id, logged_at, record_id AS appt_id, action, old_status, new_status, details "
                         "FROM Audit_Logs ORDER BY log_id DESC LIMIT 25")
        if logs:
            st.dataframe(pd.DataFrame(logs), hide_index=True, use_container_width=True)
        else:
            st.caption("No audit entries yet. Cancel an appointment in Reception to create one.")


def render_billing_tab():
    desk, analytics = st.tabs(["🧾 Billing Desk", "📊 Analytics"])
    with desk:
        _billing_desk()
    with analytics:
        _analytics()
