"""Local browser UI for the ReUseNSUT campus-sharing marketplace."""

import os
from decimal import Decimal, InvalidOperation

from flask import Flask, abort, jsonify, render_template, request
from mysql.connector import Error

from main import connect

app = Flask(__name__)

LISTING_TYPES = ("sale", "lend", "exchange", "donation")
LISTING_LABELS = {
    "sale": "For sale",
    "lend": "For lending",
    "exchange": "Exchange",
    "donation": "Free",
}


def fetch_all(sql, params=()):
    conn = connect()
    try:
        cur = conn.cursor(dictionary=True)
        try:
            cur.execute(sql, params)
            return cur.fetchall()
        finally:
            cur.close()
    finally:
        conn.close()


def fetch_one(sql, params=()):
    rows = fetch_all(sql, params)
    return rows[0] if rows else None


@app.get("/healthz")
def health_check():
    fetch_one("SELECT 1 AS ready")
    return jsonify(status="ok")


@app.get("/")
def home():
    search = request.args.get("q", "").strip()
    category = request.args.get("category", "").strip()
    listing_type = request.args.get("type", "").strip().lower()
    semester_text = request.args.get("semester", "").strip()
    max_price_text = request.args.get("max_price", "").strip()

    if len(search) > 100:
        abort(400, description="Search terms must be 100 characters or fewer.")
    if listing_type and listing_type not in LISTING_TYPES:
        abort(400, description="Choose a valid listing type.")

    semester = None
    if semester_text:
        try:
            semester = int(semester_text)
        except ValueError:
            abort(400, description="Semester must be a number from 1 to 8.")
        if not 1 <= semester <= 8:
            abort(400, description="Semester must be a number from 1 to 8.")

    max_price = None
    if max_price_text:
        try:
            max_price = Decimal(max_price_text)
        except InvalidOperation:
            abort(400, description="Enter a valid maximum price.")
        if not max_price.is_finite() or max_price < 0:
            abort(400, description="Maximum price must be zero or more.")

    conditions = ["1 = 1"]
    params = []
    if search:
        conditions.append("v.item_name LIKE %s")
        params.append(f"%{search}%")
    if category:
        conditions.append("v.category_name = %s")
        params.append(category)
    if listing_type:
        conditions.append("v.listing_type = %s")
        params.append(listing_type)
    if semester is not None:
        conditions.append("v.semester = %s")
        params.append(semester)
    if max_price is not None:
        conditions.append("v.price <= %s")
        params.append(max_price)

    listings = fetch_all(
        """
        SELECT v.listing_id, v.item_id, v.item_name, v.category_name,
               v.listing_type, v.price, v.deposit_amount, v.max_loan_days,
               v.item_condition, v.semester, v.owner_name, v.owner_branch,
               v.owner_trust_score, i.description
        FROM v_available_listings v
        JOIN items i ON i.item_id = v.item_id
        WHERE """
        + " AND ".join(conditions)
        + " ORDER BY v.listing_type, v.price, v.item_name",
        params,
    )
    categories = fetch_all(
        "SELECT category_name FROM categories ORDER BY category_name"
    )
    stats = fetch_one(
        """
        SELECT
            (SELECT COUNT(*) FROM v_available_listings) AS active_listings,
            (SELECT COUNT(*) FROM users
             WHERE account_role = 'student' AND verification_status = 'verified') AS students,
            (SELECT COUNT(*) FROM transactions
             WHERE transaction_status = 'completed') AS completed_trades,
            (SELECT COALESCE(SUM(points), 0) FROM sustainability_points) AS points_awarded
        """
    )
    leaderboard = fetch_all(
        """
        SELECT rank_no, name, branch, total_points
        FROM v_leaderboard
        ORDER BY rank_no, name
        LIMIT 5
        """
    )
    overdue = fetch_all(
        """
        SELECT item_name, borrower_name, due_date, days_overdue
        FROM v_overdue_loans
        ORDER BY days_overdue DESC
        LIMIT 4
        """
    )

    return render_template(
        "index.html",
        listings=listings,
        categories=categories,
        stats=stats,
        leaderboard=leaderboard,
        overdue=overdue,
        listing_labels=LISTING_LABELS,
        filters={
            "q": search,
            "category": category,
            "type": listing_type,
            "semester": semester_text,
            "max_price": max_price_text,
        },
    )


@app.errorhandler(Error)
def database_error(error):
    app.logger.exception("Database query failed", exc_info=error)
    return (
        render_template(
            "error.html",
            title="Database unavailable",
            message="The app could not read the ReUseNSUT database. Check that the project MySQL server is running, then refresh this page.",
        ),
        503,
    )


@app.errorhandler(400)
def bad_request(error):
    return (
        render_template(
            "error.html",
            title="Check your filters",
            message=error.description,
        ),
        400,
    )


@app.errorhandler(404)
def not_found(_error):
    return (
        render_template(
            "error.html",
            title="Page not found",
            message="That page does not exist.",
        ),
        404,
    )


if __name__ == "__main__":
    host = os.getenv("WEB_HOST", "127.0.0.1")
    port = int(os.getenv("WEB_PORT", "5000"))
    print(f"ReUseNSUT is running at http://{host}:{port}")
    app.run(host=host, port=port, debug=False)
