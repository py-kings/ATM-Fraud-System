"""
app.py
------
Flask presentation layer for the ATM Transaction Management & Fraud
Detection System.

IMPORTANT DESIGN NOTE (this is the whole point of the project):
    This file never runs a raw UPDATE/INSERT against Account or
    Transaction, and it never decides whether a transaction is
    fraudulent. Every money-movement action goes through one of the
    three stored procedures (WithdrawMoney / DepositMoney /
    TransferMoney), and fraud scoring + logging happens automatically
    inside MySQL via the LogTransaction and FraudDetection triggers.
    Flask only reads data back and renders it.
"""

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from mysql.connector import Error as MySQLError

from config import Config
import db

app = Flask(__name__)
app.config.from_object(Config)


# =====================================================================
# Helper: reference data shared by multiple pages (dropdown options)
# =====================================================================
def get_accounts():
    return db.run_query(
        """
        SELECT a.account_id, a.account_number, a.balance, a.status,
               CONCAT(c.first_name, ' ', c.last_name) AS customer_name
        FROM Account a
        JOIN Customer c ON a.customer_id = c.customer_id
        ORDER BY a.account_number
        """
    )


def get_atms():
    return db.run_query(
        "SELECT atm_id, atm_code, location, city FROM ATM WHERE status = 'ACTIVE' ORDER BY atm_code"
    )


# =====================================================================
# Route: Home -> Dashboard
# =====================================================================
@app.route("/")
def index():
    return redirect(url_for("dashboard"))


# =====================================================================
# Route: Dashboard
# KPI cards + charts + recent activity. All figures come from simple,
# indexed read queries -- no business logic is computed here.
# =====================================================================
@app.route("/dashboard")
def dashboard():
    kpis = db.run_query(
        """
        SELECT
            (SELECT COUNT(*) FROM Customer)                                   AS total_customers,
            (SELECT COUNT(*) FROM Account)                                    AS total_accounts,
            (SELECT COUNT(*) FROM Transaction)                                AS total_transactions,
            (SELECT COUNT(*) FROM Fraud_Log)                                  AS total_fraud_alerts,
            (SELECT IFNULL(SUM(balance), 0) FROM Account)                     AS total_bank_balance,
            (SELECT COUNT(*) FROM Transaction WHERE DATE(created_at) = CURDATE()) AS todays_transactions
        """,
        fetch_one=True,
    )

    recent_transactions = db.run_query(
        """
        SELECT t.transaction_id, t.transaction_type, t.amount, t.risk_score, t.status,
               t.created_at, a.account_number, CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
               atm.atm_code
        FROM Transaction t
        JOIN Account a  ON t.account_id = a.account_id
        JOIN Customer c ON a.customer_id = c.customer_id
        JOIN ATM atm    ON t.atm_id = atm.atm_id
        ORDER BY t.created_at DESC, t.transaction_id DESC
        LIMIT 8
        """
    )

    return render_template(
        "dashboard.html",
        active_page="dashboard",
        kpis=kpis,
        recent_transactions=recent_transactions,
    )


# =====================================================================
# API: Chart data for the dashboard (consumed by static/js/main.js)
# =====================================================================
@app.route("/api/chart-data")
def chart_data():

    atm_transactions = db.run_query(
        """
        SELECT
            atm.atm_code,
            COUNT(*) AS total
        FROM Transaction t
        JOIN ATM atm ON t.atm_id = atm.atm_id
        GROUP BY atm.atm_code
        ORDER BY total DESC
        """
    )

    return jsonify(
        {
            "atm_labels": [row["atm_code"] for row in atm_transactions],
            "atm_values": [row["total"] for row in atm_transactions]
        }
    )

# =====================================================================
# API: live balance lookup, used by the Transaction page via AJAX.
# Demonstrates the GetBalance() SQL function being called from Flask.
# =====================================================================
@app.route("/api/balance/<int:account_id>")
def api_balance(account_id):
    balance = db.call_function("GetBalance", [account_id])
    return jsonify({"account_id": account_id, "balance": float(balance) if balance is not None else None})


# =====================================================================
# Route: Transaction page
# GET  -> show the form
# POST -> call the appropriate stored procedure (Withdraw / Deposit / Transfer)
# =====================================================================
@app.route("/transaction", methods=["GET", "POST"])
def transaction():
    if request.method == "POST":
        txn_type = request.form.get("transaction_type")
        account_id = request.form.get("account_id", type=int)
        atm_id = request.form.get("atm_id", type=int)
        amount = request.form.get("amount", type=float)
        target_account_id = request.form.get("target_account_id", type=int)

        try:
            if not account_id or not atm_id or not amount:
                flash("Please fill in all required fields.", "danger")
            elif txn_type == "WITHDRAW":
                db.call_procedure("WithdrawMoney", [account_id, atm_id, amount])
                flash(f"Withdrawal of Rs. {amount:,.2f} completed successfully.", "success")
            elif txn_type == "DEPOSIT":
                db.call_procedure("DepositMoney", [account_id, atm_id, amount])
                flash(f"Deposit of Rs. {amount:,.2f} completed successfully.", "success")
            elif txn_type == "TRANSFER":
                if not target_account_id:
                    flash("Please select a destination account for the transfer.", "danger")
                else:
                    db.call_procedure(
                        "TransferMoney", [account_id, target_account_id, atm_id, amount]
                    )
                    flash(f"Transfer of Rs. {amount:,.2f} completed successfully.", "success")
            else:
                flash("Unknown transaction type.", "danger")

        except MySQLError as err:
            # Business-rule violations (insufficient balance, blocked
            # account, etc.) are raised inside MySQL via SIGNAL and
            # surface here as err.msg -- Flask just relays the message.
            flash(f"Transaction failed: {err.msg}", "danger")

        return redirect(url_for("transaction"))

    # GET request: render the form
    return render_template(
        "transaction.html",
        active_page="transaction",
        accounts=get_accounts(),
        atms=get_atms(),
    )


# =====================================================================
# Route: Fraud Log page
# A single SELECT against the Fraud_Transactions VIEW -- all the
# joins and ordering logic live inside the database.
# =====================================================================
@app.route("/fraud-log")
def fraud_log():
    fraud_records = db.run_query("SELECT * FROM Fraud_Transactions")

    summary = db.run_query(
        """
        SELECT
            COUNT(*)                                   AS total_alerts,
            IFNULL(AVG(risk_score), 0)                 AS avg_risk_score,
            IFNULL(MAX(risk_score), 0)                 AS max_risk_score,
            COUNT(DISTINCT account_number)              AS accounts_affected
        FROM Fraud_Transactions
        """,
        fetch_one=True,
    )

    return render_template(
        "fraud_log.html",
        active_page="fraud_log",
        fraud_records=fraud_records,
        summary=summary,
    )


# =====================================================================
# Route: About page (static project/architecture info)
# =====================================================================
@app.route("/about")
def about():
    return render_template("about.html", active_page="about")


if __name__ == "__main__":
    app.run(debug=Config.DEBUG, host="0.0.0.0", port=5000)
