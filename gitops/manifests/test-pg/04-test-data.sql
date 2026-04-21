-- Test data for CNPG backup/restore validation
-- Run this inside the PostgreSQL pod after cluster is ready

-- Create test table
CREATE TABLE IF NOT EXISTS backup_test (
    id SERIAL PRIMARY KEY,
    test_data VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO backup_test (test_data) VALUES
    ('Pre-backup record 1'),
    ('Pre-backup record 2'),
    ('Pre-backup record 3'),
    ('Pre-backup record 4'),
    ('Pre-backup record 5');

-- Verify data
SELECT * FROM backup_test ORDER BY id;

-- Show current timestamp (for PITR reference)
SELECT NOW() AS backup_timestamp;
