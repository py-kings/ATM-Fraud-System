-- =====================================================================
-- ATM Transaction Management & Fraud Detection System
-- 01_schema.sql  --  Database & Table Definitions
-- =====================================================================
-- Run this file FIRST. It creates the database and all 5 core tables
-- with proper primary keys, foreign keys, constraints and indexes.
-- =====================================================================

DROP DATABASE IF EXISTS atm_fraud_system;
CREATE DATABASE atm_fraud_system;
USE atm_fraud_system;

-- ---------------------------------------------------------------------
-- Table 1: Customer
-- Stores basic KYC information for every bank customer.
-- ---------------------------------------------------------------------
CREATE TABLE Customer (
    customer_id     INT AUTO_INCREMENT PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(100) NOT NULL UNIQUE,
    phone           VARCHAR(15)  NOT NULL,
    dob             DATE         NOT NULL,
    address         VARCHAR(255),
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Table 2: Account
-- Each customer can hold one or more bank accounts.
-- ---------------------------------------------------------------------
CREATE TABLE Account (
    account_id              INT AUTO_INCREMENT PRIMARY KEY,
    customer_id             INT NOT NULL,
    account_number          VARCHAR(20) NOT NULL UNIQUE,
    account_type            ENUM('SAVINGS', 'CURRENT') DEFAULT 'SAVINGS',
    balance                 DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    daily_withdrawal_limit  DECIMAL(12,2) NOT NULL DEFAULT 50000.00,
    status                  ENUM('ACTIVE', 'BLOCKED', 'CLOSED') DEFAULT 'ACTIVE',
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_account_customer
        FOREIGN KEY (customer_id) REFERENCES Customer(customer_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_balance_non_negative CHECK (balance >= 0)
) ENGINE=InnoDB;

CREATE INDEX idx_account_customer ON Account(customer_id);

-- ---------------------------------------------------------------------
-- Table 3: ATM
-- Physical / virtual ATM terminals used to originate transactions.
-- ---------------------------------------------------------------------
CREATE TABLE ATM (
    atm_id      INT AUTO_INCREMENT PRIMARY KEY,
    atm_code    VARCHAR(20) NOT NULL UNIQUE,
    location    VARCHAR(150) NOT NULL,
    city        VARCHAR(50)  NOT NULL,
    status      ENUM('ACTIVE', 'MAINTENANCE', 'OFFLINE') DEFAULT 'ACTIVE'
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Table 4: Transaction
-- Every withdrawal / deposit / transfer is recorded here.
-- risk_score and status are populated automatically by the
-- LogTransaction trigger (see 04_triggers.sql) -- Flask never sets them.
-- ---------------------------------------------------------------------
CREATE TABLE Transaction (
    transaction_id      INT AUTO_INCREMENT PRIMARY KEY,
    account_id           INT NOT NULL,
    atm_id                INT NOT NULL,
    related_account_id   INT DEFAULT NULL,          -- used only for TRANSFER
    transaction_type     ENUM('WITHDRAW', 'DEPOSIT', 'TRANSFER') NOT NULL,
    amount                DECIMAL(12,2) NOT NULL,
    balance_after         DECIMAL(12,2) NOT NULL,
    risk_score            INT NOT NULL DEFAULT 0,    -- set by trigger via CalculateRisk()
    status                ENUM('SUCCESS', 'FLAGGED') DEFAULT 'SUCCESS',
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_txn_account
        FOREIGN KEY (account_id) REFERENCES Account(account_id),
    CONSTRAINT fk_txn_atm
        FOREIGN KEY (atm_id) REFERENCES ATM(atm_id),
    CONSTRAINT fk_txn_related_account
        FOREIGN KEY (related_account_id) REFERENCES Account(account_id),
    CONSTRAINT chk_amount_positive CHECK (amount > 0)
) ENGINE=InnoDB;

-- Composite index: fraud-velocity checks filter by account + time window,
-- and the dashboard/reporting pages filter by date. This index serves both.
CREATE INDEX idx_txn_account_created ON Transaction(account_id, created_at);
CREATE INDEX idx_txn_type_created    ON Transaction(transaction_type, created_at);

-- ---------------------------------------------------------------------
-- Table 5: Fraud_Log
-- Populated automatically by the FraudDetection trigger whenever a
-- transaction crosses the risk threshold. Never written to by Flask.
-- ---------------------------------------------------------------------
CREATE TABLE Fraud_Log (
    fraud_id        INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id  INT NOT NULL UNIQUE,
    account_id      INT NOT NULL,
    risk_score      INT NOT NULL,
    reason          VARCHAR(255) NOT NULL,
    flagged_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fraud_txn
        FOREIGN KEY (transaction_id) REFERENCES Transaction(transaction_id),
    CONSTRAINT fk_fraud_account
        FOREIGN KEY (account_id) REFERENCES Account(account_id)
) ENGINE=InnoDB;

CREATE INDEX idx_fraud_flagged_at ON Fraud_Log(flagged_at);
