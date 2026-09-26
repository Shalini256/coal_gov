"""
Comprehensive Live QA Execution Script for Coal Governance Platform
Produces exact request/response data files, PostgreSQL verification dumps, and test logs.
"""

import os
import sys
import json
import time
import requests
import psycopg2
from dotenv import load_dotenv
from psycopg2 import sql
from psycopg2.extras import RealDictCursor

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(ROOT_DIR, "backend", ".env"))
load_dotenv(os.path.join(ROOT_DIR, ".env"))

BASE_URL = "http://localhost:8080/api"
AI_URL = "http://localhost:5000"
FRONTEND_URL = "http://localhost:8000"

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", ""),
    "dbname": os.getenv("DB_NAME", "coal_governance"),
    "autocommit": True,
    "cursor_factory": RealDictCursor
}

DATA_DIR = os.path.join("qa_evidence", "data")
DB_DIR = os.path.join("qa_evidence", "db")
SCREENSHOTS_DIR = os.path.join("qa_evidence", "screenshots")

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(DB_DIR, exist_ok=True)
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def reset_db():
    admin_config = {**DB_CONFIG, "dbname": "postgres"}
    conn = psycopg2.connect(**admin_config)
    with conn.cursor() as cur:
        cur.execute(sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(DB_CONFIG["dbname"])))
        cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(DB_CONFIG["dbname"])))
    conn.close()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            for path in ("database/schema.sql", "database/seed.sql"):
                with open(path, "r", encoding="utf-8") as sql_file:
                    cur.execute(sql_file.read())
    finally:
        conn.close()

def save_evidence(test_id, req_data, res_data, db_data=None):
    # Save HTTP request & response
    data_file = os.path.join(DATA_DIR, f"{test_id}.json")
    with open(data_file, "w", encoding="utf-8") as f:
        json.dump({
            "test_id": test_id,
            "request": req_data,
            "response": res_data
        }, f, indent=2, default=str)
    
    # Save DB dump if provided
    if db_data is not None:
        db_file = os.path.join(DB_DIR, f"{test_id}_db.json")
        with open(db_file, "w", encoding="utf-8") as f:
            json.dump(db_data, f, indent=2, default=str)
    
    print(f"[{test_id}] Evidence saved: {data_file}")

def query_db(query, args=None):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(query, args or ())
            return cur.fetchall()
    finally:
        conn.close()

def login(email, password="Coal@2026"):
    r = requests.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    if r.status_code == 200:
        data = r.json()
        token = data.get("data", {}).get("token")
        return token, r
    return None, r

def auth_headers(token):
    return {"Authorization": f"Bearer {token}"}

print("QA Runner initialized successfully.")
