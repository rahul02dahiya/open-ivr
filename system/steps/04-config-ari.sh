#!/usr/bin/env bash
# 04 - Core config & ARI setup: set config.yaml in project root, collect local paths & variables, configure ARI/HTTP/RTP
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step "Core configuration and ARI setup"

ARI_USER="${ARI_USER:-openivr}"
STASIS_APP="${STASIS_APP:-openivr}"
ARI_ADMIN_APP="${ARI_ADMIN_APP:-openivr-admin}"
ARI_PORT="${ARI_PORT:-8088}"
ARI_BIND="${ARI_BIND:-127.0.0.1}"
RTP_START="${RTP_START:-10000}"
RTP_END="${RTP_END:-20000}"
MEDIA_ADDR="${MEDIA_ADDR:-}"
STUN_ADDR="${STUN_ADDR:-stun.l.google.com:19302}"

SOUNDS_DIR="${ASTERISK_LIB}/sounds/custom"
RECORD_DIR="${ASTERISK_SPOOL}/monitor"
VOICEMAIL_DIR="${ASTERISK_SPOOL}/voicemail"

# Generate or preserve ARI password
if [ -f "${STATE_DIR}/ari_password" ]; then
  ARI_PASSWORD="$(cat "${STATE_DIR}/ari_password")"
else
  ARI_PASSWORD="${ARI_PASSWORD:-$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)}"
fi

install -d -m 0755 "${ASTERISK_ETC}"
install -d -m 0775 "${SOUNDS_DIR}" "${RECORD_DIR}" "${VOICEMAIL_DIR}" 2>/dev/null || true

# Back up before overwriting
backup_conf "${ASTERISK_ETC}/ari.conf"
backup_conf "${ASTERISK_ETC}/http.conf"
backup_conf "${ASTERISK_ETC}/rtp.conf"

render() {
  local skeleton="$1" dest="$2"; shift 2
  [ -f "${skeleton}" ] || die "skeleton missing: ${skeleton}"
  python3 - "${skeleton}" "${dest}" "$@" <<'PY'
import pathlib, re, sys

skeleton, dest = sys.argv[1], sys.argv[2]
lines = []
for line in pathlib.Path(skeleton).read_text(encoding="utf-8").splitlines(keepends=True):
    if not line.lstrip().startswith((";", "#")):
        for pair in sys.argv[3:]:
            key, _, value = pair.partition("=")
            line = line.replace("{{" + key + "}}", value)
    lines.append(line)
kept = [
    line
    for line in lines
    if not re.match(r"^[A-Za-z0-9_]+\s*=\s*$", line.rstrip("\n"))
]
pathlib.Path(dest).write_text("".join(kept), encoding="utf-8")
PY
  chown "${OPENIVR_USER}:${OPENIVR_GROUP}" "${dest}" 2>/dev/null || true
  chmod 0640 "${dest}" 2>/dev/null || true
}

# ari.conf
render "${OPENIVR_ROOT}/system/asterisk/ari.conf" "${ASTERISK_ETC}/ari.conf" \
  "ari_user=${ARI_USER}" "ari_pass=${ARI_PASSWORD}" \
  "stasis_app=${STASIS_APP},${ARI_ADMIN_APP}"
ok "wrote ${ASTERISK_ETC}/ari.conf (user: ${ARI_USER}, app: ${STASIS_APP})"

# http.conf
render "${OPENIVR_ROOT}/system/asterisk/http.conf" "${ASTERISK_ETC}/http.conf" \
  "ari_bind=${ARI_BIND}" "http_port=${ARI_PORT}"
ok "wrote ${ASTERISK_ETC}/http.conf (${ARI_BIND}:${ARI_PORT})"

# rtp.conf
render "${OPENIVR_ROOT}/system/asterisk/rtp.conf" "${ASTERISK_ETC}/rtp.conf" \
  "rtpstart=${RTP_START}" "rtpend=${RTP_END}" "stunaddr=${STUN_ADDR}" \
  "external_media_address=${MEDIA_ADDR}" "ice_acl=rtp-ice"
ok "wrote ${ASTERISK_ETC}/rtp.conf (RTP: ${RTP_START}-${RTP_END})"

# ----------------- config.yaml in project root -----------------
info "Setting up ${OPENIVR_ROOT}/config.yaml"
config_set "ari.username" "${ARI_USER}"
config_set "ari.password" "${ARI_PASSWORD}"
config_set "ari.base_url" "http://${ARI_BIND}:${ARI_PORT}/ari"
config_set "app.stasis_app" "${STASIS_APP}"

umask 077
printf '%s\n' "${ARI_PASSWORD}" > "${STATE_DIR}/ari_password"
chmod 0600 "${STATE_DIR}/ari_password"

asterisk_reload
asterisk_running && ok "Asterisk reloaded with ARI configuration" || info "Asterisk will load ARI on next start"

info "ARI connection: http://${ARI_BIND}:${ARI_PORT}/ari as user '${ARI_USER}'"
info "Credentials and paths recorded into config.yaml and system.json"

write_step "ari" "$(printf '{"ari": {"base_url": "http://%s:%s/ari", "username": "%s", "password": "%s"}, "ari_port": %s, "stasis_app": "%s", "stasis_admin_app": "%s", "rtp": {"start": %s, "end": %s}, "paths": {"root": "%s", "asterisk_etc": "%s", "asterisk_lib": "%s", "asterisk_spool": "%s", "sounds": "%s", "recording": "%s", "voicemail": "%s"}}' \
  "${ARI_BIND}" "${ARI_PORT}" "${ARI_USER}" "${ARI_PASSWORD}" "${ARI_PORT}" "${STASIS_APP}" \
  "${ARI_ADMIN_APP}" "${RTP_START}" "${RTP_END}" \
  "${OPENIVR_ROOT}" "${ASTERISK_ETC}" "${ASTERISK_LIB}" "${ASTERISK_SPOOL}" \
  "${SOUNDS_DIR}" "${RECORD_DIR}" "${VOICEMAIL_DIR}")"
