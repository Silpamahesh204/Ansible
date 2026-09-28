# SonarQube Installation and Configuration on RHEL 8

This runbook consolidates the supplied server, Java, SonarQube, and PostgreSQL notes into a manual installation procedure. The notes record SonarQube Enterprise `10.1.0.73491`, OpenJDK 17, RHEL 8, and an external Azure PostgreSQL server. This is a transcription of a historical deployment, not a recommendation to install that older SonarQube release today. Confirm the currently supported SonarQube, Java, and PostgreSQL versions before building or upgrading a production system.

## Important: Separate procedures

The existing `sonar-ansible.yml` playbook is a different deployment: it targets Ubuntu, installs local PostgreSQL, and configures SonarQube `9.9.4`. Do not treat this RHEL 8 procedure and that playbook as interchangeable, or run both against the same host.

The recordings contain redacted credentials and blurred details. This guide deliberately uses placeholders. Confirm the real hostnames, network access, disk layout, database/schema, and approved SonarQube download source with the system owners before proceeding. Never commit passwords or credential-bearing download URLs.

## 1. Confirm prerequisites

Before making changes, confirm:

- The target is the intended RHEL 8 VM and you have an approved SSH account with `sudo` access.
- The VM can reach the approved SonarQube archive source and the PostgreSQL server.
- Azure PostgreSQL firewall/network rules allow this VM to connect on TCP 5432; the VM's outbound policy permits it.
- You have the database name, schema, application username, and password from the database owner. Do not use the PostgreSQL server administrator account as SonarQube's application account.
- You have enough verified space for the application, Elasticsearch data, and temporary files.
- The SonarQube release and database version are compatible according to the vendor's documentation.

Start with a read-only inventory. Device names and sizes below are examples from the recording, not safe assumptions for another VM.

```sh
cat /etc/redhat-release
lsblk -f
df -hT
sudo pvs
sudo vgs
sudo lvs
```

## 2. Review storage before changing it

The notes show `/dev/sdc` as a 256 GB disk and describe creating `/dev/sdc1` as an approximately 131.1 GiB partition, formatting it as ext4, and mounting it at `/apps`. They also show SonarQube installed under `/opt/apps`. These are different paths: mounting `/apps` does not provide space to `/opt/apps`. Decide which path should hold the application and data before creating partitions or directories.

### Optional: Create and mount an application filesystem

Only do this if the storage owner confirms the selected disk is empty, the device name is correct, and the intended partition size and mount point are agreed. **Partitioning and `mkfs` can destroy data. Stop if `lsblk`, `fdisk -l`, or the existing mount information differs from the approved plan.** The recorded `/dev/sdc1` size did not use the full 256 GB disk.

If `/dev/sdc` is verified for this purpose, create the approved partition using the site's storage procedure, then verify it before formatting:

```sh
sudo fdisk -l /dev/sdc
sudo fdisk /dev/sdc
# Create the approved Linux partition, then write the partition table.
sudo lsblk -f /dev/sdc
```

After confirming the new partition is the intended empty device, format and mount it. Replace `/dev/sdc1` and `/apps` if the approved plan specifies different values.

```sh
sudo mkfs.ext4 /dev/sdc1
sudo mkdir -p /apps
sudo mount /dev/sdc1 /apps
sudo blkid /dev/sdc1
df -hT /apps
```

Use the UUID reported by `blkid` to add a persistent entry to `/etc/fstab`, for example:

```fstab
UUID=<verified-filesystem-uuid> /apps ext4 defaults 0 2
```

Validate the entry before rebooting:

```sh
sudo findmnt --verify --verbose
sudo mount -a
findmnt /apps
```

If the desired mount point is `/opt/apps`, prepare and mount that location instead; do not assume that the recorded `/apps` mount is used by the installation.

### Optional: Extend the root logical volume

The recording's root-storage outputs conflict: one shows the root logical volume as 2 GiB, while the `lvextend` output says it grew from 32 GiB to 160 GiB. The procedure also grows `/dev/sda2`, so it must not be copied blindly. Use this only after the administrator confirms the current disk, partition, physical volume, free space, and target root size.

The recorded operation was to grow partition 2 on `/dev/sda` and add 128 GiB to `/dev/mapper/rootvg-rootlv`. After growing the partition, verify that the LVM physical volume has detected the new space. If it has not, the LVM administrator must resize the PV (for example, `sudo pvresize /dev/sda2`) before extending the LV. Only then, and only if the requested additional size is confirmed, use the site's approved equivalent of:

