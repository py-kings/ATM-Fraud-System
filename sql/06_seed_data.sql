-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 06_seed_data.sql  --  Sample / Demo Data
-- =====================================================================
-- Run LAST, after schema, functions, procedures, triggers and views
-- all exist. This populates enough data to make the dashboard, charts
-- and fraud log look realistic in a live demo.
-- =====================================================================

USE atm_fraud_system;

-- ---------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------
INSERT INTO Customer (first_name, last_name, email, phone, dob, address) VALUES
('Aarav',   'Sharma',   'aarav.sharma@example.com',   '9820011122', '1990-04-12', 'Kothrud, Pune'),
('Isha',    'Patil',    'isha.patil@example.com',     '9820033344', '1988-11-02', 'Baner, Pune'),
('Rohan',   'Verma',    'rohan.verma@example.com',    '9820055566', '1995-07-23', 'Andheri, Mumbai'),
('Sneha',   'Kulkarni', 'sneha.kulkarni@example.com', '9820077788', '1993-01-30', 'Viman Nagar, Pune'),
('Karan',   'Mehta',    'karan.mehta@example.com',    '9820099900', '1985-09-15', 'Bandra, Mumbai'),
('Priya',   'Nair',     'priya.nair@example.com',     '9820011234', '1998-03-08', 'Hinjewadi, Pune');

-- ---------------------------------------------------------------------
-- Accounts (one primary account each; a couple of customers hold two)
-- ---------------------------------------------------------------------
INSERT INTO Account (customer_id, account_number, account_type, balance, daily_withdrawal_limit) VALUES
(1, 'ACC1000001', 'SAVINGS', 85000.00, 50000.00),
(2, 'ACC1000002', 'SAVINGS', 42000.00, 25000.00),
(3, 'ACC1000003', 'CURRENT', 250000.00, 100000.00),
(4, 'ACC1000004', 'SAVINGS', 60000.00, 25000.00),
(5, 'ACC1000005', 'CURRENT', 500000.00, 150000.00),
(6, 'ACC1000006', 'SAVINGS', 30000.00, 25000.00);

-- ---------------------------------------------------------------------
-- ATMs
-- ---------------------------------------------------------------------
INSERT INTO ATM (atm_code, location, city, status) VALUES
('ATM-PUN-01', 'FC Road Branch',       'Pune',   'ACTIVE'),
('ATM-PUN-02', 'Hinjewadi Phase 1',    'Pune',   'ACTIVE'),
('ATM-MUM-01', 'Andheri West',         'Mumbai', 'ACTIVE'),
('ATM-MUM-02', 'Bandra Kurla Complex', 'Mumbai', 'ACTIVE');

-- ---------------------------------------------------------------------
-- Sample transactions, routed through the stored procedures so that
-- the LogTransaction / FraudDetection triggers run exactly as they
-- would in production. Some are intentionally large or rapid-fire to
-- demonstrate the fraud engine catching them.
-- ---------------------------------------------------------------------

-- Normal, everyday activity
CALL WithdrawMoney(1, 1, 2000.00);
CALL DepositMoney(2, 2, 5000.00);
CALL WithdrawMoney(3, 3, 10000.00);
CALL DepositMoney(4, 1, 3000.00);
CALL TransferMoney(5, 6, 4, 7500.00);
CALL WithdrawMoney(2, 2, 1500.00);
CALL DepositMoney(6, 2, 2000.00);
CALL WithdrawMoney(4, 1, 1000.00);

-- High-value withdrawal beyond the account's daily limit -> FLAGS
-- (amount > 50000 gives +40, and it exceeds the 25000 daily limit gives +30 => 70)
CALL WithdrawMoney(4, 1, 55000.00);

-- Very large single withdrawal beyond the account's daily limit -> FLAGS
-- (amount > 50000 gives +40, and it exceeds the 150000 daily limit gives +30 => 70)
CALL WithdrawMoney(5, 4, 160000.00);

-- Rapid-fire small withdrawals on the same account (velocity rule) -> 3rd+ flags
CALL WithdrawMoney(2, 2, 500.00);
CALL WithdrawMoney(2, 2, 600.00);
CALL WithdrawMoney(2, 2, 700.00);

-- Large transfer that exceeds threshold on its own amount
CALL TransferMoney(3, 1, 3, 60000.00);
