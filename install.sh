#!/usr/bin/env bash
set -e

REPO="gongseas/XrayRre"
ASSET_NAME="XrayR-linux-amd64.zip"
FALLBACK_TAG="v0.9.5-grpcfix1"

INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

msg() {
  echo -e "${green}$1${plain}"
}

warn() {
  echo -e "${yellow}$1${plain}"
}

err() {
  echo -e "${red}$1${plain}" >&2
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Please run as root."
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    *)
      err "Unsupported architecture: $(uname -m). Current release only provides linux amd64."
      exit 1
      ;;
  esac
}

install_deps() {
  msg "[1/6] Installing dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y wget curl unzip ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum install -y wget curl unzip ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget curl unzip ca-certificates
  else
    warn "No supported package manager detected. Please make sure wget/curl/unzip/ca-certificates are installed."
  fi
}

get_latest_tag() {
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  if [ -z "$tag" ]; then
    tag="$FALLBACK_TAG"
    warn "Failed to get latest release from GitHub API. Using fallback tag: ${tag}"
  fi
  echo "$tag"
}

stop_old_services() {
  systemctl stop XrayR 2>/dev/null || true
  systemctl stop v2node 2>/dev/null || true
  systemctl disable v2node 2>/dev/null || true
}

download_and_install() {
  local tag="$1"
  local tmp_dir="/tmp/xrayrre-install"
  local zip_file="${tmp_dir}/${ASSET_NAME}"
  local url="https://github.com/${REPO}/releases/download/${tag}/${ASSET_NAME}"

  msg "[2/6] Downloading XrayRre ${tag}..."
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
  wget -O "$zip_file" "$url"

  msg "[3/6] Installing binary..."
  unzip -o "$zip_file" -d "$tmp_dir" >/dev/null

  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  if [ -f "${tmp_dir}/XrayR" ]; then
    cp -f "${tmp_dir}/XrayR" "${INSTALL_DIR}/XrayR"
  elif [ -f "${tmp_dir}/xrayr/XrayR" ]; then
    cp -f "${tmp_dir}/xrayr/XrayR" "${INSTALL_DIR}/XrayR"
  else
    err "Cannot find XrayR binary in downloaded archive."
    exit 1
  fi
  chmod +x "${INSTALL_DIR}/XrayR"
}

download_geo_data() {
  msg "[4/6] Downloading geo data..."
  wget -q https://raw.githubusercontent.com/v2fly/geoip/release/geoip.dat -O "${INSTALL_DIR}/geoip.dat" || warn "geoip.dat download failed, skipped."
  wget -q https://raw.githubusercontent.com/v2fly/domain-list-community/release/dlc.dat -O "${INSTALL_DIR}/geosite.dat" || warn "geosite.dat download failed, skipped."
}

create_service() {
  msg "[5/6] Creating systemd service..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=${INSTALL_DIR}/XrayR --config ${CONFIG_DIR}/config.yml
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable XrayR
}

create_cli() {
  cat > /usr/bin/XrayR <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start) systemctl start XrayR && echo "XrayR started" ;;
  stop) systemctl stop XrayR && echo "XrayR stopped" ;;
  restart) systemctl restart XrayR && echo "XrayR restarted" ;;
  status) systemctl status XrayR ;;
  log) journalctl -u XrayR -f --no-pager ;;
  config) ${EDITOR:-nano} /etc/XrayR/config.yml ;;
  update) bash <(curl -fsSL https://raw.githubusercontent.com/gongseas/XrayRre/master/install.sh) ;;
  uninstall)
    systemctl stop XrayR 2>/dev/null || true
    systemctl disable XrayR 2>/dev/null || true
    rm -f /etc/systemd/system/XrayR.service
    systemctl daemon-reload
    rm -rf /usr/local/XrayR /etc/XrayR /usr/bin/XrayR
    echo "XrayR uninstalled"
    ;;
  *) echo "Usage: XrayR {start|stop|restart|status|log|config|update|uninstall}" ;;
esac
EOF
  chmod +x /usr/bin/XrayR
}

generate_config_if_needed() {
  if [ -f "${CONFIG_DIR}/config.yml" ]; then
    warn "Existing config found: ${CONFIG_DIR}/config.yml"
    return
  fi

  echo ""
  warn "No config found. Generate a basic NewV2board config now."
  read -r -p "ApiHost, example https://panel.example.com: " api_host
  read -r -p "NodeID: " node_id
  read -r -p "ApiKey: " api_key
  echo "NodeType: 1) V2ray  2) Trojan  3) Shadowsocks"
  read -r -p "Choose [1-3, default 1]: " node_type_choice
  case "$node_type_choice" in
    2) node_type="Trojan" ;;
    3) node_type="Shadowsocks" ;;
    *) node_type="V2ray" ;;
  esac

  cat > "${CONFIG_DIR}/config.yml" <<EOF
Log:
  Level: warning
  AccessPath:
  ErrorPath:
DnsConfigPath:
RouteConfigPath:
InboundConfigPath:
OutboundConfigPath:
ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64
Nodes:
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${api_host}"
      ApiKey: "${api_key}"
      NodeID: ${node_id}
      NodeType: ${node_type}
      Timeout: 30
      RuleListPath:
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      EnableFallback: false
      EnableREALITY: false
EOF

  msg "Config generated: ${CONFIG_DIR}/config.yml"
}

start_service() {
  msg "[6/6] Starting XrayR..."
  systemctl restart XrayR || true
  sleep 2
  if systemctl is-active --quiet XrayR; then
    msg "XrayR installed and running."
  else
    warn "XrayR installed but not running. Check logs with: XrayR log"
  fi
}

main() {
  echo "================================"
  echo "  XrayRre one-click installer"
  echo "  https://github.com/${REPO}"
  echo "================================"

  need_root
  detect_arch >/dev/null
  install_deps
  stop_old_services
  tag="$(get_latest_tag)"
  download_and_install "$tag"
  download_geo_data
  create_service
  create_cli
  generate_config_if_needed
  start_service

  echo ""
  echo "Commands:"
  echo "  XrayR start|stop|restart|status|log|config|update|uninstall"
  echo "Config:"
  echo "  ${CONFIG_DIR}/config.yml"
}

main "$@"

