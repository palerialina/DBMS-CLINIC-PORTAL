"""
lab_tab.py | Member 2 | Diagnostic Lab tab for the Streamlit app

Two ways to use this file:
  1. On its own, to test your part:   streamlit run lab_tab.py
  2. Inside Member 3's app.py:
         from lab_tab import render_lab_tab
         with tab_lab:
             render_lab_tab(get_connection)
     where get_connection() returns a mysql-connector connection
     (a pooled connection works too, because we call .close() on it).

Workflow handled here (matches Lab_Orders.status in the schema):
    Ordered -> Sample Collected -> Completed
All SQL uses %s placeholders (parameterized), never string formatting.
"""
import mysql.connector
import streamlit as st

try:                                    # inside the main app: same messages as every other tab
    from db_connection import friendly_error
except ImportError:                     # stand-alone test mode without db_connection.py
    def friendly_error(err):
        msg = getattr(err, "msg", None) or str(err)
        return msg.split(": ", 1)[-1] if "ERR_" in msg else msg


# ---------------------------------------------------------------- helpers
def _query(get_conn, sql, params=None):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        cur.close()
        return rows
    finally:
        conn.close()


def _execute(get_conn, sql, params):
    """Run one UPDATE in its own transaction. Returns rows changed."""
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        conn.commit()
        changed = cur.rowcount
        cur.close()
        return changed
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ------------------------------------------------------------ main render
def render_lab_tab(get_conn):
    st.header("Diagnostic Lab")

    msg = st.session_state.pop("lab_msg", None)
    if msg:
        st.success(msg)

    # vw_pending_lab_reports already hides Completed tests and
    # tests that belong to cancelled appointments.
    pending = _query(
        get_conn,
        "SELECT * FROM vw_pending_lab_reports ORDER BY ordered_at, lab_order_id",
    )

    c1, c2, c3 = st.columns(3)
    c1.metric("Pending tests", len(pending))
    c2.metric("Waiting for sample", sum(1 for r in pending if r["status"] == "Ordered"))
    c3.metric("Waiting for result", sum(1 for r in pending if r["status"] == "Sample Collected"))

    st.subheader("Pending worklist")
    if pending:
        st.dataframe(pending, use_container_width=True, hide_index=True)
    else:
        st.info("No pending tests. The lab queue is empty.")

    st.divider()
    col_a, col_b = st.columns(2)
    with col_a:
        _collect_panel(get_conn, pending)
    with col_b:
        _result_panel(get_conn, pending)

    st.divider()
    _abnormal_panel(get_conn)


# ---------------------------------------------- step 1: collect the sample
def _collect_panel(get_conn, pending):
    st.subheader("1. Collect sample")
    rows = [r for r in pending if r["status"] == "Ordered"]
    if not rows:
        st.info("No orders are waiting for a sample.")
        return

    labels = {
        f"Order #{r['lab_order_id']} | {r['patient_name']} | {r['test_name']}": r
        for r in rows
    }
    choice = st.selectbox("Order", list(labels), key="lab_collect_sel")
    order = labels[choice]

    if st.button("Mark sample collected", key="lab_collect_btn"):
        try:
            changed = _execute(
                get_conn,
                "UPDATE Lab_Orders "
                "SET status = 'Sample Collected', sample_collected_at = NOW() "
                "WHERE lab_order_id = %s AND status = 'Ordered'",
                (order["lab_order_id"],),
            )
        except mysql.connector.Error as e:
            st.error(friendly_error(e))
            return
        if changed == 0:
            st.warning("This order was already updated by someone else. Refreshing.")
        else:
            st.session_state["lab_msg"] = (
                f"Sample collected for order #{order['lab_order_id']} ({order['test_name']})."
            )
        st.rerun()


