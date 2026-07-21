-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 02_functions.sql  --  Reusable SQL Functions
-- =====================================================================
-- Run AFTER 01_schema.sql.
--
-- NOTE: If your MySQL server has binary logging enabled, function
-- creation may be blocked with error 1418. Fix by running once as admin:
--     SET GLOBAL log_bin_trust_function_creators = 1;
-- =====================================================================

USE atm_fraud_system;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Function 1: GetBalance
-- Returns the current balance of an account. Used by Flask for
-- read-only balance checks (never used to mutate data).
-- ---------------------------------------------------------------------
CREATE FUNCTION GetBalance(p_account_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_balance DECIMAL(12,2) DEFAULT 0.00;

    SELECT balance INTO v_balance
    FROM Account
    WHERE account_id = p_account_id;

    RETURN IFNULL(v_balance, 0.00);
END$$

-- ---------------------------------------------------------------------
-- Function 2: CalculateRisk
-- Core fraud-scoring logic. Called automatically by the LogTransaction
-- trigger for every new transaction row (Flask never calls this
-- directly). Returns a score from 0 (safe) to 100 (highly suspicious)
-- based on three simple, explainable rules:
--   Rule A - Large amount            : bigger amount -> higher score
--   Rule B - Velocity check          : too many transactions in a
--                                       short time window -> +30
--   Rule C - Daily withdrawal limit  : withdrawal above the account's
--                                       configured limit -> +30
-- ---------------------------------------------------------------------
CREATE FUNCTION CalculateRisk(
    p_account_id      INT,
    p_amount          DECIMAL(12,2),
    p_transaction_type VARCHAR(20)
)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_score          INT DEFAULT 0;
    DECLARE v_recent_count   INT DEFAULT 0;
    DECLARE v_daily_limit    DECIMAL(12,2) DEFAULT 0.00;

    -- Rule A: Large single transaction amount
    IF p_amount > 50000 THEN
        SET v_score = v_score + 40;
    ELSEIF p_amount > 20000 THEN
        SET v_score = v_score + 20;
    END IF;

    -- Rule B: Velocity check - 3 or more transactions on the same
    -- account within the last 10 minutes is unusual ATM behaviour
    SELECT COUNT(*) INTO v_recent_count
    FROM Transaction
    WHERE account_id = p_account_id
      AND created_at >= (NOW() - INTERVAL 10 MINUTE);

    IF v_recent_count >= 3 THEN
        SET v_score = v_score + 30;
    END IF;

    -- Rule C: Withdrawal exceeding the account's own daily limit
    IF p_transaction_type = 'WITHDRAW' THEN
        SELECT daily_withdrawal_limit INTO v_daily_limit
        FROM Account
        WHERE account_id = p_account_id;

        IF p_amount > v_daily_limit THEN
            SET v_score = v_score + 30;
        END IF;
    END IF;

    -- Cap the score at 100
    IF v_score > 100 THEN
        SET v_score = 100;
    END IF;

    RETURN v_score;
END$$

DELIMITER ;
