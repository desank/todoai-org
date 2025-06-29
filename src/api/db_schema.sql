-- Database schema for Family To-Do App (Azure PostgreSQL)
-- Users table (for reference, actual auth is via JWT)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Family groups
CREATE TABLE IF NOT EXISTS family_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_by UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Family members (junction table)
CREATE TABLE IF NOT EXISTS family_members (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    family_group_id UUID REFERENCES family_groups(id) ON DELETE CASCADE NOT NULL,
    role TEXT DEFAULT 'member' NOT NULL, -- e.g., 'admin', 'member'
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, family_group_id)
);

-- Tasks
CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_group_id UUID REFERENCES family_groups(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    due_date DATE,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_completed BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tasks_family_group_id ON tasks(family_group_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user_id ON family_members(user_id);
