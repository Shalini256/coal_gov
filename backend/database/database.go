package database

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	_ "github.com/lib/pq"

	"coal-governance-backend/config"
)

// DB is the shared, pooled PostgreSQL connection used across the application.
var DB *PostgresDB

type PostgresDB struct {
	*sql.DB
}

type PostgresTx struct {
	*sql.Tx
}

func (db *PostgresDB) Exec(query string, args ...any) (sql.Result, error) {
	return execWithID(db.DB, query, args...)
}

func (db *PostgresDB) Query(query string, args ...any) (*sql.Rows, error) {
	return db.DB.Query(rebind(query), args...)
}

func (db *PostgresDB) QueryRow(query string, args ...any) *sql.Row {
	return db.DB.QueryRow(rebind(query), args...)
}

func (db *PostgresDB) Begin() (*PostgresTx, error) {
	tx, err := db.DB.Begin()
	if err != nil {
		return nil, err
	}
	return &PostgresTx{Tx: tx}, nil
}

func (tx *PostgresTx) Exec(query string, args ...any) (sql.Result, error) {
	return execWithID(tx.Tx, query, args...)
}

func (tx *PostgresTx) Query(query string, args ...any) (*sql.Rows, error) {
	return tx.Tx.Query(rebind(query), args...)
}

func (tx *PostgresTx) QueryRow(query string, args ...any) *sql.Row {
	return tx.Tx.QueryRow(rebind(query), args...)
}

type postgresResult struct {
	id int64
}

func (result postgresResult) LastInsertId() (int64, error) { return result.id, nil }
func (postgresResult) RowsAffected() (int64, error)        { return 1, nil }

type sqlExecer interface {
	Exec(query string, args ...any) (sql.Result, error)
	QueryRow(query string, args ...any) *sql.Row
}

func execWithID(execer sqlExecer, query string, args ...any) (sql.Result, error) {
	boundQuery := rebind(query)
	if shouldReturnID(query) {
		var id int64
		if err := execer.QueryRow(boundQuery+" RETURNING id", args...).Scan(&id); err != nil {
			return nil, err
		}
		return postgresResult{id: id}, nil
	}
	return execer.Exec(boundQuery, args...)
}

func shouldReturnID(query string) bool {
	upperQuery := strings.ToUpper(strings.TrimSpace(query))
	if !strings.HasPrefix(upperQuery, "INSERT INTO") || strings.Contains(upperQuery, "ON CONFLICT") || strings.Contains(upperQuery, " RETURNING ") {
		return false
	}
	valuesIndex := strings.Index(upperQuery, " VALUES ")
	if valuesIndex < 0 {
		return false
	}
	return !strings.Contains(upperQuery[valuesIndex:], "),")
}

func rebind(query string) string {
	var result strings.Builder
	result.Grow(len(query) + 8)
	parameter := 0
	quote := byte(0)
	lineComment := false
	blockComment := false

	for index := 0; index < len(query); index++ {
		character := query[index]
		next := byte(0)
		if index+1 < len(query) {
			next = query[index+1]
		}

		if lineComment {
			result.WriteByte(character)
			if character == '\n' {
				lineComment = false
			}
			continue
		}
		if blockComment {
			result.WriteByte(character)
			if character == '*' && next == '/' {
				result.WriteByte(next)
				index++
				blockComment = false
			}
			continue
		}
		if quote != 0 {
			result.WriteByte(character)
			if character == quote {
				if next == quote {
					result.WriteByte(next)
					index++
				} else {
					quote = 0
				}
			}
			continue
		}
		if character == '-' && next == '-' {
			result.WriteByte(character)
			result.WriteByte(next)
			index++
			lineComment = true
			continue
		}
		if character == '/' && next == '*' {
			result.WriteByte(character)
			result.WriteByte(next)
			index++
			blockComment = true
			continue
		}
		if character == '\'' || character == '"' {
			quote = character
			result.WriteByte(character)
			continue
		}
		if character == '?' {
			parameter++
			fmt.Fprintf(&result, "$%d", parameter)
			continue
		}
		result.WriteByte(character)
	}

	return result.String()
}

// Connect opens a connection pool to PostgreSQL and verifies it with a ping.
func Connect(cfg *config.Config) {
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.DBHost, cfg.DBPort, cfg.DBUser, cfg.DBPassword, cfg.DBName)

	conn, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("Failed to open database connection: %v", err)
	}
	DB = &PostgresDB{DB: conn}

	DB.SetMaxOpenConns(25)
	DB.SetMaxIdleConns(10)
	DB.SetConnMaxLifetime(5 * time.Minute)

	if err = DB.Ping(); err != nil {
		log.Fatalf("Failed to ping database: %v", err)
	}

	log.Println("Connected to PostgreSQL database:", cfg.DBName)
	RunMigrations()
}

