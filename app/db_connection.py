"""
app/db_connection.py  --  shared database layer (Member 3).

Built on Member 1's skeleton and keeps the same public API, so every tab works
unchanged:  run_query, run_write, call_proc, friendly_error  (+ get_connection
for lab_tab.py, + DB_CONFIG for app.py).

What this version adds:
  * Connection POOLING (mysql.connector.pooling) instead of a fresh TCP login
    for every query. Connections are borrowed and returned with .close().
  * One transaction per helper call: commit on success, rollback on error.
  * friendly_error() also covers pool exhaustion and lost connections.

SQL injection: every helper takes the SQL text and the user values separately.
The %s placeholders are filled in by the MySQL driver as DATA, never pasted
into the SQL string, so input like  ' OR 1=1 --  is stored as plain text.
"""
import os
from contextlib import contextmanager

from mysql.connector import Error, pooling

DB_CONFIG = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=int(os.getenv("DB_PORT", "3306")),
    user=os.getenv("DB_USER", "root"),
    password=os.getenv("DB_PASSWORD", ""),
    database=os.getenv("DB_NAME", "clinic_portal"),
)
POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "5"))

_pool = None


def _get_pool():
    """Create the pool on first use (so a wrong password shows a friendly
    error in the app instead of crashing at import time)."""
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(
            pool_name="clinic_pool", pool_size=POOL_SIZE, pool_reset_session=True,
            autocommit=False, **DB_CONFIG)
    return _pool


def get_connection():
    """Borrow a pooled connection. Calling .close() on it returns it to the pool.
    Used directly by lab_tab.py; other tabs use the helpers below."""
    return _get_pool().get_connection()


def friendly_error(err) -> str:
    """Turn a database error into a short message safe to show the user."""
    msg = getattr(err, "msg", None) or str(err)
    errno = getattr(err, "errno", None)
    if "ERR_" in msg:                       # our procedures/triggers: 'ERR_CODE: text'
        return msg.split(": ", 1)[-1]
    if "pool exhausted" in msg.lower():
        return "The database is busy right now. Please try again in a moment."
    known = {
        1062: "That value already exists (phone, email or another unique field is a duplicate).",
        1452: "A referenced record does not exist.",
        1451: "This record cannot be deleted because other records depend on it.",
        3819: "A value breaks a data rule (CHECK constraint).",
        1048: "A required field is missing.",
        1364: "A required field is missing.",
        1146: "A table or view is missing. Load all the SQL scripts (01 to 05) first.",
        1305: "A stored procedure or function is missing. Load 03_procedures_functions.sql.",
        2003: "Cannot connect to the database. Is MySQL running?",
        2013: "Lost the connection to the database. Please try again.",
        1045: "Database login failed. Check DB_USER / DB_PASSWORD.",
        1049: "Database 'clinic_portal' does not exist. Run 01_schema_ddl.sql first.",
    }
    return known.get(errno, msg)


@contextmanager
def get_cursor(dictionary=True):
    """Borrow a connection, yield a cursor, commit or roll back, give it back."""
    conn = get_connection()
    cur = conn.cursor(dictionary=dictionary)
    try:
        yield cur
        conn.commit()
    except Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()                        # returns the connection to the pool


def run_query(sql, params=None):
    """SELECT -> list of dict rows."""
    with get_cursor() as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def run_write(sql, params=None):
    """INSERT/UPDATE/DELETE -> last inserted id (or 0)."""
    with get_cursor() as cur:
        cur.execute(sql, params or ())
        return cur.lastrowid


def call_proc(name, args):
    """
    Call a stored procedure. Pass a placeholder (0) for each OUT parameter.
    Returns the argument tuple with the OUT parameters filled in, e.g.
        appt_id = call_proc("sp_book_appointment", (p, d, date, time, reason, 0))[5]
    The procedure manages its own START TRANSACTION / COMMIT / ROLLBACK.
    """
    with get_cursor(dictionary=False) as cur:
        result = cur.callproc(name, args)
        for rs in cur.stored_results():     # drain any result sets
            rs.fetchall()
        return result
