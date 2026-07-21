"""
db.py
-----
A small, dependency-light wrapper around mysql-connector-python's
connection pool. Every Flask route asks this module for a connection,
uses it, and returns it -- nothing about SQL business logic lives here;
this file is purely plumbing.
"""

import mysql.connector
from mysql.connector import pooling
from config import Config

_pool = None


def init_pool():
    """Create the connection pool once, at app start-up."""
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(
            pool_name="atm_pool",
            pool_size=5,
            host=Config.DB_HOST,
            port=Config.DB_PORT,
            user=Config.DB_USER,
            password=Config.DB_PASSWORD,
            database=Config.DB_NAME,
            autocommit=True,
        )
    return _pool


def get_connection():
    """Borrow a connection from the pool."""
    global _pool
    if _pool is None:
        init_pool()
    return _pool.get_connection()


def run_query(sql, params=None, fetch_one=False):
    """
    Run a SELECT and return results as a list of dicts (or a single
    dict if fetch_one=True). Used for all read-only pages / API calls.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params or ())
        result = cursor.fetchone() if fetch_one else cursor.fetchall()
        cursor.close()
        return result
    finally:
        conn.close()


def call_procedure(proc_name, params):
    """
    Call a stored procedure (WithdrawMoney / DepositMoney / TransferMoney).
    Any business-rule violation raised inside MySQL via SIGNAL surfaces
    here as a mysql.connector.errors.DatabaseError, which the calling
    route catches and turns into a friendly flash message.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.callproc(proc_name, params)
        cursor.close()
    finally:
        conn.close()


def call_function(func_name, params):
    """Call a scalar SQL function (GetBalance / CalculateRisk) and return its value."""
    placeholders = ", ".join(["%s"] * len(params))
    sql = f"SELECT {func_name}({placeholders}) AS result"
    row = run_query(sql, params, fetch_one=True)
    return row["result"] if row else None
