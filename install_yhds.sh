#!/usr/bin/env bash
# yhds-menu-full - YHDS VPN PREMIUM (All-in-one interactive menu)
# Save as /usr/local/bin/yhds-menu-full and run as root
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

DB_DIR="/etc/yhds"
USER_DB="${DB_DIR}/users.db"
UDP_DIR="/root/udp"
LOG="/tmp/yhds-menu-full.log"

mkdir -p "$DB_DIR" "$UDP_DIR"
touch "$USER_DB"
chmod 600 "$USER_DB"

# ---------- COLORS ----------
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; CYAN='\e[36m'; NC='\e[0m'

pgreen(){ printf "${GREEN}%s${NC}\n" "$1"; }
pred(){ printf "${RED}%s${NC}\n" "$1"; }
pyellow(){ printf "${YELLOW}%s${NC}\n" "$1"; }
pcyan(){ printf "${CYAN}%s${NC}\n" "$1"; }

# ---------- UTIL ----------
require_root(){
  if [ "$(id -u)" -ne 0 ]; then
    pred "Please run this script as root (sudo)."
    exit 1
  fi
}
require_root

install_deps(){
  pyellow "Installing minimal dependencies (figlet, lolcat, jq, curl, wget, netcat)..."
  apt update -y >>"$LOG" 2>&1 || true
  apt install -y figlet ruby jq curl wget netcat-openbsd >/dev/null 2>&1 || true
  if command -v lolcat >/dev/null 2>&1; then
    pgreen "lolcat already installed"
  else
    if command -v gem >/dev/null 2>&1; then
      gem install lolcat >/dev/null 2>&1 || true
    fi
  fi
  pgreen "Deps install attempted (check $LOG for details)."
  sleep 1
}

# ---------- BANNER (SMALL) ----------
banner(){
  clear
  if command -v figlet >/dev/null 2>&1; then
    if command -v lolcat >/dev/null 2>&1; then
      figlet -f small "YHDS VPN" | lolcat
      echo -e "${CYAN}      PREMIUM VPS CONTROL PANEL${NC}"
    else
      figlet -f small "YHDS VPN"
      echo -e "${CYAN}      PREMIUM VPS CONTROL PANEL${NC}"
    fi
  else
    echo -e "${GREEN}=== YHDS VPN PREMIUM - PREMIUM VPS CONTROL PANEL ===${NC}"
  fi
  echo
}

get_ip(){
  IP=""
  if command -v curl >/dev/null 2>&1; then
    IP=$(curl -fsS --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || true)
  fi
  IP=${IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}
  echo "${IP:-127.0.0.1}"
}

now_iso(){ date -u +%FT%TZ; }

# DB helpers: format username:password:expire:max:created_iso:service
db_append(){ echo "$1:$2:$3:$4:$5:$6" >> "$USER_DB"; chmod 600 "$USER_DB"; }
db_list(){
  printf "%-15s %-12s %-6s %-20s %-10s\n" "USERNAME" "EXPIRES" "MAX" "CREATED_AT" "SERVICE"
  [ -f "$USER_DB" ] || return
  while IFS=: read -r u p e m c s; do
    printf "%-15s %-12s %-6s %-20s %-10s\n" "$u" "$e" "$m" "$c" "$s"
  done < "$USER_DB"
}

db_remove(){
  local u="$1"
  [ -f "$USER_DB" ] || return
  grep -v -E "^${u}:" "$USER_DB" > "${USER_DB}.tmp" || true
  mv -f "${USER_DB}.tmp" "$USER_DB"
}

# system user create wrapper
create_system_user(){
  local username="$1" password="$2" expire="$3" maxlogin="$4"
  if id "$username" &>/dev/null; then
    return 1
  fi
  useradd -M -N -s /usr/sbin/nologin -e "$expire" "$username" || return 1
  echo "${username}:${password}" | chpasswd || true
  echo "${username} hard maxlogins ${maxlogin}" > "/etc/security/limits.d/yhds_${username}.conf" || true
  return 0
}

# payload generator
generate_payloads(){
  local user="$1" pass="$2" svc="$3"
  IP=$(get_ip)
  SSH_PORT=22
  WS_PORT=443
  TROJAN_PORT=443
  UDP_PORT=$(grep -oP '"port"\s*:\s*\K\d+' "$UDP_DIR/config.json" 2>/dev/null || echo 4096)
  echo "----- PAYLOADS -----"
  echo "SSH  : ssh://${user}:${pass}@${IP}:${SSH_PORT}"
  echo "WS   : vless://${user}@${IP}:${WS_PORT}?type=ws&path=/ws#${user}-ws"
  echo "Trojan-WS : trojan://${pass}@${IP}:${TROJAN_PORT}?sni=${IP}#${user}-trojan-ws"
  echo "UDP client example: ${UDP_DIR}/udp-custom client --server ${IP}:${UDP_PORT} --user ${user} --pass ${pass}"
  echo "--------------------"
}

