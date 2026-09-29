The script install_sonarqube.sh automates every step in the runbook. It passes a bash syntax check, but I haven't run it on a real server, so try it on a test VM first.

How to run it

bash
export SONAR_DB_PASSWORD='...'
export SONAR_ZIP_URL='https://<internal-artifactory>/.../sonarqube-10.1.0.73491.zip'
export ARTIFACTORY_USER='...' ARTIFACTORY_PASS='...'   # if the URL needs auth
sudo -E ./install_sonarqube.sh

Choices I made

Secrets: Passwords come from environment variables, so none are hardcoded in the script.
Destructive steps: Partitioning /dev/sdc and resizing the root volume are off by default. Turn them on with DO_DISK=yes and DO_GROW_ROOT=yes. The disk step refuses to run if the disk already has partitions.
Install path: It installs into /apps (the new disk), which resolves the /apps vs /opt/apps mix-up in your notes. Change INSTALL_ROOT if you want /opt/apps.
Data and temp: These go under /apps/sonar-data, not /var, to avoid filling the 8G volume.
Systemd: It creates a systemd service so SonarQube restarts on reboot.
Re-runs: It is safe to re-run, because sysctl and limits lines are added only once and an existing extract is not re-downloaded.
Final check: It polls /api/system/status until SonarQube reports UP.

Still manual: the PostgreSQL schema must exist beforehand, and you still need to apply the license, change the admin password, and open the firewall port.

