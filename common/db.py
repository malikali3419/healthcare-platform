import psycopg2
import psycopg2.extras
from common.secrets import get_secret

_connection = None

DB_SECRET_NAME = "healthcare/db"


def get_connection():
    """Return a reusable database connection (connection reuse across Lambda invocations)."""
    global _connection
    if _connection and not _connection.closed:
        return _connection

    creds = get_secret(DB_SECRET_NAME)
    _connection = psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        user=creds["username"],
        password=creds["password"],
        dbname=creds["dbname"],
    )
    _connection.autocommit = False
    return _connection


def execute_query(query: str, params: tuple = None, fetch: bool = True):
    """Execute a query and optionally return results as a list of dicts."""
    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, params)
            if fetch:
                rows = cur.fetchall()
                return [dict(row) for row in rows]
            conn.commit()
            return None
    except Exception:
        conn.rollback()
        raise


def execute_insert(query: str, params: tuple = None):
    """Execute an insert and return the inserted row."""
    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, params)
            row = cur.fetchone()
            conn.commit()
            return dict(row) if row else None
    except Exception:
        conn.rollback()
        raise
