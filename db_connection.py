"""
app/db_connection.py  --  shared database helper (SKELETON by Member 1).
Member 3 owns this file; if they already have a version, keep theirs and make
sure it exposes the same four functions: run_query, run_write, call_proc,
friendly_error.

All SQL uses %s placeholders (parameterized queries) -- user input is sent as
data, never concatenated into the SQL text, which prevents SQL injection.
"""
import os
from contextlib import contextmanager

import mysql.connector
from mysql.connector import Error

DB_CONFIG = dict(
    host=os.getenv("DB_HOST", "localhost"),
    port=int(os.getenv("DB_PORT", "3306")),
    user=os.getenv("DB_USER", "root"),
    password=os.getenv("DB_PASSWORD", ""),
    database=os.getenv("DB_NAME", "clinic_portal"),
)


def friendly_error(err) -> str:
    """Turn a database error into a short message safe to show the user."""
    msg = getattr(err, "msg", None) or str(err)
    errno = getattr(err, "errno", None)
    if "ERR_" in msg:                       # our procedures/triggers: 'ERR_CODE: text'
        return msg.split(": ", 1)[-1]
    known = {
        1062: "That value already exists (phone, email or another unique field is a duplicate).",
        1452: "A referenced record does not exist.",
        1451: "This record cannot be deleted because other records depend on it.",
        3819: "A value breaks a data rule (CHECK constraint).",
        1048: "A required field is missing.",
        1364: "A required field is missing.",
        2003: "Cannot connect to the database. Is MySQL running?",
        1045: "Database login failed. Check DB_USER / DB_PASSWORD.",
    }
    return known.get(errno, msg)


@contextmanager
def get_cursor(dictionary=True):
    conn = mysql.connector.connect(**DB_CONFIG)
    cur = conn.cursor(dictionary=dictionary)
    try:
        yield cur
        conn.commit()
    except Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


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
    """
    with get_cursor(dictionary=False) as cur:
        result = cur.callproc(name, args)
        for rs in cur.stored_results():     # drain any result sets
            rs.fetchall()
        return result