send_telegram(){
  local msg="$1"
  if [ -f /etc/yhds/telegram.conf ]; then
    . /etc/yhds/telegram.conf
    if [ -n "${BOT_TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ]; then
      curl -s --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="$msg" >/dev/null 2>&1 || true
    fi
  fi
}

# ---------- Flows ----------
flow_create_manual(){
  echo "Create manual account (SSH/WS/Trojan/VLESS/UDP)"
  read -rp "Service type (ssh/ws/trojan/vless/udp): " svc
  svc=${svc,,}
  read -rp "Username: " u
  if [ -z "$u" ]; then echo "Username empty, abort"; return; fi
  read -rp "Password (leave blank = auto): " p
  if [ -z "$p" ]; then p=$(tr -dc A-Za-z0-9 </dev/urandom | head -c12); echo "Generated password: $p"; fi
  read -rp "Expire days (default 7): " d
  if ! [[ "$d" =~ ^[0-9]+$ ]]; then d=7; fi
  read -rp "Max simultaneous logins (default 1): " m
  if ! [[ "$m" =~ ^[0-9]+$ ]]; then m=1; fi
  e=$(date -d "+${d} days" +%F)
  case "$svc" in
    ssh|ws)
      if create_system_user "$u" "$p" "$e" "$m"; then
        db_append "$u" "$p" "$e" "$m" "$(now_iso)" "$svc"
        pgreen "User $u created (service $svc) - expires $e"
        generate_payloads "$u" "$p" "$svc"
        send_telegram "New account: ${u} svc:${svc} expires:${e} on $(get_ip)"
      else
        pred "Failed: user exists or create_system_user failed"
      fi
      ;;
    trojan)
      db_append "$u" "$p" "$e" "$m" "$(now_iso)" "trojan"
      pgreen "Trojan account $u recorded. Restart xray after config."
      generate_payloads "$u" "$p" "$svc"
      send_telegram "New trojan account: ${u} expires:${e} on $(get_ip)"
      ;;
    vless|vless-ws|vless_ws|vless-ws)
      db_append "$u" "$p" "$e" "$m" "$(now_iso)" "vless"
      pgreen "VLESS account $u recorded (need to add to Xray config manually)."
      generate_payloads "$u" "$p" "$svc"
      send_telegram "New vless account: ${u} expires:${e} on $(get_ip)"
      ;;
    udp)
      db_append "$u" "$p" "$e" "$m" "$(now_iso)" "udp"
      mkdir -p "$UDP_DIR/$u"
      echo "$p" > "$UDP_DIR/$u/pass"
      pgreen "UDP user $u recorded; UDP custom client config example printed."
      generate_payloads "$u" "$p" "$svc"
      send_telegram "New udp account: ${u} expires:${e} on $(get_ip)"
      ;;
    *)
      pred "Unknown service type."
      ;;
  esac
  read -rp "Press Enter to continue..." _
}

flow_create_trial(){
  read -rp "Trial username (prefix 'trial-'): " u
  if [ -z "$u" ]; then u="trial-$(shuf -i 1000-9999 -n1)"; fi
  p=$(tr -dc A-Za-z0-9 </dev/urandom | head -c8)
  e=$(date -d "+1 day" +%F)
  m=1
  if create_system_user "$u" "$p" "$e" "$m"; then
    db_append "$u" "$p" "$e" "$m" "$(now_iso)" "trial"
    pgreen "Trial $u created, expires $e"
    generate_payloads "$u" "$p" "trial"
    send_telegram "New TRIAL ${u} expires:${e} on $(get_ip)"
  else
    pred "Failed to create trial (maybe exists)."
  fi
  read -rp "Press Enter to continue..." _
}

flow_list_users(){
  db_list
  read -rp "Press Enter to continue..." _
}

flow_delete_user(){
  read -rp "Username to delete: " u
  if grep -q "^${u}:" "$USER_DB" 2>/dev/null; then
    db_remove "$u"
    userdel -f "$u" 2>/dev/null || true
    rm -f "/etc/security/limits.d/yhds_${u}.conf" 2>/dev/null || true
    pgreen "Removed $u"
    send_telegram "Removed account: ${u} on $(get_ip)"
  else
    pred "User not found in DB"
  fi
  read -rp "Press Enter to continue..." _
}

flow_renew_user(){
  read -rp "Username to renew: " u
  if ! grep -q "^${u}:" "$USER_DB" 2>/dev/null; then pred "User not found"; read -rp "Enter..." _; return; fi
  read -rp "Add days to expiry (e.g. 30): " add
  if ! [[ "$add" =~ ^[0-9]+$ ]]; then pred "Must be number"; read -rp "Enter..." _; return; fi
  line=$(grep -E "^${u}:" "$USER_DB" | head -n1)
  IFS=: read -r _ p e m c s <<< "$line"
  new=$(date -d "${e} +${add} days" +%F)
  sed -i "s|^${u}:.*|${u}:${p}:${new}:${m}:${c}:${s}|" "$USER_DB"
  pgreen "Renewed $u -> new expiry $new"
  send_telegram "Renewed ${u} to ${new} on $(get_ip)"
  read -rp "Press Enter to continue..." _
}

