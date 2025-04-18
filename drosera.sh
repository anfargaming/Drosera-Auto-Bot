#!/bin/bash

# === Banner Start ===
print_banner() {
    echo -e "\e[36m╔════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[36m║              Drosera One Click Setup               ║\e[0m"
    echo -e "\e[36m║        Automate your Drosera Full Installation     ║\e[0m"
    echo -e "\e[36m║     Developed by: https://t.me/Offical_Im_kazuha   ║\e[0m"
    echo -e "\e[36m║        GitHub: https://github.com/Kazuha787        ║\e[0m"
    echo -e "\e[36m╠════════════════════════════════════════════════════╣\e[0m"
    echo -e "\e[36m║                                                    ║\e[0m"
    echo -e "\e[36m║  ██╗  ██╗ █████╗ ███████╗██╗   ██╗██╗  ██╗ █████╗  ║\e[0m"
    echo -e "\e[36m║  ██║ ██╔╝██╔══██╗╚══███╔╝██║   ██║██║  ██║██╔══██╗ ║\e[0m"
    echo -e "\e[36m║  █████╔╝ ███████║  ███╔╝ ██║   ██║███████║███████║ ║\e[0m"
    echo -e "\e[36m║  ██╔═██╗ ██╔══██║ ███╔╝  ██║   ██║██╔══██║██╔══██║ ║\e[0m"
    echo -e "\e[36m║  ██║  ██╗██║  ██║███████╗╚██████╔╝██║  ██║██║  ██║ ║\e[0m"
    echo -e "\e[36m║  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ║\e[0m"
    echo -e "\e[36m║                                                    ║\e[0m"
    echo -e "\e[36m╚════════════════════════════════════════════════════╝\e[0m"
}
clear
print_banner
# === Banner End ===

echo "🚀 Drosera Full Auto Install (SystemD Only)"

# === 1. User Inputs ===
read -p "📧 GitHub email: " GHEMAIL
read -p "👤 GitHub username: " GHUSER
read -p "🔐 Drosera private key (0x...): " PK
read -p "🌍 VPS public IP: " VPSIP
read -p "📬 Public address for whitelist (0x...): " OP_ADDR
read -p "🪤 Trap name: " trap_name

for var in GHEMAIL GHUSER PK VPSIP OP_ADDR trap_name; do
  if [[ -z "${!var}" ]]; then
    echo "❌ $var is required."
    exit 1
  fi
done

trap_name=${trap_name// /_}

# === 2. Install Dependencies ===
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install curl unzip ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils -y

# === 3. Install Rust & Foundry ===
curl https://sh.rustup.rs -sSf | bash -s -- -y
source $HOME/.cargo/env
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# === 4. Install Bun ===
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# === 5. Install Drosera CLI ===
curl -L https://app.drosera.io/install | bash
source ~/.bashrc
droseraup

# === 6. Clean Previous ===
rm -rf $trap_name .drosera drosera_operator

# === 7. Setup Trap Project ===
git config --global user.email "$GHEMAIL"
git config --global user.name "$GHUSER"
git clone https://github.com/drosera-network/trap-foundry-template.git "$trap_name"
cd "$trap_name"
bun install && forge build

# === 8. Deploy Trap ===
echo "🚀 Deploying trap to Holesky..."
LOG_FILE="/tmp/drosera_deploy.log"
DROSERA_PRIVATE_KEY=$PK drosera deploy | tee "$LOG_FILE"

TRAP_ADDR=$(grep -oP '0x[a-fA-F0-9]{40}' "$LOG_FILE" | head -n 1)
if [[ -z "$TRAP_ADDR" ]]; then
  echo "❌ Trap deployment failed!"
  exit 1
fi

echo "🪤 Trap deployed at: $TRAP_ADDR"

# === 9. Update Whitelist ===
echo "🔐 Updating drosera.toml with whitelist..."
sed -i '/^whitelist/d' drosera.toml
echo -e 'private_trap = true\nwhitelist = ["'"$OP_ADDR"'"]' >> drosera.toml

# === 10. Wait & Re-deploy ===
echo "⏳ Waiting 10 minutes to apply whitelist..."
sleep 600
DROSERA_PRIVATE_KEY=$PK drosera deploy | tee "$LOG_FILE"

# === 11. Download Operator Binary ===
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin && chmod +x /usr/bin/drosera-operator

# === 12. Register Operator ===
drosera-operator register --eth-rpc-url https://holesky.drpc.org --eth-private-key $PK

# === 13. Setup SystemD Service ===
echo "🛠️ Creating systemd service..."
USER=$(whoami)
sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Node
After=network-online.target

[Service]
User=$USER
ExecStart=/usr/bin/drosera-operator node --db-file-path /home/$USER/.drosera.db --network-p2p-port 31313 --server-port 31314 \\
  --eth-rpc-url https://holesky.drpc.org \\
  --eth-backup-rpc-url https://1rpc.io/holesky \\
  --drosera-address $TRAP_ADDR \\
  --eth-private-key $PK \\
  --listen-address 0.0.0.0 \\
  --network-external-p2p-address $VPSIP \\
  --disable-dnr-confirmation true
Restart=always
RestartSec=15
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera

# === 14. Bloom Boost & Opt-in ===
DROSERA_PRIVATE_KEY=$PK drosera bloomboost --trap-address $TRAP_ADDR --eth-amount 0.01
drosera-operator optin --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key $PK --trap-config-address $TRAP_ADDR

# === 15. Dryrun ===
cd ~/$trap_name
drosera dryrun

# === 16. Done ===
echo ""
echo "✅ Setup Complete!"
echo "🪤 Trap URL: https://app.drosera.io/trap?trapId=$(echo $TRAP_ADDR | tr '[:upper:]' '[:lower:]')"
echo "📖 View logs: journalctl -u drosera -f"
