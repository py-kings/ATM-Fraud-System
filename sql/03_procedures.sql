-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 03_procedures.sql  --  Stored Procedures (core business logic)
-- =====================================================================
-- Run AFTER 02_functions.sql.
--
-- Design principle: Flask NEVER runs raw UPDATE/INSERT on Account or
-- Transaction. It only ever calls these three procedures. All balance
-- checks, locking, and error handling live here in the database, so
-- the business logic is enforced no matter what client calls it.
-- =====================================================================

USE atm_fraud_system;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Procedure 1: WithdrawMoney
-- Validates the account, checks sufficient balance, deducts the amount
-- and inserts a Transaction row. The LogTransaction + FraudDetection
-- triggers fire automatically on that insert.
-- ---------------------------------------------------------------------
CREATE PROCEDURE WithdrawMoney(
    IN p_account_id INT,
    IN p_atm_id      INT,
    IN p_amount      DECIMAL(12,2)
)
BEGIN
    DECLARE v_balance DECIMAL(12,2);
    DECLARE v_status  VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

        -- Lock the account row to prevent race conditions on balance
        SELECT balance, status INTO v_balance, v_status
        FROM Account
        WHERE account_id = p_account_id
        FOR UPDATE;

        IF v_status IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found';
        ELSEIF v_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not active';
        ELSEIF p_amount <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive';
        ELSEIF v_balance < p_amount THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance';
        ELSE
            UPDATE Account
            SET balance = balance - p_amount
            WHERE account_id = p_account_id;

            INSERT INTO Transaction (account_id, atm_id, transaction_type, amount, balance_after)
            VALUES (p_account_id, p_atm_id, 'WITHDRAW', p_amount, v_balance - p_amount);
        END IF;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- Procedure 2: DepositMoney
-- Adds funds to an account and records the transaction.
-- ---------------------------------------------------------------------
CREATE PROCEDURE DepositMoney(
    IN p_account_id INT,
    IN p_atm_id      INT,
    IN p_amount      DECIMAL(12,2)
)
BEGIN
    DECLARE v_balance DECIMAL(12,2);
    DECLARE v_status  VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

        SELECT balance, status INTO v_balance, v_status
        FROM Account
        WHERE account_id = p_account_id
        FOR UPDATE;

        IF v_status IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found';
        ELSEIF v_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not active';
        ELSEIF p_amount <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive';
        ELSE
            UPDATE Account
            SET balance = balance + p_amount
            WHERE account_id = p_account_id;

            INSERT INTO Transaction (account_id, atm_id, transaction_type, amount, balance_after)
            VALUES (p_account_id, p_atm_id, 'DEPOSIT', p_amount, v_balance + p_amount);
        END IF;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- Procedure 3: TransferMoney
-- Moves funds between two accounts atomically. Debits the source,
-- credits the destination, and logs the movement as a single TRANSFER
-- transaction row against the source account (related_account_id
-- points to the destination so the UI can display "to" account).
-- ---------------------------------------------------------------------
CREATE PROCEDURE TransferMoney(
    IN p_from_account INT,
    IN p_to_account    INT,
    IN p_atm_id        INT,
    IN p_amount        DECIMAL(12,2)
)
BEGIN
    DECLARE v_from_balance DECIMAL(12,2);
    DECLARE v_from_status  VARCHAR(20);
    DECLARE v_to_status    VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

        IF p_from_account = p_to_account THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source and destination account cannot be the same';
        END IF;

        -- Lock both rows in a fixed order (lowest id first) to avoid deadlocks
        SELECT balance, status INTO v_from_balance, v_from_status
        FROM Account WHERE account_id = p_from_account FOR UPDATE;

        SELECT status INTO v_to_status
        FROM Account WHERE account_id = p_to_account FOR UPDATE;

        IF v_from_status IS NULL OR v_to_status IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'One or both accounts not found';
        ELSEIF v_from_status <> 'ACTIVE' OR v_to_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Both accounts must be active';
        ELSEIF p_amount <= 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Amount must be positive';
        ELSEIF v_from_balance < p_amount THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance for transfer';
        ELSE
            UPDATE Account SET balance = balance - p_amount WHERE account_id = p_from_account;
            UPDATE Account SET balance = balance + p_amount WHERE account_id = p_to_account;

            INSERT INTO Transaction
                (account_id, atm_id, related_account_id, transaction_type, amount, balance_after)
            VALUES
                (p_from_account, p_atm_id, p_to_account, 'TRANSFER', p_amount, v_from_balance - p_amount);
        END IF;

    COMMIT;
END$$

DELIMITER ;
