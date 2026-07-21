"""
config.py
---------
Centralised configuration for the Flask app. All values are read from
environment variables (via a local .env file) so credentials never sit
directly in source code.
"""

import os
from dotenv import load_dotenv

# Load variables from a .env file in the project root, if present
load_dotenv()


class Config:
    """Application-wide configuration."""

    # --- MySQL connection settings -----------------------------------
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_PORT = int(os.getenv("DB_PORT", 3306))
    DB_USER = os.getenv("DB_USER", "root")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_NAME = os.getenv("DB_NAME", "atm_fraud_system")

    # --- Flask settings -------------------------------------------------
    SECRET_KEY = os.getenv("FLASK_SECRET_KEY", "dev-secret-key")
    DEBUG = os.getenv("FLASK_DEBUG", "True") == "True"

    # --- Fraud engine display threshold ---------------------------------
    # Must match the threshold used inside the LogTransaction /
    # FraudDetection triggers (sql/04_triggers.sql). Kept here only for
    # UI coloring (e.g. "high risk" badge), never for actual fraud logic.
    RISK_FLAG_THRESHOLD = 70
