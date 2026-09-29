#!/usr/bin/env bash
#
# SonarQube 10.1 Enterprise installer for RHEL 8
# Consolidated from the Linux server, Java 17, and Install Sonar notes.
#
# Usage:
#   export SONAR_DB_PASSWORD='...'
#   export SONAR_ZIP_URL='https://<internal-artifactory>/.../sonarqube-10.1.0.73491.zip'
#   export ARTIFACTORY_USER='...' ARTIFACTORY_PASS='...'   # if the URL needs auth
#   sudo -E ./install_sonarqube.sh
#
# The disk and root-resize steps are destructive, so they are OFF by default:
#   DO_DISK=yes DO_GROW_ROOT=yes sudo -E ./install_sonarqube.sh
#
set -euo pipefail

########################  VARIABLES  ########################
SONAR_VERSION="${SONAR_VERSION:-10.1.0.73491}"
SONAR_USER="${SONAR_USER:-sonar}"

# Install root. Notes mixed /apps and /opt/apps; pick ONE. Default: the new disk.
INSTALL_ROOT="${INSTALL_ROOT:-/apps}"
# Data/temp on the big disk, NOT /var (only 8G on this host).
SONAR_DATA_DIR="${SONAR_DATA_DIR:-${INSTALL_ROOT}/sonar-data/data}"
SONAR_TEMP_DIR="${SONAR_TEMP_DIR:-${INSTALL_ROOT}/sonar-data/temp}"

# Database (schema must already exist)
DB_HOST="${DB_HOST:-t0016-psqlsq01r01-d.postgres.database.azure.com}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-sonar}"
DB_SCHEMA="${DB_SCHEMA:-sonar}"
DB_USER="${DB_USER:-sonar}"
: "${SONAR_DB_PASSWORD:?Set SONAR_DB_PASSWORD}"
: "${SONAR_ZIP_URL:?Set SONAR_ZIP_URL}"

# Optional destructive steps
DO_DISK="${DO_DISK:-no}"            # partition + format + mount a new disk at INSTALL_ROOT
DATA_DISK="${DATA_DISK:-/dev/sdc}"
DO_GROW_ROOT="${DO_GROW_ROOT:-no}"  # growpart + lvextend on the root LV
ROOT_DISK="${ROOT_DISK:-/dev/sda}"
ROOT_PART_NUM="${ROOT_PART_NUM:-2}"
ROOT_LV="${ROOT_LV:-/dev/mapper/rootvg-rootlv}"
ROOT_GROW_SIZE="${ROOT_GROW_SIZE:-+128G}"

DISABLE_IPV6="${DISABLE_IPV6:-no}"  # environment policy, not a SonarQube requirement

SONAR_HOME="${INSTALL_ROOT}/sonarqube-${SONAR_VERSION}"
#############################################################

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo -E ./install_sonarqube.sh)"

