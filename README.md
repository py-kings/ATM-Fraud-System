# SecureATM - ATM Transaction Management & Fraud Detection System

A small, interview-ready banking mini-project that demonstrates
**database-first design**: MySQL owns every business rule (balance
checks, transfers, fraud scoring, fraud logging), and Flask is used
strictly as a thin presentation layer that renders pages and calls
stored procedures.

Built for a 5-10 minute walkthrough - the whole story is "the database
IS the business logic."

---

## 1. Why this project is designed the way it is

Most student CRUD projects put all logic in the application (Python/
Java) and use the database as a dumb data store. This project inverts
that on purpose, because it's what interviewers for DB/Data roles want
to see:

| Concern                          | Where it lives           |
|-----------------------------------|---------------------------|
| Withdraw / Deposit / Transfer rules | MySQL stored procedures |
| Balance lookups                   | MySQL function `GetBalance()` |
| Fraud risk scoring                | MySQL function `CalculateRisk()` |
| Automatic risk stamping on every insert | Trigger `LogTransaction` |
| Automatic fraud logging           | Trigger `FraudDetection` |
| Fraud reporting / joins           | View `Fraud_Transactions` |
| Rendering pages, forms, charts    | Flask + Jinja2 (this is ALL Flask does) |

Flask never runs `UPDATE Account SET balance = ...` and never decides
if a transaction is fraudulent - it only calls `CALL WithdrawMoney(...)`
and later reads back what MySQL already computed.

---

## 2. Database design

**5 Tables**
- `Customer` - KYC info
- `Account` - balance, daily withdrawal limit, status
- `ATM` - terminal metadata
- `Transaction` - every withdraw/deposit/transfer, plus `risk_score`
  and `status` (set automatically by triggers, never by Flask)
- `Fraud_Log` - populated automatically when a transaction is flagged

**3 Stored Procedures**
- `WithdrawMoney(account_id, atm_id, amount)`
- `DepositMoney(account_id, atm_id, amount)`
- `TransferMoney(from_account_id, to_account_id, atm_id, amount)`

Each one: locks the account row (`FOR UPDATE`), validates status/
balance, updates `Account`, and inserts into `Transaction`. Errors
(insufficient balance, blocked account, etc.) are raised with
`SIGNAL SQLSTATE '45000'` and surface in Flask as a friendly flash
message.

**2 Functions**
- `GetBalance(account_id)` - returns current balance
- `CalculateRisk(account_id, amount, transaction_type)` - returns a
  0-100 fraud score based on three rules (large amount, high
  velocity, daily-limit breach) - see the in-app **About** page for
  the exact point breakdown.

**2 Triggers**
- `LogTransaction` (`BEFORE INSERT` on `Transaction`) - calls
  `CalculateRisk()` and stamps `risk_score` + `status`
- `FraudDetection` (`AFTER INSERT` on `Transaction`) - if the score is
  >= 70, inserts a row into `Fraud_Log`

**1 View**
- `Fraud_Transactions` - joins `Fraud_Log` + `Transaction` + `Account`
  + `Customer` + `ATM` into one reporting row. The Fraud Log page runs
  a single `SELECT * FROM Fraud_Transactions`.

**Indexing**
- `Transaction(account_id, created_at)` - supports the velocity check
  inside `CalculateRisk()` and account-history lookups
- `Transaction(transaction_type, created_at)` - supports dashboard
  aggregation
- Unique indexes on `Customer.email`, `Account.account_number`,
  `ATM.atm_code`, `Fraud_Log.transaction_id`

---

## 3. Pages

| Page          | Route          | What it shows |
|---------------|----------------|----------------|
| Dashboard     | `/dashboard`   | KPI cards, 7-day transaction volume chart, transaction-type breakdown, recent activity table |
| Transaction   | `/transaction` | Form to withdraw / deposit / transfer, with live balance lookup via `GetBalance()` |
| Fraud Log     | `/fraud-log`   | Reads `Fraud_Transactions` view, with a summary strip |
| About         | `/about`       | Architecture explanation, tech stack, fraud rule breakdown - useful cheat-sheet during your demo |

