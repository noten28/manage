#!/bin/bash
set -e

# ============================================================
#             AMOKHAN TECH MANAGER INSTALLER
# ============================================================

# -------------------- COLORS --------------------
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

C_RED=$'\033[38;5;196m'
C_GREEN=$'\033[38;5;46m'
C_YELLOW=$'\033[38;5;226m'
C_BLUE=$'\033[38;5;39m'
C_PURPLE=$'\033[38;5;135m'
C_CYAN=$'\033[38;5;51m'
C_WHITE=$'\033[38;5;255m'
C_GRAY=$'\033[38;5;245m'
C_ORANGE=$'\033[38;5;208m'

# Semantic aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

# -------------------- SETTINGS --------------------
BASE_URL="https://raw.githubusercontent.com/noten28/manage/main"

MENU_FILE="/usr/local/bin/menu"
SSHD_CONFIG="/etc/ssh/sshd_config"

# -------------------- ROOT CHECK --------------------
if [[ $EUID -ne 0 ]]; then
    echo
    echo -e "${C_RED}${C_BOLD}✘ ERROR${C_RESET}"
    echo -e "${C_WHITE}This installer must be run as root.${C_RESET}"
    echo
    exit 1
fi

# ============================================================
#                    HEADER
# ============================================================

clear

# --- colour vars (use these or your existing names) ---
C_RED=$'\033[91m'; C_GREEN=$'\033[92m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
C_WHITE=$'\033[97m'; C_GRAY=$'\033[90m'; C_ORANGE=$'\033[38;5;208m'

echo
# margin / box = RED
echo -e "${C_RED}${C_BOLD}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
# left border RED | spaces | title GREEN | spaces | right border RED
echo -e "${C_RED}${C_BOLD}║${C_RESET}                    ${C_GREEN}${C_BOLD}AMOKHAN TECH MANAGER INSTALLER${C_RESET}                    ${C_RED}${C_BOLD}║${C_RESET}"
echo -e "${C_RED}${C_BOLD}║${C_RESET}                           ${C_ORANGE}Premium Edition${C_RESET}                            ${C_RED}${C_BOLD}║${C_RESET}"
echo -e "${C_RED}${C_BOLD}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo
echo -e "                 ${C_GRAY}SSH • Proxy • Tunnel Management${C_RESET}"
echo

# ============================================================
#                 MANAGER SELECTION
# ============================================================

echo -e "${C_CYAN}${C_BOLD}Select Manager Type${C_RESET}"
echo
echo -e "  ${C_GREEN}${C_BOLD}1${C_RESET}  ${C_WHITE}Full Manager${C_RESET}"
echo -e "     ${C_GRAY}SSH + WebSocket + Stunnel + DNSTT + V2Ray${C_RESET}"
echo
echo -e "  ${C_GREEN}${C_BOLD}2${C_RESET}  ${C_WHITE}Advanced Manager${C_RESET}"
echo -e "     ${C_GRAY}SSH + WebSocket + Stunnel + DNSTT${C_RESET}"
echo
echo -e "  ${C_GREEN}${C_BOLD}3${C_RESET}  ${C_WHITE}Proxy Manager${C_RESET}"
echo -e "     ${C_GRAY}SSH + WebSocket + Stunnel${C_RESET}"
echo
echo -e "  ${C_GREEN}${C_BOLD}4${C_RESET}  ${C_WHITE}SSH Manager${C_RESET}"
echo -e "     ${C_GRAY}SSH management only${C_RESET}"
echo

while true; do
    echo -ne "${C_BLUE}${C_BOLD}➜ Choose an option [1-4]: ${C_RESET}"
    read -r CHOICE

    case "$CHOICE" in
        1)
            MENU_SOURCE="$BASE_URL/menu.sh"
            MANAGER_NAME="Full Manager"
            MANAGER_DESC="SSH + WebSocket + Stunnel + DNSTT + V2Ray"
            break
            ;;
        2)
            MENU_SOURCE="$BASE_URL/menu1.sh"
            MANAGER_NAME="Advanced Manager"
            MANAGER_DESC="SSH + WebSocket + Stunnel + DNSTT"
            break
            ;;
        3)
            MENU_SOURCE="$BASE_URL/menu2.sh"
            MANAGER_NAME="Proxy Manager"
            MANAGER_DESC="SSH + WebSocket + Stunnel"
            break
            ;;
        4)
            MENU_SOURCE="$BASE_URL/menu3.sh"
            MANAGER_NAME="SSH Manager"
            MANAGER_DESC="SSH management only"
            break
            ;;
        *)
            echo
            echo -e "${C_RED}✘ Invalid option.${C_RESET}"
            echo -e "${C_GRAY}Please select 1, 2, 3 or 4.${C_RESET}"
            echo
            ;;
    esac