flow_service_control(){
  echo "Services: 1) ssh 2) xray 3) udp-custom 4) nginx"
  read -rp "Choose service number: " sn
  case "$sn" in
    1) svc=ssh;;
    2) svc=xray;;
    3) svc=udp-custom;;
    4) svc=nginx;;
    *) pred "Invalid"; read -rp "Enter..." _; return;;
  esac
  echo "1) start 2) stop 3) restart 4) status"
  read -rp "Action: " act
  case "$act" in
    1) systemctl start "$svc" 2>/dev/null || true; pgreen "Started $svc";;
    2) systemctl stop "$svc" 2>/dev/null || true; pgreen "Stopped $svc";;
    3) systemctl restart "$svc" 2>/dev/null || true; pgreen "Restarted $svc";;
    4) systemctl status "$svc" --no-pager || true;;
    *) pred "Invalid";;
  esac
  read -rp "Press Enter to continue..." _
}

flow_diagnose_udp(){
  CONFIG="$UDP_DIR/config.json"
  UDP_PORT=$(grep -oP '"port"\s*:\s*\K\d+' "$CONFIG" 2>/dev/null || echo 4096)
  if systemctl is-active --quiet udp-custom 2>/dev/null; then pgreen "udp-custom: ON"; else pred "udp-custom: OFF"; fi
  if iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null; then pgreen "iptables: open"; else pred "iptables: blocked or no rule"; fi
  if ss -ulpn | grep -q ":$UDP_PORT"; then pgreen "Listening OK"; else pred "Not listening"; fi
  read -rp "Press Enter to continue..." _
}

flow_fix_udp(){
  CONFIG="$UDP_DIR/config.json"
  UDP_PORT=$(grep -oP '"port"\s*:\s*\K\d+' "$CONFIG" 2>/dev/null || echo 4096)
  systemctl start udp-custom 2>/dev/null || true
  systemctl enable udp-custom 2>/dev/null || true
  systemctl start xray 2>/dev/null || true
  systemctl start nginx 2>/dev/null || true
  if ! iptables -C INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p udp --dport "$UDP_PORT" -j ACCEPT 2>/dev/null || true
  fi
  if command -v ufw >/dev/null 2>&1; then ufw allow "${UDP_PORT}/udp" >/dev/null 2>&1 || true; fi
  pgreen "Fix steps attempted. Re-run diagnose to verify."
  send_telegram "UDP/Xray/Nginx fix attempted on $(get_ip)"
  read -rp "Press Enter to continue..." _
}

flow_install_telegram(){
  echo "Configure Telegram Bot for notifications"
  read -rp "BOT_TOKEN: " BOT_TOKEN
  read -rp "CHAT_ID: " CHAT_ID
  mkdir -p /etc/yhds
  cat >/etc/yhds/telegram.conf <<EOF
BOT_TOKEN='${BOT_TOKEN}'
CHAT_ID='${CHAT_ID}'
EOF
  chmod 600 /etc/yhds/telegram.conf
  pgreen "Telegram saved to /etc/yhds/telegram.conf"
  send_telegram "✅ Telegram Bot Connected to VPS $(get_ip) (YHDS VPS PREMIUM)"
  sleep 1
  read -rp "Press Enter to continue..." _
}

flow_restart_all(){
  for s in ssh xray udp-custom nginx; do
    systemctl restart "$s" 2>/dev/null || true
    sleep 1
  done
  pgreen "Restart commands sent."
  send_telegram "All services restarted on $(get_ip) at $(now_iso)"
  read -rp "Press Enter to continue..." _
}

# ---------- MAIN MENU ----------
main_menu(){
  while true; do
    banner
    echo "IP: $(get_ip)"
    echo "Uptime: $(uptime -p)"
    echo "Accounts total: $(wc -l < "$USER_DB" 2>/dev/null || echo 0)"
    echo "-----------------------------------------------"
    echo "1) Create Manual Account (SSH/WS/Trojan/VLESS/UDP)"
    echo "2) Create Trial Account (1 day)"
    echo "3) List Accounts"
    echo "4) Delete Account"
    echo "5) Renew Account (extend expiry)"
    echo "6) Service Control (start/stop/restart/status)"
    echo "7) Diagnose UDP"
    echo "8) Fix UDP + ensure Xray & Nginx ON"
    echo "9) Install/Configure Telegram Bot (notifications)"
    echo "10) Restart All Services"
    echo "11) Install minimal dependencies (figlet/lolcat/jq/wget/curl)"
    echo "0) Exit"
    echo "-----------------------------------------------"
    read -rp "Choose: " ch
    case "$ch" in
      1) flow_create_manual ;;
      2) flow_create_trial ;;
      3) flow_list_users ;;
      4) flow_delete_user ;;
      5) flow_renew_user ;;
      6) flow_service_control ;;
      7) flow_diagnose_udp ;;
      8) flow_fix_udp ;;
      9) flow_install_telegram ;;
      10) flow_restart_all ;;
      11) install_deps ;;
      0) pgreen "Goodbye."; exit 0 ;;
      *) pred "Invalid option"; sleep 0.6 ;;
    esac
  done
}

main_menu
