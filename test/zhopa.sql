-- PostgreSQL Advanced Features Demonstration
-- This file showcases interesting PostgreSQL capabilities

-- 1. Advanced Data Types and Functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create a sample table with various data types
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    profile_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    tags TEXT[] DEFAULT '{}'
);

-- 2. Complex Indexing Examples
CREATE INDEX IF NOT EXISTS idx_users_email ON users USING hash(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users USING brin(created_at);
CREATE INDEX IF NOT EXISTS idx_users_profile_data ON users USING gin(profile_data);
CREATE INDEX IF NOT EXISTS idx_users_tags ON users USING gin(tags);

-- 3. Advanced Functions and Procedures
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 4. Window Functions Example
CREATE TABLE IF NOT EXISTS sales (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    amount DECIMAL(10,2) NOT NULL,
    sale_date DATE NOT NULL,
    region VARCHAR(50) NOT NULL
);

-- 5. Recursive CTE Example (Employee Hierarchy)
CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    manager_id INTEGER REFERENCES employees(id),
    salary DECIMAL(10,2) NOT NULL
);

-- 6. Full Text Search Example
CREATE TABLE IF NOT EXISTS articles (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    author_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))
    ) STORED
);

CREATE INDEX IF NOT EXISTS idx_articles_search ON articles USING gin(search_vector);

-- 7. Partitioning Example (Range Partitioning)
CREATE TABLE IF NOT EXISTS sensor_data (
    sensor_id INTEGER,
    reading_value DECIMAL(8,4),
    recorded_at TIMESTAMPTZ,
    location VARCHAR(50)
) PARTITION BY RANGE (recorded_at);

CREATE TABLE sensor_data_2024_q1 PARTITION OF sensor_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE sensor_data_2024_q2 PARTITION OF sensor_data
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

-- 8. Materialized Views
CREATE MATERIALIZED VIEW IF NOT EXISTS monthly_sales_summary AS
SELECT
    DATE_TRUNC('month', sale_date) as month,
    region,
    COUNT(*) as total_sales,
    SUM(amount) as total_amount,
    AVG(amount) as avg_amount
FROM sales
GROUP BY DATE_TRUNC('month', sale_date), region;

CREATE UNIQUE INDEX IF NOT EXISTS idx_monthly_sales_summary
    ON monthly_sales_summary (month, region);

-- 9. Advanced JSON Operations
CREATE OR REPLACE FUNCTION search_users_by_profile_criteria(criteria JSONB)
RETURNS TABLE(
    user_id UUID,
    username VARCHAR,
    email VARCHAR,
    matched_criteria TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.username,
        u.email,
        jsonb_each_text(criteria)::TEXT as matched_criteria
    FROM users u
    WHERE u.profile_data @> criteria
       OR u.profile_data ?| array(SELECT jsonb_object_keys(criteria));
END;
$$ LANGUAGE plpgsql;

-- 10. Complex Query with Multiple CTEs and Window Functions
WITH monthly_stats AS (
    SELECT
        DATE_TRUNC('month', sale_date) as month,
        region,
        SUM(amount) as monthly_total,
        COUNT(*) as transaction_count
    FROM sales
    GROUP BY DATE_TRUNC('month', sale_date), region
),
regional_rankings AS (
    SELECT
        month,
        region,
        monthly_total,
        transaction_count,
        RANK() OVER (PARTITION BY month ORDER BY monthly_total DESC) as revenue_rank,
        PERCENT_RANK() OVER (PARTITION BY month ORDER BY monthly_total) as revenue_percentile
    FROM monthly_stats
)
SELECT
    TO_CHAR(month, 'YYYY-MM') as year_month,
    region,
    monthly_total,
    transaction_count,
    revenue_rank,
    ROUND(revenue_percentile::numeric, 2) as percentile
FROM regional_rankings
ORDER BY month DESC, revenue_rank;

-- 11. Recursive Query for Employee Hierarchy
WITH RECURSIVE employee_hierarchy AS (
    -- Base case: employees with no manager (top level)
    SELECT
        id,
        name,
        manager_id,
        salary,
        1 as level,
        ARRAY[name] as path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive case: employees with managers
    SELECT
        e.id,
        e.name,
        e.manager_id,
        e.salary,
        eh.level + 1,
        eh.path || e.name
    FROM employees e
    INNER JOIN employee_hierarchy eh ON e.manager_id = eh.id
)
SELECT
    id,
    name,
    level,
    array_to_string(path, ' -> ') as management_chain,
    salary
FROM employee_hierarchy
ORDER BY path;

-- 12. Sample Data Insertion
INSERT INTO users (username, email, password_hash, profile_data, tags) VALUES
('alice', 'alice@example.com', crypt('password123', gen_salt('bf')),
 '{"age": 30, "city": "New York", "interests": ["programming", "hiking"]}',
 ARRAY['premium', 'active']),
('bob', 'bob@example.com', crypt('securepass', gen_salt('bf')),
 '{"age": 25, "city": "San Francisco", "interests": ["gaming", "music"]}',
 ARRAY['standard', 'new']),
('charlie', 'charlie@example.com', crypt('mypassword', gen_salt('bf')),
 '{"age": 35, "city": "London", "interests": ["reading", "travel"]}',
 ARRAY['premium', 'vip']);

-- 13. Performance Monitoring Query
SELECT
    schemaname,
    relname,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_%'
ORDER BY seq_scan + idx_scan DESC
LIMIT 10;

-- 14. Cleanup function (optional - for testing)
CREATE OR REPLACE FUNCTION cleanup_test_data()
RETURNS void AS $$
BEGIN
    DELETE FROM sales;
    DELETE FROM articles;
    DELETE FROM employees;
    DELETE FROM sensor_data;
    DELETE FROM users;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_test_data() IS 'Utility function to clean up test data';

-- Display table information
SELECT
    table_name,
    table_type,
    is_insertable_into
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