done

# ============================================================
#                  INSTALLATION SCREEN
# ============================================================

clear

echo
echo -e "${C_PURPLE}${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_PURPLE}${C_BOLD}║${C_RESET}                  ${C_WHITE}${C_BOLD}INSTALLING AMOKHAN TECH${C_RESET}                   ${C_PURPLE}${C_BOLD}║${C_RESET}"
echo -e "${C_PURPLE}${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_RESET}"
echo

echo -e "${C_GRAY}Selected:${C_RESET} ${C_GREEN}${C_BOLD}${MANAGER_NAME}${C_RESET}"
echo -e "${C_GRAY}${MANAGER_DESC}${C_RESET}"
echo

sleep 1

# ============================================================
#                 INSTALLATION FUNCTIONS
# ============================================================

step() {
    echo -ne "  ${C_BLUE}●${C_RESET} $1"
}

done_step() {
    echo -e " ${C_GREEN}✓${C_RESET}"
}

fail_step() {
    echo -e " ${C_RED}✘${C_RESET}"
}

# ============================================================
#                     INSTALL JQ
# ============================================================

step "Preparing system dependencies..."

export DEBIAN_FRONTEND=noninteractive

NEED_PKGS=()
for _cmd in jq wget curl; do
    command -v "$_cmd" >/dev/null 2>&1 || NEED_PKGS+=("$_cmd")
done

