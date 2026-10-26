"""
ReUseNSUT - Verified Campus Sharing Marketplace (DBMS project backend)

Usage:
    python main.py setup      # drop + create database, tables, views, triggers, sample data
    python main.py demo       # print all demo output tables
    python main.py menu       # interactive menu for buyer / seller / borrower / lender / admin
    python main.py workflow   # run a live scenario (accept request -> pay -> complete) and show results

Connection settings come from environment variables (defaults in brackets):
    DB_HOST [localhost]  DB_PORT [3307]  DB_USER [root]  DB_PASSWORD []

On Windows, run .\run-project.ps1 from the project folder to start the local
MySQL server, set up the database, and print the demo.
"""
import os
import sys
from pathlib import Path

import mysql.connector
from mysql.connector import Error

DB_NAME = os.getenv("DB_NAME", "reusensut")
BASE_DIR = Path(__file__).resolve().parent
SQL_DIR = BASE_DIR / "sql"
if not SQL_DIR.exists():
    SQL_DIR = BASE_DIR
SETUP_FILES = ["01_schema.sql", "02_logic.sql", "03_seed.sql"]


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def connect(with_db=True):
    cfg = dict(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3307")),
        user=os.getenv("DB_USER", "root"),
    )
    cfg["password"] = os.getenv("DB_PASSWORD", "")
    ssl_ca = os.getenv("DB_SSL_CA")
    if ssl_ca:
        ca_path = Path(ssl_ca)
        if not ca_path.is_file():
            raise FileNotFoundError(f"MySQL TLS CA certificate was not found: {ca_path}")
        cfg["ssl_ca"] = str(ca_path)
        cfg["ssl_verify_cert"] = True
        cfg["ssl_verify_identity"] = True
    if with_db:
        cfg["database"] = DB_NAME
    conn = mysql.connector.connect(**cfg)
    conn.autocommit = True
    return conn

def split_sql(text):
    """Split a .sql file into statements. Understands the DELIMITER command,
    so triggers and procedures (which contain ';') are kept in one piece."""
    delim = ";"
    buf, statements = [], []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("DELIMITER "):
            delim = stripped.split(None, 1)[1].strip()
            continue
        buf.append(line)
        if stripped.endswith(delim) and not stripped.startswith("--"):
            stmt = "\n".join(buf).rstrip()
            stmt = stmt[: -len(delim)].strip()
            buf = []
            if any(l.strip() and not l.strip().startswith("--") for l in stmt.splitlines()):
                statements.append(stmt)
    return statements


def run_script(conn, path):
    cur = conn.cursor()
    statements = split_sql(Path(path).read_text(encoding="utf-8"))
    for stmt in statements:
        cur.execute(stmt)
        if cur.with_rows:
            cur.fetchall()
    cur.close()
    return len(statements)


def print_table(title, headers, rows):
    print(f"\n=== {title} ===")
    if not rows:
        print("(no rows)")
        return
    data = [["" if v is None else str(v) for v in row] for row in rows]
    widths = [max(len(str(h)), *(len(r[i]) for r in data)) for i, h in enumerate(headers)]
    line = "+" + "+".join("-" * (w + 2) for w in widths) + "+"
    print(line)
    print("| " + " | ".join(str(h).ljust(w) for h, w in zip(headers, widths)) + " |")
    print(line)
    for r in data:
        print("| " + " | ".join(v.ljust(w) for v, w in zip(r, widths)) + " |")
    print(line)
    print(f"{len(rows)} row(s)")


def show(conn, title, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params or ())
    rows = cur.fetchall()
    headers = [d[0] for d in cur.description]
    cur.close()
    print_table(title, headers, rows)


