#!/bin/bash
# SQL initialization script runner for PostgreSQL using existing connection info.
# This script will:
# 1) Create required tables
# 2) Create indexes and constraints
# 3) Seed development data
#
# IMPORTANT:
# - Reads connection information from db_connection.txt (existing convention)
# - Executes each SQL statement one at a time via psql -c as per project rules

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure connection info exists
if [ ! -f "${BASE_DIR}/db_connection.txt" ]; then
  echo "db_connection.txt not found. Run startup.sh to initialize PostgreSQL and generate it."
  exit 1
fi

# Extract connection URL from db_connection.txt (format: psql postgresql://user:pass@host:port/db)
PSQL_CMD="$(cat "${BASE_DIR}/db_connection.txt" | awk '{print $1}')"
CONN_URL="$(cat "${BASE_DIR}/db_connection.txt" | awk '{print $2}')"

if [ "${PSQL_CMD}" != "psql" ]; then
  echo "db_connection.txt does not appear to be in the expected format (psql <url>)"
  exit 1
fi

# Helper function to execute a single SQL statement
exec_sql() {
  local sql="$1"
  echo "Executing: ${sql}"
  psql "${CONN_URL}" -v ON_ERROR_STOP=1 -c "${sql}"
}

echo "== Creating tables =="

# users
exec_sql "CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

# profiles
exec_sql "CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  bio TEXT,
  avatar_url TEXT,
  location TEXT,
  website TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);"

# posts
exec_sql "CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  media_url TEXT,
  visibility TEXT NOT NULL DEFAULT 'public',
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

# engagements
exec_sql "CREATE TABLE IF NOT EXISTS engagements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  type TEXT NOT NULL CHECK (type IN ('like','comment','share','view')),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

# analytics_daily
exec_sql "CREATE TABLE IF NOT EXISTS analytics_daily (
  id BIGSERIAL PRIMARY KEY,
  metric_date DATE NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  posts_count INTEGER NOT NULL DEFAULT 0,
  likes_count INTEGER NOT NULL DEFAULT 0,
  comments_count INTEGER NOT NULL DEFAULT 0,
  shares_count INTEGER NOT NULL DEFAULT 0,
  views_count INTEGER NOT NULL DEFAULT 0,
  followers_count INTEGER NOT NULL DEFAULT 0,
  following_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(metric_date, user_id)
);"

# admin_flags
exec_sql "CREATE TABLE IF NOT EXISTS admin_flags (
  id BIGSERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

echo "== Creating indexes =="

exec_sql "CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_posts_posted_at ON posts(posted_at DESC);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_engagements_post_id ON engagements(post_id);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_engagements_type ON engagements(type);"
exec_sql "CREATE INDEX IF NOT EXISTS idx_analytics_daily_user_date ON analytics_daily(user_id, metric_date);"

echo "== Creating utility extensions (if available) =="

# Enable pgcrypto for gen_random_uuid if available
exec_sql "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

echo "== Seeding development data =="

# Create example users
exec_sql "INSERT INTO users (email, password_hash, is_active)
VALUES ('alice@example.com', 'hashed_password_alice', TRUE)
ON CONFLICT (email) DO NOTHING;"

exec_sql "INSERT INTO users (email, password_hash, is_active)
VALUES ('bob@example.com', 'hashed_password_bob', TRUE)
ON CONFLICT (email) DO NOTHING;"

# Create profiles for users
exec_sql "INSERT INTO profiles (user_id, display_name, bio, avatar_url, location, website)
SELECT id, 'Alice', 'Data analyst and coffee lover', 'https://example.com/avatars/alice.png', 'NYC', 'https://alice.dev'
FROM users WHERE email='alice@example.com'
ON CONFLICT (user_id) DO NOTHING;"

exec_sql "INSERT INTO profiles (user_id, display_name, bio, avatar_url, location, website)
SELECT id, 'Bob', 'Product manager. Building data-informed products.', 'https://example.com/avatars/bob.png', 'SF', 'https://bob.dev'
FROM users WHERE email='bob@example.com'
ON CONFLICT (user_id) DO NOTHING;"

# Posts for users
exec_sql "INSERT INTO posts (user_id, content, media_url, visibility)
SELECT id, 'Excited to share my latest dashboard build!', NULL, 'public'
FROM users WHERE email='alice@example.com'
RETURNING id;"

exec_sql "INSERT INTO posts (user_id, content, media_url, visibility)
SELECT id, 'Iterating on user profiles today. Feedback welcome!', NULL, 'public'
FROM users WHERE email='bob@example.com'
RETURNING id;"

# Engagements (likes and comments)
exec_sql \"INSERT INTO engagements (post_id, user_id, type, metadata)
SELECT p.id, u.id, 'like', '{}'::jsonb
FROM posts p, users u
WHERE p.user_id = (SELECT id FROM users WHERE email='alice@example.com')
AND u.email = 'bob@example.com'
LIMIT 1;\"\

exec_sql \"INSERT INTO engagements (post_id, user_id, type, metadata)
SELECT p.id, u.id, 'comment', '{\"text\":\"Looks great!\"}'::jsonb
FROM posts p, users u
WHERE p.user_id = (SELECT id FROM users WHERE email='bob@example.com')
AND u.email = 'alice@example.com'
LIMIT 1;\"\

# Admin flags
exec_sql \"INSERT INTO admin_flags (key, value, description)
VALUES ('enable_new_analytics', TRUE, 'Toggle for new analytics pipeline')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;\"\

# Analytics daily seed for last 7 days for Alice
for i in {0..6}; do
  exec_sql \"INSERT INTO analytics_daily (metric_date, user_id, posts_count, likes_count, comments_count, shares_count, views_count, followers_count, following_count)
  SELECT (CURRENT_DATE - INTERVAL '$i day')::date,
         id,
         1 + ($RANDOM % 3),
         3 + ($RANDOM % 10),
         1 + ($RANDOM % 5),
         0 + ($RANDOM % 3),
         20 + ($RANDOM % 50),
         100 + ($RANDOM % 10),
         50 + ($RANDOM % 10)
  FROM users WHERE email='alice@example.com'
  ON CONFLICT (metric_date, user_id) DO NOTHING;\"\

done

echo "== Initialization complete =="