append_once() {  # append_once <line> <file>
  grep -qxF "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

set_prop() {     # set_prop <key> <value> <file>  (removes active line, appends new)
  sed -i "/^$1=/d" "$3"
  printf '%s=%s\n' "$1" "$2" >> "$3"
}

step_disk() {
  [[ "$DO_DISK" == "yes" ]] || { log "Skipping disk setup (DO_DISK=no)"; return; }
  log "Creating ${INSTALL_ROOT} on ${DATA_DISK}"
  [[ -b "$DATA_DISK" ]] || die "$DATA_DISK not found"
  if lsblk -n -o TYPE "$DATA_DISK" | grep -q part; then
    die "$DATA_DISK already has partitions; refusing to overwrite"
  fi
  yum install -y parted >/dev/null
  parted -s "$DATA_DISK" mklabel gpt mkpart primary ext4 0% 100%
  partprobe "$DATA_DISK"; sleep 2
  local part="${DATA_DISK}1"
  mkfs.ext4 -F "$part"
  mkdir -p "$INSTALL_ROOT"
  local uuid; uuid=$(blkid -s UUID -o value "$part")
  append_once "UUID=${uuid} ${INSTALL_ROOT} ext4 defaults 0 2" /etc/fstab
  mount -a
  chmod 755 "$INSTALL_ROOT"
  df -h "$INSTALL_ROOT"
}

step_grow_root() {
  [[ "$DO_GROW_ROOT" == "yes" ]] || { log "Skipping root resize (DO_GROW_ROOT=no)"; return; }
  log "Growing root LV"
  command -v growpart >/dev/null || yum install -y cloud-utils-growpart
  LC_ALL=en_US.UTF-8 growpart "$ROOT_DISK" "$ROOT_PART_NUM" || warn "growpart reported no change"
  pvresize "${ROOT_DISK}${ROOT_PART_NUM}"
  lvextend --size "$ROOT_GROW_SIZE" --resizefs "$ROOT_LV"
  lsblk "$ROOT_DISK"
}

step_user() {
  log "Ensuring user ${SONAR_USER} exists"
  id "$SONAR_USER" &>/dev/null || useradd -m -s /bin/bash "$SONAR_USER"
}

step_kernel_limits() {
  log "Kernel parameters and limits"
  append_once "vm.max_map_count=524288" /etc/sysctl.conf
  append_once "fs.file-max=131072"      /etc/sysctl.conf
  if [[ "$DISABLE_IPV6" == "yes" ]]; then
    append_once "net.ipv6.conf.all.disable_ipv6 = 1"     /etc/sysctl.conf
    append_once "net.ipv6.conf.default.disable_ipv6 = 1" /etc/sysctl.conf
    append_once "net.ipv6.conf.lo.disable_ipv6 = 1"      /etc/sysctl.conf
  fi
  sysctl -p >/dev/null
  append_once "${SONAR_USER} - nofile 131072" /etc/security/limits.conf
  append_once "${SONAR_USER} - nproc 8192"    /etc/security/limits.conf
  grep -q '^CONFIG_SECCOMP=y' "/boot/config-$(uname -r)" \
    || warn "SECCOMP not enabled in kernel; Elasticsearch may need bootstrap.system_call_filter=false"
}

step_java() {
  log "Installing Java 17"
  yum install -y java-17-openjdk unzip
  java -version
}

step_download() {
  log "Downloading and extracting SonarQube ${SONAR_VERSION}"
  mkdir -p "$INSTALL_ROOT" "$SONAR_DATA_DIR" "$SONAR_TEMP_DIR"
  local zip="${INSTALL_ROOT}/sonarqube-${SONAR_VERSION}.zip"
  if [[ ! -d "$SONAR_HOME" ]]; then
    local auth=()
    [[ -n "${ARTIFACTORY_USER:-}" ]] && auth=(-u "${ARTIFACTORY_USER}:${ARTIFACTORY_PASS:-}")
    curl -fL "${auth[@]}" -o "$zip" "$SONAR_ZIP_URL"
    unzip -q "$zip" -d "$INSTALL_ROOT"
    rm -f "$zip"
  else
    warn "$SONAR_HOME already exists; skipping download"
  fi
  chown -R "${SONAR_USER}:${SONAR_USER}" "$SONAR_HOME" "${INSTALL_ROOT}/sonar-data"
}

step_config() {
  log "Writing sonar.properties"
  local f="${SONAR_HOME}/conf/sonar.properties"
  cp -n "$f" "${f}.orig"
  set_prop sonar.jdbc.username "$DB_USER" "$f"
  set_prop sonar.jdbc.password "$SONAR_DB_PASSWORD" "$f"
  set_prop sonar.jdbc.url "jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?currentSchema=${DB_SCHEMA}" "$f"
  set_prop sonar.path.data "$SONAR_DATA_DIR" "$f"
  set_prop sonar.path.temp "$SONAR_TEMP_DIR" "$f"
  chown "${SONAR_USER}:${SONAR_USER}" "$f"
  chmod 640 "$f"
}

step_systemd() {
  log "Creating systemd unit"
  cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube ${SONAR_VERSION}
After=network.target

[Service]
Type=forking
User=${SONAR_USER}
Group=${SONAR_USER}
ExecStart=${SONAR_HOME}/bin/linux-x86-64/sonar.sh start
ExecStop=${SONAR_HOME}/bin/linux-x86-64/sonar.sh stop
PIDFile=${SONAR_HOME}/bin/linux-x86-64/SonarQube.pid
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=300
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now sonarqube
}

step_verify() {
  log "Waiting for SonarQube to report UP (up to 5 min)"
  local i status
  for i in $(seq 1 60); do
    status=$(curl -s http://localhost:9000/api/system/status | grep -o '"status":"[A-Z_]*"' || true)
    echo "  attempt $i: ${status:-not responding}"
    [[ "$status" == *'"UP"'* ]] && { log "SonarQube is UP"; return; }
    sleep 5
  done
  warn "Not UP yet. Check ${SONAR_HOME}/logs/{sonar,web,es,ce}.log"
  return 1
}

step_disk
step_grow_root
step_user
step_kernel_limits
step_java
step_download
step_config
step_systemd
step_verify

cat <<EOF

Done. Next manual steps:
  - Log in at http://<host>:9000 and change the default admin password (fresh DB only)
  - Apply the Enterprise license: Administration > Configuration > License Manager
  - Open port 9000 in the firewall or add a reverse proxy
  - Health check: curl -u <user>:<pass> http://localhost:9000/api/system/health
EOF
