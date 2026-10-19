Understood — you are migrating the SonarQube database from one Azure Database for PostgreSQL server to another Azure Database for PostgreSQL server.

You can do this with pg_dump and pg_restore from a Linux VM that can connect to both Azure servers. This preserves the SonarQube database contents without moving the SonarQube application installation itself.

The key requirements are:
- The target database must be empty and compatible with your SonarQube version.
- Both Azure PostgreSQL servers must allow network access from the migration host.
- SonarQube should be stopped during the final backup and cutover to prevent database changes during migration.
Exact migration commands
Replace the placeholders with the actual Azure server names and credentials. The examples assume both are Azure PostgreSQL Flexible Servers and the database is named sonarqube.
1. Stop SonarQube
sudo systemctl stop sonarqube


2. Back up from the source Azure PostgreSQL server
pg_dump \
  -h SOURCE_SERVER.postgres.database.azure.com \
  -U SOURCE_USER \
  -d sonarqube \
  -Fc \
  -f /tmp/sonarqube.dump


3. Create an empty database on the target server
Connect to the target server's postgres database using an administrator account:
psql "host=TARGET_SERVER.postgres.database.azure.com port=5432 dbname=postgres user=TARGET_ADMIN sslmode=require"


Then execute:
CREATE DATABASE sonarqube;


If the database already exists, do not run this statement; verify that it is empty and approved for restoration.
4. Restore to the target Azure PostgreSQL server
pg_restore \
  -h TARGET_SERVER.postgres.database.azure.com \
  -U TARGET_USER \
  -d sonarqube \
  --no-owner \
  --no-acl \
  --exit-on-error \
  -v /tmp/sonarqube.dump


Azure's official guide covers dump/restore workflows, database preparation, and role considerations. 

Microsoft Learn
+1



5. Update SonarQube
Edit sonar.properties to use the target Azure server:
sonar.jdbc.url=jdbc:postgresql://TARGET_SERVER.postgres.database.azure.com:5432/sonarqube?sslmode=require
sonar.jdbc.username=TARGET_USER
sonar.jdbc.password=YOUR_PASSWORD


Then start SonarQube:
sudo systemctl start sonarqube
sudo systemctl status sonarqube


Check SonarQube logs and verify the projects and analysis history before retiring the source server.
Before you execute
Please confirm these two details so I can adjust the commands correctly:
1. Are both servers Azure PostgreSQL Flexible Server?
2. Are the PostgreSQL major versions the same, or is the target version different?