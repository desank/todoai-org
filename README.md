# Family To-Do App

A modern, mobile-first collaborative task management app for families, built with Flutter, Azure Database for PostgreSQL, Azure Container Apps, Azure Key Vault, and Azure Static Web Apps. This MVP enables families to manage shared to-do lists, assign tasks, and receive real-time updates.

---

## Features

- **User Accounts:** Registration and login for each family member (JWT Auth)
- **Family Group Management:** Admins can create family groups and invite members
- **Shared Task Lists:** All tasks are visible to all members of a family group
- **Task Management:** Create, assign, edit, complete, and delete tasks
- **Notifications:** In-app notifications for assignments and due dates
- **Mobile-First UI:** Responsive Flutter app for iOS, Android, and Web
- **Secure Data:** All data stored in Azure Database for PostgreSQL, protected by VNet and Key Vault
- **Role-based Access:** All authorization and RLS logic enforced in backend API

---

## Architecture Overview

- **Frontend:** Flutter (mobile/web), using Riverpod for state management and REST API for backend integration
- **Backend:**
  - **API:** Python FastAPI, containerized for Azure Container Apps, connects securely to Azure Database for PostgreSQL using credentials from Azure Key Vault
  - **Database:** Azure Database for PostgreSQL Flexible Server, private subnet, VNet-restricted
  - **Secrets:** Azure Key Vault for storing DB password, accessed via managed identity
- **Cloud Deployment:**
  - **Flutter Web:** Azure Static Web Apps
  - **API:** Azure Container Apps (in VNet)
  - **IaC:** Bicep templates in `infra/`
  - **Orchestration:** Azure Developer CLI (`azd`)
  - **CI/CD:** GitHub Actions pipeline for full infra/app deployment and DB schema initialization

---

## Project Structure

```
.
├── .azure/                 # azd environment files
├── .github/workflows/      # CI/CD pipelines (GitHub Actions)
│   └── ci-cd.yaml          # Main pipeline
├── infra/
│   └── main.bicep          # Azure infrastructure as code
├── src/
│   ├── flutter_app/        # Flutter mobile/web app
│   └── api/                # Python FastAPI backend
│       ├── app.py
│       ├── requirements.txt
│       ├── Dockerfile
│       └── db_schema.sql   # PostgreSQL schema
└── azure.yaml              # azd configuration file
```

---

## Database Schema (Azure PostgreSQL)

The schema is defined in `src/api/db_schema.sql` and is automatically applied by the CI/CD pipeline after infra deployment.

```
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
    role TEXT DEFAULT 'member' NOT NULL,
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
```

---

## How to Run Locally

### 1. Azure PostgreSQL
- Provisioned automatically by Bicep/azd in a private subnet
- DB password is stored in Azure Key Vault
- Schema is in `src/api/db_schema.sql`

### 2. Flutter App
- Install [Flutter](https://docs.flutter.dev/get-started/install)
- `cd src/flutter_app`
- Update API endpoint in your Dart code to point to your deployed backend
- Run `flutter pub get`
- Run `flutter run` (for mobile) or `flutter run -d chrome` (for web)

### 3. Python API
- Install Python 3.9+
- `cd src/api`
- `pip install -r requirements.txt`
- Set environment variables for DB connection (see Bicep outputs or Key Vault)
- Run `uvicorn app:app --reload`

---

## How to Deploy to Azure

### Prerequisites
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- Azure subscription
- GitHub repository with secrets set for OIDC login and Key Vault/DB info

### Steps
1. Login: `azd auth login`
2. Initialize: `azd init`
3. Provision resources: `azd provision`
4. Deploy: `azd deploy`

- The Flutter web app will be deployed to Azure Static Web Apps
- The API will be deployed to Azure Container Apps (in VNet)
- All infrastructure is defined in `infra/main.bicep`
- The database schema is applied automatically by the CI/CD pipeline

### Environment Variables & Secrets
- All DB credentials are stored in Azure Key Vault
- The API retrieves DB password at runtime using managed identity
- Never commit real secrets to source control

---

## CI/CD Pipeline

- Located at `.github/workflows/ci-cd.yaml`
- Provisions infra, deploys app, retrieves DB password from Key Vault, and runs schema migration
- Uses managed identity for secure access
- Example step for DB schema:
  ```yaml
  - name: Run DB schema migration
    env:
      PGPASSWORD: ${{ env.PGPASSWORD }}
    run: |
      psql "host=${{ env.POSTGRES_HOST }} dbname=${{ env.POSTGRES_DB }} user=${{ env.POSTGRES_USER }} password=${{ env.PGPASSWORD }} sslmode=require" -f src/api/db_schema.sql
  ```

---

## Security & Best Practices
- **RLS & Authorization:** All access control is enforced in the backend API (not in DB)
- **No hardcoded secrets:** Use Azure Key Vault and managed identity
- **VNet-restricted:** Database is not publicly accessible
- **Error handling:** Both frontend and backend handle errors gracefully
- **Mobile responsive:** Flutter UI adapts to all screen sizes

---

## Roadmap
- Invite flow with email
- Push/device notifications
- Task comments and attachments
- Calendar integration
- Enhanced admin controls

---

## License
MIT License.
