#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# ----- Configuration -----
HTML_DIR="/var/www/html"
TEMPLATE_NAME="filecloud"          # the folder name inside sni-templates

# ----- Update and install dependencies -----
apt-get update
apt-get install -y golang git libcap2-bin

# ----- Create system user, group, and directories -----
getent group caddy >/dev/null || groupadd --system caddy
getent passwd caddy >/dev/null || useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
mkdir -p /etc/caddy
mkdir -p /var/lib/caddy
mkdir -p "$HTML_DIR"
chown -R caddy:caddy /var/lib/caddy

# ----- Download the decoy site template -----
download_template() {
    local template="$1"
    if ! command -v git >/dev/null 2>&1; then
        echo "git is required but not found."
        return 1
    fi

    local temp_dir="/tmp/decoy-template-$$"
    mkdir -p "$temp_dir" || return 1

    git clone --filter=blob:none --sparse \
        "https://github.com/DigneZzZ/remnawave-scripts.git" "$temp_dir" || {
        rm -rf "$temp_dir"
        return 1
    }
    cd "$temp_dir" || return 1
    git sparse-checkout set "sni-templates/$template" || {
        cd /
        rm -rf "$temp_dir"
        return 1
    }

    local source="$temp_dir/sni-templates/$template"
    if [ -d "$source" ]; then
        rm -rf "$HTML_DIR"/*
        cp -r "$source"/* "$HTML_DIR/"
        local count
        count=$(find "$HTML_DIR" -type f | wc -l)
        echo "✔ Decoy template '$template' installed: $count files"
        chown -R caddy:caddy "$HTML_DIR"
        cd /
        rm -rf "$temp_dir"
        return 0
    else
        echo "✘ Template folder '$template' not found in the repository"
        cd /
        rm -rf "$temp_dir"
        return 1
    fi
}

echo "Downloading decoy template '$TEMPLATE_NAME'..."
download_template "$TEMPLATE_NAME" || {
    echo "Failed to download template – continuing with empty site."
}

# ----- Install xcaddy and build Caddy with NaiveProxy -----
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

xcaddy build --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive

# ----- Stop service and swap binaries -----
systemctl stop caddy 2>/dev/null || true
[ -f /usr/bin/caddy ] && mv /usr/bin/caddy /usr/bin/caddy.bak
mv caddy /usr/bin/caddy
chmod +x /usr/bin/caddy
setcap cap_net_bind_service=+ep /usr/bin/caddy

# ----- Performance tuning: systemd limits -----
mkdir -p /etc/systemd/system/caddy.service.d
cat << 'EOF' > /etc/systemd/system/caddy.service.d/limits.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
EOF

# ----- Create the systemd service unit for Caddy -----
cat << 'EOF' > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=infinity
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# ----- Performance tuning: kernel parameters -----
modprobe tcp_bbr 2>/dev/null || true
cat << 'EOF' > /etc/sysctl.d/99-naiveproxy.conf
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
EOF

# ----- Write Caddyfile with correct forward_proxy syntax -----
cat << 'EOF' > /etc/caddy/Caddyfile
{
  order forward_proxy before file_server
  log {
    exclude http.log.error
  }
}
:443, 504529.senko.network {
  tls rryowa@gmail.com
  encode
  forward_proxy {
    basic_auth user pass
    hide_ip
    hide_via
    probe_resistance
  }
  file_server {
    root /var/www/html
  }
}
EOF

# ----- Set ownership and start service -----
chown -R caddy:caddy /etc/caddy
systemctl daemon-reload
systemctl enable --now caddy

echo "Installation complete with decoy site and performance tuning."
