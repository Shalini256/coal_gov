-- =====================================================================
-- AI-Based Smart Governance and Compliance Monitoring System
-- Coal India Limited / Ministry of Coal - SIH 2026 (SIH26024)
-- PostgreSQL database schema
-- =====================================================================

-- 1. ROLES
CREATE TABLE roles (
    id            SERIAL PRIMARY KEY,
    role_key      VARCHAR(50) NOT NULL UNIQUE,
    role_name     VARCHAR(100) NOT NULL,
    description   VARCHAR(255),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- 2. SUBSIDIARIES
CREATE TABLE subsidiaries (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(150) NOT NULL,
    code          VARCHAR(20) NOT NULL UNIQUE,
    headquarters  VARCHAR(150),
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- 3. USERS
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    role_id         INT NOT NULL,
    subsidiary_id   INT NULL,
    phone           VARCHAR(20),
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED')),
    last_login_at   TIMESTAMP NULL,
    created_by      INT NULL,
    updated_by      INT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (subsidiary_id) REFERENCES subsidiaries(id)
);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role_id);

-- 4. MINES
CREATE TABLE mines (
    id                  SERIAL PRIMARY KEY,
    mine_name           VARCHAR(150) NOT NULL,
    mine_code           VARCHAR(30) NOT NULL UNIQUE,
    subsidiary_id       INT NOT NULL,
    state               VARCHAR(100),
    district            VARCHAR(100),
    latitude            DECIMAL(10,6),
    longitude           DECIMAL(10,6),
    mine_type VARCHAR(50) DEFAULT 'OPENCAST' CHECK (mine_type IN ('OPENCAST','UNDERGROUND','MIXED')),
    production_capacity DECIMAL(12,2),
    manager_id          INT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','UNDER_MAINTENANCE')),
    created_by          INT NULL,
    updated_by          INT NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (subsidiary_id) REFERENCES subsidiaries(id),
    FOREIGN KEY (manager_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_mines_subsidiary ON mines (subsidiary_id);
CREATE INDEX IF NOT EXISTS idx_mines_status ON mines (status);

-- 5. MINE ZONES
CREATE TABLE mine_zones (
    id          SERIAL PRIMARY KEY,
    mine_id     INT NOT NULL,
    zone_name   VARCHAR(100) NOT NULL,
    zone_type   VARCHAR(100),
    latitude    DECIMAL(10,6),
    longitude   DECIMAL(10,6),
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE
);


-- 6. DEPARTMENTS
CREATE TABLE departments (
    id          SERIAL PRIMARY KEY,
    mine_id     INT NOT NULL,
    dept_name   VARCHAR(100) NOT NULL,
    dept_head_id INT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
    FOREIGN KEY (dept_head_id) REFERENCES users(id)
);


-- 7. WORKERS
CREATE TABLE workers (
    id              SERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    worker_code     VARCHAR(30) NOT NULL UNIQUE,
    full_name       VARCHAR(150) NOT NULL,
    designation     VARCHAR(100),
    department_id   INT NULL,
    contractor_id   INT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
    FOREIGN KEY (department_id) REFERENCES departments(id)
);


-- 8. CONTRACTORS
CREATE TABLE contractors (
    id              SERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    company_name    VARCHAR(150) NOT NULL,
    contact_person  VARCHAR(150),
    phone           VARCHAR(20),
    email           VARCHAR(150),
    contract_type   VARCHAR(100),
    contract_start  DATE,
    contract_end    DATE,
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','BLACKLISTED')),
    blacklist_reason TEXT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE
);


ALTER TABLE workers ADD FOREIGN KEY (contractor_id) REFERENCES contractors(id);

-- 9. COMPLIANCE CATEGORIES
CREATE TABLE compliance_categories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    description VARCHAR(255)
);


-- 10. COMPLIANCE RULES
CREATE TABLE compliance_rules (
    id                  SERIAL PRIMARY KEY,
    rule_code           VARCHAR(30) NOT NULL UNIQUE,
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    category_id         INT NOT NULL,
    applicable_mine_id  INT NULL,
    frequency VARCHAR(50) DEFAULT 'MONTHLY' CHECK (frequency IN ('DAILY','WEEKLY','MONTHLY','QUARTERLY','ANNUAL','ONE_TIME')),
    severity VARCHAR(50) DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    responsible_dept    VARCHAR(100),
    due_period_days     INT DEFAULT 30,
    status VARCHAR(50) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
    created_by          INT NULL,
    updated_by          INT NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES compliance_categories(id),
    FOREIGN KEY (applicable_mine_id) REFERENCES mines(id)
);


-- 11. INSPECTIONS
CREATE TABLE inspections (
    id                  SERIAL PRIMARY KEY,
    mine_id             INT NOT NULL,
    inspection_type     VARCHAR(100),
    inspector_id        INT NOT NULL,
    inspection_date     DATE NOT NULL,
    inspection_time     TIME,
    gps_latitude        DECIMAL(10,6),
    gps_longitude       DECIMAL(10,6),
    remarks             TEXT,
    status VARCHAR(50) DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','REVIEWED','APPROVED','VOIDED')),
    void_reason         VARCHAR(255) NULL,
    voided_by           INT NULL,
    voided_at           TIMESTAMP NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (inspector_id) REFERENCES users(id),
    FOREIGN KEY (voided_by) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_inspections_mine ON inspections (mine_id);
CREATE INDEX IF NOT EXISTS idx_inspections_date ON inspections (inspection_date);

-- 12. INSPECTION ITEMS
CREATE TABLE inspection_items (
    id              SERIAL PRIMARY KEY,
    inspection_id   INT NOT NULL,
    checklist_item  VARCHAR(255) NOT NULL,
    result VARCHAR(50) DEFAULT 'NA' CHECK (result IN ('PASS','FAIL','NA')),
    remarks         VARCHAR(255),
    FOREIGN KEY (inspection_id) REFERENCES inspections(id) ON DELETE CASCADE
);


-- 13. OBSERVATIONS
CREATE TABLE observations (
    id              SERIAL PRIMARY KEY,
    inspection_id   INT NOT NULL,
    category_id     INT NULL,
    observation     TEXT NULL,
    severity VARCHAR(50) DEFAULT 'LOW' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    evidence_path   VARCHAR(255),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inspection_id) REFERENCES inspections(id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES compliance_categories(id)
);


-- 14. VIOLATIONS
CREATE TABLE violations (
    id                  SERIAL PRIMARY KEY,
    violation_code      VARCHAR(30) NOT NULL UNIQUE,
    mine_id             INT NOT NULL,
    inspection_id       INT NULL,
    category_id         INT NOT NULL,
    description         TEXT NOT NULL,
    severity VARCHAR(50) DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    evidence_path       VARCHAR(255),
    reported_by         INT NOT NULL,
    responsible_person  INT NULL,
    deadline            DATE,
    status VARCHAR(50) DEFAULT 'OPEN' CHECK (status IN ('OPEN','IN_PROGRESS','RESOLVED','VERIFIED','CLOSED','OVERDUE','DISMISSED')),
    escalation_level    INT DEFAULT 1,
    sla_hours           INT DEFAULT 48,
    escalated_at        TIMESTAMP NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (inspection_id) REFERENCES inspections(id),
    FOREIGN KEY (category_id) REFERENCES compliance_categories(id),
    FOREIGN KEY (reported_by) REFERENCES users(id),
    FOREIGN KEY (responsible_person) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_violations_mine ON violations (mine_id);
CREATE INDEX IF NOT EXISTS idx_violations_status ON violations (status);

-- 15. CORRECTIVE ACTIONS
CREATE TABLE corrective_actions (
    id                      SERIAL PRIMARY KEY,
    violation_id            INT NOT NULL,
    assigned_to             INT NOT NULL,
    action_description      TEXT NOT NULL,
    deadline                DATE NOT NULL,
    submitted_at            TIMESTAMP NULL,
    verified_by             INT NULL,
    verified_at             TIMESTAMP NULL,
    escalation_level        INT DEFAULT 0,
    status VARCHAR(50) DEFAULT 'ASSIGNED' CHECK (status IN ('ASSIGNED','SUBMITTED','VERIFIED','CLOSED','OVERDUE')),
    evidence_photo_path     VARCHAR(255) NULL,
    resolution_gps_latitude  DECIMAL(10,6) NULL,
    resolution_gps_longitude DECIMAL(10,6) NULL,
    resolution_notes        TEXT NULL,
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (violation_id) REFERENCES violations(id),
    FOREIGN KEY (assigned_to) REFERENCES users(id),
    FOREIGN KEY (verified_by) REFERENCES users(id)
);


-- 16. INCIDENTS
CREATE TABLE incidents (
    id              SERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    incident_type   VARCHAR(100),
    description     TEXT,
    severity VARCHAR(50) DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    reported_by     INT NOT NULL,
    incident_date   TIMESTAMP NOT NULL,
    status VARCHAR(50) DEFAULT 'OPEN' CHECK (status IN ('OPEN','UNDER_REVIEW','CLOSED')),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (reported_by) REFERENCES users(id)
);


-- 17. OPERATIONAL DATA
CREATE TABLE operational_data (
    id                  BIGSERIAL PRIMARY KEY,
    mine_id             INT NOT NULL,
    record_date         DATE NOT NULL,
    production_tonnes   DECIMAL(12,2),
    expected_production DECIMAL(12,2),
    equipment_health_pct DECIMAL(5,2),
    attendance_pct      DECIMAL(5,2),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id)
);
CREATE INDEX IF NOT EXISTS idx_opdata_mine_date ON operational_data (mine_id, record_date);
CREATE UNIQUE INDEX IF NOT EXISTS uq_opdata_mine_record_date ON operational_data (mine_id, record_date);

-- 18. ENVIRONMENTAL DATA
CREATE TABLE environmental_data (
    id              BIGSERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    record_date     DATE NOT NULL,
    aqi             DECIMAL(6,2),
    water_quality_index DECIMAL(6,2),
    noise_level_db  DECIMAL(6,2),
    dust_level      DECIMAL(6,2),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_environmental_mine_record_date ON environmental_data (mine_id, record_date);


-- 19. ATTENDANCE
CREATE TABLE attendance (
    id                  BIGSERIAL PRIMARY KEY,
    mine_id             INT NOT NULL,
    worker_id           INT NULL,
    record_date         DATE NOT NULL,
    status VARCHAR(50) DEFAULT 'PRESENT' CHECK (status IN ('PRESENT','ABSENT','LEAVE','HALF_DAY')),
    shift               VARCHAR(20) DEFAULT 'GENERAL',
    overtime_hours      DECIMAL(4,2) DEFAULT 0.00,
    present_count       INT NULL,
    total_count         INT NULL,
    marked_by           INT NULL,
    checkin_lat         DECIMAL(10,6) NULL,
    checkin_lng         DECIMAL(10,6) NULL,
    distance_from_mine_m DECIMAL(8,2) NULL,
    is_mock_location    BOOLEAN DEFAULT FALSE,
    device_uptime_ms    BIGINT NULL,
    client_reported_time TIMESTAMP NULL,
    tamper_flag         BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (worker_id) REFERENCES workers(id),
    FOREIGN KEY (marked_by) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_attendance_mine_date ON attendance (mine_id, record_date);
CREATE INDEX IF NOT EXISTS idx_attendance_worker ON attendance (worker_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_mine_worker_date ON attendance (mine_id, worker_id, record_date);

-- 19b. ATTENDANCE CHECKIN EVENTS (Append-only telemetry log)
CREATE TABLE attendance_checkin_events (
    id                  BIGSERIAL PRIMARY KEY,
    mine_id             INT NOT NULL,
    worker_id           INT NOT NULL,
    lat                 DECIMAL(10,6) NOT NULL,
    lng                 DECIMAL(10,6) NOT NULL,
    distance_from_mine_m DECIMAL(8,2) NOT NULL,
    event_type VARCHAR(50) DEFAULT 'CHECKIN' CHECK (event_type IN ('CHECKIN','CHECKOUT')),
    is_mock_location    BOOLEAN DEFAULT FALSE,
    device_uptime_ms    BIGINT NULL,
    client_reported_time TIMESTAMP NULL,
    tamper_flag         BOOLEAN DEFAULT FALSE,
    liveness_passed     BOOLEAN DEFAULT TRUE,
    recorded_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
    FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_events_worker_time ON attendance_checkin_events (worker_id, recorded_at);
CREATE INDEX IF NOT EXISTS idx_events_mine_time ON attendance_checkin_events (mine_id, recorded_at);

-- 20. DOCUMENTS
CREATE TABLE documents (
    id                  SERIAL PRIMARY KEY,
    mine_id             INT NULL,
    contractor_id       INT NULL,
    document_type       VARCHAR(100),
    file_path           VARCHAR(255) NOT NULL,
    certificate_number  VARCHAR(100),
    issue_date          DATE,
    expiry_date         DATE,
    ocr_raw_text        TEXT,
    mine_code           VARCHAR(50) NULL,
    inspector_name      VARCHAR(100) NULL,
    inspection_date     DATE NULL,
    compliance_status   VARCHAR(50) DEFAULT 'COMPLIANT',
    violation_details   TEXT NULL,
    risk_level          VARCHAR(30) DEFAULT 'LOW',
    corrective_action   TEXT NULL,
    due_date            DATE NULL,
    regulatory_reference VARCHAR(255) NULL,
    ocr_data_json       JSON NULL,
    workflow_status     VARCHAR(50) DEFAULT 'PENDING_REVIEW',
    uploaded_by         INT NOT NULL,
    reviewed_by         INT NULL,
    reviewed_at         TIMESTAMP NULL,
    approved_by         INT NULL,
    approved_at         TIMESTAMP NULL,
    verified_by         INT NULL,
    verified_at         TIMESTAMP NULL,
    status VARCHAR(50) DEFAULT 'VALID' CHECK (status IN ('VALID','EXPIRING_SOON','EXPIRED')),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (contractor_id) REFERENCES contractors(id),
    FOREIGN KEY (uploaded_by) REFERENCES users(id),
    FOREIGN KEY (reviewed_by) REFERENCES users(id),
    FOREIGN KEY (approved_by) REFERENCES users(id),
    FOREIGN KEY (verified_by) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_documents_contractor ON documents (contractor_id);

-- 21. RISK SCORES
CREATE TABLE risk_scores (
    id              BIGSERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    score           DECIMAL(5,2) NOT NULL,
    classification VARCHAR(50) NOT NULL CHECK (classification IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    factors_json    JSON,
    computed_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id)
);
CREATE INDEX IF NOT EXISTS idx_risk_mine ON risk_scores (mine_id);

-- 22. ANOMALIES
CREATE TABLE anomalies (
    id              BIGSERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    worker_id       INT NULL,
    anomaly_type    VARCHAR(100),
    description     TEXT,
    detected_value  DECIMAL(12,2),
    expected_value  DECIMAL(12,2),
    severity VARCHAR(50) DEFAULT 'MEDIUM' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    status VARCHAR(50) DEFAULT 'NEW' CHECK (status IN ('NEW','ACKNOWLEDGED','RESOLVED')),
    detected_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id),
    FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_anomalies_worker ON anomalies (worker_id);

-- 23. NOTIFICATIONS
CREATE TABLE notifications (
    id              BIGSERIAL PRIMARY KEY,
    recipient_id    INT NOT NULL,
    title           VARCHAR(200) NOT NULL,
    message         TEXT NOT NULL,
    severity VARCHAR(50) DEFAULT 'INFO' CHECK (severity IN ('INFO','WARNING','CRITICAL')),
    type            VARCHAR(50),
    is_read         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (recipient_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_notif_recipient ON notifications (recipient_id, is_read);

-- 24. AUDIT LOGS (Hash-chained for tamper evidence)
CREATE TABLE audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    user_id         INT NULL,
    action          VARCHAR(100) NOT NULL,
    module          VARCHAR(100),
    record_id       VARCHAR(50),
    details         JSON,
    ip_address      VARCHAR(50),
    prev_hash       VARCHAR(64) NULL,
    hash            VARCHAR(64) NOT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_module ON audit_logs (module);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs (created_at);

-- 25. GRIEVANCES
CREATE TABLE grievances (
    id              SERIAL PRIMARY KEY,
    worker_id       INT NULL,
    mine_id         INT NOT NULL,
    category        VARCHAR(100) NOT NULL,
    description     TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'SUBMITTED' CHECK (status IN ('SUBMITTED','IN_REVIEW','RESOLVED','ESCALATED','CLOSED')),
    assigned_to     INT NULL,
    resolution_notes TEXT NULL,
    escalation_level INT DEFAULT 1,
    sla_hours        INT DEFAULT 48,
    escalated_at     TIMESTAMP NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE SET NULL,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_grievances_mine ON grievances (mine_id);
CREATE INDEX IF NOT EXISTS idx_grievances_status ON grievances (status);

-- 26. REPORTS
CREATE TABLE reports (
    id              SERIAL PRIMARY KEY,
    report_type     VARCHAR(100) NOT NULL,
    generated_by    INT NOT NULL,
    mine_id         INT NULL,
    file_path       VARCHAR(255),
    format VARCHAR(50) DEFAULT 'PDF' CHECK (format IN ('PDF','CSV')),
    parameters_json JSON,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (generated_by) REFERENCES users(id),
    FOREIGN KEY (mine_id) REFERENCES mines(id)
);


-- 27. AI INSPECTION ANALYSES
CREATE TABLE ai_inspection_analyses (
    id                 SERIAL PRIMARY KEY,
    inspection_id      INT NOT NULL,
    category           VARCHAR(100),
    severity VARCHAR(50) DEFAULT 'LOW' CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    risk_level VARCHAR(50) DEFAULT 'LOW' CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    risk_score         INT NOT NULL,
    summary            TEXT,
    reasoning          TEXT,
    recommended_action TEXT,
    recurring_issue    BOOLEAN DEFAULT FALSE,
    urgency            VARCHAR(50),
    confidence         DECIMAL(5,2),
    model_name         VARCHAR(100),
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inspection_id) REFERENCES inspections(id) ON DELETE CASCADE
);


-- 28. UNDERGROUND MESH TELEMETRY NODES
CREATE TABLE mesh_nodes (
    id              SERIAL PRIMARY KEY,
    mine_id         INT NOT NULL,
    zone_id         INT NULL,
    node_name       VARCHAR(100) NOT NULL,
    hop_sequence    INT NOT NULL,
    battery_pct     DECIMAL(5,2) DEFAULT 100.00,
    status VARCHAR(50) DEFAULT 'ONLINE' CHECK (status IN ('ONLINE','OFFLINE')),
    last_heartbeat  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
    FOREIGN KEY (zone_id) REFERENCES mine_zones(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_mesh_mine_hop ON mesh_nodes (mine_id, hop_sequence);

-- 29. SOS RELAY LOGS
CREATE TABLE sos_relay_logs (
    id                  BIGSERIAL PRIMARY KEY,
    incident_id         INT NOT NULL,
    node_id             INT NOT NULL,
    hop_number          INT NOT NULL,
    latency_ms          INT NOT NULL,
    signal_strength_pct DECIMAL(5,2) NOT NULL,
    relayed_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES mesh_nodes(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_relay_incident ON sos_relay_logs (incident_id);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    table_name TEXT;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['subsidiaries', 'users', 'mines', 'compliance_rules', 'inspections', 'violations', 'corrective_actions', 'grievances'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON %I', table_name);
        EXECUTE format('CREATE TRIGGER set_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()', table_name);
    END LOOP;
END $$;
