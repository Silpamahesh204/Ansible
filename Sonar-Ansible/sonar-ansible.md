# SonarQube Configuration with Ansible

This playbook installs SonarQube on Debian/Ubuntu hosts and configures a local PostgreSQL database. Run it only on a fresh or deliberately prepared host; it changes packages, users, files under `/opt`, and systemd services.

## 1. Prepare the control node

Install Ansible and the PostgreSQL collection used by the playbook:

```sh
ansible-galaxy collection install community.postgresql
```

## 2. Prepare the managed host

The target must be reachable over SSH with Python available, use an apt-based Linux distribution, and allow the SSH user to become root with `sudo`. The playbook installs Java 17 and PostgreSQL locally. The `community.postgresql` modules also need the PostgreSQL Python adapter available to Ansible on the managed host (for Debian/Ubuntu, install `python3-psycopg2`).

Create an inventory file, for example `inventory.ini`:

```ini
[sonarqube]
sonar01 ansible_host=192.0.2.10 ansible_user=ubuntu
```

Replace the example address and SSH user with your host's values. Test connectivity and privilege escalation:

```sh
ansible sonarqube -i inventory.ini -m ping
ansible sonarqube -i inventory.ini -b -m command -a 'whoami'
```

The second command should report `root`.

## 3. Set deployment variables securely

Review the variables at the top of `sonar-ansible.yml`, especially the SonarQube version, install directory, port, and database settings. Do not use the example database password currently in the playbook. Supply a unique password through Ansible Vault or another secret manager. For example, create an encrypted vars file:

```sh
ansible-vault create sonar-secrets.yml
```

Put this YAML in the encrypted file, replacing the placeholder with a strong secret:

```yaml
db_password: "replace-with-a-unique-secret"
```

Pass the file at run time with `-e @sonar-secrets.yml`; Ansible Vault will prompt for its decryption password.

## 4. Check the install-directory task before running

The current playbook creates `/opt/sonarqube` before trying to rename the extracted versioned directory to that path. Its rename task is guarded by `creates: /opt/sonarqube`, so it is skipped after the directory has already been created. Correct this ordering (or install directly into the final directory) before the first run; otherwise later configuration tasks will not find `conf/sonar.properties` under the expected path.

## 5. Run the playbook

After correcting the install-directory ordering, run:

```sh
ansible-playbook -i inventory.ini Sonar-Ansible/sonar-ansible.yml \
	-e @sonar-secrets.yml --ask-vault-pass
```

For an initial review without making changes, add `--check --diff`. Check mode is a preview and does not prove that downloads, database modules, or service startup will succeed.

## 6. Verify the service

On the managed host, check the service and recent logs:

```sh
sudo systemctl status sonarqube
sudo journalctl -u sonarqube -n 100 --no-pager
```

From a machine that can reach the host, check the configured web port (9000 by default):

```sh
curl -I http://192.0.2.10:9000
```

Allow the port through the host firewall and any cloud network rules only for the clients that need access. Review SonarQube's application logs under `/opt/sonarqube/logs` if the service does not become ready.
