# SonarQube PostgreSQL Setup – Red Hat AAP Runbook

Automates the manual `psql` session (Azure Database for PostgreSQL Flexible Server, v16) as an Ansible playbook run from Red Hat Ansible Automation Platform (AAP), **using hosts from an AAP inventory**.

- **Playbook:** `sonarqube_db_setup.yml`
- **Inventory group used by the playbook:** `sonarqube_servers`
- **Inventory host:** the SonarQube VM `t0016vmsq01r01d` (the host where `psql` was run in the recording)
- **Database server:** `t0016-pgqlsq02r01-d.postgres.database.azure.com:5432`
- **Admin user:** `pgadmin` (not a superuser; member of `azure_pg_admin`)

> **How it works:** AAP connects by SSH to the VM in the inventory. The PostgreSQL modules run *on that VM* and connect to the Azure PostgreSQL server over the network, exactly like `psql` did in the recording. The Azure PaaS server itself is not an SSH host and is not in the inventory; it is a variable (`pg_host`).

---

## 1. What the recording does

| # | Manual step in recording | Playbook equivalent |
|---|---|---|
| 1 | `\list`, list non-template DBs | not needed (idempotent modules) |
| 2 | `DROP DATABASE sonar;` | `postgresql_db state=absent` – **opt-in only** |
| 3 | `CREATE ROLE sonar LOGIN PASSWORD ...; ALTER USER ... ENCRYPTED PASSWORD` | `postgresql_user` |
| 4 | `ALTER ROLE sonar CREATEDB REPLICATION BYPASSRLS` | `role_attr_flags` variable |
| 5 | Reconnect as `sonar`, `CREATE DATABASE sonar WITH OWNER sonar ENCODING 'UTF8' LC_COLLATE/LC_CTYPE 'en_US.UTF-8' TEMPLATE template0` | `postgresql_db` logged in as `sonar` |
| 6 | `create SCHEMA sonar` (fails in `postgres` DB, works in `sonar` DB) | `postgresql_schema` with `login_db: sonar` |
| 7 | `ALTER USER sonar SET search_path to sonar` | `ALTER ROLE ... SET search_path` (only if not already set) |
| 8 | `GRANT`/`REVOKE` on database, schema, tables | `postgresql_privs` tasks |
| 9 | Verify with `SELECT SESSION_USER, CURRENT_USER` | `postgresql_query` + `assert` |

## 2. Findings from the recording (and what changed in the playbook)

1. **Plaintext password** `Son@rD3` is visible in the recording. Treat it as compromised and use a **new** password stored in AAP (never in Git).
2. **`DROP DATABASE sonar` is destructive.** The playbook skips it unless `sonar_drop_existing_db=true` **and** `sonar_drop_confirm=sonar` are both supplied.
3. **`REPLICATION` and `BYPASSRLS` are not required by SonarQube.** Default attributes are `LOGIN,CREATEDB` (CREATEDB only because `sonar` creates its own DB). To reproduce the recording exactly, set `sonar_role_attrs: "LOGIN,CREATEDB,REPLICATION,BYPASSRLS"`.
4. **Schema creation must run inside the `sonar` DB**, not `postgres` (the recording hit `permission denied for database postgres`).
5. **Redundant grants collapsed.** The owner already holds all privileges; the final `GRANT SELECT, INSERT, UPDATE, DELETE` is a subset of the earlier `GRANT ALL`.
6. **`REVOKE CONNECT ... FROM PUBLIC` also blocks `pgadmin`** (not a superuser on Azure). The playbook re-grants `CONNECT` to `pgadmin` (`sonar_db_connect_roles`).
7. The recording's syntax errors and the `\c` wrong-password "Previous connection kept" are not an issue with automation.
8. Collation `en_US.UTF-8` matches what the recording created; it can't be changed after creation.

---

## 3. Prerequisites

