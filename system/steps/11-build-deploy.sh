#!/usr/bin/env bash
# 11 - build the Asterisk config from builder JSON or baseline skeleton, and deploy it.
#      render -> stage (data/asterisk-build) -> copy (/etc/asterisk) -> reload
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/permissions.sh"

step "Build and deploy Asterisk configuration"

DEST="${ASTERISK_ETC}"

if [ "$(id -u)" -eq 0 ]; then
  grant_asterisk_dirs
  ensure_operator_in_group "${SUDO_USER:-root}"
fi

if [ ! -f "${OPENIVR_ROOT}/data/trunk.json" ] && [ ! -f "${OPENIVR_ROOT}/data/endpoints.json" ]; then
  info "No custom builder configuration in data/ yet - deploying baseline Asterisk skeleton"
  # Copy skeleton configs into /etc/asterisk if they exist
  if [ -d "${OPENIVR_ROOT}/system/asterisk" ]; then
    cp -n "${OPENIVR_ROOT}"/system/asterisk/*.conf "${DEST}/" 2>/dev/null || true
    chown -R "${OPENIVR_USER}:${OPENIVR_GROUP}" "${DEST}" 2>/dev/null || true
    chmod 2775 "${DEST}" 2>/dev/null || true
    ok "Baseline skeleton configuration deployed to ${DEST}"
  fi
  write_step "build_deploy" '{"ran": true, "reason": "baseline skeleton deployed"}'
  asterisk_reload
  return 0 2>/dev/null || exit 0
fi

if ! have "${OPENIVR_PYTHON}"; then
  die "no python interpreter found (${OPENIVR_PYTHON})"
fi

log "Rendering from builder JSON ..."
( cd "${OPENIVR_ROOT}" && PYTHONPATH="${OPENIVR_ROOT}" OPENIVR_ASTERISK_ETC="${DEST}" \
    "${OPENIVR_PYTHON}" -m openivr publish --dest "${DEST}" ) \
  && ok "configuration deployed to ${DEST}" \
  || warn "publish reported problems; staged files are in ${OPENIVR_ROOT}/data/asterisk-build"

asterisk_reload

write_step "build_deploy" "$(printf '{"ran": true, "dest": "%s", "staging": "%s"}' \
  "${DEST}" "${OPENIVR_ROOT}/data/asterisk-build")"
