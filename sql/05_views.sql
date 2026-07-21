-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 05_views.sql  --  Reporting View
-- =====================================================================
-- Run AFTER 04_triggers.sql.
--
-- The Fraud Log page in Flask runs a single "SELECT * FROM
-- Fraud_Transactions" -- no JOINs written in Python. All reporting
-- logic and column shaping lives in the database.
-- =====================================================================

USE atm_fraud_system;

CREATE OR REPLACE VIEW Fraud_Transactions AS
SELECT
    f.fraud_id,
    f.flagged_at,
    t.transaction_id,
    t.transaction_type,
    t.amount,
    t.risk_score,
    f.reason,
    a.account_number,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.email,
    atm.atm_code,
    atm.location AS atm_location,
    atm.city     AS atm_city
FROM Fraud_Log f
JOIN Transaction t ON f.transaction_id = t.transaction_id
JOIN Account a      ON t.account_id    = a.account_id
JOIN Customer c      ON a.customer_id  = c.customer_id
JOIN ATM atm         ON t.atm_id       = atm.atm_id
ORDER BY f.flagged_at DESC;
