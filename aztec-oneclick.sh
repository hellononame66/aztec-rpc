#!/bin/bash

set -euo pipefail
trap 'echo -e "\033[1;31m❌ Error occurred at line $LINENO. Exiting.\033[0m"' ERR

GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
NC="\033[0m"

BASE_DIR="/opt/eth-rpc-node"
JWT_PATH="$BASE_DIR/jwt.hex"

# Fetch IP safely
IP_ADDR="$(curl -s ifconfig.me || true)"
if [ -z "$IP_ADDR" ]; then
  IP_ADDR="$(hostname -I | awk '{print $1}')"
fi

print_banner() {
    clear
    echo "┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│  ██╗░░██╗██╗░░░██╗░██████╗████████╗██╗░░░░░███████╗  ░█████╗░██╗██████╗░██████╗░██████╗░░█████╗░██████╗░░██████╗  │"
    echo "│  ██║░░██║██║░░░██║██╔════╝╚══██╔══╝██║░░░░░██╔════╝  ██╔══██╗██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝  │"
    echo "│  ███████║██║░░░██║╚█████╗░░░░██║░░░██║░░░░░█████╗░░  ███████║██║██████╔╝██║░░██║██████╔╝██║░░██║██████╔╝╚█████╗░  │"
    echo "│  ██╔══██║██║░░░██║░╚═══██╗░░░██║░░░██║░░░░░██╔══╝░░  ██╔══██║██║██╔══██╗██║░░██║██╔══██╗██║░░██║██╔═══╝░░╚═══██╗  │"
    echo "│  ██║░░██║╚██████╔╝██████╔╝░░░██║░░░███████╗███████╗  ██║░░██║██║██║░░██║██████╔╝██║░░██║╚█████╔╝██║░░░░░██████╔╝  │"
    echo "│  ╚═╝░░╚═╝░╚═════╝░╚═════╝░░░░╚═╝░░░╚══════╝╚══════╝  ╚═╝░░╚═╝╚═╝╚═╝░░╚═╝╚═════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░░░░╚═════╝░  │"
    echo "└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
    echo -e "${YELLOW}                  🚀 Aztec Node Manager by AJ 🚀${NC}"
    echo -e "${YELLOW}              GitHub: https://github.com/HustleAirdrops${NC}"
    echo -e "${YELLOW}              Telegram: https://t.me/Hustle_Airdrops${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
    
    echo -e "  📡 Ethereum Sepolia Full Node Setup Menu"
    echo -e "  🔗 Geth (Execution) + Prysm (Beacon Chain)"
    echo -e "==============================================${NC}"
    echo "1) 🚀 Install & Start Node"
    echo "2) 📜 View Logs"
    echo "3) 📶 Check Node Status"
    echo "4) 🔗 Get RPC URLs"
    echo "5) ❌ Exit"
    echo -e "==============================================${NC}"
    echo -en "${NC}Choose an option [1-5]: "
}

install_dependencies() {
  echo -e "${YELLOW}🔧 Installing required packages...${NC}"
  sudo apt update -y && sudo apt upgrade -y

  # Fix common lock issues
  sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend
  sudo dpkg --configure -a

  local packages=(
    curl jq net-tools iptables build-essential git wget lz4 make gcc nano
    automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev
    libleveldb-dev tar clang bsdmainutils ncdu unzip ufw openssl
  )

  for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      echo -e "${BLUE}🔄 Installing $pkg...${NC}"
      sudo apt-get install -y "$pkg"
      echo -e "${GREEN}✅ $pkg installed${NC}"
    else
      echo -e "${CYAN}✔️ $pkg already present${NC}"
    fi
  done
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${CYAN}🐳 Installing Docker...${NC}"
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
    sudo apt-get install -y ca-certificates gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl restart docker

    echo -e "${GREEN}✅ Docker installed successfully${NC}"
  else
    echo -e "${CYAN}ℹ️ Docker already installed. Skipping.${NC}"
  fi
}

check_ports() {
  echo -e "${YELLOW}🕵️ Checking required ports...${NC}"
  local conflicts
  conflicts=$(sudo netstat -tuln | grep -E '30303|8545|8546|8551|4000|3500' || true)

  if [ -n "$conflicts" ]; then
    echo -e "${RED}❌ Ports already in use:\n$conflicts${NC}"
    exit 1
  else
    echo -e "${GREEN}✅ All required ports are available.${NC}"
  fi
}

create_directories() {
  echo -e "${YELLOW}📁 Setting up directory structure...${NC}"
  sudo mkdir -p "$BASE_DIR/execution" "$BASE_DIR/consensus"
  sudo rm -f "$JWT_PATH"
  sudo openssl rand -hex 32 | sudo tee "$JWT_PATH" > /dev/null
  echo -e "${GREEN}✅ JWT secret created at $JWT_PATH${NC}"
}

