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

# === 1. User Inputs ===
echo "\n🚀 Drosera Full Auto Install (SystemD Only)"
read -p "📧 GitHub email: " GHEMAIL
read -p "👤 GitHub username: " GHUSER
read -p "🔐 Drosera private key (0x...): " PK
read -p "🌍 VPS public IP: " VPSIP
read -p "📬 Public address for whitelist (0x...): " OP_ADDR

for var in GHEMAIL GHUSER PK VPSIP OP_ADDR; do
  if [[ -z "${!var}" ]]; then
    echo "❌ $var is required."
    exit 1
  fi
  if [[ "$var" == *PK || "$var" == *OP_ADDR ]] && [[ ! ${!var} =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    echo "❌ $var must be a valid 0x-prefixed private key or address."
    exit 1
  fi
  if [[ "$var" == *VPSIP ]] && [[ ! ${!var} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ VPSIP must be a valid IP address."
    exit 1
  fi
  sleep 0.2
done

# === 2. Install Dependencies ===
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils -y

# === 3. Install Drosera CLI ===
curl -L https://app.drosera.io/install | bash
source ~/.bashrc
droseraup

# === 4. Install Foundry ===
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# === 5. Install Bun ===
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# === 6. Clean Old Directories ===
rm -rf drosera_operator .drosera my_drosera_trap

# === 7. Set Up Trap ===
mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
git config --global user.email "$GHEMAIL"
git config --global user.name "$GHUSER"
forge init -t drosera-network/trap-foundry-template
bun install && forge build

# === 8. Deploy Trap ===
echo "\n🚀 Deploying trap to Holesky..."
LOG_FILE="/tmp/drosera_deploy.log"
DROSERA_PRIVATE_KEY=$PK drosera apply <<< "ofc" | tee "$LOG_FILE"

TRAP_ADDR=$(grep -oP '(?<=address: 0x)[a-fA-F0-9]{40}' "$LOG_FILE" | head -n 1)
TRAP_ADDR="0x$TRAP_ADDR"

if [[ -z "$TRAP_ADDR" || "$TRAP_ADDR" == "0x" ]]; then
  echo "❌ Failed to detect trap address."
  exit 1
fi

echo "🪤 Trap deployed at: $TRAP_ADDR"

# === 9. Whitelist Operator ===
echo "\n🔐 Updating drosera.toml with whitelist..."
echo -e "\nprivate_trap = true\nwhitelist = [\"$OP_ADDR\"]" >> drosera.toml

# === 10. Wait & Reapply ===
echo "⏳ Waiting 10 minutes before re-applying config with whitelist..."
sleep 600
DROSERA_PRIVATE_KEY=$PK drosera apply <<< "ofc" | tee "$LOG_FILE"

# === 11. Download Operator Binary ===
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
sudo cp drosera-operator /usr/bin && chmod +x /usr/bin/drosera-operator

# === 12. Register Operator ===
drosera-operator register --eth-rpc-url https://holesky.drpc.org --eth-private-key $PK

# === 13. Enable Firewall ===
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw allow 31313/tcp
sudo ufw allow 31314/tcp
sudo ufw --force enable

# === 14. Setup SystemD ===
echo "\n🛠️ Setting up systemd service..."
USER=$(whoami)
sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=/usr/bin/drosera-operator node --db-file-path /home/$USER/.drosera.db --network-p2p-port 31313 --server-port 31314 \\
  --eth-rpc-url https://holesky.drpc.org \\
  --eth-backup-rpc-url https://1rpc.io/holesky \\
  --drosera-address $TRAP_ADDR \\
  --eth-private-key $PK \\
  --listen-address 0.0.0.0 \\
  --network-external-p2p-address $VPSIP \\
  --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

# === 15. Start Service ===
sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera

# === 16. Bloom Boost ===
echo "\n⚡ Sending Bloom Boost to trap: $TRAP_ADDR"
DROSERA_PRIVATE_KEY=$PK drosera bloomboost --trap-address $TRAP_ADDR --eth-amount 0.01

# === 17. Opt-in ===
echo "\n🔗 Opting in operator to trap..."
drosera-operator optin --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key $PK --trap-config-address $TRAP_ADDR

# === 18. Dryrun ===
cd ~/my-drosera-trap
drosera dryrun

# === 19. Done ===
echo "\n✅ Setup complete."
echo "🪤 Trap: https://app.drosera.io/trap?trapId=$(echo $TRAP_ADDR | tr '[:upper:]' '[:lower:]')"
echo "📖 Logs: journalctl -u drosera -f"