```sh
sudo growpart /dev/sda 2
sudo pvs
sudo vgs
sudo lvs
sudo lvextend -r -L +128G /dev/mapper/rootvg-rootlv
df -hT /
```

Do not run these commands if the device map or available extents differ from the reviewed plan. The `-r` option asks LVM to resize the filesystem as part of the logical-volume extension.

## 3. Install and verify Java 17

The notes show OpenJDK 17 installed from the RHEL package repositories. Install the approved Java 17 package and check the active runtime:

```sh
sudo dnf install -y java-17-openjdk
java -version
```

The recording does not show a `java -version` check; confirm that the output is Java 17 before continuing.

## 4. Set kernel and user limits

The recorded SonarQube host settings are `vm.max_map_count=524288`, `fs.file-max=131072`, `nofile=131072`, and `nproc=8192`. Confirm these values are appropriate for the selected SonarQube version and host policy.

Create a dedicated sysctl configuration file so the values persist across reboot:

```sh
sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null <<'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF
sudo sysctl --system
sysctl vm.max_map_count fs.file-max
```

Add the account limits using the site's approved limits configuration method. The recorded entries were:

```sh
sudo tee /etc/security/limits.d/99-sonarqube.conf >/dev/null <<'EOF'
sonar - nofile 131072
sonar - nproc 8192
EOF
```

These PAM limits may not apply to a process started by systemd. If SonarQube will run as a systemd service, configure and verify `LimitNOFILE` and `LimitNPROC` in that service as well. The notes show a manual `sonar.sh start`, not a complete systemd service setup.

The recording also disables IPv6. Disabling IPv6 is not shown as a SonarQube requirement; do not apply those host-wide settings unless required by the organization's network policy.

## 5. Create or verify the PostgreSQL database

The recorded application uses an external Azure PostgreSQL server, database `sonar`, application user `sonar`, and schema `sonar`. Verify these values with the database owner rather than assuming the transcript is current. Provision the database, login, and schema through the approved DBA process; the application login should have only the permissions SonarQube needs. Do not store credentials in shell history, source control, or this guide.

From the SonarQube host, verify DNS and network reachability. Use SSL if required by the Azure PostgreSQL configuration; `sslmode=require` is shown in this example and should be retained for a server requiring TLS.

```sh
getent hosts <postgres-server-fqdn>
psql "host=<postgres-server-fqdn> port=5432 dbname=<database-name> user=<application-user> sslmode=require" -c 'select current_database(), current_user, version();'
```

`psql` prompts for the application user's password. If the connection fails, check the server firewall, private DNS/VNet routing, credentials, TLS requirements, and database/schema grants with the database owner.

## 6. Install SonarQube

The recording uses an Enterprise archive named `sonarqube-10.1.0.73491.zip`, downloaded from an internal Artifactory location. The exact credential-bearing URL is omitted. Obtain the approved archive and license through the organization's authorized source; do not put credentials in the command line or shell history.

The later configuration and system information identify `/opt/apps/sonarqube-10.1.0.73491` as the home path. The recording also mentions `/opt/sonar` in one extraction output, so verify the intended path and keep it consistent. The following uses `/opt/apps`:

```sh
getent group sonar >/dev/null || sudo groupadd sonar
id sonar >/dev/null 2>&1 || sudo useradd -m -g sonar -s /bin/bash sonar
id sonar
sudo mkdir -p /opt/apps
sudo chown sonar:sonar /opt/apps
```

As the `sonar` account, place the approved ZIP in `/opt/apps`, extract it, and verify ownership and the resulting directory:

```sh
sudo -iu sonar
cd /opt/apps
unzip sonarqube-10.1.0.73491.zip
ls -ld /opt/apps/sonarqube-10.1.0.73491
```

If the archive was extracted as root, correct ownership of the extracted directory before starting SonarQube:

```sh
exit
sudo chown -R sonar:sonar /opt/apps/sonarqube-10.1.0.73491
```

Create the data and temporary directories recorded for this deployment, and grant ownership to the service account:

```sh
sudo mkdir -p /var/sonar/data /var/sonar/temp
sudo chown -R sonar:sonar /var/sonar
```

## 7. Configure `sonar.properties`

Edit `/opt/apps/sonarqube-10.1.0.73491/conf/sonar.properties` as the `sonar` account. Set the actual database values; angle-bracket placeholders below must be replaced. Keep the password out of source control and restrict access to this file.

```properties
sonar.jdbc.username=<application-user>
sonar.jdbc.password=<application-password>
sonar.jdbc.url=jdbc:postgresql://<postgres-server-fqdn>:5432/<database-name>?currentSchema=<schema-name>&sslmode=require
sonar.path.data=/var/sonar/data
sonar.path.temp=/var/sonar/temp
```