write_compose_file() {
   echo -e "${YELLOW}📝 Writing docker-compose.yml...${NC}"
   sudo tee "$BASE_DIR/docker-compose.yml" > /dev/null <<EOF
version: '3.8'
services:
  execution:
    image: ethereum/client-go:stable
    container_name: geth
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./execution:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --http
      - --http.api=eth,net,web3
      - --http.addr=0.0.0.0
      - --authrpc.addr=0.0.0.0
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/data/jwt.hex
      - --authrpc.port=8551
      - --syncmode=snap
      - --datadir=/data

  consensus:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:stable
    container_name: prysm
    network_mode: host
    restart: unless-stopped
    depends_on:
      - execution
    volumes:
      - ./consensus:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --accept-terms-of-use
      - --datadir=/data
      - --disable-monitoring
      - --rpc-host=0.0.0.0
      - --execution-endpoint=http://$IP_ADDR:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-port=4000
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --min-sync-peers=3
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
EOF
  echo -e "${GREEN}✅ Compose file created.${NC}"
}

start_services() {
  echo -e "${CYAN}🚀 Starting Ethereum Sepolia services...${NC}"
  cd "$BASE_DIR"
  sudo docker compose up -d
  echo -e "${GREEN}✅ Services started.${NC}"
}

monitor_sync() {
  echo -e "${CYAN}📡 Monitoring sync status...${NC}"
  while true; do
    echo "DEBUG: contacting http://$IP_ADDR:8545"
    geth_sync=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://$IP_ADDR:8545 || echo "")
    prysm_sync=$(curl -s http://$IP_ADDR:3500/eth/v1/node/syncing || echo "")

    if [[ "$geth_sync" == *"false"* ]]; then
      echo -e "${GREEN}✅ Geth fully synced.${NC}"
    else
      current=$(echo "$geth_sync" | jq -r .result.currentBlock)
      highest=$(echo "$geth_sync" | jq -r .result.highestBlock)
      percent=$(awk "BEGIN {printf \"%.2f\", (0x${current}/0x${highest})*100}")
      echo -e "${YELLOW}🔄 Geth syncing: Block $current of $highest (~$percent%)${NC}"
    fi

    distance=$(echo "$prysm_sync" | jq -r '.data.sync_distance' 2>/dev/null || echo "")
    head=$(echo "$prysm_sync" | jq -r '.data.head_slot' 2>/dev/null || echo "")

    if [[ "$distance" == "0" ]]; then
      echo -e "${GREEN}✅ Prysm fully synced.${NC}"
    else
      echo -e "${YELLOW}🔄 Prysm syncing: $distance slots behind (head: $head)${NC}"
    fi

    [[ "$geth_sync" == *"false"* && "$distance" == "0" ]] && break
    sleep 10
  done
}

print_endpoints() {
  echo -e "${CYAN}\n🔗 Ethereum Sepolia RPC Endpoints:${NC}"
  echo -e "${GREEN}📎 Geth:     http://$IP_ADDR:8545${NC}"
  echo -e "${GREEN}📎 Prysm:    http://$IP_ADDR:3500${NC}"
  echo -e "${BLUE}\n🎉 Setup complete — Powered by AJ💖 ✨${NC}"
}

check_node_status() {
  echo -e "${CYAN}🔍 Checking Ethereum Sepolia node status...${NC}"
  
  # Geth status check
  geth_response=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://$IP_ADDR:8545 || echo "")
  
  if [[ -z "$geth_response" ]]; then
    echo -e "${RED}⚠️ Geth is not responding. Is the node running?${NC}"
  else
    if echo "$geth_response" | jq -e '.result == false' >/dev/null 2>&1; then
      echo -e "✅ ${GREEN}Geth (Execution Layer) is fully synced.${NC}"
    elif echo "$geth_response" | jq -e '.result | type == "object"' >/dev/null 2>&1; then
      current_hex=$(echo "$geth_response" | jq -r '.result.currentBlock')
      highest_hex=$(echo "$geth_response" | jq -r '.result.highestBlock')
      if [[ "$current_hex" == "null" || "$highest_hex" == "null" ]]; then
        echo -e "${RED}⚠️ Geth returned an unexpected response.${NC}"
      else
        current_dec=$(printf "%d" "$current_hex")
        highest_dec=$(printf "%d" "$highest_hex")
        if [[ $highest_dec -gt 0 ]]; then
          percent=$(awk "BEGIN {printf \"%.2f\", ($current_dec/$highest_dec)*100}")
          echo -e "🔄 ${YELLOW}Geth is syncing: Block $current_dec of $highest_dec (~$percent%)${NC}"
        else
          echo -e "${RED}⚠️ Could not calculate sync progress (highest block is zero).${NC}"
        fi
      fi
    else
      echo -e "${RED}⚠️ Geth returned an error: $(echo "$geth_response" | jq -r '.error.message')${NC}"
    fi
  fi

  # Prysm status check
  prysm_response=$(curl -s http://$IP_ADDR:3500/eth/v1/node/syncing || echo "")
  
  if [[ -z "$prysm_response" ]]; then
    echo -e "${RED}⚠️ Prysm is not responding. Is the node running?${NC}"
  else
    if echo "$prysm_response" | jq -e '.data' >/dev/null 2>&1; then
      distance=$(echo "$prysm_response" | jq -r '.data.sync_distance')
      head=$(echo "$prysm_response" | jq -r '.data.head_slot')
      if [[ "$distance" == "0" ]]; then
        echo -e "✅ ${GREEN}Prysm (Consensus Layer) is fully synced.${NC}"
      elif [[ -n "$distance" ]]; then
        echo -e "🔄 ${YELLOW}Prysm is syncing: $distance slots behind (head: $head)${NC}"
      else
        echo -e "${RED}⚠️ Could not fetch Prysm sync status.${NC}"
      fi
    else
      echo -e "${RED}⚠️ Prysm returned an error: $(echo "$prysm_response" | jq -r '.message')${NC}"
    fi
  fi
  echo ""
}

print_rpc_endpoints() {
  echo -e "${CYAN}\n🔗 Ethereum Sepolia RPC Endpoints:${NC}"
  echo -e "${GREEN}📎 Geth:     http://$IP_ADDR:8545${NC}"
  echo -e "${GREEN}📎 Prysm:    http://$IP_ADDR:3500${NC}"

  echo -e "${CYAN}\n🔍 Checking Ethereum Sepolia node status...${NC}"

  geth_response=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://$IP_ADDR:8545 || echo "")
  prysm_response=$(curl -s http://$IP_ADDR:3500/eth/v1/node/syncing || echo "")
  
  # Geth status
  if [[ -z "$geth_response" ]]; then
    echo -e "${RED}⚠️ Geth is not responding.${NC}"
    geth_synced=false
  else
    if echo "$geth_response" | jq -e '.result == false' >/dev/null 2>&1; then
      echo -e "✅ ${GREEN}Geth (Execution Layer) is fully synced.${NC}"
      geth_synced=true
    elif echo "$geth_response" | jq -e '.result | type == "object"' >/dev/null 2>&1; then
      current_hex=$(echo "$geth_response" | jq -r '.result.currentBlock')
      highest_hex=$(echo "$geth_response" | jq -r '.result.highestBlock')
      if [[ "$current_hex" != "null" && "$highest_hex" != "null" ]]; then
        current_dec=$(printf "%d" "$current_hex")
        highest_dec=$(printf "%d" "$highest_hex")
        if [[ $highest_dec -gt 0 ]]; then
          percent=$(awk "BEGIN {printf \"%.2f\", ($current_dec/$highest_dec)*100}")
          echo -e "🔄 ${YELLOW}Geth is syncing: Block $current_dec of $highest_dec (~$percent%)${NC}"
        else
          echo -e "${RED}⚠️ Could not calculate sync progress (highest block is zero).${NC}"
        fi
      fi
      geth_synced=false
    else
      echo -e "${RED}⚠️ Geth returned an error.${NC}"
      geth_synced=false
    fi
  fi

  # Prysm status
  if [[ -z "$prysm_response" ]]; then
    echo -e "${RED}⚠️ Prysm is not responding.${NC}"
    prysm_synced=false
  else
    if echo "$prysm_response" | jq -e '.data' >/dev/null 2>&1; then
      distance=$(echo "$prysm_response" | jq -r '.data.sync_distance')
      head=$(echo "$prysm_response" | jq -r '.data.head_slot')
      if [[ "$distance" == "0" ]]; then
        echo -e "✅ ${GREEN}Prysm (Consensus Layer) is fully synced.${NC}"
        prysm_synced=true
      elif [[ -n "$distance" ]]; then
        echo -e "🔄 ${YELLOW}Prysm is syncing: $distance slots behind (head: $head)${NC}"
        prysm_synced=false
      else
        echo -e "${RED}⚠️ Could not fetch Prysm sync status.${NC}"
        prysm_synced=false
      fi
    else
      echo -e "${RED}⚠️ Prysm returned an error.${NC}"
      prysm_synced=false
    fi
  fi

  if [[ "$geth_synced" == true && "$prysm_synced" == true ]]; then
    echo -e "${BLUE}\n🎉 Node is fully synced — Powered by AJ💖 ✨${NC}"
  else
    echo -e "${YELLOW}\n⚠️ Node is still syncing. Please wait...${NC}"
  fi
}

handle_choice() {
  case "$1" in
    1)
      install_dependencies
      install_docker
      check_ports
      create_directories
      write_compose_file
      start_services
      monitor_sync
      print_endpoints
      ;;
    2)
      if [ -f "$BASE_DIR/docker-compose.yml" ]; then
        cd "$BASE_DIR"
        echo -e "${YELLOW}📜 Showing logs... Ctrl+C to exit.${NC}"
        sudo docker compose logs -f
      else
        echo -e "${RED}❌ No docker-compose.yml found. Please run installation first.${NC}"
      fi
      ;;
    3)
      check_node_status
      ;;
    4)
      print_rpc_endpoints
      ;;
    5)
      echo -e "${CYAN}👋 Goodbye!${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ Invalid input. Enter 1, 2, 3, or 4.${NC}"
      ;;
  esac
}

main() {
  while true; do
    print_banner
    read -r choice
    handle_choice "$choice"
    echo ""
    read -rp "Press Enter to return to the menu..."
  done
}

main
