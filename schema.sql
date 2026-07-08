-- GoalCraft Database Schema
-- Matches SQLAlchemy models in app/models/schemas.py

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS check_ins CASCADE;
DROP TABLE IF EXISTS chat_messages CASCADE;
DROP TABLE IF EXISTS metric_entries CASCADE;
DROP TABLE IF EXISTS metrics CASCADE;
DROP TABLE IF EXISTS milestones CASCADE;
DROP TABLE IF EXISTS goals CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    auth0_id VARCHAR(255) UNIQUE,
    google_refresh_token TEXT,
    google_calendar_id VARCHAR(255),
    phone_number VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_auth0_id ON users(auth0_id);

-- Goals table
CREATE TABLE goals (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    identity TEXT,
    target_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_goals_user_id ON goals(user_id);

-- Metrics table (custom, user-defined measurements for a goal)
CREATE TABLE metrics (
    id SERIAL PRIMARY KEY,
    goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    unit VARCHAR(64) NOT NULL DEFAULT '',
    symbol VARCHAR(64) NOT NULL DEFAULT 'chart.bar.fill',
    color VARCHAR(9) NOT NULL DEFAULT '#1E9068',
    target INTEGER,
    "order" INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_metrics_goal_id ON metrics(goal_id);

-- Metric entries table (each logged event that increments a metric)
CREATE TABLE metric_entries (
    id SERIAL PRIMARY KEY,
    metric_id INTEGER NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL DEFAULT 1,
    note TEXT NOT NULL DEFAULT '',
    logged_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_metric_entries_metric_id ON metric_entries(metric_id);

-- Milestones table
CREATE TABLE milestones (
    id SERIAL PRIMARY KEY,
    goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    due_date TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped')),
    "order" INTEGER DEFAULT 0,
    calendar_event_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_milestones_goal_id ON milestones(goal_id);

-- Chat messages table
CREATE TABLE chat_messages (
    id SERIAL PRIMARY KEY,
    goal_id INTEGER NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chat_messages_goal_id ON chat_messages(goal_id);

-- Check-ins table
CREATE TABLE check_ins (
    id SERIAL PRIMARY KEY,
    milestone_id INTEGER NOT NULL REFERENCES milestones(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE,
    response TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_check_ins_milestone_id ON check_ins(milestone_id);
CREATE INDEX idx_check_ins_scheduled ON check_ins(scheduled_at) WHERE sent_at IS NULL;