### 3.1 Target host (inventory host = SonarQube VM)
- RHEL/compatible Linux with Python 3 and SSH access.
- An SSH user with **sudo** (used only to install `python3-psycopg2`). If the package is already installed, set `sonar_install_psycopg2: false` and sudo is not needed.
- Outbound **TCP 5432** from the VM to the Azure PostgreSQL server (Azure firewall / VNet rule must allow the VM's IP). The playbook checks this first with `wait_for`.
- TLS is enforced by Azure; the playbook uses `ssl_mode: require`.

### 3.2 AAP side
- AAP controller can reach the VM over **SSH (22)**.
- A **Machine credential** (SSH user + key/password, sudo/become) for the VM.

### 3.3 Accounts / secrets
- `pgadmin` password (Flexible Server administrator).
- A **new** password for the `sonar` role (min 8 chars; use a strong one).

### 3.4 Collection in the Execution Environment
The playbook needs the `community.postgresql` collection **inside the EE** (the Python driver is installed on the target VM, not in the EE).

Option A – project-level `collections/requirements.yml` (AAP installs it at project sync; needs Galaxy/Automation Hub access):
```yaml
---
collections:
  - name: community.postgresql
    version: ">=3.4.0"
```

Option B – custom EE (for restricted/offline networks)

`execution-environment.yml` (ansible-builder v3; adjust base image to your AAP version)
```yaml
---
version: 3
images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9:latest
dependencies:
  galaxy: requirements.yml
options:
  package_manager_path: /usr/bin/microdnf
```
```bash
podman login registry.redhat.io
ansible-builder build -t <your-registry>/ee-postgres-sonar:1.0 -f execution-environment.yml
podman push <your-registry>/ee-postgres-sonar:1.0
```

---

## 4. Steps to create everything in AAP

Menu names follow AAP 2.5/2.6 (*Automation Execution*). On 2.4 and earlier use the same names under the left-hand *Resources / Access* menus.

### Step 1 – Organization (skip if you already have one)
**Access Management → Organizations → Create** → name `Platform-Ops`.

### Step 2 – Create the Inventory
**Automation Execution → Infrastructure → Inventories → Create inventory**
- Name: `SonarQube-DEV`
- Organization: `Platform-Ops`
- Click **Create inventory**.

### Step 3 – Create the group
Open `SonarQube-DEV` → **Groups → Create group**
- Name: **`sonarqube_servers`** (must match `hosts:` in the playbook exactly)

### Step 4 – Add the host(s)
Open `SonarQube-DEV` → **Hosts → Create host**
- Name: `t0016vmsq01r01d` (FQDN or IP the controller can resolve/reach)
- Enable the host.
- Variables (optional):
  ```yaml
  ansible_host: t0016vmsq01r01d.<your-domain>   # only if the name above is not resolvable
  ansible_python_interpreter: /usr/bin/python3
  ```
- After creating, open the host → **Groups** tab → associate with `sonarqube_servers`.
  (Alternatively: Group → Hosts → Add existing host.)

For multiple environments, create separate inventories (`SonarQube-TEST`, `SonarQube-PROD`) or add groups, and set `pg_host` as a **group variable** so each environment points to its own PostgreSQL server:
```yaml
# Group variables for sonarqube_servers in SonarQube-DEV
pg_host: t0016-pgqlsq02r01-d.postgres.database.azure.com
```

> **Dynamic option:** if the VM is in Azure, you can instead add an *Inventory Source* of type **Microsoft Azure Resource Manager** and filter by tag/resource group, then use a `keyed_groups`/compose rule to put the VM into `sonarqube_servers`.

### Step 5 – Machine credential (SSH to the VM)
**Automation Execution → Infrastructure → Credentials → Create credential**
- Name: `SonarQube VM SSH`
- Credential type: **Machine**
- Username: e.g. `sonar` or an admin user
- Password or SSH private key
- Privilege escalation method: `sudo`, and username `root` (+ password if required)

### Step 6 – Custom Credential Type for the database passwords
**Credential Types → Create credential type**
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

### Step 7 – Credential for the database passwords
**Credentials → Create credential**
- Name: `SonarQube PG Secrets – DEV`
- Credential type: `PostgreSQL SonarQube Secrets`
- Enter both passwords. Create one per environment.

### Step 8 – (If using Option B) Add the Execution Environment
**Infrastructure → Execution Environments → Create**
- Name: `ee-postgres-sonar`
- Image: `<your-registry>/ee-postgres-sonar:1.0`
- Pull: *Only pull the image if not present*
- Registry credential if the registry is private.

### Step 9 – Create the Project
Push `sonarqube_db_setup.yml` (and `collections/requirements.yml` for Option A) to a Git repo.

**Automation Execution → Projects → Create project**
- Name: `SonarQube DB Setup`
- Organization: `Platform-Ops`
- Source control type: Git
- Source control URL, branch, and SCM credential
- Execution environment: default, or `ee-postgres-sonar`
- Enable **Update revision on launch**

Wait for the project status to turn **Successful**.

### Step 10 – Create the Job Template
**Automation Execution → Templates → Create template → Create job template**

| Field | Value |
|---|---|
| Name | `SonarQube – PostgreSQL DB Setup` |
| Job type | Run |
| Inventory | `SonarQube-DEV` |
| Project | `SonarQube DB Setup` |
| Playbook | `sonarqube_db_setup.yml` |
| Execution environment | default or `ee-postgres-sonar` |
| Credentials | **two**: `SonarQube VM SSH` (Machine) **and** `SonarQube PG Secrets – DEV` (custom) |
| Limit | optional, e.g. `t0016vmsq01r01d` |
| Verbosity | 0 (Normal) |
| Options | Enable privilege escalation ✔ (needed to install psycopg2); Prompt on launch for Variables, Limit |

**Variables** (override as needed):
```yaml
pg_host: t0016-pgqlsq02r01-d.postgres.database.azure.com
pg_port: 5432
pg_admin_user: pgadmin
sonar_db_name: sonar
sonar_db_user: sonar
sonar_schema: sonar
sonar_install_psycopg2: true
sonar_role_attrs: "LOGIN,CREATEDB,NOSUPERUSER,NOCREATEROLE,NOREPLICATION,NOBYPASSRLS"
sonar_drop_existing_db: false
sonar_drop_confirm: ""
```

> A job template accepts multiple credentials as long as they are of different types, which is the case here (Machine + custom).

### Step 11 – (Optional) Add a Survey
Open the template → **Survey → Create survey question**:

| Question | Variable | Type | Default |
|---|---|---|---|
| PostgreSQL server FQDN | `pg_host` | Text | `t0016-pgqlsq02r01-d.postgres.database.azure.com` |
| Drop existing DB first? | `sonar_drop_existing_db` | Multiple choice (`true`/`false`) | `false` |
| Type DB name to confirm drop | `sonar_drop_confirm` | Text | *(blank)* |

Switch the survey **On**. Use RBAC (Step 12) so only senior operators can run it with the drop option.

### Step 12 – Set permissions (RBAC)
Template → **Team Access / User Access → Add roles**
- Operators: **Execute**
- Admins: **Admin**
Give the credential roles **Use** only to the people/teams who may run the job.

### Step 13 – Launch
1. Open the template → **Launch**.
2. Fresh install: keep `sonar_drop_existing_db=false`.
3. Rebuild (data loss!): `sonar_drop_existing_db=true` and `sonar_drop_confirm=sonar`.
4. Expected output at the end:
   `OK: sonar@sonar, schema sonar, encoding UTF8, collate en_US.UTF-8`
   followed by the JDBC settings to use in SonarQube.
5. A second run should show no changes for the create tasks.

### Step 14 – (Optional) Workflow and notifications
- **Templates → Create workflow job template**: `DB setup → SonarQube install → SonarQube start`.
- Add **Notifications** (email/Teams/Slack) on success/failure.
- Add a **Schedule** only if you want periodic drift correction (not required).

---

## 5. Manual verification (optional)

From the VM:
```bash
psql -h t0016-pgqlsq02r01-d.postgres.database.azure.com -p 5432 -U sonar -d sonar -W
```
```sql
SELECT session_user, current_user, current_database(), current_schema();
\dn+
\l+ sonar
\du sonar
```

## 6. Configure SonarQube (`sonar.properties`)

```properties
sonar.jdbc.username=sonar
sonar.jdbc.password=<sonar password from AAP credential>
sonar.jdbc.url=jdbc:postgresql://t0016-pgqlsq02r01-d.postgres.database.azure.com:5432/sonar?sslmode=require&currentSchema=sonar
```
Restart SonarQube. On first start it creates its tables in the `sonar` schema.

## 7. Rollback

Run the job with `sonar_drop_existing_db=true` / `sonar_drop_confirm=sonar` (take a `pg_dump` first). To remove the role afterwards, as `pgadmin`:
```sql
DROP ROLE sonar;
```

## 8. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `skipping: no hosts matched` | Inventory has no group named `sonarqube_servers`, or the host isn't in it, or the Limit excludes it. |
| `UNREACHABLE` / SSH timeout | Machine credential wrong, or controller/execution node can't reach the VM on port 22. |
| `Missing sudo password` / `become` failed | Enable privilege escalation on the template and set the become method/password in the Machine credential, or set `sonar_install_psycopg2: false`. |
| `Failed to import the required Python library (psycopg2) on <host>` | Package not installed for the Python interpreter Ansible uses on the VM. Install `python3-psycopg2` or set `ansible_python_interpreter` to the interpreter that has it. |
| `wait_for` timeout on port 5432 | Azure firewall / VNet rule doesn't allow the VM's IP, or DNS can't resolve `pg_host`. |
| SSL errors | Keep `pg_ssl_mode: require`; for `verify-full` place the CA cert on the VM and add `ca_cert`. |
| `permission denied to create database` | `sonar_role_attrs` is missing `CREATEDB`. |
| `permission denied for database postgres` when creating schema | Schema must be created while connected to the `sonar` DB (the playbook does this). |
| `pgadmin` can't connect to `sonar` DB afterwards | CONNECT revoked from PUBLIC; keep the admin in `sonar_db_connect_roles`. |
| `Changing database collate/encoding is not supported` | DB exists with different encoding/collation. Drop and recreate, or align variables. |
| `couldn't resolve module/action 'community.postgresql...'` | Collection not available in the EE (see 3.4). |

## 9. Security checklist

- [ ] Rotate the password shown in the recording (`Son@rD3`).
- [ ] Passwords exist only in the AAP credential (encrypted), never in Git or plain Extra Variables.
- [ ] Restrict who can edit/launch the template; limit the drop survey option.
- [ ] Remove `REPLICATION`/`BYPASSRLS` unless a real need exists.
- [ ] Prefer `sslmode=verify-full` with the Azure CA bundle for production.
- [ ] Back up (`pg_dump` or Azure backup) before any drop/rebuild.