# --------------------------------------------------------------------------
# queries (one per end-user need in the project document)
# --------------------------------------------------------------------------
def q_available(conn, category="Textbooks", semester=None, max_price=None):
    sql = """SELECT listing_id, item_name, category_name, listing_type, price, deposit_amount,
                    item_condition, semester, owner_name, owner_trust_score
             FROM v_available_listings WHERE category_name = %s"""
    params = [category]
    if semester:
        sql += " AND semester = %s"
        params.append(semester)
    if max_price is not None:
        sql += " AND price <= %s"
        params.append(max_price)
    sql += " ORDER BY price, item_name"
    label = f"Available {category}" + (f", semester {semester}" if semester else "") + \
            (f", price <= {max_price}" if max_price is not None else "")
    show(conn, f"BUYER: {label}", sql, params)


def q_requests(conn, owner_id):
    show(conn, f"SELLER/DONOR: requests on listings of user {owner_id}",
         """SELECT request_id, item_name, listing_type, requester_name, requester_branch,
                   requester_trust_score, offered_item, request_status
            FROM v_listing_requests WHERE owner_id = %s ORDER BY requested_at DESC""", (owner_id,))


def q_borrowed(conn, borrower_id):
    show(conn, f"BORROWER: items currently borrowed by user {borrower_id}",
         """SELECT item_name, owner_name, due_date, days_left, deposit_amount, deposit_status, loan_status
            FROM v_loan_details WHERE borrower_id = %s AND returned_at IS NULL
            ORDER BY due_date""", (borrower_id,))


def q_on_loan(conn, owner_id):
    show(conn, f"LENDER: items of user {owner_id} on loan and not yet returned",
         """SELECT item_name, borrower_name, borrower_phone, due_date, days_left,
                  IF(is_late, 'LATE', 'on time') AS status
            FROM v_loan_details WHERE owner_id = %s AND returned_at IS NULL
            ORDER BY due_date""", (owner_id,))


def q_overdue(conn):
    show(conn, "ADMIN/LENDER: items overdue today",
         "SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC")


def q_leaderboard(conn, n=5):
    show(conn, f"Top {n} students by sustainability points",
         "SELECT rank_no, name, branch, total_points FROM v_leaderboard ORDER BY rank_no, name LIMIT %s", (n,))


def q_trust(conn, n=5):
    show(conn, f"Top {n} students by trust score",
         """SELECT name, avg_rating, review_count, on_time_returns, late_returns, trust_score
            FROM v_trust_scores ORDER BY trust_score DESC, name LIMIT %s""", (n,))


def q_my_standing(conn, user_id):
    show(conn, f"MY TRUST SCORE (user {user_id})",
         "SELECT name, avg_rating, review_count, on_time_returns, late_returns, trust_score "
         "FROM v_trust_scores WHERE user_id = %s", (user_id,))
    show(conn, f"MY SUSTAINABILITY RANK (user {user_id})",
         "SELECT rank_no, name, total_points FROM v_leaderboard WHERE user_id = %s", (user_id,))


def q_money_saved(conn):
    show(conn, "Total money saved by students through reuse (sell, donate, exchange)",
         """SELECT COUNT(*) AS items_reused, COALESCE(SUM(original_price),0) AS retail_value,
                   COALESCE(SUM(agreed_amount),0) AS actually_paid,
                   COALESCE(SUM(amount_saved),0) AS total_saved
            FROM v_money_saved""")


def q_notifications(conn, user_id):
    show(conn, f"NOTIFICATIONS for user {user_id}",
         "SELECT notif_type, message, created_at FROM notifications "
         "WHERE user_id = %s ORDER BY notification_id DESC", (user_id,))


def q_admin(conn):
    show(conn, "ADMIN: open disputes",
         "SELECT dispute_id, item_name, dispute_reason, raised_by_name, resolution_status, raised_at "
         "FROM v_open_disputes ORDER BY raised_at")
    show(conn, "ADMIN: unverified accounts",
         "SELECT user_id, name, roll_number, university_email, branch, joined_at "
         "FROM v_unverified_users")