if (( ${#NEED_PKGS[@]} > 0 )); then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y "${NEED_PKGS[@]}" >/dev/null 2>&1 || true
fi

if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    fail_step
    echo
    echo -e "${C_RED}Neither wget nor curl could be installed. Check your internet connection and try again.${C_RESET}"
    exit 1
fi

done_step

# ============================================================
#                  DOWNLOAD MENU
# ============================================================

step "Installing selected manager..."

fetch_file() {
    # usage: fetch_file <url> <output>
    if command -v wget >/dev/null 2>&1 && wget -4 -q --tries=3 --timeout=20 -O "$2" "$1" 2>/dev/null && [[ -s "$2" ]]; then
        return 0
    fi
    if command -v curl >/dev/null 2>&1 && curl -4 -fsSL --retry 3 --max-time 60 -o "$2" "$1" 2>/dev/null && [[ -s "$2" ]]; then
        return 0
    fi
    return 1
}

MENU_TMP="$(mktemp)"
if fetch_file "$MENU_SOURCE" "$MENU_TMP"; then
    install -m 755 "$MENU_TMP" "$MENU_FILE"
    rm -f "$MENU_TMP"
else
    rm -f "$MENU_TMP"
    fail_step
    echo
    echo -e "${C_RED}Unable to download the selected manager.${C_RESET}"
    echo -e "${C_GRAY}Source: ${MENU_SOURCE}${C_RESET}"
    exit 1
fi

done_step

# ============================================================
#                  SSH CONFIGURATION
# ============================================================

step "Applying AMOKHAN TECH SSH configuration..."

SSHD_URL="$BASE_URL/ssh"
SSHD_TMP="$(mktemp)"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="$SSHD_DROPIN_DIR/00-amokhantech.conf"

mkdir -p /run/sshd 2>/dev/null

if [[ ! -f "$SSHD_CONFIG" ]]; then
    mkdir -p "$(dirname "$SSHD_CONFIG")"
    touch "$SSHD_CONFIG"
fi

BACKUP="/etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP"

# Pakua kwa faili la muda (siyo moja kwa moja kwenye sshd_config).
download_sshd_config() {
    fetch_file "$SSHD_URL" "$SSHD_TMP"
}

# Mpango wa akiba: hauhitaji mtandao. Unaongeza mipangilio ya tunnel kwenye drop-in
# bila kubadilisha sshd_config yako ya sasa.
apply_builtin_ssh_config() {
    mkdir -p "$SSHD_DROPIN_DIR"
    if ! grep -Eqi '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_CONFIG"; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$SSHD_CONFIG"
    fi
    cat > "$SSHD_DROPIN" <<'SSHEOF'
# amokhanTech - SSH tunnel settings (built-in fallback)
PasswordAuthentication yes
AllowTcpForwarding yes
PermitTunnel yes
ClientAliveInterval 60
ClientAliveCountMax 3
UseDNS no
MaxSessions 100
MaxStartups 100:30:200
SSHEOF
    chmod 644 "$SSHD_DROPIN"
    if ! sshd -t 2>/dev/null; then
        rm -f "$SSHD_DROPIN"
        cp "$BACKUP" "$SSHD_CONFIG"
        return 1
    fi
    return 0
}

SSH_CONFIG_NOTE=""
SSH_CONFIG_OK=0

# 1) Jaribu config ya mtandaoni; 2) ikishindikana/ikiwa batili tumia ya ndani (kimya, bila onyo).
if download_sshd_config; then
    cp "$SSHD_TMP" "$SSHD_CONFIG"
    chmod 600 "$SSHD_CONFIG"
    if sshd -t 2>/dev/null; then
        SSH_CONFIG_OK=1
    else
        cp "$BACKUP" "$SSHD_CONFIG"
    fi
fi

if (( SSH_CONFIG_OK == 0 )); then
    if apply_builtin_ssh_config; then
        SSH_CONFIG_OK=1
    else
        SSH_CONFIG_NOTE="SSH config unchanged (could not validate new settings)."
    fi
fi

rm -f "$SSHD_TMP"

if [[ -n "$SSH_CONFIG_NOTE" ]]; then
    echo -e " ${C_YELLOW}⚠${C_RESET}"
    echo -e "    ${C_GRAY}${SSH_CONFIG_NOTE}${C_RESET}"
else
    done_step
fi

# ============================================================
#                  RESTART SSH
# ============================================================

step "Restarting SSH service..."

restart_ssh() {
    local svc
    for svc in ssh sshd; do
        if command -v systemctl >/dev/null 2>&1 && systemctl restart "$svc" >/dev/null 2>&1; then return 0; fi
        if command -v service >/dev/null 2>&1 && service "$svc" restart >/dev/null 2>&1; then return 0; fi
        if command -v rc-service >/dev/null 2>&1 && rc-service "$svc" restart >/dev/null 2>&1; then return 0; fi
        if [[ -x "/etc/init.d/$svc" ]] && "/etc/init.d/$svc" restart >/dev/null 2>&1; then return 0; fi
    done
    return 1
}

if restart_ssh; then
    done_step
else
    echo -e " ${C_YELLOW}⚠${C_RESET}"
fi

# ============================================================
#                MANAGER SETUP
# ============================================================

step "Configuring AMOKHAN TECH manager..."

if bash "$MENU_FILE" --install-setup >/dev/null 2>&1; then
    done_step
else
    echo -e " ${C_YELLOW}⚠${C_RESET}"
fi

# ============================================================
#                  AUTO START MENU
# ============================================================

step "Configuring automatic manager access..."

if ! grep -qxF "$MENU_FILE" /etc/profile 2>/dev/null; then
    echo "$MENU_FILE" >> /etc/profile
fi

done_step

# ============================================================
#                     CLEANUP
# ============================================================

step "Finalizing installation..."

chmod +x "$MENU_FILE"

sleep 1

done_step

# ============================================================
#                     COMPLETE
# ============================================================

clear

echo
echo -e "${C_GREEN}${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}║${C_RESET}                   ${C_WHITE}${C_BOLD}INSTALLATION COMPLETE${C_RESET}                    ${C_GREEN}${C_BOLD}║${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_RESET}"
echo

echo -e "  ${C_GRAY}Manager:${C_RESET}  ${C_GREEN}${C_BOLD}${MANAGER_NAME}${C_RESET}"
echo -e "  ${C_GRAY}Features:${C_RESET} ${C_WHITE}${MANAGER_DESC}${C_RESET}"
echo

echo -e "${C_CYAN}${C_BOLD}────────────────────────────────────────────────────────────${C_RESET}"
echo
echo -e "  ${C_YELLOW}${C_BOLD}Type ${C_WHITE}menu${C_YELLOW} to start the manager.${C_RESET}"
echo
echo -e "  ${C_GRAY} AMOKHAN TECH .Cyber👨‍💻${C_RESET}"
echo -e "  ${C_GRAY}Premium Proxy Server 🇹🇿${C_RESET}"
echo
echo -e "${C_CYAN}${C_BOLD}────────────────────────────────────────────────────────────${C_RESET}"
echo
