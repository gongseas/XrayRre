# XrayRre Fork Notes

This fork is based on XrayR and includes a V2Board/NewV2board compatibility fix for Trojan nodes.

## What Changed

- Fixed Trojan node transport parsing in `api/newV2board/v2board.go`.
- Trojan transport is no longer hardcoded to `tcp`.
- Supported panel-provided transport values now include:
  - `tcp`
  - `grpc`
  - `ws`
  - `httpupgrade`
  - `splithttp`
- Trojan TLS remains enabled by default, which avoids breaking normal Trojan TCP nodes.
- gRPC service name is read from `networkSettings.serviceName`.

## Build

Windows PowerShell cross-compile for Debian/Linux amd64:

```powershell
$env:GOOS = "linux"
$env:GOARCH = "amd64"
$env:CGO_ENABLED = "0"
go build -v -o XrayR -trimpath -ldflags "-s -w -buildid="
```

The compiled binary should be uploaded as a GitHub Release asset, not committed into Git.

## Debian VPS Install

One-click install:

```bash
wget -N https://raw.githubusercontent.com/gongseas/XrayRre/master/install.sh && bash install.sh
```

Alternative with curl:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gongseas/XrayRre/master/install.sh)
```

Upload the compiled `XrayR` binary and install it:

```bash
mkdir -p /usr/local/XrayR /etc/XrayR
cp /tmp/XrayR /usr/local/XrayR/XrayR
chmod +x /usr/local/XrayR/XrayR

cat > /etc/systemd/system/XrayR.service << 'EOF'
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable XrayR
systemctl start XrayR
```

Common commands:

```bash
systemctl status XrayR
systemctl restart XrayR
journalctl -u XrayR -f --no-pager
```

## Release Asset

Current local build output:

```text
D:\open claw\xrayr\XrayR
```

Upload this file to the GitHub Release asset list as:

```text
XrayR-linux-amd64
```