---

## 4. Project structure

```
atm-fraud-system/
├── app.py                  # Flask routes (presentation layer only)
├── config.py                # Env-based configuration
├── db.py                    # Connection pool + query/procedure helpers
├── requirements.txt
├── .env.example              # Copy to .env and fill in DB credentials
├── sql/
│   ├── 01_schema.sql          # 5 tables, keys, indexes
│   ├── 02_functions.sql       # GetBalance, CalculateRisk
│   ├── 03_procedures.sql      # WithdrawMoney, DepositMoney, TransferMoney
│   ├── 04_triggers.sql        # LogTransaction, FraudDetection
│   ├── 05_views.sql           # Fraud_Transactions
│   └── 06_seed_data.sql       # Demo customers/accounts/ATMs/transactions
├── static/
│   ├── css/style.css          # Design system (banking navy/white/gray palette)
│   └── js/main.js             # Shared JS (alert auto-dismiss)
└── templates/
    ├── base.html               # Sidebar layout shared by all pages
    ├── dashboard.html
    ├── transaction.html
    ├── fraud_log.html
    └── about.html
```

---

## 5. Setup instructions

### Prerequisites
- Python 3.10+
- MySQL 8.0+ running locally (or reachable over network)

### Step 1 - Create a virtual environment and install dependencies
```bash
cd atm-fraud-system
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Step 2 - Configure environment variables
```bash
cp .env.example .env
# then edit .env with your MySQL host/user/password
```

### Step 3 - Build the database (run in this exact order)
```bash
mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_functions.sql
mysql -u root -p < sql/03_procedures.sql
mysql -u root -p < sql/04_triggers.sql
mysql -u root -p < sql/05_views.sql
mysql -u root -p < sql/06_seed_data.sql
```

> **Note:** if step 2 fails with error 1418 ("This function has none
> of DETERMINISTIC..."), your server has binary logging enabled. Fix
> it once with:
> ```sql
> SET GLOBAL log_bin_trust_function_creators = 1;
> ```

### Step 4 - Run the app
```bash
python app.py
```
Visit **http://localhost:5000** - it redirects straight to the Dashboard.

---

## 6. Suggested demo script (5-10 minutes)

1. **Dashboard** - "Here's a live view of the bank: KPIs, transaction
   volume, and recent activity, all read from MySQL."
2. **Transaction page** - Submit a normal withdrawal (e.g. Rs. 2,000)
   -> show it succeeds and appears on the dashboard. Then submit a
   large withdrawal that exceeds an account's daily limit (e.g. Rs.
   55,000 from account `ACC1000004`, limit Rs. 25,000) -> point out it
   still succeeds (funds move) but gets `status = FLAGGED`.
3. **Fraud Log** - Show the same transaction now sitting in the
   `Fraud_Transactions` view with its risk score and reason -
   generated with **zero Flask code**.
4. **About page** - Walk through the architecture table and the 3
   fraud rules while explaining that Flask only ever calls stored
   procedures, never writes to `Account`/`Transaction` directly.
5. If asked "why put logic in the database instead of Python?" -
   answer: enforced consistency across every client that touches the
   data (not just this Flask app), atomic locking via `FOR UPDATE`,
   and fraud detection that cannot be bypassed by any application bug.

---

## 7. Notes on the fraud scoring rules

| Rule | Condition | Points |
|------|-----------|--------|
| Large amount | amount > Rs. 50,000 | +40 |
| Large amount (moderate) | amount > Rs. 20,000 | +20 |
| High velocity | 3+ transactions on the same account in the last 10 minutes | +30 |
| Limit breach | withdrawal amount exceeds the account's `daily_withdrawal_limit` | +30 |

Score is capped at 100. A transaction is `FLAGGED` and copied into
`Fraud_Log` when its score is **>= 70**. These rules were chosen to be
simple, explainable in an interview, and easy to trigger live during a
demo - not a production-grade fraud model.