def q_history(conn):
    show(conn, "Complete transaction history",
         "SELECT transaction_id, item_name, listing_type, giver_name, receiver_name, "
         "agreed_amount, transaction_status FROM v_transaction_history ORDER BY transaction_id")


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------
def cmd_setup():
    conn = connect(with_db=False)
    try:
        cur = conn.cursor()
        try:
            cur.execute("DROP DATABASE IF EXISTS reusensut")
            cur.execute(
                "CREATE DATABASE reusensut CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
        finally:
            cur.close()
        for name in SETUP_FILES:
            n = run_script(conn, SQL_DIR / name)
            print(f"ran {name}: {n} statements")
    finally:
        conn.close()
    print("\nDatabase ready. Try:  python main.py demo")


def cmd_demo():
    conn = connect()
    q_available(conn, "Textbooks", semester=3, max_price=300)
    q_requests(conn, 3)
    q_borrowed(conn, 8)
    q_on_loan(conn, 7)
    q_overdue(conn)
    q_leaderboard(conn, 5)
    q_trust(conn, 5)
    q_money_saved(conn)
    q_admin(conn)
    q_history(conn)
    conn.close()


def cmd_workflow():
    """Demonstrate accepting a request, paying for it, and completing an order."""
    conn = connect()
    cur = conn.cursor()
    try:
        cur.execute("CALL accept_request(3, 'Main Library Gate', DATE_ADD(NOW(), INTERVAL 1 DAY))")
        cur.execute("SELECT transaction_id FROM transactions WHERE request_id = 3")
        txn = cur.fetchone()[0]
        cur.execute("CALL confirm_payment(%s, 'upi')", (txn,))
        cur.execute("CALL complete_transaction(%s)", (txn,))
        cur.execute("CALL verify_user(11, 1, 'verified')")
        print(f"Order {txn} created, paid and completed. Demo account 11 verified by admin.")
    except Error as e:
        print("Workflow stopped:", e.msg, "(run 'python main.py setup' to reset the data)")
    cur.close()
    show(conn, "Requests on listing 3 (second request auto-rejected)",
         "SELECT request_id, requester_name, request_status FROM v_listing_requests WHERE listing_id = 3")
    q_notifications(conn, 8)
    q_notifications(conn, 10)
    q_leaderboard(conn, 5)
    conn.close()


def ask_int(prompt, default=None):
    raw = input(prompt).strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


MENU = """
===== ReUseNSUT =====
 1  Buyer      - browse available items
 2  Seller     - requests on my listings
 3  Borrower   - my borrowed items
 4  Lender     - my items on loan
 5  Student    - my trust score and sustainability rank
 6  Student    - my notifications
 7  Admin      - open disputes and unverified accounts
 8  Overdue loans today
 9  Leaderboard and trust ranking
10  Money saved by reuse
11  Transaction history
 0  Exit
"""


def cmd_menu():
    conn = connect()
    while True:
        print(MENU)
        choice = input("Choose: ").strip()
        try:
            if choice == "1":
                cat = input("Category [Textbooks]: ").strip() or "Textbooks"
                sem = ask_int("Semester (blank = any): ")
                price = ask_int("Max price (blank = any): ")
                q_available(conn, cat, sem, price)
            elif choice in {"2", "3", "4", "5", "6"}:
                uid = ask_int("Your user id: ")
                if uid is None:
                    print("Please enter a number.")
                    continue
                {"2": q_requests, "3": q_borrowed, "4": q_on_loan,
                 "5": q_my_standing, "6": q_notifications}[choice](conn, uid)
            elif choice == "7":
                q_admin(conn)
            elif choice == "8":
                q_overdue(conn)
            elif choice == "9":
                q_leaderboard(conn, 5)
                q_trust(conn, 5)
            elif choice == "10":
                q_money_saved(conn)
            elif choice == "11":
                q_history(conn)
            elif choice == "0":
                break
            else:
                print("Invalid choice.")
        except Error as e:
            print("Database error:", e.msg)
    conn.close()


def main():
    cmds = {"setup": cmd_setup, "demo": cmd_demo, "menu": cmd_menu, "workflow": cmd_workflow}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds:
        print(__doc__)
        sys.exit(1)
    try:
        cmds[sys.argv[1]]()
    except Error as e:
        print("Database error:", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
