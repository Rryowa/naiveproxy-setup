# NaiveProxy Setup Script

An automated bash script to set up [NaiveProxy](https://github.com/klzgrad/naiveproxy) using [Caddy v2](https://caddyserver.com/) on a Linux server. The script handles dependencies, builds Caddy with the required `forwardproxy` module, installs a decoy site to cloak the proxy, and applies advanced performance tuning.

## Features

- **Interactive Setup**: Prompts for your domain, email (for TLS), proxy username, and proxy password dynamically.
- **Decoy Site**: Automatically downloads and deploys a decoy website template to cloak your proxy traffic under legitimate HTTPS file server traffic.
- **Automated Caddy Build**: Uses `xcaddy` to compile the latest Caddy with the `forwardproxy@naive` module.
- **System Service Configuration**: Configures Caddy as a systemd service with correct capabilities (`setcap cap_net_bind_service=+ep`) so it can bind to port 443 without running as root.
- **Performance Tuning**:
  - Modifies systemd `LimitNOFILE` and `LimitNPROC` for Caddy.
  - Applies optimized kernel networking parameters via `sysctl` (`tcp_bbr`, `fq`, `tcp_fastopen`, `tcp_max_syn_backlog`).
- **Auto-TLS**: Automatically provisions SSL certificates for your domain using Let's Encrypt / ZeroSSL via Caddy.

## Prerequisites

Before running the script, ensure you have:
1. **A Linux VPS** (Debian/Ubuntu recommended).
2. **Root Privileges** (`root` user).
3. **A Domain Name** with an **A/AAAA Record** pointed to the public IP address of your VPS. Caddy needs this to successfully generate the TLS certificate.

## Usage

1. Clone or copy the setup script to your server.
2. Make the script executable:
   ```bash
   chmod +x naive.sh
   ```
3. Run the script as root:
   ```bash
   ./naive.sh
   ```
4. During execution, you will be prompted to enter:
   - Your **Domain** (e.g., `proxy.yourdomain.com`)
   - An **Email** (used for generating TLS certificates)
   - A **Proxy Username**
   - A **Proxy Password**

Wait for the script to finish installing dependencies, compiling Caddy, and tuning the server.

## Post-Installation

Once the script completes, Caddy will be running and serving your proxy alongside the decoy site.

- **Check Caddy Logs**: If your domain is inaccessible or you face SSL errors, check the logs:
  ```bash
  journalctl -u caddy -n 50 --no-pager
  ```
- **Edit Configuration**: You can modify your proxy configuration by editing the Caddyfile:
  ```bash
  nano /etc/caddy/Caddyfile
  ```
- **Restart Service**: After making changes to the Caddyfile, restart the service:
  ```bash
  systemctl restart caddy
  ```

## Important Notes

- **DNS Propagation**: If you just created the DNS A record for your domain, it might take a few minutes to propagate. If Caddy fails to obtain a TLS certificate due to an `NXDOMAIN` error, wait a bit and restart Caddy.
- **Client Configuration**: To connect to your new proxy from your local device, use a compatible NaiveProxy client configured with the domain, username, and password you provided.