// RunMigrations applies additive PostgreSQL migrations to an initialized schema.
func RunMigrations() {
	columns := []string{
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS workflow_status VARCHAR(50) DEFAULT 'PENDING_REVIEW'",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS mine_code VARCHAR(50) NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS inspector_name VARCHAR(100) NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS inspection_date DATE NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS compliance_status VARCHAR(50) DEFAULT 'COMPLIANT'",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS violation_details TEXT NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS risk_level VARCHAR(30) DEFAULT 'LOW'",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS corrective_action TEXT NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS due_date DATE NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS regulatory_reference VARCHAR(255) NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS ocr_data_json JSONB NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS reviewed_by INT NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMP NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS approved_by INT NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS verified_by INT NULL",
		"ALTER TABLE documents ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP NULL",
		"ALTER TABLE violations ADD COLUMN IF NOT EXISTS escalation_level INT DEFAULT 1",
		"ALTER TABLE violations ADD COLUMN IF NOT EXISTS sla_hours INT DEFAULT 48",
		"ALTER TABLE violations ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP NULL",
		"ALTER TABLE grievances ADD COLUMN IF NOT EXISTS escalation_level INT DEFAULT 1",
		"ALTER TABLE grievances ADD COLUMN IF NOT EXISTS sla_hours INT DEFAULT 48",
		"ALTER TABLE grievances ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS checkin_lat DECIMAL(10,6) NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS checkin_lng DECIMAL(10,6) NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS distance_from_mine_m DECIMAL(8,2) NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS is_mock_location BOOLEAN DEFAULT FALSE",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS device_uptime_ms BIGINT NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS client_reported_time TIMESTAMP NULL",
		"ALTER TABLE attendance ADD COLUMN IF NOT EXISTS tamper_flag BOOLEAN DEFAULT FALSE",
		"ALTER TABLE anomalies ADD COLUMN IF NOT EXISTS worker_id INT NULL",
		"ALTER TABLE inspections ADD COLUMN IF NOT EXISTS void_reason VARCHAR(255) NULL",
		"ALTER TABLE inspections ADD COLUMN IF NOT EXISTS voided_by INT NULL",
		"ALTER TABLE inspections ADD COLUMN IF NOT EXISTS voided_at TIMESTAMP NULL",
		"ALTER TABLE corrective_actions ADD COLUMN IF NOT EXISTS evidence_photo_path VARCHAR(255) NULL",
		"ALTER TABLE corrective_actions ADD COLUMN IF NOT EXISTS resolution_gps_latitude DECIMAL(10,6) NULL",
		"ALTER TABLE corrective_actions ADD COLUMN IF NOT EXISTS resolution_gps_longitude DECIMAL(10,6) NULL",
		"ALTER TABLE corrective_actions ADD COLUMN IF NOT EXISTS resolution_notes TEXT NULL",
	}

	for _, stmt := range columns {
		if _, err := DB.Exec(stmt); err != nil {
			log.Fatalf("Failed to apply database migration %q: %v", stmt, err)
		}
	}

	tables := []string{
		`CREATE TABLE IF NOT EXISTS attendance_checkin_events (
			id                  BIGSERIAL PRIMARY KEY,
			mine_id             INT NOT NULL,
			worker_id           INT NOT NULL,
			lat                 DECIMAL(10,6) NOT NULL,
			lng                 DECIMAL(10,6) NOT NULL,
			distance_from_mine_m DECIMAL(8,2) NOT NULL,
			event_type          VARCHAR(20) DEFAULT 'CHECKIN' CHECK (event_type IN ('CHECKIN','CHECKOUT')),
			is_mock_location    BOOLEAN DEFAULT FALSE,
			device_uptime_ms    BIGINT NULL,
			client_reported_time TIMESTAMP NULL,
			tamper_flag         BOOLEAN DEFAULT FALSE,
			liveness_passed     BOOLEAN DEFAULT TRUE,
			recorded_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
			FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE CASCADE
		)`,
		`CREATE TABLE IF NOT EXISTS mine_zones (
			id          SERIAL PRIMARY KEY,
			mine_id     INT NOT NULL,
			zone_name   VARCHAR(100) NOT NULL,
			zone_type   VARCHAR(100),
			latitude    DECIMAL(10,6),
			longitude   DECIMAL(10,6),
			created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE
		)`,
		`CREATE TABLE IF NOT EXISTS mesh_nodes (
			id              SERIAL PRIMARY KEY,
			mine_id         INT NOT NULL,
			zone_id         INT NULL,
			node_name       VARCHAR(100) NOT NULL,
			hop_sequence    INT NOT NULL,
			battery_pct     DECIMAL(5,2) DEFAULT 100.00,
			status          VARCHAR(20) DEFAULT 'ONLINE' CHECK (status IN ('ONLINE','OFFLINE')),
			last_heartbeat  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (mine_id) REFERENCES mines(id) ON DELETE CASCADE,
			FOREIGN KEY (zone_id) REFERENCES mine_zones(id) ON DELETE SET NULL
		)`,
		`CREATE TABLE IF NOT EXISTS sos_relay_logs (
			id                  BIGSERIAL PRIMARY KEY,
			incident_id         INT NOT NULL,
			node_id             INT NOT NULL,
			hop_number          INT NOT NULL,
			latency_ms          INT NOT NULL,
			signal_strength_pct DECIMAL(5,2) NOT NULL,
			relayed_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
			FOREIGN KEY (node_id) REFERENCES mesh_nodes(id) ON DELETE CASCADE
		)`,
		"CREATE INDEX IF NOT EXISTS idx_events_worker_time ON attendance_checkin_events (worker_id, recorded_at)",
		"CREATE INDEX IF NOT EXISTS idx_events_mine_time ON attendance_checkin_events (mine_id, recorded_at)",
		"CREATE INDEX IF NOT EXISTS idx_mesh_mine_hop ON mesh_nodes (mine_id, hop_sequence)",
		"CREATE INDEX IF NOT EXISTS idx_relay_incident ON sos_relay_logs (incident_id)",
	}

	for _, stmt := range tables {
		if _, err := DB.Exec(stmt); err != nil {
			log.Fatalf("Failed to apply database migration: %v", err)
		}
	}

	log.Println("PostgreSQL schema migrations applied.")
}
