# SonarQube PostgreSQL Setup – Red Hat AAP Runbook

Automates the manual `psql` session (Azure Database for PostgreSQL Flexible Server, v16) as an Ansible playbook run from Red Hat Ansible Automation Platform (AAP).

- **Playbook:** `sonarqube_db_setup.yml`
- **Target server:** `t0016-pgqlsq02r01-d.postgres.database.azure.com:5432`
- **Admin user:** `pgadmin` (not a superuser; member of `azure_pg_admin`)

---

## 1. What the recording does

| # | Manual step in recording | Playbook equivalent |
|---|---|---|
| 1 | `\list`, list non-template DBs | not needed (idempotent modules) |
| 2 | `DROP DATABASE sonar;` | `postgresql_db state=absent` – **opt-in only** |
| 3 | `CREATE ROLE sonar LOGIN PASSWORD ...; ALTER USER ... ENCRYPTED PASSWORD` | `postgresql_user` (password stored as SCRAM/hashed) |
| 4 | `ALTER ROLE sonar CREATEDB REPLICATION BYPASSRLS` | `role_attr_flags` variable |
| 5 | Reconnect as `sonar`, `CREATE DATABASE sonar WITH OWNER sonar ENCODING 'UTF8' LC_COLLATE/LC_CTYPE 'en_US.UTF-8' TEMPLATE template0` | `postgresql_db` logged in as `sonar` |
| 6 | `create SCHEMA sonar` (fails in `postgres` DB, works in `sonar` DB) | `postgresql_schema` with `login_db: sonar` |
| 7 | `ALTER USER sonar SET search_path to sonar` | `ALTER ROLE ... SET search_path` (only if not already set) |
| 8 | `GRANT`/`REVOKE` on database, schema, tables | `postgresql_privs` tasks |
| 9 | Verify with `SELECT SESSION_USER, CURRENT_USER` | `postgresql_query` + `assert` |

## 2. Findings from the recording (and what changed in the playbook)

1. **Plaintext password** `Son@rD3` is visible in the recording. Treat it as compromised and use a **new** password stored in AAP (never in Git).
2. **`DROP DATABASE sonar` is destructive.** The playbook skips it unless `sonar_drop_existing_db=true` **and** `sonar_drop_confirm=sonar` are both supplied.
3. **`REPLICATION` and `BYPASSRLS` are not required by SonarQube.** The default attributes are `LOGIN,CREATEDB` (CREATEDB is only needed because the `sonar` role creates its own DB). To reproduce the recording exactly, set `sonar_role_attrs: "LOGIN,CREATEDB,REPLICATION,BYPASSRLS"`.
4. **Schema creation must run inside the `sonar` DB**, not `postgres` (the recording hit `permission denied for database postgres`). The playbook handles this.
5. **Redundant grants collapsed.** The owner already holds all privileges, and the final `GRANT SELECT, INSERT, UPDATE, DELETE` is a subset of the earlier `GRANT ALL`.
6. **`REVOKE CONNECT ... FROM PUBLIC` also blocks `pgadmin`** (not a superuser on Azure). The playbook re-grants `CONNECT` to `pgadmin` (`sonar_db_connect_roles`).
7. The recording's syntax errors (missing `;`, `\c` with wrong password: "Previous connection kept") are not an issue with automation.
8. Collation `en_US.UTF-8` matches what the recording created. Keep it consistent, because a database's collation can't be changed afterwards.

---

## 3. Prerequisites

### 3.1 Network
- AAP execution node / container group must reach the PostgreSQL server on **TCP 5432**.
- Azure side: add the AAP egress IP to the server's firewall rules (public access) or ensure VNet/private-endpoint connectivity.
- TLS is enforced by Azure; the playbook uses `ssl_mode: require`.

### 3.2 Accounts
- `pgadmin` password (administrator of the Flexible Server).
- A new password for the `sonar` role (min 8 chars; use a strong one).

### 3.3 Execution Environment (EE) with the PostgreSQL collection and driver
The default EE does not include `psycopg2`. Build a custom EE.