# ------------------------------------------------ step 2: enter the result
def _result_panel(get_conn, pending):
    st.subheader("2. Enter result")
    rows = [r for r in pending if r["status"] == "Sample Collected"]
    if not rows:
        st.info("No samples are waiting for a result.")
        return

    labels = {
        f"Order #{r['lab_order_id']} | {r['patient_name']} | {r['test_name']}": r
        for r in rows
    }
    choice = st.selectbox("Order", list(labels), key="lab_result_sel")
    order = labels[choice]
    oid = order["lab_order_id"]

    test = _query(
        get_conn,
        "SELECT ref_range_low, ref_range_high, unit FROM Diagnostic_Tests WHERE test_id = %s",
        (order["test_id"],),
    )[0]
    low, high = test["ref_range_low"], test["ref_range_high"]
    unit = test["unit"] or ""
    has_range = low is not None and high is not None

    value = None
    if has_range:
        st.caption(f"Reference range: {low} to {high} {unit}")
        value = st.number_input(
            f"Result value ({unit})" if unit else "Result value",
            min_value=0.0, value=0.0, step=0.1, format="%.2f", key=f"lab_val_{oid}",
        )
    else:
        st.caption("Report-type test (no numeric range). Write the findings in the notes.")

    notes = st.text_input("Notes", max_chars=200, key=f"lab_notes_{oid}")

    if st.button("Complete order", key=f"lab_done_{oid}"):
        if not has_range and not notes.strip():
            st.error("Please enter the findings in the notes box.")
            return
        stored_value = round(float(value), 2) if value is not None else None
        try:
            changed = _execute(
                get_conn,
                "UPDATE Lab_Orders "
                "SET status = 'Completed', result_value = %s, result_notes = %s, "
                "    completed_at = NOW() "
                "WHERE lab_order_id = %s AND status = 'Sample Collected'",
                (stored_value, notes.strip() or None, oid),
            )
        except mysql.connector.Error as e:
            st.error(friendly_error(e))
            return
        if changed == 0:
            st.warning("This order was already updated by someone else. Refreshing.")
        else:
            flag = ""
            if has_range and stored_value is not None:
                if stored_value < float(low):
                    flag = " Result is LOW."
                elif stored_value > float(high):
                    flag = " Result is HIGH."
            st.session_state["lab_msg"] = (
                f"Order #{oid} ({order['test_name']}) completed.{flag}"
            )
        st.rerun()


# ------------------------------------------- abnormal results (Query Q8)
def _abnormal_panel(get_conn):
    st.subheader("Abnormal results (outside reference range)")
    rows = _query(
        get_conn,
        """
        SELECT CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
               t.test_name, lo.result_value, t.ref_range_low, t.ref_range_high, t.unit,
               CASE WHEN lo.result_value < t.ref_range_low  THEN 'LOW'
                    WHEN lo.result_value > t.ref_range_high THEN 'HIGH' END AS flag
        FROM Lab_Orders lo
        JOIN Diagnostic_Tests t ON t.test_id = lo.test_id
        JOIN Appointments a     ON a.appt_id = lo.appt_id
        JOIN Patients p         ON p.patient_id = a.patient_id
        WHERE lo.status = 'Completed' AND lo.result_value IS NOT NULL
          AND (lo.result_value < t.ref_range_low OR lo.result_value > t.ref_range_high)
        ORDER BY lo.completed_at DESC
        """,
    )
    if rows:
        st.dataframe(rows, use_container_width=True, hide_index=True)
    else:
        st.info("No abnormal results yet.")


# ------------------------------------------- stand-alone mode for testing
if __name__ == "__main__":
    st.set_page_config(page_title="Diagnostic Lab", layout="wide")

    with st.sidebar:
        st.markdown("**Database login**")
        host = st.text_input("Host", "localhost")
        user = st.text_input("User", "root")
        password = st.text_input("Password", type="password")
        database = st.text_input("Database", "clinic_portal")

    def _standalone_conn():
        return mysql.connector.connect(
            host=host, user=user, password=password, database=database
        )

    try:
        _standalone_conn().close()
    except mysql.connector.Error as e:
        st.error(f"Cannot connect: {e.msg}. Check the password in the sidebar.")
        st.stop()

    render_lab_tab(_standalone_conn)
