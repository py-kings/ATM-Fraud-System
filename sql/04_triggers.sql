-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 04_triggers.sql  --  Triggers
-- =====================================================================
-- Run AFTER 03_procedures.sql.
--
-- These two triggers are the heart of the fraud detection system.
-- Together they mean fraud detection happens automatically for EVERY
-- transaction, from EVERY source (Flask app, another app, even a
-- manual INSERT run by a DBA) -- the logic cannot be bypassed.
-- =====================================================================

USE atm_fraud_system;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Trigger 1: LogTransaction
-- Fires BEFORE every INSERT on Transaction. Calculates the risk score
-- for the incoming transaction using CalculateRisk() and stamps the
-- row's status as FLAGGED if the score crosses the risk threshold.
-- This guarantees risk_score is never missing or client-supplied.
-- ---------------------------------------------------------------------
CREATE TRIGGER LogTransaction
BEFORE INSERT ON Transaction
FOR EACH ROW
BEGIN
    SET NEW.risk_score = CalculateRisk(NEW.account_id, NEW.amount, NEW.transaction_type);

    IF NEW.risk_score >= 70 THEN
        SET NEW.status = 'FLAGGED';
    ELSE
        SET NEW.status = 'SUCCESS';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- Trigger 2: FraudDetection
-- Fires AFTER every INSERT on Transaction. If the row that was just
-- written was flagged (risk_score >= 70) it is automatically copied
-- into Fraud_Log with a human-readable reason, so the Fraud Log page
-- and Fraud_Transactions view populate themselves with zero Flask code.
-- ---------------------------------------------------------------------
CREATE TRIGGER FraudDetection
AFTER INSERT ON Transaction
FOR EACH ROW
BEGIN
    IF NEW.risk_score >= 70 THEN
        INSERT INTO Fraud_Log (transaction_id, account_id, risk_score, reason)
        VALUES (
            NEW.transaction_id,
            NEW.account_id,
            NEW.risk_score,
            CONCAT(
                'High-risk ', NEW.transaction_type,
                ' of amount ', NEW.amount,
                ' scored ', NEW.risk_score, '/100'
            )
        );
    END IF;
END$$

DELIMITER ;