`requirements.yml`
```yaml
---
collections:
  - name: community.postgresql
    version: ">=3.4.0"
```

`execution-environment.yml` (ansible-builder v3; adjust base image to your AAP version)
```yaml
---
version: 3
images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9:latest
dependencies:
  galaxy: requirements.yml
  python:
    - psycopg2-binary>=2.9
options:
  package_manager_path: /usr/bin/microdnf
```

Build and push:
```bash
podman login registry.redhat.io
ansible-builder build -t <your-registry>/ee-postgres-sonar:1.0 -f execution-environment.yml
podman push <your-registry>/ee-postgres-sonar:1.0
```

> If you use Private Automation Hub, push the image there and, if needed, mirror the collection too.

---

## 4. AAP configuration steps

### Step 1 – Add the Execution Environment
**Automation Execution → Infrastructure → Execution Environments → Create**
- Name: `ee-postgres-sonar`
- Image: `<your-registry>/ee-postgres-sonar:1.0`
- Pull: *Only pull the image if not present*
- Registry credential: if the registry is private.

### Step 2 – Create the Project
Put `sonarqube_db_setup.yml` (and optionally `collections/requirements.yml`) in a Git repo.

**Automation Execution → Projects → Create**
- Name: `SonarQube DB Setup`
- Source control type: Git
- URL / branch / SCM credential
- Execution environment: `ee-postgres-sonar`
- Enable *Update revision on launch* (recommended)

### Step 3 – Create a custom Credential Type
**Automation Execution → Infrastructure → Credential Types → Create**
- Name: `PostgreSQL SonarQube Secrets`

*Input configuration*
```yaml
fields:
  - id: pg_admin_password
    type: string
    label: PostgreSQL admin (pgadmin) password
    secret: true
  - id: sonar_db_password
    type: string
    label: SonarQube DB role (sonar) password
    secret: true
required:
  - pg_admin_password
  - sonar_db_password
```

*Injector configuration*
```yaml
extra_vars:
  pg_admin_password: "{{ pg_admin_password }}"
  sonar_db_password: "{{ sonar_db_password }}"
```

### Step 4 – Create the Credential
**Credentials → Create**
- Name: `SonarQube PG Secrets – DEV`
- Credential type: `PostgreSQL SonarQube Secrets`
- Enter both passwords. Create one credential per environment (dev/test/prod).

### Step 5 – Create the Inventory
**Inventories → Create** → name `localhost-inventory`, then add host `localhost` with variables:
```yaml
ansible_connection: local
ansible_python_interpreter: "{{ ansible_playbook_python }}"
```
(The playbook talks to PostgreSQL over the network from the EE; no SSH is needed.)

### Step 6 – Create the Job Template
**Templates → Create job template**

| Field | Value |
|---|---|
| Name | `SonarQube – PostgreSQL DB Setup` |
| Job type | Run |
| Inventory | `localhost-inventory` |
| Project | `SonarQube DB Setup` |
| Playbook | `sonarqube_db_setup.yml` |
| Execution environment | `ee-postgres-sonar` |
| Credentials | `SonarQube PG Secrets – DEV` |
| Verbosity | 0 (Normal) – keep low; secrets use `no_log` |
| Prompt on launch → Variables | enabled (or use a survey) |

**Extra variables** (override per environment):
```yaml
pg_host: t0016-pgqlsq02r01-d.postgres.database.azure.com
pg_port: 5432
pg_admin_user: pgadmin
sonar_db_name: sonar
sonar_db_user: sonar
sonar_schema: sonar
sonar_role_attrs: "LOGIN,CREATEDB,NOSUPERUSER,NOCREATEROLE,NOREPLICATION,NOBYPASSRLS"
sonar_drop_existing_db: false
sonar_drop_confirm: ""
```

### Step 7 – (Optional) Add a Survey
Survey tab → Add questions:

