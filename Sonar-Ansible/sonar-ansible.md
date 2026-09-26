# Install SonarQube on an Azure Ubuntu VM with Ansible

This playbook is launched from Red Hat Ansible Automation Platform (AAP). AAP runs it in an execution environment and connects over SSH to the remote Ubuntu Azure VM in the `sonarqube` inventory group. SonarQube and PostgreSQL are installed on that VM, not on AAP. The play changes packages, kernel settings, users, files under `/opt`, and systemd services on the VM. Use a fresh or deliberately prepared VM. The playbook uses Java 17 and SonarQube 9.9.4; verify current SonarQube support requirements before changing either version.

## 1. Prepare the AAP project and execution environment

Add this directory to a source-control repository accessible to AAP, including `sonar-ansible.yml` and the encrypted `sonar-secrets.yml` described below. Ensure the execution environment selected for the job template has the `community.postgresql` collection installed. The playbook installs PostgreSQL and `python3-psycopg2` on the Azure VM, where the database modules run.

Create or select an AAP project that syncs this repository. In the AAP inventory, add the Azure VM to a group named `sonarqube`; set its SSH address and remote user as host variables. Attach an SSH Machine credential to the job template, with privilege escalation configured for the VM if sudo requires a password. Attach a Vault credential containing the password used to encrypt `sonar-secrets.yml`.

## 2. Prepare the Azure VM

The target must be an Ubuntu VM reachable over SSH from the AAP execution environment, have Python available, and allow the SSH user to become root with `sudo`. The playbook installs Java 17, PostgreSQL, and the PostgreSQL Python adapter on this VM.

The inventory host should have the equivalent of these variables:

```ini
[sonarqube]
sonar01 ansible_host=192.0.2.10 ansible_user=azureuser
```

Replace the example address and SSH user with your VM's values. Use its private IP if the AAP execution environment can reach the Azure virtual network; otherwise use an approved public IP. Ensure the Azure NSG and VM firewall allow SSH from the AAP execution environment.

## 3. Store the database password in Ansible Vault

On a trusted workstation with Ansible installed, create `sonar-secrets.yml` in the same directory as the playbook:

```sh
ansible-vault create sonar-secrets.yml
```

Enter this YAML, replacing the placeholder with a unique secret of at least 20 characters:

```yaml
db_password: "replace-with-a-unique-secret"
```

Commit the encrypted file to the AAP project's source repository. Do not commit the plaintext password or the Vault password. AAP uses the attached Vault credential to decrypt the file when the job runs. The playbook loads this file automatically.

## 4. Configure and launch an AAP job template

Create a job template with the synced project, the `sonarqube` inventory, and `sonar-ansible.yml` as the playbook. Attach the SSH Machine credential and Vault credential, and select an execution environment that contains `community.postgresql`. Launch the job; no `-e @sonar-secrets.yml` argument is needed.

For a preview, enable check mode and diff in the job template. Check mode does not prove that downloads, database modules, or service startup will succeed.

## 5. Allow access and verify the service

In the Azure network security group, allow inbound TCP port 9000 only from the trusted client or network that needs the web UI. Do not expose the SonarQube port broadly to the internet. Also ensure the VM's host firewall permits that traffic if one is enabled.

On the managed host, check the service and recent logs:

```sh
sudo systemctl status sonarqube
sudo journalctl -u sonarqube -n 100 --no-pager
```

From a machine that can reach the host, check the configured web port (9000 by default):

```sh
curl -I http://192.0.2.10:9000
```

Review SonarQube's application logs under `/opt/sonarqube/logs` if the service does not become ready.


Mahesh Annapureddy