The recorded JDBC URL uses `currentSchema=sonar` and does not show an SSL parameter. Confirm the schema name and TLS requirement with the database owner. If TLS is not required or the provider specifies a different connection policy, use the verified JDBC URL instead. Set file permissions so only the service account and authorized administrators can read the database password.

## 8. Start SonarQube and check health

Start it as the `sonar` account, not root:

```sh
sudo -iu sonar
cd /opt/apps/sonarqube-10.1.0.73491/bin/linux-x86-64
./sonar.sh start
./sonar.sh status
```

Inspect logs if startup is delayed or fails:

```sh
cd /opt/apps/sonarqube-10.1.0.73491/logs
tail -n 100 sonar.log web.log ce.log es.log
```

Check local health and system information. The recorded health request returned `GREEN`; the password in the original request is redacted here.

```sh
curl --fail --silent --show-error http://localhost:9000/api/system/health
curl --fail --silent --show-error http://localhost:9000/api/system/info
```

Confirm health is `GREEN`, the version and edition are the expected ones, the database is the intended PostgreSQL server, and search is healthy. The SonarQube UI/API may require authentication depending on local configuration.

## 9. Restrict network access and plan service management

The notes show the web process responding on localhost port 9000 and separately mention an HTTPS address. They do not document how HTTPS is configured. Do not assume SonarQube itself terminates TLS. Prefer an approved reverse proxy/load balancer for HTTPS, and restrict inbound access to trusted networks. Do not expose port 9000 directly to the public internet. Coordinate NSG, host firewall, proxy, and DNS changes with the network owner.

The transcription confirms a manual start and a health check, but does not establish that SonarQube starts after reboot or is supervised by systemd. Before considering the installation production-ready, configure an approved systemd service (running as `sonar` with the required limits), enable it, and test stop/start and reboot recovery. Follow the service-management guidance for the exact SonarQube release.

## 10. Run the Ansible playbook

The companion `sonarqube-rhel8.yml` playbook automates Java installation, the SonarQube service account, kernel and process limits, archive extraction, configuration, systemd startup, and the health check. It intentionally does not repartition disks, extend LVM, create the Azure PostgreSQL database/schema, or change firewalls. Complete those steps through the approved infrastructure and DBA processes first.

Create an inventory for the RHEL 8 host, replacing the example address and SSH account:

```ini
[sonarqube_rhel8]
sonar01 ansible_host=192.0.2.10 ansible_user=azureuser
```

Create the encrypted secret file in the playbook directory:

```sh
ansible-vault create sonar-secrets.yml
```

Enter the database password as YAML. Optional artifact-repository credentials and API health-check credentials can also be stored here if required:

```yaml
sonar_db_password: "replace-with-the-database-application-password"
# sonar_download_username: "artifact-reader"
# sonar_download_password: "replace-with-artifact-token"
# sonar_api_username: "health-check-user"
# sonar_api_password: "replace-with-api-token"
```

Run the playbook with the approved archive URL and PostgreSQL hostname. The archive URL must not contain embedded credentials. Add the archive's SHA-256 digest if one is available from the trusted source.

```sh
ansible-playbook -i inventory.ini sonarqube-rhel8.yml \\
	--ask-vault-pass \\
	-e '{"sonar_archive_url":"https://<approved-artifact-source>/sonarqube-10.1.0.73491.zip","sonar_postgres_host":"<postgres-server-fqdn>"}' \\
	-e 'sonar_archive_sha256=<verified-sha256>'
```

The playbook uses the PostgreSQL defaults recorded in the notes: port `5432`, database `sonar`, schema `sonar`, and application user `sonar`. Override them with extra variables if the DBA confirms different values. The database and schema must already exist, and the application user must have the required permissions. AAP users can put the non-secret connection/download values in job-template extra variables and supply the encrypted secrets file through an Ansible Vault credential.

## Items to verify from the original system

- The VM hostname, IP address, SSH access, and whether the HTTPS endpoint belongs to a proxy.
- The intended disk and partition sizes. The `/dev/sdc` notes create about 131 GiB on a 256 GB disk; `/apps` and `/opt/apps` are not the same mount point.
- The actual `/dev/sda2` and LVM sizes before any root-volume expansion; the recorded outputs disagree.
- The PostgreSQL FQDN, database, schema, TLS policy, firewall, and application-user permissions.
- The authorized SonarQube Enterprise archive, license, version support, and deployment path.
- Whether IPv6 changes are required by policy; they are not required by the installation steps shown.