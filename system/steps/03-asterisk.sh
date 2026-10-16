#!/usr/bin/env bash
# 03 - install Asterisk (distro packages or build from source), enable and start it, verify running
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/permissions.sh"

step "Asterisk installation and startup"

ASTERISK_VERSION="${ASTERISK_VERSION:-22.4.0}"
SOURCE_BUILD="${SOURCE_BUILD:-auto}"
SRC_DIR="${SRC_DIR:-/usr/src/asterisk}"

asterisk_installed() {
  command -v asterisk >/dev/null 2>&1 || [ -x /usr/sbin/asterisk ]
}

asterisk_package_registered() {
  case "${PKG}" in
    apt) dpkg -s asterisk >/dev/null 2>&1 ;;
    dnf) rpm -q asterisk >/dev/null 2>&1 ;;
    *)   return 1 ;;
  esac
}

install_from_packages() {
  require_root
  local -a packages=(asterisk sox)

  local reinstall=""
  asterisk_package_registered && reinstall="--reinstall"

  case "${PKG}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y ${reinstall} "${packages[@]}" \
        || die "apt-get install ${packages[*]} failed"
      ;;
    dnf)
      dnf install -y epel-release || true
      dnf install -y ${reinstall} "${packages[@]}" \
        || die "dnf install ${packages[*]} failed - try SOURCE_BUILD=1"
      ;;
    *)
      die "Unsupported package manager '${PKG}' - use SOURCE_BUILD=1"
      ;;
  esac
}

install_from_source() {
  require_root
  local tarball="https://downloads.asterisk.org/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz"
  local url="https://downloads.asterisk.org/asterisk/${ASTERISK_VERSION}.tar.gz"
  log "Building Asterisk ${ASTERISK_VERSION} from source (this takes a while)"
  [ -d /etc/asterisk ] || [ -d "${SRC_DIR}" ] || mkdir -p "${SRC_DIR}"
  if [ ! -d "${SRC_DIR}/asterisk-${ASTERISK_VERSION}" ]; then
    mkdir -p "${SRC_DIR}"
    curl -fsSL -o "${SRC_DIR}/asterisk.tar.gz" "${url}" \
      || curl -fsSL -o "${SRC_DIR}/asterisk.tar.gz" "${tarball}" \
      || die "cannot download Asterisk ${ASTERISK_VERSION}"
    tar -xzf "${SRC_DIR}/asterisk.tar.gz" -C "${SRC_DIR}"
  fi

  cd "${SRC_DIR}/asterisk-${ASTERISK_VERSION}"
  if [ -x ./contrib/scripts/install_prereq ]; then
    ./contrib/scripts/install_prereq install || warn "prereq script failed - continuing"
  fi
  ./configure
  make menuselect || warn "menuselect skipped"
  make -j"$(nproc)"
  make install
  make basic-pbx >/dev/null 2>&1 || true
  ok "Asterisk ${ASTERISK_VERSION} built and installed"
}

if asterisk_installed; then
  ok "Asterisk already installed: $(asterisk -V 2>/dev/null | head -1)"
elif [ "${SOURCE_BUILD}" = "1" ]; then
  install_from_source
else
  if asterisk_package_registered; then
    warn "The asterisk package is registered with ${PKG} but binary is missing - reinstalling"
  fi
  log "Installing Asterisk packages (${PKG})"
  install_from_packages
fi

if ! asterisk_installed; then
  [ -x /usr/sbin/asterisk ] || die "Asterisk was not installed and /usr/sbin/asterisk does not exist"
  die "Asterisk is not working after installation"
fi

VERSION_LINE="$(asterisk -V 2>/dev/null | head -1 | tr -d '\r')"
[ -n "${VERSION_LINE}" ] || VERSION_LINE="Asterisk $(cat /usr/sbin/asterisk 2>/dev/null | head -1 || echo 'unknown')"
ok "Verified Asterisk: ${VERSION_LINE}"

# Configure Asterisk permissions for the user and asterisk group
grant_asterisk_dirs
ensure_operator_in_group "${SUDO_USER:-${USER:-root}}"

# Enable and start Asterisk service
if have systemctl; then
  systemctl enable asterisk >/dev/null 2>&1 || warn "could not enable asterisk via systemd"
  systemctl restart asterisk >/dev/null 2>&1 || systemctl start asterisk >/dev/null 2>&1 || warn "could not start asterisk via systemd"
fi

# Verify Asterisk is running
started=false
for _ in $(seq 1 10); do
  if asterisk_running || asterisk -rx "core show status" >/dev/null 2>&1; then
    started=true
    break
  fi
  sleep 1
done

if [ "${started}" = "true" ]; then
  ok "Asterisk is running"
else
  warn "Asterisk is not running yet (check: systemctl status asterisk)"
fi

# Modules verification (res_pjsip, res_http_websocket, res_ari, app_stasis)
missing=""
for mod in res_pjsip res_http_websocket res_ari app_stasis; do
  asterisk -rx "module show ${mod}" 2>/dev/null | grep -qi "${mod}" || missing="${missing} ${mod}"
done
if [ -n "${missing}" ]; then
  info "Required modules will be loaded on configuration deploy:${missing}"
else
  ok "Required Asterisk modules available (${missing:-all loaded})"
fi

write_step "asterisk" "$(printf '{"installed": true, "version": %s, "modules_ok": %s, "running": %s, "source_build": %s}' \
  "$(json_escape "${VERSION_LINE}")" "$([ -z "${missing}" ] && echo true || echo false)" \
  "$(bool_json "${started}")" "$(json_escape "${SOURCE_BUILD}")")"