| Question | Variable | Type | Default |
|---|---|---|---|
| PostgreSQL server FQDN | `pg_host` | Text | `t0016-pgqlsq02r01-d.postgres.database.azure.com` |
| Drop existing DB first? | `sonar_drop_existing_db` | Multiple choice (`true`/`false`) | `false` |
| Type DB name to confirm drop | `sonar_drop_confirm` | Text | *(blank)* |

Enable the survey. Use RBAC so only senior operators can launch with the drop option.

### Step 8 – Run the job
1. **Launch** the template.
2. Fresh install: leave `sonar_drop_existing_db=false`.
3. Rebuild from scratch (data loss!): set `sonar_drop_existing_db=true` and `sonar_drop_confirm=sonar`.
4. Expected last tasks: *Assert expected state* → `OK: sonar@sonar, schema sonar, encoding UTF8, collate en_US.UTF-8`.
5. Re-running the job should show `changed=0` (apart from query tasks that always report ok).

### Step 9 – Promote / schedule (optional)
- Run it as a step in a **Workflow Job Template**: `DB setup → SonarQube install → SonarQube start`.
- Add **Notifications** (email/Teams/Slack) on success/failure.

---

## 5. Manual verification (optional)

```bash
psql -h t0016-pgqlsq02r01-d.postgres.database.azure.com -p 5432 -U sonar -d sonar -W
```
```sql
SELECT session_user, current_user, current_database(), current_schema();
\dn+
\l+ sonar
\du sonar
```
Expected: user `sonar`, database `sonar`, schema `sonar`, encoding `UTF8`, collation `en_US.UTF-8`.

## 6. Configure SonarQube (`sonar.properties`)

```properties
sonar.jdbc.username=sonar
sonar.jdbc.password=<sonar password from AAP credential>
sonar.jdbc.url=jdbc:postgresql://t0016-pgqlsq02r01-d.postgres.database.azure.com:5432/sonar?sslmode=require&currentSchema=sonar
```
Restart SonarQube. On first start it creates its tables in the `sonar` schema.

> Store the password in your secrets tooling (vault, environment variable, or `SONAR_JDBC_PASSWORD`) rather than in plain text where possible.

---

## 7. Rollback

Run the job again with `sonar_drop_existing_db=true` / `sonar_drop_confirm=sonar` to drop the database (all SonarQube data is lost, so take a `pg_dump` first). To remove the role as well:
```sql
DROP ROLE sonar;   -- run as pgadmin, after the database is dropped
```

## 8. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Failed to import the required Python library (psycopg2)` | The job isn't using the custom EE. Check the Job Template and Project EE. |
| `could not connect ... timed out` | Azure firewall / private network doesn't allow the AAP egress IP on 5432. |
| `no pg_hba.conf entry` / SSL errors | Keep `pg_ssl_mode: require`; for `verify-full` supply the CA cert in the EE. |
| `permission denied to create database` | `sonar_role_attrs` is missing `CREATEDB`. |
| `permission denied for database postgres` when creating schema | Schema must be created while connected to the `sonar` DB (the playbook does this). |
| `pgadmin` can't connect to `sonar` DB afterwards | CONNECT was revoked from PUBLIC; ensure the admin is in `sonar_db_connect_roles`. |
| `Changing database collate/encoding is not supported` | DB already exists with different encoding/collation. Drop and recreate, or align the variables. |
| `unknown action group` / `module_defaults` error | Collection `community.postgresql` missing or too old in the EE. |
| Password task shows `changed` every run | Normal for some collection versions; passwords are hidden by `no_log`. |

## 9. Security checklist

- [ ] Rotate the password shown in the recording (`Son@rD3`).
- [ ] Passwords exist only in the AAP credential (encrypted), never in Git or Extra Variables.
- [ ] Restrict who can edit/launch the template (AAP RBAC); limit the drop survey option.
- [ ] Remove `REPLICATION`/`BYPASSRLS` unless a real need exists.
- [ ] Prefer `sslmode=verify-full` with the Azure CA bundle for production.
- [ ] Back up (`pg_dump` or Azure backup) before any drop/rebuild.
