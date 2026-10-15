#!/usr/bin/env bash
# 02 - system requirements preflight: OS, tools, python packages, disk, and firewall/ffmpeg options.
# Exits immediately with a clear error message if requirements are not fulfilled.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step "System requirements"

# ------------------------------------------------------------------- the OS
ARCH="$(uname -m)"
info "OS: ${OS_ID} ${OS_VER} (${ARCH}), kernel $(uname -r)"
info "package manager: ${PKG}"

case "${PKG}" in
  apt|dnf) ;;
  *)
    die "Unsupported package manager '${PKG}'. OpenIVR requires a Debian/Ubuntu (apt) or RHEL/CentOS/Fedora (dnf) based distribution."
    ;;
esac

# ---------------------------------------------------------------- the tools
MISSING_TOOLS=""
for tool in python3 curl tar git; do
  if have "${tool}"; then
    ok "${tool} present"
  else
    err "${tool} is missing"
    MISSING_TOOLS="${MISSING_TOOLS} ${tool}"
  fi
done

if [ -n "${MISSING_TOOLS}" ]; then
  die "System is missing required tools:${MISSING_TOOLS}. Please install them (e.g. apt-get install -y${MISSING_TOOLS}) and re-run."
fi

# --------------------------------------------------------------- python 3.10+
PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "0.0")"
if python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
  ok "python ${PY_VER} (>= 3.10 required) at $(command -v python3)"
else
  die "System Python version (${PY_VER}) is older than 3.10. OpenIVR requires Python >= 3.10."
fi

# --------------------------------------------------- python packages (.venv)
if [ ! -x "${OPENIVR_PYTHON}" ]; then
  info "virtual environment not found at ${OPENIVR_ROOT}/.venv - attempting to create it"
  python3 -m venv "${OPENIVR_ROOT}/.venv" || die "Failed to create python virtual environment. Install python3-venv (e.g. apt-get install python3-venv)."
  OPENIVR_PYTHON="${OPENIVR_ROOT}/.venv/bin/python"
  "${OPENIVR_ROOT}/.venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
  "${OPENIVR_ROOT}/.venv/bin/pip" install -r "${OPENIVR_ROOT}/requirements.txt" || die "Failed to install Python requirements from requirements.txt"
fi

PKG_MISSING=""
for mod in yaml fastapi uvicorn jinja2 multipart; do
  if "${OPENIVR_PYTHON}" -c "import ${mod}" >/dev/null 2>&1; then
    ok "python module: ${mod}"
  else
    PKG_MISSING="${PKG_MISSING} ${mod}"
  fi
done

if [ -n "${PKG_MISSING}" ]; then
  die "Missing required Python packages:${PKG_MISSING}. Please run: make venv"
fi

# -------------------------------------------------------------- disk space (>= 2GB)
FREE_GB="$(df -Pk "${OPENIVR_ROOT}" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1048576}')"
if [ -n "${FREE_GB}" ] && [ "${FREE_GB}" -ge 2 ]; then
  ok "${FREE_GB} GB free in ${OPENIVR_ROOT} (2 GB required)"
else
  die "Insufficient disk space: only ${FREE_GB:-0} GB free in ${OPENIVR_ROOT}. Asterisk and OpenIVR require at least 2 GB free disk space."
fi

# -------------------------------------------------------------- ffmpeg
if have ffmpeg; then
  FFMPEG_PRESENT=true
  FFMPEG_REQUESTED="$(ask_yes_no "ffmpeg is installed - use it to convert uploaded audio?" "y")"
else
  FFMPEG_PRESENT=false
  FFMPEG_REQUESTED="$(ask_yes_no "Install ffmpeg so the builder can convert uploaded audio?" "y")"
fi
if [ "${FFMPEG_REQUESTED}" = "y" ] && [ "${FFMPEG_PRESENT}" = "false" ]; then
  case "${PKG}" in
    apt) apt-get update -qq && apt-get install -y ffmpeg || warn "ffmpeg install failed" ;;
    dnf) dnf install -y ffmpeg || warn "ffmpeg install failed" ;;
  esac
  have ffmpeg && ok "ffmpeg installed" || warn "ffmpeg is still missing - only .wav/.gsm/.ulaw uploads will be accepted"
fi
have ffmpeg && FFMPEG_PRESENT=true || FFMPEG_PRESENT=false

# ---------------------------------------------------------------- firewall?
if have ufw || have firewall-cmd; then
  DEFAULT_FW="y"
else
  DEFAULT_FW="n"
fi
FIREWALL_ACTIVE="$(ask_yes_no "Is a firewall (ufw/firewalld) active on this system?" "${DEFAULT_FW}")"
ok "firewall active: ${FIREWALL_ACTIVE} (step 05 opens ports)"

# -------------------------------------------------------------- directories
if [ -d "${ASTERISK_ETC}" ]; then
  ok "asterisk config dir ${ASTERISK_ETC} present"
else
  info "asterisk not installed yet (step 03 will install it)"
fi

write_step "preflight" "$(printf '{"os": %s, "os_version": %s, "arch": %s, "pkg_manager": %s, "python": %s, "python_bin": %s, "ffmpeg_present": %s, "ffmpeg_requested": %s, "firewall_active": %s, "disk_free_gb": %s, "missing_tools": "", "checked_at": %s}' \
  "$(json_escape "${OS_ID}")" "$(json_escape "${OS_VER}")" "$(json_escape "${ARCH}")" \
  "$(json_escape "${PKG}")" "$(json_escape "$(python3 --version 2>&1)")" "$(json_escape "${OPENIVR_PYTHON}")" \
  "$(bool_json "${FFMPEG_PRESENT}")" "$(bool_json "${FFMPEG_REQUESTED}")" "$(bool_json "${FIREWALL_ACTIVE}")" \
  "${FREE_GB:-0}" "$(json_escape "$(date -Is)")")"
