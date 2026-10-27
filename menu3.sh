#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_UL=$'\033[4m'

# Premium Color Palette
C_RED=$'\033[38;5;196m'      # Bright Red
C_GREEN=$'\033[38;5;46m'     # Neon Green
C_YELLOW=$'\033[38;5;226m'   # Bright Yellow
C_BLUE=$'\033[38;5;39m'      # Deep Sky Blue
C_PURPLE=$'\033[38;5;135m'   # Light Purple
C_CYAN=$'\033[38;5;51m'      # Cyan
C_WHITE=$'\033[38;5;255m'    # Bright White
C_GRAY=$'\033[38;5;245m'     # Gray
C_ORANGE=$'\033[38;5;208m'   # Orange

# Semantic Aliases
C_TITLE=$C_PURPLE
C_CHOICE=$C_CYAN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_GRAY
C_ACCENT=$C_ORANGE

DB_DIR="/etc/AmokhanTech"
DB_FILE="$DB_DIR/users.db"
INSTALL_FLAG_FILE="$DB_DIR/.install"
DNS_INFO_FILE="$DB_DIR/dns_info.conf"
SSH_BANNER_FILE="/etc/bannerssh"
LIMITER_SCRIPT="/usr/local/bin/AmokhanTech-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/AmokhanTech-limiter.service"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
BANDWIDTH_SCRIPT="/usr/local/bin/AmokhanTech-bandwidth.sh"
BANDWIDTH_SERVICE="/etc/systemd/system/AmokhanTech-bandwidth.service"
LEGACY_BANDWIDTH_DIR="/usr/local/bin/AmokhanTech-bandwidth"
TRIAL_CLEANUP_SCRIPT="/usr/local/bin/AmokhanTech-trial-cleanup.sh"
LOGIN_INFO_SCRIPT="/usr/local/bin/AmokhanTech-login-info.sh"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/AmokhanTech.conf"

# --- Web Panel Variables ---
PANEL_SCRIPT="/usr/local/bin/AmokhanTech-panel.py"
PANEL_HTML_DIR="$DB_DIR/panel"
PANEL_HTML_FILE="$DB_DIR/panel/index.html"
PANEL_CONF="$DB_DIR/panel.conf"
PANEL_SERVICE_FILE="/etc/systemd/system/AmokhanTech-panel.service"
PANEL_PORT=44380
PANEL_REPO_BASE="https://raw.githubusercontent.com/noten28/manage/main/panel"

DESEC_TOKEN="V55cFY8zTictLCPfviiuX5DHjs15"
DESEC_DOMAIN="manager.VisibleTech.qzz.io"


SELECTED_USER=""
UNINSTALL_MODE="interactive"
BANNER_CACHE_TTL=15
BANNER_CACHE_TS=0
BANNER_CACHE_OS_NAME=""
BANNER_CACHE_UP_TIME=""
BANNER_CACHE_RAM_USAGE=""
BANNER_CACHE_CPU_LOAD=""
BANNER_CACHE_ONLINE_USERS=0
BANNER_CACHE_TOTAL_USERS=0
SSH_SESSION_CACHE_TTL=10
SSH_SESSION_CACHE_TS=0
SSH_SESSION_CACHE_DB_MTIME=0
SSH_SESSION_TOTAL=0
APT_CACHE_READY=0
FF_USERS_GROUP="ffusers"
declare -A SSH_SESSION_COUNTS=()
declare -A SSH_SESSION_PIDS=()

# --- Package Manager Abstraction ---
FF_PKG_MGR=""
_detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        FF_PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
        FF_PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        FF_PKG_MGR="yum"
    elif command -v zypper &>/dev/null; then
        FF_PKG_MGR="zypper"
    elif command -v pacman &>/dev/null; then
        FF_PKG_MGR="pacman"
    else
        echo -e "${C_RED}❌ No supported package manager found (apt/dnf/yum/zypper/pacman).${C_RESET}"
        exit 1
    fi
}
_detect_pkg_manager

_map_pkg_names() {
    local -a result=()
    local pkg
    for pkg in "$@"; do
        case "$FF_PKG_MGR" in
            dnf|yum)
                case "$pkg" in
                    build-essential) result+=(gcc gcc-c++ make) ;;
                    libssl-dev) result+=(openssl-devel) ;;
                    libnspr4-dev) result+=(nspr-devel) ;;
                    libnss3-dev) result+=(nss-devel) ;;
                    stunnel4) result+=(stunnel) ;;
                    pkg-config) result+=(pkgconf) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            zypper)
                case "$pkg" in
                    build-essential) result+=(gcc gcc-c++ make) ;;
                    libssl-dev) result+=(libopenssl-devel) ;;
                    libnspr4-dev) result+=(mozilla-nspr-devel) ;;
                    libnss3-dev) result+=(mozilla-nss-devel) ;;
                    stunnel4) result+=(stunnel) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            pacman)
                case "$pkg" in
                    build-essential) result+=(base-devel) ;;
                    libssl-dev) result+=(openssl) ;;
                    libnspr4-dev) result+=(nspr) ;;
                    libnss3-dev) result+=(nss) ;;
                    stunnel4) result+=(stunnel) ;;
                    bc) result+=(bc) ;;
                    *) result+=("$pkg") ;;
                esac ;;
            *) result+=("$pkg") ;;
        esac
    done
    printf '%s\n' "${result[@]}"
}

if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
   exit 1
fi

get_ubuntu_codename() {
    local codename=""

    if [[ -r /etc/os-release ]]; then
        codename=$(awk -F= '/^(VERSION_CODENAME|UBUNTU_CODENAME)=/{gsub(/"/, "", $2); if ($2 != "") { print $2; exit }}' /etc/os-release 2>/dev/null)
    fi

    if [[ -z "$codename" ]] && command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi

    echo "$codename"
}

is_known_eol_ubuntu_codename() {
    case "$1" in
        yakkety|zesty|artful|cosmic|disco|eoan|groovy|hirsute|impish|kinetic|lunar|mantic|oracular|plucky)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

rewrite_ubuntu_apt_sources() {
    local mode="$1"
    local os_id=""
    local changed=false
    local file backup_file
    local from_archive to_archive from_security to_security from_ports to_ports
    local -a source_files=("/etc/apt/sources.list" /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources)

    if [[ -r /etc/os-release ]]; then
        os_id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null)
    fi
    [[ "$os_id" == "ubuntu" ]] || return 1

    case "$mode" in
        primary)
            from_archive='https?://([A-Za-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu'
            to_archive='http://archive.ubuntu.com/ubuntu'
            from_security='https?://security\.ubuntu\.com/ubuntu'
            to_security='http://security.ubuntu.com/ubuntu'
            from_ports='https?://ports\.ubuntu\.com/ubuntu-ports'
            to_ports='http://ports.ubuntu.com/ubuntu-ports'
            ;;
        old-releases)
            from_archive='https?://([A-Za-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu'
            to_archive='http://old-releases.ubuntu.com/ubuntu'
            from_security='https?://security\.ubuntu\.com/ubuntu'
            to_security='http://old-releases.ubuntu.com/ubuntu'
            from_ports='https?://ports\.ubuntu\.com/ubuntu-ports'
            to_ports='http://old-releases.ubuntu.com/ubuntu'
            ;;
        *)
            return 1
            ;;
    esac

    for file in "${source_files[@]}"; do
        [[ -f "$file" ]] || continue
        if grep -Eq "$from_archive|$from_security|$from_ports" "$file" 2>/dev/null; then
            backup_file="${file}.bak.AmokhanTech"
            [[ -f "$backup_file" ]] || cp "$file" "$backup_file" 2>/dev/null || true
            sed -i -E \
                -e "s|$from_archive|$to_archive|g" \
                -e "s|$from_security|$to_security|g" \
                -e "s|$from_ports|$to_ports|g" \
                "$file" 2>/dev/null
            changed=true
        fi
    done

    $changed
}

repair_ubuntu_apt_mirrors() {
    rewrite_ubuntu_apt_sources "primary"
}

switch_ubuntu_to_old_releases() {
    local codename
    codename=$(get_ubuntu_codename)
    [[ -n "$codename" ]] || return 1
    is_known_eol_ubuntu_codename "$codename" || return 1
    rewrite_ubuntu_apt_sources "old-releases"
}

ff_apt_update() {
    local -a apt_opts=(
        -o Acquire::Retries=3
        -o Acquire::ForceIPv4=true
        -o Acquire::http::Timeout=20
        -o Acquire::https::Timeout=20
        -o Acquire::http::Pipeline-Depth=0
    )

    if (( APT_CACHE_READY == 1 )); then
        return 0
    fi

    if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
        APT_CACHE_READY=1
        return 0
    fi

    if repair_ubuntu_apt_mirrors; then
        echo -e "${C_YELLOW}⚠️ APT mirror timed out. Switching Ubuntu sources to archive.ubuntu.com and retrying...${C_RESET}"
        apt-get clean >/dev/null 2>&1 || true
        if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
            APT_CACHE_READY=1
            return 0
        fi
    fi

    if switch_ubuntu_to_old_releases; then
        echo -e "${C_YELLOW}⚠️ Detected an end-of-life Ubuntu release. Switching APT sources to old-releases.ubuntu.com and retrying...${C_RESET}"
        apt-get clean >/dev/null 2>&1 || true
        if DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" update; then
            APT_CACHE_READY=1
            return 0
        fi
    fi

    echo -e "${C_RED}❌ Failed to refresh package lists. Please check VPS network, DNS, or blocked Ubuntu mirrors.${C_RESET}"
    return 1
}

ff_apt_install() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0

    ff_apt_update || return 1
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 install "${packages[@]}"
}

ff_apt_purge() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0 purge "${packages[@]}"
}

ff_pkg_install() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    local -a mapped=()
    mapfile -t mapped < <(_map_pkg_names "${packages[@]}")
    case "$FF_PKG_MGR" in
        apt) ff_apt_install "${mapped[@]}" ;;
        dnf) dnf install -y -q "${mapped[@]}" ;;
        yum) yum install -y -q "${mapped[@]}" ;;
        zypper) zypper install -y -q "${mapped[@]}" ;;
        pacman) pacman -S --noconfirm --needed "${mapped[@]}" ;;
        *) echo -e "${C_RED}❌ Unsupported package manager.${C_RESET}"; return 1 ;;
    esac
}

ff_pkg_purge() {
    local -a packages=("$@")
    (( ${#packages[@]} > 0 )) || return 0
    local -a mapped=()
    mapfile -t mapped < <(_map_pkg_names "${packages[@]}")
    case "$FF_PKG_MGR" in
        apt) ff_apt_purge "${mapped[@]}" ;;
        dnf) dnf remove -y -q "${mapped[@]}" ;;
        yum) yum remove -y -q "${mapped[@]}" ;;
        zypper) zypper remove -y "${mapped[@]}" ;;
        pacman) pacman -Rns --noconfirm "${mapped[@]}" 2>/dev/null ;;
        *) echo -e "${C_RED}❌ Unsupported package manager.${C_RESET}"; return 1 ;;
    esac
}

ff_pkg_autoremove() {
    case "$FF_PKG_MGR" in
        apt) apt-get autoremove -y >/dev/null 2>&1 ;;
        dnf) dnf autoremove -y -q >/dev/null 2>&1 ;;
        yum) yum autoremove -y -q >/dev/null 2>&1 ;;
        zypper) zypper packages --unneeded 2>/dev/null | awk -F'|' 'NR>3{print $3}' | xargs -r zypper remove -y >/dev/null 2>&1 ;;
        pacman) pacman -Qdtq 2>/dev/null | xargs -r pacman -Rns --noconfirm >/dev/null 2>&1 ;;
    esac
    return 0
}

ff_pkg_is_installed() {
    local pkg="$1"
    case "$FF_PKG_MGR" in
        apt) dpkg -s "$pkg" &>/dev/null ;;
        dnf|yum) rpm -q "$pkg" &>/dev/null ;;
        zypper) rpm -q "$pkg" &>/dev/null ;;
        pacman) pacman -Q "$pkg" &>/dev/null ;;
    esac
}

# Mandatory Dependency Check (Added jq and curl)
check_environment() {
    local missing_packages=()
    local cmd

    for cmd in bc jq curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_packages+=("$cmd")
        fi
    done

    if (( ${#missing_packages[@]} > 0 )); then
        echo -e "${C_YELLOW}⚠️ Installing missing dependencies: ${missing_packages[*]}${C_RESET}"
        ff_pkg_install "${missing_packages[@]}" >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Error: Failed to install required dependencies: ${missing_packages[*]}.${C_RESET}"
            exit 1
        }
    fi
}

ensure_AmokhanTech_dirs() {
    mkdir -p "$DB_DIR" "$SSL_CERT_DIR" "$BANDWIDTH_DIR" /etc/ssh/sshd_config.d
    touch "$DB_FILE"
}

ensure_AmokhanTech_system_group() {
    getent group "$FF_USERS_GROUP" >/dev/null 2>&1 || groupadd "$FF_USERS_GROUP" >/dev/null 2>&1 || true
}

db_has_user() {
    [[ -f "$DB_FILE" ]] || return 1
    awk -F: -v target="$1" '$1 == target { found=1; exit } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

is_AmokhanTech_orphan_user() {
    local username="$1"
    local passwd_line system_user _ uid _ home shell

    passwd_line=$(getent passwd "$username" 2>/dev/null) || return 1
    IFS=: read -r system_user _ uid _ _ home shell <<< "$passwd_line"
    [[ "$uid" =~ ^[0-9]+$ ]] || return 1
    db_has_user "$username" && return 1

    if id -nG "$username" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$FF_USERS_GROUP"; then
        return 0
    fi

    (( uid >= 1000 )) || return 1
    [[ "$home" == "/home/$username" || "$home" == /home/* ]] || return 1

    case "$shell" in
        /usr/sbin/nologin|/usr/bin/false|/bin/false) return 0 ;;
    esac

    return 1
}

get_AmokhanTech_orphan_users() {
    local username
    while IFS=: read -r username _rest; do
        [[ -n "$username" ]] || continue
        if is_AmokhanTech_orphan_user "$username"; then
            echo "$username"
        fi
    done < /etc/passwd
}

get_AmokhanTech_known_users() {
    local username
    local -A seen_users=()

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r username _rest; do
            [[ -n "$username" && "$username" != \#* ]] || continue
            seen_users["$username"]=1
        done < "$DB_FILE"
    fi

    while IFS= read -r username; do
        [[ -n "$username" ]] && seen_users["$username"]=1
    done < <(get_AmokhanTech_orphan_users)

    (( ${#seen_users[@]} > 0 )) || return 0
    printf "%s\n" "${!seen_users[@]}" | sort
}

delete_AmokhanTech_user_accounts() {
    local -a users_to_delete=("$@")
    local username

    [[ ${#users_to_delete[@]} -gt 0 ]] || return 0

    for username in "${users_to_delete[@]}"; do
        [[ -n "$username" ]] || continue
        killall -u "$username" -9 &>/dev/null
        pkill -9 -u "$username" &>/dev/null
        sleep 0.5
        if id "$username" &>/dev/null; then
            if userdel -rf "$username" &>/dev/null; then
                echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted."
            else
                # Retry after harder kill
                pkill -9 -u "$username" &>/dev/null
                sleep 1
                if userdel -rf "$username" &>/dev/null; then
                    echo -e " ✅ System user '${C_YELLOW}$username${C_RESET}' deleted (retry)."
                else
                    echo -e " ❌ Failed to delete system user '${C_YELLOW}$username${C_RESET}'."
                fi
            fi
        else
            echo -e " ℹ️ System user '${C_YELLOW}$username${C_RESET}' was already missing. Removing manager data only."
        fi
        rm -f "$BANDWIDTH_DIR/${username}.usage"
        rm -f "$BANDWIDTH_DIR/${username}.daily_usage"
        rm -f "$BANDWIDTH_DIR/${username}.conn_locked"
        rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
        rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
        rm -f "$DB_DIR/admin_msg/users/${username}.txt" "$DB_DIR/admin_msg/users/${username}.off" "$DB_DIR/admin_msg/rendered/${username}.html"
    done

    if [[ -f "$DB_FILE" ]]; then
        local db_tmp
        db_tmp=$(mktemp)
        awk -F: 'NR==FNR { drop[$1]=1; next } !($1 in drop)' <(printf "%s\n" "${users_to_delete[@]}") "$DB_FILE" > "$db_tmp" && mv "$db_tmp" "$DB_FILE"
        rm -f "$db_tmp" 2>/dev/null
    fi

    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

require_interactive_terminal() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo -e "${C_RED}❌ Error: The Amokhan Tech menu must be run from an interactive terminal.${C_RESET}"
        exit 1
    fi
}

initial_setup() {
    echo -e "${C_BLUE}⚙️ Initializing Amokhan Tech Manager setup...${C_RESET}"
    check_environment
    
    ensure_AmokhanTech_dirs
    ensure_AmokhanTech_system_group
    
    echo -e "${C_BLUE}🔹 Configuring user limiter service...${C_RESET}"
    setup_limiter_service
    
    echo -e "${C_BLUE}🔹 Configuring bandwidth monitoring service...${C_RESET}"
    setup_bandwidth_service
    
    echo -e "${C_BLUE}🔹 Installing trial account cleanup script...${C_RESET}"
    setup_trial_cleanup_script
    
    echo -e "${C_BLUE}🔹 Cleaning legacy dynamic SSH banner hooks...${C_RESET}"
    disable_dynamic_ssh_banner_system
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    
    if [ ! -f "$INSTALL_FLAG_FILE" ]; then
        touch "$INSTALL_FLAG_FILE"
    fi
    echo -e "${C_GREEN}✅ Setup finished.${C_RESET}"
}

_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_and_open_firewall_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and port ${port}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port/$protocol"
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
             echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --list-ports --permanent | grep -qw "$port/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and port ${port}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Port ${port}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Port ${port}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port ${port}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming ports are open.${C_RESET}"
    fi
    return 0
}

check_and_open_firewall_port_range() {
    local port_range="$1"
    local protocol="${2:-tcp}"
    local firewall_detected=false

    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        firewall_detected=true
        if ! ufw status | grep -Fq "$port_range/$protocol"; then
            echo -e "${C_YELLOW}🔥 UFW firewall is active and range ${port_range}/${protocol} is closed.${C_RESET}"
            read -p "👉 Do you want to open this port range now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                ufw allow "$port_range/$protocol"
                echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} has been opened in UFW.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Range ${port_range}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} is already open in UFW.${C_RESET}"
        fi
    fi

    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall_detected=true
        if ! firewall-cmd --quiet --query-port="$port_range/$protocol"; then
            echo -e "${C_YELLOW}🔥 firewalld is active and range ${port_range}/${protocol} is not open.${C_RESET}"
            read -p "👉 Do you want to open this port range now? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                firewall-cmd --add-port="$port_range/$protocol" --permanent
                firewall-cmd --reload
                echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} has been opened in firewalld.${C_RESET}"
            else
                echo -e "${C_RED}❌ Warning: Range ${port_range}/${protocol} was not opened. The service may not work correctly.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Range ${port_range}/${protocol} is already open in firewalld.${C_RESET}"
        fi
    fi

    if ! $firewall_detected; then
        echo -e "${C_BLUE}ℹ️ No active firewall (UFW or firewalld) detected. Assuming range ${port_range}/${protocol} is open.${C_RESET}"
    fi
    return 0
}

check_and_free_ports() {
    local ports_to_check=("$@")
    for port in "${ports_to_check[@]}"; do
        echo -e "\n${C_BLUE}🔎 Checking if port $port is available...${C_RESET}"
        local conflicting_process_info
        conflicting_process_info=$(
            ss -H -lntp "( sport = :$port )" 2>/dev/null
            ss -H -lunp "( sport = :$port )" 2>/dev/null
        )
        
        if [[ -n "$conflicting_process_info" ]]; then
            local conflicting_pid
            conflicting_pid=$(echo "$conflicting_process_info" | grep -oP 'pid=\K[0-9]+' | head -n 1)
            local conflicting_name
            conflicting_name=$(echo "$conflicting_process_info" | grep -oP 'users:\(\("(\K[^"]+)' | head -n 1)
            
            echo -e "${C_YELLOW}⚠️ Warning: Port $port is in use by process '${conflicting_name:-unknown}' (PID: ${conflicting_pid:-N/A}).${C_RESET}"
            read -p "👉 Do you want to attempt to stop this process? (y/n): " kill_confirm
            if [[ "$kill_confirm" == "y" || "$kill_confirm" == "Y" ]]; then
                if [[ -z "$conflicting_pid" ]]; then
                    echo -e "${C_RED}❌ Could not determine which PID owns port $port. Please free it manually.${C_RESET}"
                    return 1
                fi
                echo -e "${C_GREEN}🛑 Stopping process PID $conflicting_pid...${C_RESET}"
                systemctl stop "$(ps -p "$conflicting_pid" -o comm=)" &>/dev/null || kill -9 "$conflicting_pid"
                sleep 2
                
                if ss -H -lntp "( sport = :$port )" 2>/dev/null | grep -q . || ss -H -lunp "( sport = :$port )" 2>/dev/null | grep -q .; then
                     echo -e "${C_RED}❌ Failed to free port $port. Please handle it manually. Aborting.${C_RESET}"
                     return 1
                else
                     echo -e "${C_GREEN}✅ Port $port has been successfully freed.${C_RESET}"
                fi
            else
                echo -e "${C_RED}❌ Cannot proceed without freeing port $port. Aborting.${C_RESET}"
                return 1
            fi
        else
            echo -e "${C_GREEN}✅ Port $port is free to use.${C_RESET}"
        fi
    done
    return 0
}

setup_limiter_service() {
    # Combined limiter + bandwidth monitoring
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# Amokhan Tech limiter version 2026-10-25.1
DB_FILE="/etc/AmokhanTech/users.db"
BW_DIR="/etc/AmokhanTech/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/AmokhanTech/banners"
ADMIN_MSG_DIR="/etc/AmokhanTech/admin_msg"
SCAN_INTERVAL=10
CONN_LOCK_DURATION=60

mkdir -p "$BW_DIR" "$PID_DIR"
shopt -s nullglob

html_escape() {
    local s="$1"
    s=${s//&/"&amp;"}
    s=${s//</"&lt;"}
    s=${s//>/"&gt;"}
    printf '%s' "$s"
}

write_banner_if_changed() {
    local user="$1"
    local content="$2"
    local banner_file="$BANNER_DIR/${user}.txt"
    local tmp_file="${banner_file}.tmp"

    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
}

# Excess sessions are killed immediately every scan cycle. No account locking.

while true; do
    if [[ ! -s "$DB_FILE" ]]; then
        sleep "$SCAN_INTERVAL"
        continue
    fi
    
    # Daily reset logic
    today=$(date +%Y-%m-%d)
    if [[ ! -f "$BW_DIR/current_date" ]]; then
        echo "$today" > "$BW_DIR/current_date"
    fi
    saved_date=$(cat "$BW_DIR/current_date" 2>/dev/null || echo "$today")
    if [[ "$today" != "$saved_date" ]]; then
        # New day! Reset daily usage and unlock users locked due to daily limit
        rm -f "$BW_DIR/"*.daily_usage 2>/dev/null
        for locked_file in "$BW_DIR/"*.daily_locked; do
            [[ -f "$locked_file" ]] || continue
            locked_user=$(basename "$locked_file" .daily_locked)
            usermod -U "$locked_user" &>/dev/null
            rm -f "$locked_file"
        done
        echo "$today" > "$BW_DIR/current_date"
    fi

    # Connection limit auto-unlock: check marker files and unlock after CONN_LOCK_DURATION seconds
    for conn_lock_file in "$BW_DIR/"*.conn_locked; do
        [[ -f "$conn_lock_file" ]] || continue
        lock_ts=0
        read -r lock_ts < "$conn_lock_file" 2>/dev/null || lock_ts=0
        [[ "$lock_ts" =~ ^[0-9]+$ ]] || lock_ts=0
        printf -v now_ts '%(%s)T' -1
        if (( now_ts - lock_ts >= CONN_LOCK_DURATION )); then
            conn_locked_user=$(basename "$conn_lock_file" .conn_locked)
            usermod -U "$conn_locked_user" &>/dev/null
            rm -f "$conn_lock_file"
        fi
    done

    printf -v current_ts '%(%s)T' -1
    dynamic_banners_enabled=false

    # Reset associative arrays each cycle (unset first to avoid stale data)
    unset session_pids locked_users uid_to_user loginuid_pids
    declare -A session_pids=()
    declare -A locked_users=()
    declare -A uid_to_user=()
    declare -A loginuid_pids=()

    while IFS=: read -r username _ uid _rest; do
        [[ -n "$username" && "$uid" =~ ^[0-9]+$ ]] && uid_to_user["$uid"]="$username"
    done < /etc/passwd

    # Method 1: process owner from ps (primary source for connection counting)
    # sshd-session is the user-owned process on Ubuntu 24.04+ (OpenSSH 9.8+)
    # On Ubuntu 22, the per-session sshd is user-owned instead.
    # Either way, exactly 1 user-owned process exists per SSH session.
    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" ]]; then
            session_pids["$ssh_owner"]+="$ssh_pid "
        fi
    done < <(ps -C sshd,sshd-session -o pid=,user= 2>/dev/null)

    # Method 2: kernel loginuid (reliable even when sshd runs as root)
    for p in /proc/[0-9]*/loginuid; do
        [[ -f "$p" ]] || continue
        login_uid=""
        read -r login_uid < "$p" || login_uid=""
        [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]] || continue

        session_user="${uid_to_user[$login_uid]}"
        [[ -n "$session_user" ]] || continue

        pid_dir=$(dirname "$p")
        pid_num=$(basename "$pid_dir")
        comm=""
        read -r comm < "$pid_dir/comm" || comm=""
        [[ "$comm" == "sshd" ]] || continue

        ppid_val=""
        while read -r key value; do
            if [[ "$key" == "PPid:" ]]; then
                ppid_val="${value:-}"
                break
            fi
        done < "$pid_dir/status"
        [[ "$ppid_val" == "1" ]] && continue

        loginuid_pids["$session_user"]+="$pid_num "
    done

    # Detect locked users via /etc/shadow (cheaper than passwd -Sa)
    if [[ -r /etc/shadow ]]; then
        while IFS=: read -r shadow_user shadow_hash _rest; do
            [[ -n "$shadow_user" && "${shadow_hash:0:1}" == "!" ]] && locked_users["$shadow_user"]=1
        done < /etc/shadow
    else
        while read -r passwd_user _ passwd_status _rest; do
            [[ "$passwd_status" == "L" ]] && locked_users["$passwd_user"]=1
        done < <(passwd -Sa 2>/dev/null)
    fi

    if [[ -f "/etc/AmokhanTech/banners_enabled" ]]; then
        mkdir -p "$BANNER_DIR"
        dynamic_banners_enabled=true
    fi

    while IFS=: read -r user pass expiry limit bandwidth_gb daily_bandwidth_gb _extra; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        
        [[ ! "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && daily_bandwidth_gb=0

        # CRITICAL: unset before declare to reset per-user (bash declare is function-scoped)
        unset unique_pids
        declare -A unique_pids=()

        # Use ONLY ps-based session_pids for connection counting.
        # loginuid_pids can double-count (root-owned sshd has user's loginuid on Ubuntu 24)
        for pid in ${session_pids[$user]}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        online_count=${#unique_pids[@]}
        user_locked=false
        if [[ -n "${locked_users[$user]+x}" ]]; then
            user_locked=true
        fi

        expiry_ts=0
        if [[ "$expiry" != "Never" && -n "$expiry" && "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    killall -u "$user" -9 &>/dev/null
                    locked_users["$user"]=1
                fi
                continue
            fi
        fi

        [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        if (( online_count > limit )); then
            # Kill only the EXCESS sessions, keep the oldest ones alive
            sorted_pids=()
            for pid in "${!unique_pids[@]}"; do
                sorted_pids+=("$pid")
            done
            IFS=$'\n' sorted_pids=($(sort -n <<<"${sorted_pids[*]}")); unset IFS

            for (( i=limit; i<${#sorted_pids[@]}; i++ )); do
                kill -9 "${sorted_pids[$i]}" &>/dev/null
            done

            # Remove killed PIDs from unique_pids so bandwidth tracking is correct
            for (( i=limit; i<${#sorted_pids[@]}; i++ )); do
                unset unique_pids["${sorted_pids[$i]}"]
            done
            online_count=${#unique_pids[@]}
        fi

        if $dynamic_banners_enabled; then
            banner_content=""
            if $dynamic_banners_enabled; then
            days_left="N/A"
            if [[ "$expiry" != "Never" && -n "$expiry" && "$expiry_ts" =~ ^[0-9]+$ && $expiry_ts -gt 0 ]]; then
                diff_secs=$((expiry_ts - current_ts))
                if (( diff_secs <= 0 )); then
                    days_left="EXPIRED"
                else
                    d_l=$(( diff_secs / 86400 ))
                    h_l=$(( (diff_secs % 86400) / 3600 ))
                    if (( d_l == 0 )); then
                        days_left="${h_l}h left"
                    else
                        days_left="${d_l}d ${h_l}h"
                    fi
                fi
            fi

            bw_info="Unlimited"
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                usagefile="$BW_DIR/${user}.usage"
                accum_disp=0
                if [[ -f "$usagefile" ]]; then
                    read -r accum_disp < "$usagefile"
                    [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
                fi
                used_gb_int=$((accum_disp / 1073741824))
                used_gb_frac=$(( (accum_disp % 1073741824) * 100 / 1073741824 ))
                printf -v used_gb "%d.%02d" "$used_gb_int" "$used_gb_frac"
                quota_b=$(( ${bandwidth_gb%%.*} * 1073741824 ))
                remain_b=$(( quota_b - accum_disp ))
                (( remain_b < 0 )) && remain_b=0
                remain_gb_int=$((remain_b / 1073741824))
                remain_gb_frac=$(( (remain_b % 1073741824) * 100 / 1073741824 ))
                printf -v remain_gb "%d.%02d" "$remain_gb_int" "$remain_gb_frac"
                bw_info="${used_gb}/${bandwidth_gb} GB used | ${remain_gb} GB left"
            fi
            
            banner_content="<center>"
            banner_content+="<br><font color=\"blue\"><b>🅐︎🅜︎🅞︎🅚︎🅗︎🅐︎🅝︎ 🅣🅔🅒🅗 🅜🅐🅝🅐🅖🅔🅡</b></font><br>"
            banner_content+="<font color=\"red\"><b>ғᴏᴜɴᴅᴇʀ ᴏʀ sᴄʀɪᴘᴛ . Cyber👨‍💻</b></font><br>"
            banner_content+="<font color=\"yellow\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"
            banner_content+="<font color=\"cyan\"><b>✨🅃🄰🄰🅁🄸🄵🄰 🅉🄰 🄰🄲🄲🄾🅄🄽🅃✨</b></font><br>"
            banner_content+="<font color=\"magenta\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br><br>"

            banner_content+="<font color=\"orange\">👤<b>🅹🅸🅽🅰 🅻🅰 🅰🅲🅲🅾🆄🅽🆃:</b></font> <font color=\"white\">$user</font><br>"
            banner_content+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"

            banner_content+="<font color=\"lime\">📅<b> 🅂🄸🄺🅄 🅈🄰🄺🅄🄴🅇🄿🄸🅁🄴 :</b></font> <font color=\"red\">$expiry ($days_left)</font><br>"
            banner_content+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"

            if [[ "$bandwidth_gb" != "0" ]]; then
                banner_content+="<font color=\"cyan\">📊<b>█▓▒░MATUMIZI░▒▓█:</b></font> <font color=\"white\">$bw_info</font><br>"
                banner_content+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"
            fi

            if [[ "$daily_bandwidth_gb" != "0" ]]; then
                daily_usagefile="$BW_DIR/${user}.daily_usage"
                accum_disp=0
                if [[ -f "$daily_usagefile" ]]; then
                    read -r accum_disp < "$daily_usagefile"
                    [[ "$accum_disp" =~ ^[0-9]+$ ]] || accum_disp=0
                fi
                used_gb_int=$((accum_disp / 1073741824))
                used_gb_frac=$(( (accum_disp % 1073741824) * 100 / 1073741824 ))
                printf -v used_gb "%d.%02d" "$used_gb_int" "$used_gb_frac"
                quota_b=$(( ${daily_bandwidth_gb%%.*} * 1073741824 ))
                remain_b=$(( quota_b - accum_disp ))
                (( remain_b < 0 )) && remain_b=0
                remain_gb_int=$((remain_b / 1073741824))
                remain_gb_frac=$(( (remain_b % 1073741824) * 100 / 1073741824 ))
                printf -v remain_gb "%d.%02d" "$remain_gb_int" "$remain_gb_frac"
                daily_bw_info="${used_gb}/${daily_bandwidth_gb} GB used | ${remain_gb} GB left"
                banner_content+="<font color=\"white\">📊 <b>𝕄𝔸𝕋𝕌𝕄𝕀ℤ𝕀 𝕐𝔸 𝕊𝕀𝕂𝕌:</b></font> <font color=\"cyan\">$daily_bw_info</font><br>"
                banner_content+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"
            fi

            banner_content+="<font color=\"gold\">🖲️ <b>FILE ZILIZO CONNECT:</b></font> <font color=\"lightgreen\">$online_count/$limit</font><br>"
            banner_content+="<font color=\"magenta\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br><br>"
            fi

            # ---- Admin Message hook (read-only) ----
            # Admin Message ina huduma yake; hapa tunasoma tu kipande chake kilichokamilika (kama kipo).
            admin_html=""
            if [[ -s "$ADMIN_MSG_DIR/rendered/${user}.html" ]]; then
                IFS= read -r admin_html < "$ADMIN_MSG_DIR/rendered/${user}.html"
            fi
            banner_content+="${admin_html}</center>"

            write_banner_if_changed "$user" "$banner_content"
        fi

        [[ ( -z "$bandwidth_gb" || "$bandwidth_gb" == "0" ) && ( -z "$daily_bandwidth_gb" || "$daily_bandwidth_gb" == "0" ) ]] && continue

        usagefile="$BW_DIR/${user}.usage"
        accumulated=0
        if [[ -f "$usagefile" ]]; then
            read -r accumulated < "$usagefile"
            [[ "$accumulated" =~ ^[0-9]+$ ]] || accumulated=0
        fi

        if (( ${#unique_pids[@]} == 0 )); then
            rm -f "$PID_DIR/${user}__"*.last 2>/dev/null
            continue
        fi

        delta_total=0
        for pid in "${!unique_pids[@]}"; do
            io_file="/proc/$pid/io"
            cur=0
            if [[ -r "$io_file" ]]; then
                rchar=0
                wchar=0
                while read -r key value; do
                    case "$key" in
                        rchar:) rchar=${value:-0} ;;
                        wchar:) wchar=${value:-0} ;;
                    esac
                done < "$io_file"
                cur=$((rchar + wchar))
            fi

            pidfile="$PID_DIR/${user}__${pid}.last"
            if [[ -f "$pidfile" ]]; then
                read -r prev < "$pidfile"
                [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
                if (( cur >= prev )); then
                    d=$((cur - prev))
                else
                    d=$cur
                fi
                delta_total=$((delta_total + d))
            fi
            printf "%s\n" "$cur" > "$pidfile"
        done

        for f in "$PID_DIR/${user}__"*.last; do
            [[ -f "$f" ]] || continue
            fpid=${f##*__}
            fpid=${fpid%.last}
            [[ -d "/proc/$fpid" ]] || rm -f "$f"
        done

        new_total=$((accumulated + delta_total))
        printf "%s\n" "$new_total" > "$usagefile"

        if awk "BEGIN{exit(!($bandwidth_gb > 0))}" 2>/dev/null; then
            quota_bytes=$(awk "BEGIN{printf \"%.0f\", $bandwidth_gb * 1073741824}")
            if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( quota_bytes > 0 && new_total >= quota_bytes )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    locked_users["$user"]=1
                    user_locked=true
                fi
            fi
        fi
        
        daily_usagefile="$BW_DIR/${user}.daily_usage"
        daily_accumulated=0
        if [[ -f "$daily_usagefile" ]]; then
            read -r daily_accumulated < "$daily_usagefile"
            [[ "$daily_accumulated" =~ ^[0-9]+$ ]] || daily_accumulated=0
        fi
        new_daily_total=$((daily_accumulated + delta_total))
        printf "%s\n" "$new_daily_total" > "$daily_usagefile"
        
        if awk "BEGIN{exit(!($daily_bandwidth_gb > 0))}" 2>/dev/null; then
            d_quota_bytes=$(awk "BEGIN{printf \"%.0f\", $daily_bandwidth_gb * 1073741824}")
            if [[ "$d_quota_bytes" =~ ^[0-9]+$ ]] && (( d_quota_bytes > 0 && new_daily_total >= d_quota_bytes )); then
                if ! $user_locked; then
                    usermod -L "$user" &>/dev/null
                    locked_users["$user"]=1
                    user_locked=true
                    touch "$BW_DIR/${user}.daily_locked"
                fi
            fi
        fi
    done < "$DB_FILE"

    sleep "$SCAN_INTERVAL"
done
EOF
    chmod +x "$LIMITER_SCRIPT"
    # Strip DOS line endings in case menu.sh was uploaded from Windows
    sed -i 's/\r$//' "$LIMITER_SCRIPT" 2>/dev/null

    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=Amokhan Tech Active User Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
MemoryHigh=48M
MemoryMax=64M

[Install]
WantedBy=multi-user.target
EOF
    sed -i 's/\r$//' "$LIMITER_SERVICE" 2>/dev/null

    pkill -f "AmokhanTech-limiter" 2>/dev/null

    if ! systemctl is-active --quiet AmokhanTech-limiter; then
        systemctl daemon-reload
        systemctl enable AmokhanTech-limiter &>/dev/null
        systemctl start AmokhanTech-limiter --no-block &>/dev/null
        
    else
        systemctl restart AmokhanTech-limiter --no-block &>/dev/null
        
    fi
}

sync_runtime_components_if_needed() {
    local limiter_marker="# Amokhan Tech limiter version 2026-10-25.1"
    cleanup_legacy_bandwidth_runtime
    setup_trial_cleanup_script >/dev/null 2>&1
    if [[ ! -f "$LIMITER_SCRIPT" ]] || ! grep -Fqx "$limiter_marker" "$LIMITER_SCRIPT" 2>/dev/null; then
        setup_limiter_service >/dev/null 2>&1
    fi
    if banner_routing_needed; then
        update_ssh_banners_config
    elif [[ -f "$SSHD_FF_CONFIG" ]]; then
        disable_dynamic_ssh_banner_system
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
}


setup_bandwidth_service() {
    mkdir -p "$BANDWIDTH_DIR"
    # Bandwidth monitoring is now integrated into the limiter service above.
    cleanup_legacy_bandwidth_runtime
}

cleanup_legacy_bandwidth_runtime() {
    local needs_reload=false

    systemctl stop AmokhanTech-bandwidth &>/dev/null || true
    systemctl disable AmokhanTech-bandwidth &>/dev/null || true
    pkill -f "AmokhanTech-bandwidth" &>/dev/null || true

    if [[ -e "$BANDWIDTH_SERVICE" || -e "$BANDWIDTH_SCRIPT" || -e "$LEGACY_BANDWIDTH_DIR" ]]; then
        rm -f "$BANDWIDTH_SERVICE" "$BANDWIDTH_SCRIPT" 2>/dev/null
        rm -rf "$LEGACY_BANDWIDTH_DIR" 2>/dev/null
        needs_reload=true
    fi

    if $needs_reload; then
        systemctl daemon-reload &>/dev/null || true
    fi
}

setup_trial_cleanup_script() {
    cat > "$TRIAL_CLEANUP_SCRIPT" << 'TREOF'
#!/bin/bash
# Amokhan Tech Trial Account Auto-Cleanup
# Usage: AmokhanTech-trial-cleanup.sh <username>
DB_FILE="/etc/AmokhanTech/users.db"
BW_DIR="/etc/AmokhanTech/bandwidth"

username="$1"
if [[ -z "$username" ]]; then exit 1; fi

db_line=$(grep "^${username}:" "$DB_FILE" 2>/dev/null | head -n 1)
if [[ -z "$db_line" ]]; then exit 0; fi

IFS=: read -r _ _ _ _ _ trial_marker _rest <<< "$db_line"
if [[ "$trial_marker" != "trial" ]]; then
    exit 0
fi

# Kill active sessions
killall -u "$username" -9 &>/dev/null
pkill -9 -u "$username" &>/dev/null
sleep 1

# Delete system user
userdel -rf "$username" &>/dev/null

# Remove from DB
sed -i "/^${username}:/d" "$DB_FILE"

# Remove bandwidth tracking
rm -f "$BW_DIR/${username}.usage"
rm -rf "$BW_DIR/pidtrack/${username}"
rm -f "/etc/AmokhanTech/admin_msg/users/${username}.txt" "/etc/AmokhanTech/admin_msg/users/${username}.off" "/etc/AmokhanTech/admin_msg/rendered/${username}.html"
TREOF
    chmod +x "$TRIAL_CLEANUP_SCRIPT"
}

disable_dynamic_ssh_banner_system() {
    rm -f "$DB_DIR/banners_enabled" /usr/local/bin/AmokhanTech-login-info.sh 2>/dev/null
    if [[ -f "$DB_DIR/admin_msg/global_enabled" ]] || compgen -G "$DB_DIR/admin_msg/users/*.txt" >/dev/null; then
        # Admin Message keeps working on its own: keep the routing, drop the dynamic content
        rm -f "$DB_DIR/banners/"*.txt 2>/dev/null
        update_ssh_banners_config
    else
        rm -f "$SSHD_FF_CONFIG" 2>/dev/null
        rm -rf "$DB_DIR/banners" 2>/dev/null
    fi
    invalidate_banner_cache
}

disable_static_ssh_banner_in_sshd_config() {
    sed -i.bak -E "s|^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$|# Banner $SSH_BANNER_FILE|" /etc/ssh/sshd_config 2>/dev/null
}

is_static_ssh_banner_enabled() {
    grep -q -E "^[[:space:]]*Banner[[:space:]]+$SSH_BANNER_FILE[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null && [ -f "$SSH_BANNER_FILE" ]
}

is_dynamic_ssh_banner_enabled() {
    [[ -f "/etc/AmokhanTech/banners_enabled" && -f "$SSHD_FF_CONFIG" ]]
}

get_ssh_banner_mode() {
    if is_dynamic_ssh_banner_enabled; then
        echo "dynamic"
    elif is_static_ssh_banner_enabled; then
        echo "static"
    else
        echo "disabled"
    fi
}

refresh_dynamic_banner_routing_if_enabled() {
    if banner_routing_needed; then
        update_ssh_banners_config
    fi
}

update_ssh_banners_config() {
    local tmp_conf

    if ! banner_routing_needed; then
        rm -rf "$DB_DIR/banners" 2>/dev/null
        if [[ -f "$SSHD_FF_CONFIG" ]]; then
            rm -f "$SSHD_FF_CONFIG" 2>/dev/null
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
        fi
        return
    fi

    ensure_AmokhanTech_dirs
    tmp_conf="/tmp/ff_banners_new.conf"
    echo "# Amokhan Tech - Dynamic per-user SSH banners" > "$tmp_conf"

    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r u _rest; do
            [[ -z "$u" || "$u" == \#* ]] && continue
            echo "Match User $u" >> "$tmp_conf"
            echo "    Banner /etc/AmokhanTech/banners/${u}.txt" >> "$tmp_conf"
        done < "$DB_FILE"
    fi

    if ! cmp -s "$tmp_conf" "$SSHD_FF_CONFIG" 2>/dev/null; then
        mv "$tmp_conf" "$SSHD_FF_CONFIG"
        if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
            echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        fi
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    else
        rm -f "$tmp_conf"
    fi
}

setup_ssh_login_info() {
    ensure_AmokhanTech_dirs || return 1
    if ! touch "/etc/AmokhanTech/banners_enabled"; then
        echo -e "${C_RED}❌ Failed to enable dynamic SSH banners.${C_RESET}"
        return 1
    fi
    disable_static_ssh_banner_in_sshd_config
    update_ssh_banners_config
    return 0
}


generate_dns_record() {
    echo -e "\n${C_BLUE}⚙️ Generating a random domain...${C_RESET}"
    if ! command -v jq &> /dev/null; then
        echo -e "${C_YELLOW}⚠️ jq not found, attempting to install...${C_RESET}"
        ff_pkg_install jq >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to install jq. Cannot manage DNS records.${C_RESET}"
            return 1
        }
    fi
    local SERVER_IPV4
    SERVER_IPV4=$(curl -s -4 icanhazip.com)
    if ! _is_valid_ipv4 "$SERVER_IPV4"; then
        echo -e "\n${C_RED}❌ Error: Could not retrieve a valid public IPv4 address from icanhazip.com.${C_RESET}"
        echo -e "${C_YELLOW}ℹ️ Please check your server's network connection and DNS resolver settings.${C_RESET}"
        echo -e "   Output received: '$SERVER_IPV4'"
        return 1
    fi

    local SERVER_IPV6
    SERVER_IPV6=$(curl -s -6 icanhazip.com --max-time 5)

    local RANDOM_SUBDOMAIN="vps-$(tr -dc a-z0-9 < /dev/urandom | head -c 8)"
    local FULL_DOMAIN="$RANDOM_SUBDOMAIN.$DESEC_DOMAIN"
    local HAS_IPV6="false"

    local API_DATA
    API_DATA=$(printf '[{"subname": "%s", "type": "A", "ttl": 3600, "records": ["%s"]}]' "$RANDOM_SUBDOMAIN" "$SERVER_IPV4")

    if [[ -n "$SERVER_IPV6" ]]; then
        local aaaa_record
        aaaa_record=$(printf ',{"subname": "%s", "type": "AAAA", "ttl": 3600, "records": ["%s"]}' "$RANDOM_SUBDOMAIN" "$SERVER_IPV6")
        API_DATA="${API_DATA%?}${aaaa_record}]"
        HAS_IPV6="true"
    fi

    local CREATE_RESPONSE
    CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
        --data "$API_DATA")
    
    local HTTP_CODE=${CREATE_RESPONSE: -3}
    local RESPONSE_BODY=${CREATE_RESPONSE:0:${#CREATE_RESPONSE}-3}

    if [[ "$HTTP_CODE" -ne 201 ]]; then
        echo -e "${C_RED}❌ Failed to create DNS records. API returned HTTP $HTTP_CODE.${C_RESET}"
        if ! echo "$RESPONSE_BODY" | jq . > /dev/null 2>&1; then
            echo "Raw Response: $RESPONSE_BODY"
        else
            echo "Response: $RESPONSE_BODY" | jq
        fi
        return 1
    fi
    
    cat > "$DNS_INFO_FILE" <<-EOF
SUBDOMAIN="$RANDOM_SUBDOMAIN"
FULL_DOMAIN="$FULL_DOMAIN"
HAS_IPV6="$HAS_IPV6"
EOF
    echo -e "\n${C_GREEN}✅ Successfully created domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
}

delete_dns_record() {
    if [ ! -f "$DNS_INFO_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No domain to delete.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}🗑️ Deleting DNS records...${C_RESET}"
    source "$DNS_INFO_FILE"
    if [[ -z "$SUBDOMAIN" ]]; then
        echo -e "${C_RED}❌ Could not read record details from config file. Skipping deletion.${C_RESET}"
        return
    fi

    curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/A/" \
         -H "Authorization: Token $DESEC_TOKEN" > /dev/null

    if [[ "$HAS_IPV6" == "true" ]]; then
        curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$SUBDOMAIN/AAAA/" \
             -H "Authorization: Token $DESEC_TOKEN" > /dev/null
    fi

    echo -e "\n${C_GREEN}✅ Deleted domain: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
    rm -f "$DNS_INFO_FILE"
}

dns_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 DNS Domain Management ---${C_RESET}"
    if [ -f "$DNS_INFO_FILE" ]; then
        source "$DNS_INFO_FILE"
        echo -e "\nℹ️ A domain already exists for this server:"
        echo -e "  - ${C_CYAN}Domain:${C_RESET} ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
        echo
        read -p "👉 Do you want to DELETE this domain? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            delete_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    else
        echo -e "\nℹ️ No domain has been generated for this server yet."
        echo
        read -p "👉 Do you want to generate a new random domain now? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            generate_dns_record
        else
            echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        fi
    fi
}

_select_user_interface() {
    local title="$1"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    if [[ ! -s $DB_FILE ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the database.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    
    mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    local -A all_user_lookup=()
    local username
    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USER="NO_USERS"; return
    fi
    echo -e "\nPlease select a user:\n"
    for i in "${!users[@]}"; do
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "${users[$i]}"
    done
    echo -e "\n  ${C_RED} [ 0]${C_RESET} ↩️ Cancel"
    echo -e "${C_CYAN}💡 Tip: you can also type the exact username directly.${C_RESET}"
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter the number or exact username: " choice; then
            echo
            SELECTED_USER=""
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "${#users[@]}" ]; then
            if [ "$choice" -eq 0 ]; then
                SELECTED_USER=""; return
            else
                SELECTED_USER="${users[$((choice-1))]}"; return
            fi
        elif [[ -n "${all_user_lookup[$choice]+x}" ]]; then
            SELECTED_USER="$choice"; return
        else
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
        fi
    done
}

_select_multi_user_interface() {
    local title="$1"
    local include_orphan_users="${2:-false}"
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}${title}${C_RESET}\n"
    SELECTED_USERS=()
    local -a all_users=()
    local -a orphan_users=()
    local -A all_user_lookup=()
    local -A orphan_user_lookup=()
    local username

    if [[ -s $DB_FILE ]]; then
        mapfile -t all_users < <(cut -d: -f1 "$DB_FILE" | sort)
    fi

    if [[ "$include_orphan_users" == "true" ]]; then
        mapfile -t orphan_users < <(get_AmokhanTech_orphan_users)
        for username in "${orphan_users[@]}"; do
            orphan_user_lookup["$username"]=1
            if ! printf "%s\n" "${all_users[@]}" | grep -Fxq "$username"; then
                all_users+=("$username")
            fi
        done
        if [[ ${#all_users[@]} -gt 0 ]]; then
            mapfile -t all_users < <(printf "%s\n" "${all_users[@]}" | sort)
        fi
    fi

    if [[ ${#all_users[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}ℹ️ No users found in the manager database.${C_RESET}"
        if [[ "$include_orphan_users" == "true" ]]; then
            echo -e "${C_DIM}No orphan Amokhan Tech system users were found either.${C_RESET}"
        fi
        SELECTED_USERS=("NO_USERS"); return
    fi

    for username in "${all_users[@]}"; do
        all_user_lookup["$username"]=1
    done
    
    if [ ${#all_users[@]} -ge 15 ]; then
        read -p "👉 Enter a search term (or press Enter to list all): " search_term
        if [[ -n "$search_term" ]]; then
            mapfile -t users < <(printf "%s\n" "${all_users[@]}" | grep -i "$search_term")
        else
            users=("${all_users[@]}")
        fi
    else
        users=("${all_users[@]}")
    fi

    if [ ${#users[@]} -eq 0 ]; then
        echo -e "\n${C_YELLOW}ℹ️ No users found matching your criteria.${C_RESET}"
        SELECTED_USERS=("NO_USERS"); return
    fi
    echo -e "\nPlease select users:\n"
    for i in "${!users[@]}"; do
        local display_user="${users[$i]}"
        if [[ "$include_orphan_users" == "true" && -n "${orphan_user_lookup[${users[$i]}]+x}" ]]; then
            display_user="${display_user} ${C_DIM}(system-only)${C_RESET}"
        fi
        printf "  ${C_GREEN}[%2d]${C_RESET} %s\n" "$((i+1))" "$display_user"
    done
    echo -e "\n  ${C_GREEN}[all]${C_RESET} Select ALL listed users"
    echo -e "  ${C_RED}  [0]${C_RESET} ↩️ Cancel and return to main menu"
    echo -e "\n${C_CYAN}💡 You can select multiple by number, range, or exact username.${C_RESET}"
    echo -e "${C_CYAN}   Examples: '1 3 5' or '1,3' or '1-4' or 'alice bob'${C_RESET}"
    if [[ "$include_orphan_users" == "true" ]]; then
        echo -e "${C_CYAN}   Users marked '(system-only)' are old accounts still on the VPS but missing from users.db${C_RESET}"
    fi
    echo
    local choice
    while true; do
        if ! read -r -p "👉 Enter user numbers or usernames: " choice; then
            echo
            SELECTED_USERS=()
            return
        fi
        choice=${choice//,/ } # Replace commas with spaces
        
        if [[ -z "$choice" ]]; then
            echo -e "${C_RED}❌ Invalid selection. Please try again.${C_RESET}"
            continue
        fi

        if [[ "$choice" == "0" ]]; then
            SELECTED_USERS=(); return
        fi
        
        if [[ "${choice,,}" == "all" ]]; then
            SELECTED_USERS=("${users[@]}")
            return
        fi
        
        local valid=true
        local selected_indices=()
        local selected_names=()
        for token in $choice; do
            if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=${token%-*}
                local end=${token#*-}
                if [ "$start" -le "$end" ]; then
                    for (( idx=start; idx<=end; idx++ )); do
                        if [ "$idx" -ge 1 ] && [ "$idx" -le "${#users[@]}" ]; then
                            selected_indices+=($idx)
                        else
                            valid=false; break
                        fi
                    done
                else
                    valid=false; break
                fi
            elif [[ "$token" =~ ^[0-9]+$ ]]; then
                if [ "$token" -ge 1 ] && [ "$token" -le "${#users[@]}" ]; then
                    selected_indices+=($token)
                elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                    selected_names+=("$token")
                else
                    valid=false; break
                fi
            elif [[ -n "${all_user_lookup[$token]+x}" ]]; then
                selected_names+=("$token")
            else
                valid=false; break
            fi
        done
        
        if [[ "$valid" == true && ( ${#selected_indices[@]} -gt 0 || ${#selected_names[@]} -gt 0 ) ]]; then
            mapfile -t unique_indices < <(printf "%s\n" "${selected_indices[@]}" | sort -u -n)
            for idx in "${unique_indices[@]}"; do
                SELECTED_USERS+=("${users[$((idx-1))]}")
            done
            if (( ${#selected_names[@]} > 0 )); then
                mapfile -t unique_names < <(printf "%s\n" "${selected_names[@]}" | sort -u)
                for username in "${unique_names[@]}"; do
                    if [[ -n "$username" ]] && ! printf "%s\n" "${SELECTED_USERS[@]}" | grep -Fxq "$username"; then
                        SELECTED_USERS+=("$username")
                    fi
                done
            fi
            return
        else
            echo -e "${C_RED}❌ Invalid selection. Please check your numbers or usernames.${C_RESET}"
            SELECTED_USERS=()
            selected_indices=()
            selected_names=()
        fi
    done
}

get_user_status() {
    local username="$1"
    if ! id "$username" &>/dev/null; then echo -e "${C_RED}Not Found${C_RESET}"; return; fi
    local expiry_date=$(grep "^$username:" "$DB_FILE" | cut -d: -f3)
    if passwd -S "$username" 2>/dev/null | grep -q " L "; then echo -e "${C_YELLOW}🔒 Locked${C_RESET}"; return; fi
    local expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    if [[ $expiry_ts -lt $current_ts ]]; then echo -e "${C_RED}🗓️ Expired${C_RESET}"; return; fi
    echo -e "${C_GREEN}🟢 Active${C_RESET}"
}

create_user() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create New SSH User ---${C_RESET}"
    read -p "👉 Enter username (or '0' to cancel): " username
    local adopt_existing=false
    if [[ "$username" == "0" ]]; then
        echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
        return
    fi
    if [[ -z "$username" ]]; then
        echo -e "\n${C_RED}❌ Error: Username cannot be empty.${C_RESET}"
        return
    fi
    if db_has_user "$username"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists in AmokhanTech.${C_RESET}"
        return
    fi
    if id "$username" &>/dev/null; then
        if is_AmokhanTech_orphan_user "$username"; then
            echo -e "\n${C_YELLOW}⚠️ User '$username' already exists on the system but is missing from users.db.${C_RESET}"
            echo -e "${C_DIM}This usually happens after uninstalling the script without deleting the SSH users.${C_RESET}"
            read -p "👉 Do you want to take control of this existing user and manage it with Amokhan Tech? (y/n): " adopt_confirm
            if [[ "$adopt_confirm" == "y" || "$adopt_confirm" == "Y" ]]; then
                adopt_existing=true
            else
                echo -e "\n${C_YELLOW}❌ User creation cancelled.${C_RESET}"
                return
            fi
        else
            echo -e "\n${C_RED}❌ Error: System user '$username' already exists and does not look like a Amokhan Tech SSH account.${C_RESET}"
            return
        fi
    fi
    local password=""
    while true; do
        read -p "🔑 Enter password (or press Enter for auto-generated): " password
        if [[ -z "$password" ]]; then
            password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
            echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$password${C_RESET}"
            break
        else
            break
        fi
    done
    read -p "🗓️ Enter account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📶 Enter simultaneous connection limit [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📦 Enter bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    read -p "📦 Enter DAILY bandwidth limit in GB (0 = unlimited) [0]: " daily_bandwidth_gb
    daily_bandwidth_gb=${daily_bandwidth_gb:-0}
    if ! [[ "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    local admin_msg_input=""
    read -r -p "💬 Admin Message for this user (optional, HTML allowed, Enter = none): " admin_msg_input
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    ensure_AmokhanTech_system_group
    if [[ "$adopt_existing" == "true" ]]; then
        usermod -s /usr/sbin/nologin "$username" &>/dev/null
    else
        useradd -m -s /usr/sbin/nologin "$username"
    fi
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd; chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:$daily_bandwidth_gb:trial" >> "$DB_FILE"
    [[ -n "$admin_msg_input" ]] && set_user_admin_message "$username" "$admin_msg_input"
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    local daily_bw_display="Unlimited"
    if [[ "$daily_bandwidth_gb" != "0" ]]; then daily_bw_display="${daily_bandwidth_gb} GB/day"; fi
    
    clear; show_banner
    if [[ "$adopt_existing" == "true" ]]; then
        echo -e "${C_GREEN}✅ Existing system user '$username' has been imported into Amokhan Tech!${C_RESET}\n"
    else
        echo -e "${C_GREEN}✅ User '$username' created successfully!${C_RESET}\n"
    fi
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - 🗓️ Expires on:        ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Total Bandwidth:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "  - 📦 Daily Bandwidth:   ${C_YELLOW}$daily_bw_display${C_RESET}"
    echo -e "    ${C_DIM}(Active monitoring service will enforce these limits)${C_RESET}"

    # Auto-ask for config generation
    echo
    read -p "👉 Do you want to generate a client connection config for this user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

delete_user() {
    _select_multi_user_interface "--- 🗑️ Delete Amokhan Tech Users ---" "true"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_RED}⚠️ You selected ${#SELECTED_USERS[@]} user(s) to delete: ${C_YELLOW}${SELECTED_USERS[*]}${C_RESET}"
    read -p "👉 Are you sure you want to PERMANENTLY delete them? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Deletion cancelled.${C_RESET}"; return; fi
    
    echo -e "\n${C_BLUE}🗑️ Deleting selected users...${C_RESET}"
    delete_AmokhanTech_user_accounts "${SELECTED_USERS[@]}"
}

edit_user() {
    _select_user_interface "--- ✏️ Edit a User ---"
    local username=$SELECTED_USER
    if [[ "$username" == "NO_USERS" ]] || [[ -z "$username" ]]; then return; fi
    while true; do
        clear; show_banner; echo -e "${C_BOLD}${C_PURPLE}--- Editing User: ${C_YELLOW}$username${C_PURPLE} ---${C_RESET}"
        
        # Show current user details
        local current_line; current_line=$(grep "^$username:" "$DB_FILE")
        local cur_pass cur_expiry cur_limit cur_bw cur_daily_bw
        IFS=: read -r _ cur_pass cur_expiry cur_limit cur_bw cur_daily_bw _ <<< "$current_line"
        [[ -z "$cur_bw" ]] && cur_bw="0"
        [[ ! "$cur_daily_bw" =~ ^[0-9]+\.?[0-9]*$ ]] && cur_daily_bw="0"
        
        local cur_bw_display="Unlimited"; [[ "$cur_bw" != "0" ]] && cur_bw_display="${cur_bw} GB"
        local cur_daily_bw_display="Unlimited"; [[ "$cur_daily_bw" != "0" ]] && cur_daily_bw_display="${cur_daily_bw} GB/day"
        
        # Show bandwidth usage
        local bw_used_display="N/A"
        if [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
            local used_bytes=0; read -r used_bytes < "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || used_bytes=0
            if [[ -n "$used_bytes" && "$used_bytes" != "0" ]]; then
                bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $used_bytes / 1073741824}")
            else
                bw_used_display="0.00 GB"
            fi
        fi
        
        local daily_bw_used_display="N/A"
        if [[ -f "$BANDWIDTH_DIR/${username}.daily_usage" ]]; then
            local d_used_bytes=0; read -r d_used_bytes < "$BANDWIDTH_DIR/${username}.daily_usage" 2>/dev/null || d_used_bytes=0
            if [[ -n "$d_used_bytes" && "$d_used_bytes" != "0" ]]; then
                daily_bw_used_display=$(awk "BEGIN {printf \"%.2f GB\", $d_used_bytes / 1073741824}")
            else
                daily_bw_used_display="0.00 GB"
            fi
        fi
        
        echo -e "\n  ${C_DIM}Current: Pass=${C_YELLOW}$cur_pass${C_RESET}${C_DIM} Exp=${C_YELLOW}$cur_expiry${C_RESET}${C_DIM} Conn=${C_YELLOW}$cur_limit${C_RESET}${C_DIM} BW=${C_YELLOW}$cur_bw_display${C_RESET}${C_DIM} Used=${C_CYAN}$bw_used_display${C_RESET}${C_DIM} Daily BW=${C_YELLOW}$cur_daily_bw_display${C_RESET}${C_DIM} Daily Used=${C_CYAN}$daily_bw_used_display${C_RESET}"
        echo -e "\nSelect a detail to edit:\n"
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🔑 Change Password"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗓️ Change Expiration Date"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "📶 Change Connection Limit"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "📦 Change Total Bandwidth Limit"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "📦 Change Daily Bandwidth Limit"
        printf "  ${C_GREEN}[ 6]${C_RESET} %-35s\n" "🔄 Reset Bandwidth Counters"
        printf "  ${C_GREEN}[ 7]${C_RESET} %-35s\n" "💬 Admin Message (This User)"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ✅ Finish Editing"
        echo
        if ! read -r -p "👉 Enter your choice: " edit_choice; then
            echo
            return
        fi
        case $edit_choice in
            1)
               local new_pass=""
               read -p "Enter new password (or press Enter for auto-generated): " new_pass
               if [[ -z "$new_pass" ]]; then
                   new_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
                   echo -e "${C_GREEN}🔑 Auto-generated: ${C_YELLOW}$new_pass${C_RESET}"
               fi
               echo "$username:$new_pass" | chpasswd
               sed -i "s/^$username:.*/$username:$new_pass:$cur_expiry:$cur_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
               echo -e "\n${C_GREEN}✅ Password for '$username' changed to: ${C_YELLOW}$new_pass${C_RESET}"
               ;;
            2) read -p "Enter new duration (in days from today): " days
               if [[ "$days" =~ ^[0-9]+$ ]]; then
                   local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d); chage -E "$new_expire_date" "$username"
                   sed -i "s/^$username:.*/$username:$cur_pass:$new_expire_date:$cur_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Expiration for '$username' set to ${C_YELLOW}$new_expire_date${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid number of days.${C_RESET}"; fi ;;
            3) read -p "Enter new simultaneous connection limit: " new_limit
               if [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$new_limit:$cur_bw:$cur_daily_bw/" "$DB_FILE"
                   echo -e "\n${C_GREEN}✅ Connection limit for '$username' set to ${C_YELLOW}$new_limit${C_RESET}."
               else echo -e "\n${C_RED}❌ Invalid limit.${C_RESET}"; fi ;;
            4) read -p "Enter new TOTAL bandwidth limit in GB (0 = unlimited): " new_bw
               if [[ "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$new_bw:$cur_daily_bw/" "$DB_FILE"
                   local bw_msg="Unlimited"; [[ "$new_bw" != "0" ]] && bw_msg="${new_bw} GB"
                   echo -e "\n${C_GREEN}✅ Total bandwidth limit for '$username' set to ${C_YELLOW}$bw_msg${C_RESET}."
                   # Unlock user if they were locked due to bandwidth
                   if [[ "$new_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.usage" ]]; then
                       local used_bytes; used_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
                       local new_quota_bytes; new_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_bw * 1073741824}")
                       if [[ "$new_bw" == "0" ]] || [[ "$used_bytes" -lt "$new_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            5) read -p "Enter new DAILY bandwidth limit in GB (0 = unlimited): " new_daily_bw
               if [[ "$new_daily_bw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                   sed -i "s/^$username:.*/$username:$cur_pass:$cur_expiry:$cur_limit:$cur_bw:$new_daily_bw/" "$DB_FILE"
                   local daily_bw_msg="Unlimited"; [[ "$new_daily_bw" != "0" ]] && daily_bw_msg="${new_daily_bw} GB/day"
                   echo -e "\n${C_GREEN}✅ Daily bandwidth limit for '$username' set to ${C_YELLOW}$daily_bw_msg${C_RESET}."
                   # Unlock user if they were locked due to daily bandwidth
                   if [[ "$new_daily_bw" == "0" ]] || [[ -f "$BANDWIDTH_DIR/${username}.daily_usage" ]]; then
                       local d_used_bytes; d_used_bytes=$(cat "$BANDWIDTH_DIR/${username}.daily_usage" 2>/dev/null || echo 0)
                       local new_d_quota_bytes; new_d_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $new_daily_bw * 1073741824}")
                       if [[ "$new_daily_bw" == "0" ]] || [[ "$d_used_bytes" -lt "$new_d_quota_bytes" ]]; then
                           usermod -U "$username" &>/dev/null
                           rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
                       fi
                   fi
               else echo -e "\n${C_RED}❌ Invalid bandwidth value.${C_RESET}"; fi ;;
            6)
               echo "0" > "$BANDWIDTH_DIR/${username}.usage"
               echo "0" > "$BANDWIDTH_DIR/${username}.daily_usage"
               rm -f "$BANDWIDTH_DIR/${username}.daily_locked"
               # Unlock user if they were locked due to bandwidth
               usermod -U "$username" &>/dev/null
               echo -e "\n${C_GREEN}✅ All bandwidth counters for '$username' have been reset to 0.${C_RESET}"
               ;;
            7)
               user_admin_message_actions "$username"
               ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" ;;
        esac
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to continue editing..." && read -r || return
    done
}

lock_user() {
    _select_multi_user_interface "--- 🔒 Lock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔒 Locking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -L "$u"
        if [ $? -eq 0 ]; then
            killall -u "$u" -9 &>/dev/null
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} locked and active sessions killed."
        else
            echo -e " ❌ Failed to lock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

unlock_user() {
    _select_multi_user_interface "--- 🔓 Unlock Users (from DB) ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    
    echo -e "\n${C_BLUE}🔓 Unlocking selected users...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        if ! id "$u" &>/dev/null; then
             echo -e " ❌ User '${C_YELLOW}$u${C_RESET}' does not exist on this system."
             continue
        fi
        
        usermod -U "$u"
        if [ $? -eq 0 ]; then
            echo -e " ✅ ${C_YELLOW}$u${C_RESET} unlocked."
        else
            echo -e " ❌ Failed to unlock ${C_YELLOW}$u${C_RESET}."
        fi
    done
}

list_users() {
    clear; show_banner
    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_YELLOW}ℹ️ No users are currently being managed.${C_RESET}"
        return
    fi
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Managed Users ---${C_RESET}"
    echo -e "${C_YELLOW}---------------------------------------------------------------------------------------------------${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-18s | %-12s | %-10s | %-25s | %-20s${C_RESET}\n" "USERNAME" "EXPIRATION" "SESSIONS" "BANDWIDTH" "STATUS"
    echo -e "${C_YELLOW}---------------------------------------------------------------------------------------------------${C_RESET}"

    local current_ts
    printf -v current_ts '%(%s)T' -1
    local -A system_user_lookup=()
    local -A locked_user_lookup=()

    while IFS=: read -r system_user _rest; do
        [[ -n "$system_user" ]] && system_user_lookup["$system_user"]=1
    done < /etc/passwd

    if [[ -r /etc/shadow ]]; then
        while IFS=: read -r shadow_user shadow_hash _rest; do
            [[ -n "$shadow_user" && "${shadow_hash:0:1}" == "!" ]] && locked_user_lookup["$shadow_user"]=1
        done < /etc/shadow
    else
        while read -r passwd_user _ passwd_status _rest; do
            [[ -z "$passwd_user" ]] && continue
            [[ "$passwd_status" == "L" ]] && locked_user_lookup["$passwd_user"]=1
        done < <(passwd -Sa 2>/dev/null)
    fi
    refresh_ssh_session_cache

    while IFS=: read -r user pass expiry limit bandwidth_gb daily_bandwidth_gb _extra; do
        local online_count="${SSH_SESSION_COUNTS[$user]:-0}"
        local connection_string="$online_count / $limit"
        local plain_status="Active"
        local status="${C_GREEN}🟢 Active${C_RESET}"
        local quota_exceeded=false

        [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
        [[ ! "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && daily_bandwidth_gb="0"
        
        local bw_string="Unlimited"
        local total_str=""
        local daily_str=""
        
        if [[ "$bandwidth_gb" != "0" ]]; then
            local used_bytes=0
            if [[ -f "$BANDWIDTH_DIR/${user}.usage" ]]; then
                read -r used_bytes < "$BANDWIDTH_DIR/${user}.usage" 2>/dev/null || used_bytes=0
                [[ "$used_bytes" =~ ^[0-9]+$ ]] || used_bytes=0
            fi
            local used_gb
            used_gb=$(awk "BEGIN {printf \"%.1f\", $used_bytes / 1073741824}")
            total_str="${used_gb}/${bandwidth_gb}G"
            local quota_bytes
            quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
            if [[ "$quota_bytes" =~ ^[0-9]+$ ]] && (( used_bytes >= quota_bytes )); then
                quota_exceeded=true
            fi
        fi
        
        if [[ "$daily_bandwidth_gb" != "0" ]]; then
            local d_used_bytes=0
            if [[ -f "$BANDWIDTH_DIR/${user}.daily_usage" ]]; then
                read -r d_used_bytes < "$BANDWIDTH_DIR/${user}.daily_usage" 2>/dev/null || d_used_bytes=0
                [[ "$d_used_bytes" =~ ^[0-9]+$ ]] || d_used_bytes=0
            fi
            local d_used_gb
            d_used_gb=$(awk "BEGIN {printf \"%.1f\", $d_used_bytes / 1073741824}")
            daily_str="${d_used_gb}/${daily_bandwidth_gb}G/d"
            local d_quota_bytes
            d_quota_bytes=$(awk "BEGIN {printf \"%.0f\", $daily_bandwidth_gb * 1073741824}")
            if [[ "$d_quota_bytes" =~ ^[0-9]+$ ]] && (( d_used_bytes >= d_quota_bytes )); then
                quota_exceeded=true
            fi
        fi
        
        if [[ -n "$total_str" && -n "$daily_str" ]]; then
            bw_string="$total_str | $daily_str"
        elif [[ -n "$total_str" ]]; then
            bw_string="$total_str"
        elif [[ -n "$daily_str" ]]; then
            bw_string="$daily_str"
        fi

        if [[ -z "${system_user_lookup[$user]+x}" ]]; then
            plain_status="Not Found"
            status="${C_RED}Not Found${C_RESET}"
        elif [[ -n "$expiry" && "$expiry" != "Never" ]]; then
            local expiry_ts
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ "$expiry_ts" =~ ^[0-9]+$ ]] && (( expiry_ts > 0 && expiry_ts < current_ts )); then
                plain_status="Expired"
                status="${C_RED}🗓️ Expired${C_RESET}"
            fi
        fi

        if [[ "$plain_status" == "Active" && "$quota_exceeded" == true ]]; then
            if [[ -n "${locked_user_lookup[$user]+x}" ]]; then
                plain_status="BW Locked"
                status="${C_RED}🔒 BW Locked${C_RESET}"
            else
                plain_status="Quota Exceeded"
                status="${C_RED}📦 Quota Exceeded${C_RESET}"
            fi
        elif [[ "$plain_status" == "Active" && -n "${locked_user_lookup[$user]+x}" ]]; then
            plain_status="Locked"
            status="${C_YELLOW}🔒 Locked${C_RESET}"
        fi

        local line_color="$C_WHITE"
        case "$plain_status" in
            "Active") line_color="$C_GREEN" ;;
            "Locked") line_color="$C_YELLOW" ;;
            "Expired") line_color="$C_RED" ;;
            "BW Locked") line_color="$C_RED" ;;
            "Quota Exceeded") line_color="$C_RED" ;;
            "Not Found") line_color="$C_DIM" ;;
        esac

        printf "${line_color}%-18s ${C_RESET}| ${C_YELLOW}%-12s ${C_RESET}| ${C_CYAN}%-10s ${C_RESET}| ${C_ORANGE}%-25s ${C_RESET}| %-20s\n" "$user" "$expiry" "$connection_string" "$bw_string" "$status"
    done < <(sort "$DB_FILE")
    echo -e "${C_CYAN}=========================================================================================${C_RESET}\n"
}

renew_user() {
    _select_multi_user_interface "--- 🔄 Renew Users ---"
    if [[ ${#SELECTED_USERS[@]} -eq 0 || "${SELECTED_USERS[0]}" == "NO_USERS" ]]; then return; fi
    read -p "👉 Enter number of days to extend the account(s): " days; if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    local new_expire_date; new_expire_date=$(date -d "+$days days" +%Y-%m-%d)
    
    echo -e "\n${C_BLUE}🔄 Renewing selected users for $days days...${C_RESET}"
    for u in "${SELECTED_USERS[@]}"; do
        chage -E "$new_expire_date" "$u"
        local line pass _expiry limit bw
        line=$(grep "^$u:" "$DB_FILE")
        IFS=: read -r _ pass _expiry limit bw _ <<< "$line"
        [[ -z "$bw" ]] && bw="0"
        sed -i "s/^$u:.*/$u:$pass:$new_expire_date:$limit:$bw/" "$DB_FILE"
        echo -e " ✅ ${C_YELLOW}$u${C_RESET} renewed until ${C_GREEN}${new_expire_date}${C_RESET}."
    done
}

cleanup_expired() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🧹 Cleanup Expired Users ---${C_RESET}"
    
    local expired_users=()
    local current_ts
    current_ts=$(date +%s)

    if [[ ! -s "$DB_FILE" ]]; then
        echo -e "\n${C_GREEN}✅ User database is empty. No expired users found.${C_RESET}"
        return
    fi
    
    while IFS=: read -r user pass expiry limit bandwidth_gb _extra; do
        local expiry_ts
        expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        
        if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
            expired_users+=("$user")
        fi
    done < "$DB_FILE"

    if [ ${#expired_users[@]} -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ No expired users found.${C_RESET}"
        return
    fi

    echo -e "\nThe following users have expired: ${C_RED}${expired_users[*]}${C_RESET}"
    read -p "👉 Do you want to delete all of them? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "\n${C_BLUE}🗑️ Deleting expired users...${C_RESET}"
        delete_AmokhanTech_user_accounts "${expired_users[@]}"
        echo -e "\n${C_GREEN}✅ Expired users have been cleaned up.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}❌ Cleanup cancelled.${C_RESET}"
    fi
}


backup_user_data() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 💾 Backup User Data ---${C_RESET}"
    read -p "👉 Enter path for backup file [/root/AmokhanTech_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/AmokhanTech_users.tar.gz}
    if [ ! -d "$DB_DIR" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "\n${C_YELLOW}ℹ️ No user data found to back up.${C_RESET}"
        return
    fi
    echo -e "\n${C_BLUE}⚙️ Backing up user database and settings to ${C_YELLOW}$backup_path${C_RESET}..."
    tar -czf "$backup_path" -C "$(dirname "$DB_DIR")" "$(basename "$DB_DIR")"
    if [ $? -eq 0 ]; then
        echo -e "\n${C_GREEN}✅ SUCCESS: User data backup created at ${C_YELLOW}$backup_path${C_RESET}"
    else
        echo -e "\n${C_RED}❌ ERROR: Backup failed.${C_RESET}"
    fi
}

restore_user_data() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📥 Restore User Data ---${C_RESET}"
    read -p "👉 Enter the full path to the user data backup file [/root/AmokhanTech_users.tar.gz]: " backup_path
    backup_path=${backup_path:-/root/AmokhanTech_users.tar.gz}
    if [ ! -f "$backup_path" ]; then
        echo -e "\n${C_RED}❌ ERROR: Backup file not found at '$backup_path'.${C_RESET}"
        return
    fi
    echo -e "\n${C_RED}${C_BOLD}⚠️ WARNING:${C_RESET} This will overwrite all current users and settings."
    echo -e "It will restore user accounts, passwords, limits, and expiration dates from the backup file."
    read -p "👉 Are you absolutely sure you want to proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then echo -e "\n${C_YELLOW}❌ Restore cancelled.${C_RESET}"; return; fi
    local temp_dir
    temp_dir=$(mktemp -d)
    echo -e "\n${C_BLUE}⚙️ Extracting backup file to a temporary location...${C_RESET}"
    tar -xzf "$backup_path" -C "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}❌ ERROR: Failed to extract backup file. Aborting.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    local _legacy_name
    for _legacy_name in "visible""Tech" "Visible""Tech"; do
        if [ -d "$temp_dir/$_legacy_name" ] && [ ! -d "$temp_dir/AmokhanTech" ]; then
            mv "$temp_dir/$_legacy_name" "$temp_dir/AmokhanTech"
        fi
    done
    local restored_db_file="$temp_dir/AmokhanTech/users.db"
    if [ ! -f "$restored_db_file" ]; then
        echo -e "\n${C_RED}❌ ERROR: users.db not found in the backup. Cannot restore user accounts.${C_RESET}"
        rm -rf "$temp_dir"
        return
    fi
    echo -e "${C_BLUE}⚙️ Overwriting current user database...${C_RESET}"
    mkdir -p "$DB_DIR"
    cp "$restored_db_file" "$DB_FILE"
    if [ -f "$temp_dir/AmokhanTech/dns_info.conf" ]; then
        cp "$temp_dir/AmokhanTech/dns_info.conf" "$DB_DIR/"
    fi
    if [ -d "$temp_dir/AmokhanTech/admin_msg" ]; then
        cp -r "$temp_dir/AmokhanTech/admin_msg" "$DB_DIR/"
    fi

    
    echo -e "${C_BLUE}⚙️ Re-synchronizing system accounts with the restored database...${C_RESET}"
    ensure_AmokhanTech_system_group
    
    while IFS=: read -r user pass expiry limit; do
        echo "Processing user: ${C_YELLOW}$user${C_RESET}"
        if ! id "$user" &>/dev/null; then
            echo " - User does not exist in system. Creating..."
            useradd -m -s /usr/sbin/nologin "$user"
        fi
        usermod -aG "$FF_USERS_GROUP" "$user" 2>/dev/null
        echo " - Setting password..."
        echo "$user:$pass" | chpasswd
        echo " - Setting expiration to $expiry..."
        chage -E "$expiry" "$user"
        echo " - Connection limit is $limit (enforced by PAM)"
    done < "$DB_FILE"
    rm -rf "$temp_dir"
    echo -e "\n${C_GREEN}✅ SUCCESS: User data restore completed.${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

_enable_banner_in_sshd_config() {
    echo -e "\n${C_BLUE}⚙️ Configuring sshd_config...${C_RESET}"
    disable_dynamic_ssh_banner_system
    sed -i.bak -E 's/^( *Banner *).*/#\1/' /etc/ssh/sshd_config
    if ! grep -q -E "^Banner $SSH_BANNER_FILE" /etc/ssh/sshd_config; then
        echo -e "\n# Amokhan Tech SSH Banner\nBanner $SSH_BANNER_FILE" >> /etc/ssh/sshd_config
    fi
    echo -e "${C_GREEN}✅ sshd_config updated.${C_RESET}"
}

_restart_ssh() {
    echo -e "\n${C_BLUE}🔄 Restarting SSH service to apply changes...${C_RESET}"
    local ssh_service_name=""
    if [ -f /lib/systemd/system/sshd.service ]; then
        ssh_service_name="sshd.service"
    elif [ -f /lib/systemd/system/ssh.service ]; then
        ssh_service_name="ssh.service"
    else
        echo -e "${C_RED}❌ Could not find sshd.service or ssh.service. Cannot restart SSH.${C_RESET}"
        return 1
    fi

    systemctl restart "${ssh_service_name}"
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✅ SSH service ('${ssh_service_name}') restarted successfully.${C_RESET}"
    else
        echo -e "${C_RED}❌ Failed to restart SSH service ('${ssh_service_name}'). Please check 'journalctl -u ${ssh_service_name}' for errors.${C_RESET}"
    fi
}

set_ssh_banner_paste() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 Paste Static SSH Banner ---${C_RESET}"
    echo -e "Paste your custom banner below. Press ${C_YELLOW}[Ctrl+D]${C_RESET} when you are finished."
    echo -e "${C_DIM}This will be shown to all SSH users through 'Banner $SSH_BANNER_FILE'.${C_RESET}"
    echo -e "${C_DIM}The current banner (if any) will be overwritten.${C_RESET}"
    echo -e "--------------------------------------------------"
    cat > "$SSH_BANNER_FILE"
    chmod 644 "$SSH_BANNER_FILE"
    echo -e "\n--------------------------------------------------"
    echo -e "\n${C_GREEN}✅ Static banner content saved.${C_RESET}"
    _enable_banner_in_sshd_config
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

view_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👁️ Current SSH Banner ---${C_RESET}"
    if [ -f "$SSH_BANNER_FILE" ]; then
        echo -e "\n${C_CYAN}--- BEGIN BANNER ---${C_RESET}"
        cat "$SSH_BANNER_FILE"
        echo -e "${C_CYAN}---- END BANNER ----${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file found at $SSH_BANNER_FILE.${C_RESET}"
    fi
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

remove_ssh_banner() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Disable SSH Banners ---${C_RESET}"
    read -p "👉 Are you sure you want to disable all SSH banners? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "\n${C_YELLOW}❌ Action cancelled.${C_RESET}"
        echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
        return
    fi
    if [ -f "$SSH_BANNER_FILE" ]; then
        rm -f "$SSH_BANNER_FILE"
        echo -e "\n${C_GREEN}✅ Removed banner file: $SSH_BANNER_FILE${C_RESET}"
    else
        echo -e "\n${C_YELLOW}ℹ️ No banner file to remove.${C_RESET}"
    fi
    disable_dynamic_ssh_banner_system
    echo -e "\n${C_BLUE}⚙️ Disabling banner in sshd_config...${C_RESET}"
    disable_static_ssh_banner_in_sshd_config
    echo -e "${C_GREEN}✅ Banner disabled in configuration.${C_RESET}"
    _restart_ssh
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return..." && read -r
}

# ===================== ADMIN MESSAGE: bootstrap =====================
# Admin Message ina FAILI lake (adminmsg.sh), huduma yake (AmokhanTech-adminmsg) na swichi yake.
# Menu kuu inajua njia mbili tu: banner_routing_needed (sshd inahitaji njia ya Banner ya kila user)
# na kupakia faili la moduli. Mantiki yote ya Admin Message iko ndani ya adminmsg.sh.
ADMINMSG_LIB_DIR="/usr/local/lib/AmokhanTech"
ADMINMSG_LIB="$ADMINMSG_LIB_DIR/adminmsg.sh"
ADMINMSG_SERVICE_FILE="/etc/systemd/system/AmokhanTech-adminmsg.service"
ADMINMSG_MARKER="# Amokhan Tech - ADMIN MESSAGE module version 2026-10-25.2"

banner_routing_needed() {
    [[ -f "$DB_DIR/banners_enabled" || -f "$DB_DIR/admin_msg/global_enabled" ]] || compgen -G "$DB_DIR/admin_msg/users/*.txt" >/dev/null
}

adminmsg_install_lib() {
    mkdir -p "$ADMINMSG_LIB_DIR"
    cat > "$ADMINMSG_LIB" << 'AMSG_EOF'
#!/bin/bash
# Amokhan Tech - ADMIN MESSAGE module version 2026-10-25.2
#
# FAILI HII NI YA ADMIN MESSAGE PEKE YAKE. Haitegemei Dynamic Banner.
#   * Inaweza ku-sourced na menu (menu functions)  ->  source adminmsg.sh
#   * Inaweza kuendeshwa kama huduma (daemon)      ->  adminmsg.sh --daemon
#
# Data (zote ni zake peke yake):
#   Hakuna master switch: global_enabled ndiyo swichi ya ujumbe wa wote.
#   /etc/AmokhanTech/admin_msg/global.txt       -> ujumbe kwa watumiaji WOTE
#   /etc/AmokhanTech/admin_msg/global_enabled   -> ujumbe wa wote umewashwa
#   /etc/AmokhanTech/admin_msg/users/<u>.txt    -> ujumbe wa user mmoja
#   /etc/AmokhanTech/admin_msg/users/<u>.off    -> ujumbe wa user huyo umezimwa (ujumbe unabaki)
#   /etc/AmokhanTech/admin_msg/rendered/<u>.html-> kipande cha HTML kilichokamilika (kichwa + mistari ya blue + ujumbe)
#
# Ujumbe unakubali HTML yako mwenyewe (<font color="...">, <b>, <i>, <u>, <br>).
# Hakuna rangi inayowekwa kwa lazima: ujumbe una-render bila rangi mpaka uweke wewe.

AM_ROOT="${AM_ROOT:-/etc/AmokhanTech}"
AM_DIR="$AM_ROOT/admin_msg"
AM_RENDER_DIR="$AM_DIR/rendered"
AM_BANNER_DIR="$AM_ROOT/banners"
AM_USERS_DB="$AM_ROOT/users.db"
AM_STATIC_BANNER="${AM_STATIC_BANNER:-/etc/bannerssh}"
AM_MAXLEN=1500
AM_INTERVAL=5
AM_LINE_CHARS='▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬'
AM_HEADING_COLOR="yellow"

# ---------------------------------------------------------------------------
# Hali na uhifadhi
# ---------------------------------------------------------------------------
is_global_admin_message_enabled() { [[ -f "$AM_DIR/global_enabled" ]]; }
_admin_msg_valid_user()           { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

# Ondoa control characters tu na nafasi za pembeni. HTML inabaki kama ulivyoandika.
_admin_msg_sanitize() {
    local m="$1"
    m=$(printf '%s' "$m" | tr -d '\000-\037\177')
    m="${m#"${m%%[![:space:]]*}"}"
    m="${m%"${m##*[![:space:]]}"}"
    printf '%s' "${m:0:$AM_MAXLEN}"
}

get_global_admin_message() {
    local f="$AM_DIR/global.txt" m=""
    [[ -s "$f" ]] && IFS= read -r m < "$f"
    printf '%s' "$m"
}

get_user_admin_message() {
    local u="$1" f="$AM_DIR/users/$1.txt" m=""
    _admin_msg_valid_user "$u" || return 0
    [[ -s "$f" ]] && IFS= read -r m < "$f"
    printf '%s' "$m"
}

# NO_MESSAGE | ENABLED | DISABLED
get_user_admin_message_state() {
    local u="$1"
    if [[ -z "$(get_user_admin_message "$u")" ]]; then
        echo "NO_MESSAGE"
    elif [[ -f "$AM_DIR/users/$u.off" ]]; then
        echo "DISABLED"
    else
        echo "ENABLED"
    fi
}

set_user_admin_message() {
    local u="$1" msg
    _admin_msg_valid_user "$u" || return 1
    msg=$(_admin_msg_sanitize "$2")
    mkdir -p "$AM_DIR/users"
    if [[ -z "$msg" ]]; then
        rm -f "$AM_DIR/users/$u.txt" "$AM_DIR/users/$u.off"
    else
        printf '%s\n' "$msg" > "$AM_DIR/users/$u.txt"
        chmod 644 "$AM_DIR/users/$u.txt" 2>/dev/null
    fi
    return 0
}

count_user_admin_messages() {
    local n=0 f
    shopt -s nullglob
    for f in "$AM_DIR/users/"*.txt; do
        [[ -s "$f" ]] && n=$((n + 1))
    done
    shopt -u nullglob
    echo "$n"
}

# ---------------------------------------------------------------------------
# Kutengeneza kipande cha HTML (kichwa kikubwa + mistari ya blue + ujumbe)
# ---------------------------------------------------------------------------
adminmsg_build_fragment() {
    local g="$1" u="$2" line out
    [[ -z "$g" && -z "$u" ]] && return 0
    line="<font color=\"blue\">${AM_LINE_CHARS}</font><br>"
    out="<font size=\"6\" color=\"${AM_HEADING_COLOR}\"><b>📢 ADMIN MESSAGE 📢</b></font><br>${line}"
    # Ujumbe unawekwa kama ulivyoandika (bila rangi). Vifunga vinazuia rangi/bold kuvuja kwenye mstari wa chini.
    [[ -n "$g" ]] && out+="${g}</u></i></b></font><br>"
    [[ -n "$u" ]] && out+="${u}</u></i></b></font><br>"
    out+="${line}"
    printf '%s' "$out"
}

_adminmsg_write_if_changed() {
    local file="$1" content="$2" tmp="$1.tmp"
    printf '%s' "$content" > "$tmp"
    if ! cmp -s "$tmp" "$file" 2>/dev/null; then
        mv "$tmp" "$file"
        chmod 644 "$file" 2>/dev/null
    else
        rm -f "$tmp"
    fi
}

# Render kwa watumiaji wote. Inatumiwa na daemon na na menu (kuonyesha mabadiliko mara moja).
adminmsg_render_all() {
    local dyn=false g="" static="" user frag umsg content f
    local -A valid=()

    [[ -f "$AM_ROOT/banners_enabled" ]] && dyn=true

    mkdir -p "$AM_RENDER_DIR"

    if [[ -f "$AM_DIR/global_enabled" && -s "$AM_DIR/global.txt" ]]; then
        IFS= read -r g < "$AM_DIR/global.txt"
    fi

    # Dynamic Banner OFF: banner ya mwisho inamilikiwa na Admin Message (maandishi ya static + ujumbe).
    if ! $dyn; then
        mkdir -p "$AM_BANNER_DIR"
        if [[ -f "$AM_STATIC_BANNER" ]] && \
           grep -q -E "^[[:space:]]*Banner[[:space:]]+${AM_STATIC_BANNER}[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null; then
            static=$(cat "$AM_STATIC_BANNER" 2>/dev/null)
        fi
    fi

    [[ -s "$AM_USERS_DB" ]] || return 0
    while IFS=: read -r user _rest; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        _admin_msg_valid_user "$user" || continue
        valid["$user"]=1

        umsg=""
        if [[ -s "$AM_DIR/users/${user}.txt" && ! -f "$AM_DIR/users/${user}.off" ]]; then
            IFS= read -r umsg < "$AM_DIR/users/${user}.txt"
        fi

        frag=$(adminmsg_build_fragment "$g" "$umsg")
        if [[ -n "$frag" ]]; then
            _adminmsg_write_if_changed "$AM_RENDER_DIR/${user}.html" "$frag"
        else
            rm -f "$AM_RENDER_DIR/${user}.html"
        fi

        if ! $dyn; then
            content="$static"
            [[ -n "$frag" ]] && content+="<center><br>${frag}</center>"
            _adminmsg_write_if_changed "$AM_BANNER_DIR/${user}.txt" "$content"
        fi
    done < "$AM_USERS_DB"

    # Vipande vya watumiaji waliofutwa
    shopt -s nullglob
    for f in "$AM_RENDER_DIR/"*.html; do
        user=$(basename "$f" .html)
        [[ -n "${valid[$user]+x}" ]] || rm -f "$f"
    done
    shopt -u nullglob
}

adminmsg_daemon() {
    mkdir -p "$AM_DIR/users" "$AM_RENDER_DIR"
    while true; do
        adminmsg_render_all
        sleep "$AM_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Menu (zinahitaji rangi na helpers za menu kuu: C_*, show_banner, press_enter, _select_user_interface)
# ---------------------------------------------------------------------------
admin_message_apply() {
    adminmsg_render_all
    # Njia ya sshd (routing) ni ile ile ya menu kuu; Admin Message inaiomba tu isasishwe.
    declare -F update_ssh_banners_config >/dev/null && update_ssh_banners_config
    declare -F invalidate_banner_cache >/dev/null && invalidate_banner_cache
    return 0
}

_admin_msg_html_hint() {
    echo -e "  ${C_DIM}Unaweza kutumia HTML yako mwenyewe, mfano: <font color=\"yellow\">Habari</font> <b>mpya</b> <br>${C_RESET}"
    echo -e "  ${C_DIM}Hakuna rangi inayowekwa kwa lazima. (max $AM_MAXLEN characters, mstari mmoja)${C_RESET}"
}

_admin_msg_update_note() {
    echo -e "${C_DIM}Ujumbe unasasishwa ndani ya sekunde chache (user atauona akiconnect tena).${C_RESET}"
}

# Menu ya user mmoja: Create / Enable / Disable / Edit / Delete
user_admin_message_actions() {
    local u="$1" choice cur state state_txt new ans
    _admin_msg_valid_user "$u" || { echo -e "${C_RED}❌ Jina la user si sahihi.${C_RESET}"; press_enter; return; }
    while true; do
        clear; show_banner
        cur=$(get_user_admin_message "$u")
        state=$(get_user_admin_message_state "$u")
        case "$state" in
            ENABLED)  state_txt="${C_STATUS_A}ENABLED${C_RESET}" ;;
            DISABLED) state_txt="${C_DANGER}DISABLED${C_RESET}" ;;
            *)        state_txt="${C_DIM}NO MESSAGE${C_RESET}" ;;
        esac
        echo -e "\n${C_TITLE}══════════════════[ ${C_BOLD}💬 ADMIN MESSAGE: ${u} ${C_RESET}${C_TITLE}]══════════════════${C_RESET}"
        echo -e "${C_GREEN}Status:${C_RESET}  $state_txt"
        if [[ -n "$cur" ]]; then
            echo -e "${C_GREEN}Message:${C_RESET} $cur"
        else
            echo -e "${C_GREEN}Message:${C_RESET} ${C_DIM}(not set)${C_RESET}"
        fi
        echo -e "${C_GREEN}Global Admin Message is separate and is not affected by these options.${C_RESET}\n"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✏️ Create message"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "✅ Enable message for this user"
        printf "     ${C_DANGER}[ 3]${C_RESET} %-40s\n" "⛔ Disable message for this user"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "📝 Edit message"
        printf "     ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "🧹 Delete message"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return\n"
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                if [[ -n "$cur" ]]; then
                    read -r -p "⚠️ User huyu ana ujumbe tayari. Uuandike upya? (y/n): " ans
                    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo -e "\n${C_YELLOW}ℹ️ Hakuna mabadiliko.${C_RESET}"; press_enter; continue; }
                fi
                echo; _admin_msg_html_hint
                read -r -p "💬 Ujumbe wa '$u': " new
                new=$(_admin_msg_sanitize "$new")
                if [[ -z "$new" ]]; then
                    echo -e "\n${C_YELLOW}ℹ️ Hakuna mabadiliko.${C_RESET}"
                else
                    set_user_admin_message "$u" "$new"
                    rm -f "$AM_DIR/users/$u.off"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Ujumbe wa '$u' umehifadhiwa na umewashwa.${C_RESET}"
                    _admin_msg_update_note
                fi
                press_enter
                ;;
            2)
                if [[ -z "$cur" ]]; then
                    echo -e "\n${C_RED}❌ Hakuna ujumbe. Tumia [1] Create message kwanza.${C_RESET}"
                else
                    rm -f "$AM_DIR/users/$u.off"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Ujumbe umewashwa kwa '$u'.${C_RESET}"
                    _admin_msg_update_note
                fi
                press_enter
                ;;
            3)
                if [[ -z "$cur" ]]; then
                    echo -e "\n${C_RED}❌ Hakuna ujumbe wa kuzima.${C_RESET}"
                else
                    mkdir -p "$AM_DIR/users"
                    touch "$AM_DIR/users/$u.off"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Ujumbe umezimwa kwa '$u' (ujumbe umebaki, unaweza kuuwasha tena).${C_RESET}"
                fi
                press_enter
                ;;
            4)
                if [[ -z "$cur" ]]; then
                    echo -e "\n${C_RED}❌ Hakuna ujumbe wa kubadilisha. Tumia [1] Create message.${C_RESET}"
                    press_enter
                    continue
                fi
                echo -e "\n  ${C_DIM}Ujumbe wa sasa:${C_RESET} $cur"
                echo -e "  ${C_DIM}Andika ujumbe mpya, au bonyeza Enter ubaki kama ulivyo.${C_RESET}"
                _admin_msg_html_hint
                read -r -p "📝 Ujumbe mpya wa '$u': " new
                new=$(_admin_msg_sanitize "$new")
                if [[ -z "$new" ]]; then
                    echo -e "\n${C_YELLOW}ℹ️ Hakuna mabadiliko.${C_RESET}"
                else
                    set_user_admin_message "$u" "$new"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Ujumbe wa '$u' umebadilishwa.${C_RESET}"
                fi
                press_enter
                ;;
            5)
                if [[ -z "$cur" ]]; then
                    echo -e "\n${C_YELLOW}ℹ️ Hakuna ujumbe wa kufuta.${C_RESET}"
                else
                    read -r -p "🧹 Futa ujumbe wa '$u'? (y/n): " ans
                    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
                        set_user_admin_message "$u" ""
                        admin_message_apply
                        echo -e "\n${C_GREEN}✅ Ujumbe wa '$u' umefutwa.${C_RESET}"
                    else
                        echo -e "\n${C_YELLOW}ℹ️ Hakuna mabadiliko.${C_RESET}"
                    fi
                fi
                press_enter
                ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

# Orodha ya users -> chagua kwa namba -> menu ya user huyo
user_admin_message_menu() {
    _select_user_interface "--- 💬 User Admin Message ---"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        [[ "$u" == "NO_USERS" ]] && press_enter
        return
    fi
    user_admin_message_actions "$u"
}

list_user_admin_messages() {
    local f u m st found=false
    echo
    shopt -s nullglob
    for f in "$AM_DIR/users/"*.txt; do
        [[ -s "$f" ]] || continue
        u=$(basename "$f" .txt)
        IFS= read -r m < "$f"
        st=$(get_user_admin_message_state "$u")
        echo -e "   ${C_YELLOW}$u${C_RESET} [$st]: $m"
        found=true
    done
    shopt -u nullglob
    $found || echo -e "   ${C_DIM}(hakuna user mwenye Admin Message)${C_RESET}"
}

admin_message_menu() {
    local choice new g_status gmsg
    while true; do
        clear; show_banner
        if is_global_admin_message_enabled; then
            g_status="${C_STATUS_A}ENABLED (all users)${C_RESET}"
        else
            g_status="${C_STATUS_I}DISABLED${C_RESET}"
        fi
        gmsg=$(get_global_admin_message)
        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}📢 ADMIN MESSAGE ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        echo -e "   ${C_DIM}Inafanya kazi yenyewe. Haitegemei Dynamic Banner.${C_RESET}"
        echo -e "   Global message: $g_status"
        if [[ -n "$gmsg" ]]; then
            echo -e "   Text:           $gmsg"
        else
            echo -e "   Text:           ${C_DIM}(not set)${C_RESET}"
        fi
        echo -e "   Users with their own message: ${C_YELLOW}$(count_user_admin_messages)${C_RESET}\n"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✏️ Set / Change Global Message"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📢 Enable Global Message (all users)"
        printf "     ${C_DANGER}[ 3]${C_RESET} %-40s\n" "🔕 Disable Global Message"
        printf "     ${C_DANGER}[ 4]${C_RESET} %-40s\n" "🧹 Delete Global Message"
        printf "     ${C_CHOICE}[ 5]${C_RESET} %-40s\n" "📋 List User Messages"
        printf "     ${C_CHOICE}[ 6]${C_RESET} %-40s\n" "💬 User Admin Message (one user)"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return\n"
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                echo; _admin_msg_html_hint
                echo -e "  ${C_DIM}Bonyeza Enter kwenye mstari mtupu kughairi.${C_RESET}"
                read -r -p "📢 Global Admin Message: " new
                new=$(_admin_msg_sanitize "$new")
                if [[ -z "$new" ]]; then
                    echo -e "\n${C_YELLOW}ℹ️ Hakuna mabadiliko.${C_RESET}"
                else
                    mkdir -p "$AM_DIR"
                    printf '%s\n' "$new" > "$AM_DIR/global.txt"
                    chmod 644 "$AM_DIR/global.txt" 2>/dev/null
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Global Admin Message imehifadhiwa.${C_RESET}"
                    is_global_admin_message_enabled || echo -e "${C_YELLOW}ℹ️ Global message bado imezimwa. Chagua [2] kuiwezesha.${C_RESET}"
                fi
                press_enter
                ;;
            2)
                if [[ -z "$(get_global_admin_message)" ]]; then
                    echo -e "\n${C_RED}❌ Weka Global Admin Message kwanza (option 1).${C_RESET}"
                else
                    mkdir -p "$AM_DIR"
                    touch "$AM_DIR/global_enabled"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Global message imewashwa kwa watumiaji wote.${C_RESET}"
                fi
                press_enter
                ;;
            3)
                rm -f "$AM_DIR/global_enabled"
                admin_message_apply
                echo -e "\n${C_GREEN}✅ Global message imezimwa. Ujumbe wa user mmoja mmoja unaendelea kufanya kazi.${C_RESET}"
                press_enter
                ;;
            4)
                rm -f "$AM_DIR/global.txt" "$AM_DIR/global_enabled"
                admin_message_apply
                echo -e "\n${C_GREEN}✅ Global message imefutwa.${C_RESET}"
                press_enter
                ;;
            5) list_user_admin_messages; press_enter ;;
            6) user_admin_message_menu ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Kuendesha moja kwa moja: adminmsg.sh --daemon | --render
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "$1" in
        --daemon) adminmsg_daemon ;;
        --render) adminmsg_render_all ;;
        *) echo "Usage: $0 --daemon | --render   (au 'source' faili hili kwenye menu)" ;;
    esac
fi
AMSG_EOF
    chmod 755 "$ADMINMSG_LIB"
    sed -i 's/\r$//' "$ADMINMSG_LIB" 2>/dev/null
}

adminmsg_setup_service() {
    cat > "$ADMINMSG_SERVICE_FILE" << EOF
[Unit]
Description=Amokhan Tech Admin Message renderer
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $ADMINMSG_LIB --daemon
Restart=always
RestartSec=10
Nice=10
MemoryHigh=32M
MemoryMax=48M

[Install]
WantedBy=multi-user.target
EOF
    sed -i 's/\r$//' "$ADMINMSG_SERVICE_FILE" 2>/dev/null
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable AmokhanTech-adminmsg >/dev/null 2>&1
    systemctl restart AmokhanTech-adminmsg --no-block >/dev/null 2>&1
}

adminmsg_bootstrap() {
    local refreshed=false
    if [[ ! -f "$ADMINMSG_LIB" ]] || ! grep -Fqx "$ADMINMSG_MARKER" "$ADMINMSG_LIB" 2>/dev/null; then
        adminmsg_install_lib
        refreshed=true
    fi
    if $refreshed || [[ ! -f "$ADMINMSG_SERVICE_FILE" ]]; then
        adminmsg_setup_service
    elif ! systemctl is-active --quiet AmokhanTech-adminmsg 2>/dev/null; then
        systemctl start AmokhanTech-adminmsg --no-block >/dev/null 2>&1
    fi
    # shellcheck disable=SC1090
    source "$ADMINMSG_LIB"
}
# ================= END ADMIN MESSAGE: bootstrap =====================

# ===================== LEGACY -> AmokhanTech MIGRATION =====================
# Runs once. Old installs used the previous product name for the data dir, services and scripts.
# AMOKHAN_MIGRATE_ROOT is only used for testing (prefix for every path).
migrate_legacy_install() {
    local R="${AMOKHAN_MIGRATE_ROOT:-}"
    local new_dir="$R/etc/AmokhanTech" old_dir="" d f nf
    [[ -d "$new_dir" ]] && return 0
    for d in "$R/etc/visible""Tech" "$R/etc/Visible""Tech"; do
        [[ -d "$d" ]] && { old_dir="$d"; break; }
    done
    [[ -n "$old_dir" ]] || return 0

    echo "⚙️ Migrating existing installation to the Amokhan Tech names (one time)..."
    local -a was_enabled=() was_active=()
    local have_systemctl=false
    command -v systemctl >/dev/null 2>&1 && [[ -z "$R" ]] && have_systemctl=true

    # 1) stop + disable the old units (remember their state)
    for f in "$R"/etc/systemd/system/[vV]isible[T]ech-*.service; do
        [[ -e "$f" ]] || continue
        nf=$(basename "$f")
        if $have_systemctl; then
            systemctl is-enabled --quiet "$nf" 2>/dev/null && was_enabled+=("${nf//[vV]isible[T]ech/AmokhanTech}")
            systemctl is-active  --quiet "$nf" 2>/dev/null && was_active+=("${nf//[vV]isible[T]ech/AmokhanTech}")
            systemctl stop "$nf" >/dev/null 2>&1
            systemctl disable "$nf" >/dev/null 2>&1
        fi
    done

    # 2) move the data directory
    mv "$old_dir" "$new_dir"

    # 3) rename every file/dir that carries the old name
    for d in "$R/etc/systemd/system" "$R/usr/local/bin" "$R/usr/local/lib" "$R/etc/ssh/sshd_config.d" \
             "$R/etc/letsencrypt/renewal-hooks/deploy" "$R/etc/logrotate.d" "$R/etc/nginx/conf.d" "$R/etc/stunnel"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*[vV]isible[T]ech*; do
            [[ -e "$f" || -L "$f" ]] || continue
            nf="$d/$(basename "$f")"
            nf="${nf//[vV]isible[T]ech/AmokhanTech}"
            mv "$f" "$nf"
        done
    done
    while IFS= read -r f; do
        nf="$(dirname "$f")/$(basename "$f" | sed 's/[vV]isible[T]ech/AmokhanTech/g')"
        [[ "$f" != "$nf" ]] && mv "$f" "$nf"
    done < <(find "$new_dir" -depth -name '*[vV]isible[T]ech*' 2>/dev/null)

    # 4) rewrite the old name inside text files (the registered DNS domain is protected)
    local -a roots=("$new_dir" "$R/etc/systemd/system" "$R/usr/local/bin" "$R/usr/local/lib" "$R/etc/ssh/sshd_config.d" \
                    "$R/etc/letsencrypt/renewal-hooks/deploy" "$R/etc/logrotate.d" "$R/etc/nginx" "$R/etc/stunnel")
    local r
    for r in "${roots[@]}"; do
        [[ -e "$r" ]] || continue
        while IFS= read -r f; do
            [[ -L "$f" ]] && continue
            sed -i -E 's/([vV])isible[T]ech\.qzz\.io/\1@@KEEP@@.qzz.io/g; s/[vV]isible[T]ech/AmokhanTech/g; s/([vV])@@KEEP@@/\1isible'"T"'ech/g' "$f"
        done < <(grep -rIl '[vV]isible[T]ech' "$r" 2>/dev/null)
    done

    # 5) old scheduled trial-cleanup jobs still point at the old script path: keep a compatibility link
    if [[ -f "$R/usr/local/bin/AmokhanTech-trial-cleanup.sh" ]]; then
        ln -sf "$R/usr/local/bin/AmokhanTech-trial-cleanup.sh" "$R/usr/local/bin/visible""Tech-trial-cleanup.sh" 2>/dev/null
    fi

    # 6) reload systemd and bring the renamed services back to their previous state
    if $have_systemctl; then
        systemctl daemon-reload >/dev/null 2>&1
        for nf in "${was_enabled[@]}"; do systemctl enable "$nf" >/dev/null 2>&1; done
        for nf in "${was_active[@]}"; do systemctl restart "$nf" >/dev/null 2>&1; done
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    fi
    echo "✅ Migration finished."
}
# =================== END LEGACY MIGRATION ====================

preview_dynamic_ssh_banner() {
    if ! is_dynamic_ssh_banner_enabled; then
        echo -e "\n${C_RED}❌ Dynamic banners are not enabled right now.${C_RESET}"
        press_enter
        return
    fi

    echo -e "${C_DIM}Refreshing dynamic banner worker...${C_RESET}"
    setup_limiter_service >/dev/null 2>&1
    _select_user_interface "--- 📝 Preview Dynamic Banner ---"
    local u=$SELECTED_USER
    if [[ -z "$u" || "$u" == "NO_USERS" ]]; then
        return
    fi

    echo -e "\n${C_CYAN}--- Dynamic Banner Preview for user '$u' ---${C_RESET}\n"
    if [[ -f "/etc/AmokhanTech/banners/${u}.txt" ]]; then
        cat "/etc/AmokhanTech/banners/${u}.txt"
    else
        echo -e "${C_RED}Banner file not generated yet. Waiting up to 10s for the worker...${C_RESET}"
        sleep 5
        if ! cat "/etc/AmokhanTech/banners/${u}.txt" 2>/dev/null; then
            echo -e "\n${C_RED}Still not generated. Here are the last limiter logs:${C_RESET}"
            echo -e "----------------------------------------------------------------------"
            journalctl -u AmokhanTech-limiter -n 15 --no-pager
            echo -e "----------------------------------------------------------------------"
        fi
    fi
    press_enter
}

# NOTE: The full ssh_banner_menu() with dynamic/static support is defined later in the file.

refresh_ssh_session_cache() {
    local now db_mtime
    printf -v now '%(%s)T' -1
    db_mtime=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo 0)

    if (( SSH_SESSION_CACHE_TS > 0 && now - SSH_SESSION_CACHE_TS < SSH_SESSION_CACHE_TTL && db_mtime == SSH_SESSION_CACHE_DB_MTIME )); then
        return
    fi

    SSH_SESSION_COUNTS=()
    SSH_SESSION_PIDS=()
    SSH_SESSION_TOTAL=0
    SSH_SESSION_CACHE_DB_MTIME=$db_mtime

    if [[ ! -s "$DB_FILE" ]]; then
        SSH_SESSION_CACHE_TS=$now
        return
    fi

    local -A managed_user_lookup=()
    local -A uid_user_lookup=()
    local -A session_pids=()
    local -A loginuid_pids=()
    local managed_user system_user system_uid ssh_pid ssh_owner candidate_user login_uid

    while IFS=: read -r managed_user _rest; do
        [[ -n "$managed_user" && "$managed_user" != \#* ]] && managed_user_lookup["$managed_user"]=1
    done < "$DB_FILE"

    while IFS=: read -r system_user _ system_uid _rest; do
        [[ -n "$system_user" && "$system_uid" =~ ^[0-9]+$ ]] && uid_user_lookup["$system_uid"]="$system_user"
    done < /etc/passwd

    while read -r ssh_pid ssh_owner; do
        [[ "$ssh_pid" =~ ^[0-9]+$ ]] || continue

        # Method 1: process owner matches a managed user directly
        if [[ -n "$ssh_owner" && "$ssh_owner" != "root" && "$ssh_owner" != "sshd" && -n "${managed_user_lookup[$ssh_owner]+x}" ]]; then
            session_pids["$ssh_owner"]+="$ssh_pid "
        fi
    done < <(ps -C sshd,sshd-session -o pid=,user= 2>/dev/null)

    # Method 2: kernel loginuid with comm/PPid validation (more robust — matches limiter logic)
    local p pid_dir pid_num comm ppid_val session_user
    for p in /proc/[0-9]*/loginuid; do
        [[ -f "$p" ]] || continue
        login_uid=""
        read -r login_uid < "$p" || login_uid=""
        [[ "$login_uid" =~ ^[0-9]+$ && "$login_uid" != "4294967295" ]] || continue

        candidate_user="${uid_user_lookup[$login_uid]}"
        [[ -n "$candidate_user" && -n "${managed_user_lookup[$candidate_user]+x}" ]] || continue

        pid_dir=$(dirname "$p")
        pid_num=$(basename "$pid_dir")
        comm=""
        read -r comm < "$pid_dir/comm" 2>/dev/null || comm=""
        [[ "$comm" == "sshd" || "$comm" == "sshd-session" ]] || continue

        # Filter out the master sshd process (PPid=1)
        ppid_val=""
        while read -r key value; do
            [[ "$key" == "PPid:" ]] && { ppid_val="$value"; break; }
        done < "$pid_dir/status" 2>/dev/null
        [[ "$ppid_val" == "1" ]] && continue

        loginuid_pids["$candidate_user"]+="$pid_num "
    done

    local user pid
    for user in "${!managed_user_lookup[@]}"; do
        # CRITICAL: unset before declare to reset per-user (bash declare is function-scoped)
        unset unique_pids
        local -A unique_pids=()

        # Use ONLY ps-based session_pids for accurate counting.
        # loginuid_pids can double-count (root-owned sshd has user's loginuid on Ubuntu 24)
        for pid in ${session_pids[$user]}; do
            [[ "$pid" =~ ^[0-9]+$ ]] && unique_pids["$pid"]=1
        done

        SSH_SESSION_COUNTS["$user"]=${#unique_pids[@]}
        if (( ${#unique_pids[@]} > 0 )); then
            for pid in "${!unique_pids[@]}"; do
                SSH_SESSION_PIDS["$user"]+="$pid "
            done
            SSH_SESSION_TOTAL=$((SSH_SESSION_TOTAL + ${#unique_pids[@]}))
        fi
    done

    SSH_SESSION_CACHE_TS=$now
}

count_managed_online_sessions() {
    refresh_ssh_session_cache
    echo "$SSH_SESSION_TOTAL"
}

invalidate_banner_cache() {
    BANNER_CACHE_TS=0
    SSH_SESSION_CACHE_TS=0
}

refresh_banner_cache() {
    local now
    printf -v now '%(%s)T' -1
    if (( BANNER_CACHE_TS > 0 && now - BANNER_CACHE_TS < BANNER_CACHE_TTL )); then
        return
    fi

    if [[ -z "$BANNER_CACHE_OS_NAME" ]]; then
        BANNER_CACHE_OS_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
    fi
    BANNER_CACHE_UP_TIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    BANNER_CACHE_RAM_USAGE=$(free -m | awk '/^Mem:/{if($2>0){printf "%.2f", $3*100/$2}else{print "0.00"}}')
    BANNER_CACHE_CPU_LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
    if [[ -s "$DB_FILE" ]]; then
        BANNER_CACHE_TOTAL_USERS=0
        while IFS=: read -r _u _rest; do
            [[ -n "$_u" && "$_u" != \#* ]] && (( BANNER_CACHE_TOTAL_USERS++ ))
        done < "$DB_FILE"
    else
        BANNER_CACHE_TOTAL_USERS=0
    fi
    BANNER_CACHE_ONLINE_USERS=$(count_managed_online_sessions)
    BANNER_CACHE_TS=$now
}

show_banner() {
    refresh_banner_cache
    [[ -t 1 ]] && clear
    echo
    echo -e "${C_TITLE}   Amokhan Tech SSH Manager ${C_RESET}${C_DIM}| v4.0.0 SSH-Only Edition${C_RESET}"

    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "OS" "$BANNER_CACHE_OS_NAME" "Uptime: $BANNER_CACHE_UP_TIME"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Memory" "${BANNER_CACHE_RAM_USAGE}% Used" "Online Sessions: ${C_WHITE}${BANNER_CACHE_ONLINE_USERS}${C_RESET}"
    printf "   ${C_GRAY}%-10s${C_RESET} %-20s ${C_GRAY}|${C_RESET} %s\n" "Users" "${BANNER_CACHE_TOTAL_USERS} Managed Accounts" "Sys Load (1m): ${C_GREEN}${BANNER_CACHE_CPU_LOAD}${C_RESET}"
    echo -e "${C_BLUE}   ─────────────────────────────────────────────────────────${C_RESET}"
}

# ====================================================================

install_web_panel() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Installing Web Control Panel ---${C_RESET}"

    if [ -f "$PANEL_SERVICE_FILE" ]; then
        # Migrate older installations: pass the exact DB_DIR used by menu.sh.
        if ! grep -q '^Environment=PANEL_DB_DIR=' "$PANEL_SERVICE_FILE"; then
            if grep -q '^Environment=PANEL_PORT=' "$PANEL_SERVICE_FILE"; then
                sed -i "/^Environment=PANEL_PORT=/a Environment=PANEL_DB_DIR=$DB_DIR" "$PANEL_SERVICE_FILE"
            else
                sed -i "/^ExecStart=/a Environment=PANEL_DB_DIR=$DB_DIR" "$PANEL_SERVICE_FILE"
            fi
            systemctl daemon-reload
            systemctl restart AmokhanTech-panel &>/dev/null
            sleep 2
        fi
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is already installed; checking service configuration.${C_RESET}"
        if systemctl is-active --quiet AmokhanTech-panel; then
            echo -e "${C_GREEN}Panel service is running.${C_RESET}"
        else
            echo -e "${C_RED}Panel service is not running. Recent logs:${C_RESET}"
            journalctl -u AmokhanTech-panel -n 15 --no-pager
        fi
        show_panel_credentials
        return
    fi

    if ! command -v python3 &>/dev/null; then
        echo -e "${C_YELLOW}Installing python3...${C_RESET}"
        ff_pkg_install python3 || { echo -e "${C_RED}❌ Failed to install python3.${C_RESET}"; return; }
    fi

    echo -e "${C_BLUE}🔎 Checking if port $PANEL_PORT is available...${C_RESET}"
    check_and_free_ports "$PANEL_PORT" || return
    check_and_open_firewall_port "$PANEL_PORT" tcp || return

    local panel_user panel_pass panel_pass_hash
    while :; do
        read -r -p "👤 Set Web Panel username: " panel_user
        [[ -n "$panel_user" ]] && break
        echo -e "${C_RED}Username cannot be empty.${C_RESET}"
    done
    while :; do
        read -r -s -p "🔑 Set Web Panel password: " panel_pass
        echo
        [[ -n "$panel_pass" ]] && break
        echo -e "${C_RED}Password cannot be empty.${C_RESET}"
    done
    panel_pass_hash=$(printf '%s' "$panel_pass" | sha256sum | awk '{print $1}')

    echo -e "${C_BLUE}📥 Downloading panel files...${C_RESET}"
    mkdir -p "$PANEL_HTML_DIR" || return
    local tmp_py tmp_html
    tmp_py=$(mktemp) || return
    tmp_html=$(mktemp) || { rm -f "$tmp_py"; return; }
    if ! curl -fsSL --retry 2 --connect-timeout 10 "$PANEL_REPO_BASE/panel.py" -o "$tmp_py"; then
        echo -e "${C_RED}❌ Failed to download panel.py from $PANEL_REPO_BASE.${C_RESET}"
        rm -f "$tmp_py" "$tmp_html"; return
    fi
    if ! curl -fsSL --retry 2 --connect-timeout 10 "$PANEL_REPO_BASE/index.html" -o "$tmp_html"; then
        echo -e "${C_RED}❌ Failed to download index.html from $PANEL_REPO_BASE.${C_RESET}"
        rm -f "$tmp_py" "$tmp_html"; return
    fi
    if ! python3 -m py_compile "$tmp_py"; then
        echo -e "${C_RED}❌ Downloaded panel.py failed Python syntax validation.${C_RESET}"
        rm -f "$tmp_py" "$tmp_html"; return
    fi
    if ! grep -qi '<html' "$tmp_html"; then
        echo -e "${C_RED}❌ Downloaded index.html does not look like an HTML page.${C_RESET}"
        rm -f "$tmp_py" "$tmp_html"; return
    fi
    install -m 755 "$tmp_py" "$PANEL_SCRIPT" || { rm -f "$tmp_py" "$tmp_html"; return; }
    install -m 644 "$tmp_html" "$PANEL_HTML_FILE" || { rm -f "$tmp_py" "$tmp_html"; return; }
    rm -f "$tmp_py" "$tmp_html"
    sed -i 's/\r$//' "$PANEL_SCRIPT" 2>/dev/null

    # Store values safely so spaces and punctuation in credentials are preserved.
    {
        printf 'PANEL_USER=%q\n' "$panel_user"
        printf 'PANEL_PASS_HASH=%q\n' "$panel_pass_hash"
        printf 'PANEL_PASS_PLAIN=%q\n' "$panel_pass"
        printf 'PANEL_SECRET=%q\n' ""
    } > "$PANEL_CONF"
    chmod 600 "$PANEL_CONF"

    cat > "$PANEL_SERVICE_FILE" <<-SEOF
[Unit]
Description=Amokhan Tech Web Control Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $PANEL_SCRIPT
Restart=always
RestartSec=5
Nice=10
MemoryHigh=64M
MemoryMax=96M
Environment=PANEL_PORT=$PANEL_PORT
Environment=PANEL_DB_DIR=$DB_DIR

[Install]
WantedBy=multi-user.target
SEOF

    systemctl daemon-reload
    systemctl enable AmokhanTech-panel &>/dev/null
    systemctl restart AmokhanTech-panel &>/dev/null
    sleep 2

    if systemctl is-active --quiet AmokhanTech-panel; then
        local server_ip
        server_ip=$(curl -s -4 --max-time 3 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
        clear; show_banner
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "${C_GREEN}     ✅ Web Control Panel Installed Successfully!     ${C_RESET}"
        echo -e "${C_GREEN}=====================================================${C_RESET}"
        echo -e "\n${C_CYAN}  🌐 Panel URL:${C_RESET}    ${C_YELLOW}http://${server_ip}:${PANEL_PORT}/${C_RESET}"
        echo -e "${C_CYAN}  👤 Username:${C_RESET}     ${C_YELLOW}${panel_user}${C_RESET}"
        echo -e "${C_CYAN}  🔑 Password:${C_RESET}     ${C_YELLOW}${panel_pass}${C_RESET}"
        echo -e "\n${C_DIM}Save these credentials. They can be viewed from Web Control Panel > Show Panel Credentials.${C_RESET}"
    else
        echo -e "\n${C_RED}❌ Panel service failed to start. Checking logs:${C_RESET}"
        journalctl -u AmokhanTech-panel -n 25 --no-pager
    fi
}
uninstall_web_panel() {
    if [ ! -f "$PANEL_SERVICE_FILE" ]; then
        if [[ "$UNINSTALL_MODE" != "silent" ]]; then
            echo -e "${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        fi
        return
    fi
    
    if [[ "$UNINSTALL_MODE" != "silent" ]]; then
        echo -e "\n${C_BOLD}${C_PURPLE}--- 🗑️ Uninstalling Web Control Panel ---${C_RESET}"
        read -p "👉 Are you sure you want to uninstall the Web Panel? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            echo -e "\n${C_YELLOW}❌ Uninstallation cancelled.${C_RESET}"
            return
        fi
    fi
    
    echo -e "${C_BLUE}🛑 Stopping and removing Web Panel service...${C_RESET}"
    systemctl stop AmokhanTech-panel &>/dev/null
    systemctl disable AmokhanTech-panel &>/dev/null
    rm -f "$PANEL_SERVICE_FILE"
    rm -f "$PANEL_SCRIPT"
    rm -rf "$PANEL_HTML_DIR"
    rm -f "$PANEL_CONF"
    systemctl daemon-reload
    
    echo -e "${C_GREEN}✅ Web Panel has been uninstalled.${C_RESET}"
}

show_panel_credentials() {
    if [ ! -f "$PANEL_CONF" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        return
    fi
    source "$PANEL_CONF"
    local server_ip
    server_ip=$(curl -s -4 --max-time 3 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    echo -e "\n${C_GREEN}=====================================================${C_RESET}"
    echo -e "${C_GREEN}         🌐 Web Panel Credentials                    ${C_RESET}"
    echo -e "${C_GREEN}=====================================================${C_RESET}"
    echo -e "\n${C_CYAN}  🌐 Panel URL:${C_RESET}    ${C_YELLOW}http://${server_ip}:${PANEL_PORT}/${C_RESET}"
    echo -e "${C_CYAN}  👤 Username:${C_RESET}     ${C_YELLOW}${PANEL_USER}${C_RESET}"
    echo -e "${C_CYAN}  🔑 Password:${C_RESET}     ${C_YELLOW}${PANEL_PASS_PLAIN}${C_RESET}"
    if systemctl is-active --quiet AmokhanTech-panel 2>/dev/null; then
        echo -e "\n${C_CYAN}  📡 Status:${C_RESET}       ${C_GREEN}🟢 Running${C_RESET}"
    else
        echo -e "\n${C_CYAN}  📡 Status:${C_RESET}       ${C_RED}🔴 Stopped${C_RESET}"
    fi
}
change_panel_credentials() {
    if [ ! -f "$PANEL_CONF" ]; then
        echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
        return
    fi
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔑 Change Web Panel Credentials ---${C_RESET}"
    show_panel_credentials
    source "$PANEL_CONF"
    local new_user new_pass new_hash
    read -r -p "👉 Enter new username (Enter keeps current): " new_user
    read -r -s -p "🔑 Enter new password (Enter keeps current): " new_pass
    echo
    [[ -z "$new_user" ]] && new_user="$PANEL_USER"
    [[ -z "$new_pass" ]] && new_pass="$PANEL_PASS_PLAIN"
    new_hash=$(printf '%s' "$new_pass" | sha256sum | awk '{print $1}')
    {
        printf 'PANEL_USER=%q\n' "$new_user"
        printf 'PANEL_PASS_HASH=%q\n' "$new_hash"
        printf 'PANEL_PASS_PLAIN=%q\n' "$new_pass"
        printf 'PANEL_SECRET=%q\n' ""
    } > "$PANEL_CONF"
    chmod 600 "$PANEL_CONF"
    systemctl restart AmokhanTech-panel &>/dev/null
    echo -e "\n${C_GREEN}✅ Panel credentials updated.${C_RESET}"
    echo -e "  ${C_CYAN}👤 Username:${C_RESET}    ${C_YELLOW}$new_user${C_RESET}"
    echo -e "  ${C_CYAN}🔑 Password:${C_RESET}    ${C_YELLOW}$new_pass${C_RESET}"
}
web_panel_menu() {
    while true; do
        clear; show_banner
        echo -e "${C_BOLD}${C_PURPLE}--- 🌐 Web Control Panel ---${C_RESET}\n"
        
        if [ -f "$PANEL_SERVICE_FILE" ]; then
            if systemctl is-active --quiet AmokhanTech-panel 2>/dev/null; then
                echo -e "  ${C_DIM}Status: ${C_GREEN}🟢 Installed & Running${C_RESET}\n"
            else
                echo -e "  ${C_DIM}Status: ${C_RED}🔴 Installed but Stopped${C_RESET}\n"
            fi
        else
            echo -e "  ${C_DIM}Status: ${C_YELLOW}⚪ Not Installed${C_RESET}\n"
        fi
        
        printf "  ${C_GREEN}[ 1]${C_RESET} %-35s\n" "🚀 Install Web Panel"
        printf "  ${C_GREEN}[ 2]${C_RESET} %-35s\n" "🗑️  Uninstall Web Panel"
        printf "  ${C_GREEN}[ 3]${C_RESET} %-35s\n" "🔑 Show Panel Credentials"
        printf "  ${C_GREEN}[ 4]${C_RESET} %-35s\n" "🔄 Change Panel Credentials"
        printf "  ${C_GREEN}[ 5]${C_RESET} %-35s\n" "🔃 Restart Panel Service"
        echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️  Back to Main Menu"
        echo
        
        read -r -p "👉 Enter your choice: " panel_choice
        case $panel_choice in
            1) install_web_panel; press_enter ;;
            2) uninstall_web_panel; press_enter ;;
            3) show_panel_credentials; press_enter ;;
            4) change_panel_credentials; press_enter ;;
            5)
                if [ -f "$PANEL_SERVICE_FILE" ]; then
                    systemctl restart AmokhanTech-panel &>/dev/null
                    sleep 1
                    if systemctl is-active --quiet AmokhanTech-panel; then
                        echo -e "\n${C_GREEN}✅ Web Panel service restarted successfully.${C_RESET}"
                    else
                        echo -e "\n${C_RED}❌ Failed to restart. Checking logs:${C_RESET}"
                        journalctl -u AmokhanTech-panel -n 10 --no-pager
                    fi
                else
                    echo -e "\n${C_YELLOW}ℹ️ Web Panel is not installed.${C_RESET}"
                fi
                press_enter
                ;;
            0) return ;;
            *) invalid_option ;;
        esac
    done
}

uninstall_script() {
    clear; show_banner
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_RED}       🔥 DANGER: UNINSTALL SCRIPT & ALL DATA 🔥      ${C_RESET}"
    echo -e "${C_RED}=====================================================${C_RESET}"
    echo -e "${C_YELLOW}This will PERMANENTLY remove this script and all its components, including:"
    echo -e " - The main command ($(command -v menu 2>/dev/null || echo 'menu'))"
    echo -e " - All configuration and user data ($DB_DIR)"
    echo -e " - The active limiter service ($LIMITER_SERVICE)"
    echo -e " - Web Control Panel (if installed)"
    echo -e "\n${C_RED}This action is irreversible.${C_RESET}"
    echo ""
    read -p "👉 Type 'yes' to confirm and proceed with uninstallation: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "\n${C_GREEN}✅ Uninstallation cancelled.${C_RESET}"
        return
    fi
    local -a removable_users=()
    local remove_users_confirm
    local remove_users_on_uninstall=false
    mapfile -t removable_users < <(get_AmokhanTech_known_users)
    if [[ ${#removable_users[@]} -gt 0 ]]; then
        echo -e "\n${C_YELLOW}Amokhan Tech SSH users detected on this VPS:${C_RESET} ${removable_users[*]}"
        read -p "👉 Do you also want to permanently delete these SSH users before uninstalling? (y/n): " remove_users_confirm
        if [[ "$remove_users_confirm" == "y" || "$remove_users_confirm" == "Y" ]]; then
            remove_users_on_uninstall=true
        fi
    fi
    export UNINSTALL_MODE="silent"
    echo -e "\n${C_BLUE}--- 💥 Starting Uninstallation 💥 ---${C_RESET}"
    
    if [[ "$remove_users_on_uninstall" == "true" ]]; then
        echo -e "\n${C_BLUE}🗑️ Removing Amokhan Tech SSH users before uninstall...${C_RESET}"
        delete_AmokhanTech_user_accounts "${removable_users[@]}"
    fi
    
    echo -e "\n${C_BLUE}🗑️ Removing active limiter service...${C_RESET}"
    systemctl stop AmokhanTech-limiter &>/dev/null
    systemctl disable AmokhanTech-limiter &>/dev/null
    rm -f "$LIMITER_SERVICE"
    rm -f "$LIMITER_SCRIPT"
    systemctl stop AmokhanTech-adminmsg &>/dev/null
    systemctl disable AmokhanTech-adminmsg &>/dev/null
    rm -f "$ADMINMSG_SERVICE_FILE" "$ADMINMSG_LIB"
    
    echo -e "\n${C_BLUE}🗑️ Removing bandwidth monitoring service...${C_RESET}"
    systemctl stop AmokhanTech-bandwidth &>/dev/null
    systemctl disable AmokhanTech-bandwidth &>/dev/null
    rm -f "$BANDWIDTH_SERVICE"
    rm -f "$BANDWIDTH_SCRIPT"
    rm -rf "$LEGACY_BANDWIDTH_DIR"
    rm -f "$TRIAL_CLEANUP_SCRIPT"
    
    echo -e "\n${C_BLUE}🗑️ Removing SSH login banner...${C_RESET}"
    rm -f "$LOGIN_INFO_SCRIPT"
    rm -f "$SSHD_FF_CONFIG"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    
    uninstall_web_panel
    delete_dns_record
    
    echo -e "\n${C_BLUE}🔄 Reloading systemd daemon...${C_RESET}"
    systemctl daemon-reload
    
    echo -e "\n${C_BLUE}🗑️ Removing script and configuration files...${C_RESET}"
    rm -rf "$DB_DIR"
    rm -f "$(command -v menu 2>/dev/null)"
    
    echo -e "\n${C_GREEN}=============================================${C_RESET}"
    echo -e "${C_GREEN}      Script has been successfully uninstalled.     ${C_RESET}"
    echo -e "${C_GREEN}=============================================${C_RESET}"
    echo -e "\nAll associated files and services have been removed."
    echo "The 'menu' command will no longer work."
    exit 0
}


# --- NEW FEATURES ---

create_trial_account() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ⏱️ Create Trial/Test Account ---${C_RESET}"
    
    # Ensure 'at' daemon is available
    if ! command -v at &>/dev/null; then
        echo -e "${C_YELLOW}⚠️ 'at' command not found. Installing...${C_RESET}"
        ff_pkg_install at >/dev/null 2>&1 || {
            echo -e "${C_RED}❌ Failed to install 'at'. Cannot schedule auto-expiry.${C_RESET}"
            return
        }
        systemctl enable atd &>/dev/null
        systemctl start atd &>/dev/null
    fi
    
    # Ensure atd is running
    if ! systemctl is-active --quiet atd; then
        systemctl start atd &>/dev/null
    fi
    
    echo -e "\n${C_CYAN}Select trial duration:${C_RESET}\n"
    printf "  ${C_GREEN}[ 1]${C_RESET} ⏱️  1 Hour\n"
    printf "  ${C_GREEN}[ 2]${C_RESET} ⏱️  2 Hours\n"
    printf "  ${C_GREEN}[ 3]${C_RESET} ⏱️  3 Hours\n"
    printf "  ${C_GREEN}[ 4]${C_RESET} ⏱️  6 Hours\n"
    printf "  ${C_GREEN}[ 5]${C_RESET} ⏱️  12 Hours\n"
    printf "  ${C_GREEN}[ 6]${C_RESET} 📅  1 Day\n"
    printf "  ${C_GREEN}[ 7]${C_RESET} 📅  3 Days\n"
    printf "  ${C_GREEN}[ 8]${C_RESET} ⚙️  Custom (enter hours)\n"
    echo -e "\n  ${C_RED}[ 0]${C_RESET} ↩️ Cancel"
    echo
    read -p "👉 Select duration: " dur_choice
    
    local duration_hours=0
    local duration_label=""
    case $dur_choice in
        1) duration_hours=1;   duration_label="1 Hour" ;;
        2) duration_hours=2;   duration_label="2 Hours" ;;
        3) duration_hours=3;   duration_label="3 Hours" ;;
        4) duration_hours=6;   duration_label="6 Hours" ;;
        5) duration_hours=12;  duration_label="12 Hours" ;;
        6) duration_hours=24;  duration_label="1 Day" ;;
        7) duration_hours=72;  duration_label="3 Days" ;;
        8) read -p "👉 Enter custom duration in hours: " custom_hours
           if ! [[ "$custom_hours" =~ ^[0-9]+$ ]] || [[ "$custom_hours" -lt 1 ]]; then
               echo -e "\n${C_RED}❌ Invalid number of hours.${C_RESET}"; return
           fi
           duration_hours=$custom_hours
           duration_label="$custom_hours Hours"
           ;;
        0) echo -e "\n${C_YELLOW}❌ Cancelled.${C_RESET}"; return ;;
        *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}"; return ;;
    esac
    
    # Username
    local rand_suffix=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 5)
    local default_username="trial_${rand_suffix}"
    read -p "👤 Username [${default_username}]: " username
    username=${username:-$default_username}
    
    if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
        echo -e "\n${C_RED}❌ Error: User '$username' already exists.${C_RESET}"; return
    fi
    
    # Password
    local password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
    read -p "🔑 Password [${password}]: " custom_pass
    password=${custom_pass:-$password}
    
    # Connection limit
    read -p "📶 Connection limit [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Bandwidth limit
    read -p "📦 Bandwidth limit in GB (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    # Calculate expiry
    local expire_date
    if [[ "$duration_hours" -ge 24 ]]; then
        local days=$((duration_hours / 24))
        expire_date=$(date -d "+$days days" +%Y-%m-%d)
    else
        # For sub-day durations, set expiry to tomorrow to be safe (at job does the real cleanup)
        expire_date=$(date -d "+1 day" +%Y-%m-%d)
    fi
    local expiry_timestamp
    expiry_timestamp=$(date -d "+${duration_hours} hours" '+%Y-%m-%d %H:%M:%S')
    
    # Create the system user
    ensure_AmokhanTech_system_group
    useradd -m -s /usr/sbin/nologin "$username"
    usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:trial" >> "$DB_FILE"
    
    # Schedule auto-cleanup via 'at'
    echo "$TRIAL_CLEANUP_SCRIPT $username" | at now + ${duration_hours} hours 2>/dev/null
    
    local bw_display="Unlimited"
    if [[ "$bandwidth_gb" != "0" ]]; then bw_display="${bandwidth_gb} GB"; fi
    
    clear; show_banner
    echo -e "${C_GREEN}✅ Trial account created successfully!${C_RESET}\n"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  ⏱️  ${C_BOLD}TRIAL ACCOUNT${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "  - 👤 Username:          ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password:          ${C_YELLOW}$password${C_RESET}"
    echo -e "  - ⏱️ Duration:          ${C_CYAN}$duration_label${C_RESET}"
    echo -e "  - 🕐 Auto-expires at:   ${C_RED}$expiry_timestamp${C_RESET}"
    echo -e "  - 📶 Connection Limit:  ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth Limit:   ${C_YELLOW}$bw_display${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "\n${C_DIM}The account will be automatically deleted when the trial expires.${C_RESET}"
    
    # Auto-ask for config generation
    echo
    read -p "👉 Generate client config for this trial user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_client_config "$username" "$password"
    fi
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

view_user_bandwidth() {
    _select_user_interface "--- 📊 View User Bandwidth ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 Bandwidth Details: ${C_YELLOW}$u${C_PURPLE} ---${C_RESET}\n"
    
    local line; line=$(grep "^$u:" "$DB_FILE")
    local _u _p _e _l bandwidth_gb
    IFS=: read -r _u _p _e _l bandwidth_gb _ <<< "$line"
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    
    local used_bytes=0
    if [[ -f "$BANDWIDTH_DIR/${u}.usage" ]]; then
        read -r used_bytes < "$BANDWIDTH_DIR/${u}.usage" 2>/dev/null || used_bytes=0
        [[ -z "$used_bytes" ]] && used_bytes=0
    fi
    
    local used_mb; used_mb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1048576}")
    local used_gb; used_gb=$(awk "BEGIN {printf \"%.3f\", $used_bytes / 1073741824}")
    
    echo -e "  ${C_CYAN}Data Used:${C_RESET}        ${C_WHITE}${used_gb} GB${C_RESET} (${used_mb} MB)"
    
    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_GREEN}Unlimited${C_RESET}"
        echo -e "  ${C_CYAN}Status:${C_RESET}           ${C_GREEN}No quota restrictions${C_RESET}"
    else
        local quota_bytes; quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
        local percentage; percentage=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / $quota_bytes) * 100}")
        local remaining_bytes; remaining_bytes=$((quota_bytes - used_bytes))
        if [[ "$remaining_bytes" -lt 0 ]]; then remaining_bytes=0; fi
        local remaining_gb; remaining_gb=$(awk "BEGIN {printf \"%.3f\", $remaining_bytes / 1073741824}")
        
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Remaining:${C_RESET}        ${C_WHITE}${remaining_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Usage:${C_RESET}            ${C_WHITE}${percentage}%${C_RESET}"
        
        # Progress bar
        local bar_width=30
        local filled; filled=$(awk "BEGIN {printf \"%.0f\", ($percentage / 100) * $bar_width}")
        if [[ "$filled" -gt "$bar_width" ]]; then filled=$bar_width; fi
        local empty=$((bar_width - filled))
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percentage > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percentage > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        printf "  ${C_CYAN}Progress:${C_RESET}         ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percentage}%%\n"
        
        if [[ "$used_bytes" -ge "$quota_bytes" ]]; then
            echo -e "\n  ${C_RED}⚠️ USER HAS EXCEEDED BANDWIDTH QUOTA — ACCOUNT LOCKED${C_RESET}"
        fi
    fi
}

bulk_create_users() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 👥 Bulk Create Users ---${C_RESET}"
    
    read -p "👉 Enter username prefix (e.g., 'user'): " prefix
    if [[ -z "$prefix" ]]; then echo -e "\n${C_RED}❌ Prefix cannot be empty.${C_RESET}"; return; fi
    
    read -p "🔢 How many users to create? " count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 100 ]]; then
        echo -e "\n${C_RED}❌ Invalid count (1-100).${C_RESET}"; return
    fi
    
    read -p "🗓️ Account duration (in days) [30]: " days
    days=${days:-30}
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📶 Connection limit per user [1]: " limit
    limit=${limit:-1}
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📦 Bandwidth limit in GB per user (0 = unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    if ! [[ "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    read -p "📦 DAILY bandwidth limit in GB per user (0 = unlimited) [0]: " daily_bandwidth_gb
    daily_bandwidth_gb=${daily_bandwidth_gb:-0}
    if ! [[ "$daily_bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]]; then echo -e "\n${C_RED}❌ Invalid number.${C_RESET}"; return; fi
    
    local expire_date
    expire_date=$(date -d "+$days days" +%Y-%m-%d)
    local bw_display="Unlimited"; [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb} GB"
    local daily_bw_display="Unlimited"; [[ "$daily_bandwidth_gb" != "0" ]] && daily_bw_display="${daily_bandwidth_gb} GB/day"
    ensure_AmokhanTech_system_group
    
    echo -e "\n${C_BLUE}⚙️ Creating $count users with prefix '${prefix}'...${C_RESET}\n"
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-20s | %-15s | %-12s${C_RESET}\n" "USERNAME" "PASSWORD" "EXPIRES"
    echo -e "${C_YELLOW}----------------------------------------------------------------${C_RESET}"
    
    local created=0
    for ((i=1; i<=count; i++)); do
        local username="${prefix}${i}"
        if id "$username" &>/dev/null || grep -q "^$username:" "$DB_FILE"; then
            echo -e "${C_RED}  ⚠️ Skipping '$username' — already exists${C_RESET}"
            continue
        fi
        local password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
        useradd -m -s /usr/sbin/nologin "$username"
        usermod -aG "$FF_USERS_GROUP" "$username" 2>/dev/null
        echo "$username:$password" | chpasswd
        chage -E "$expire_date" "$username"
        echo "$username:$password:$expire_date:$limit:$bandwidth_gb:$daily_bandwidth_gb:bulk" >> "$DB_FILE"
        printf "  ${C_GREEN}%-20s${C_RESET} | ${C_YELLOW}%-15s${C_RESET} | ${C_CYAN}%-12s${C_RESET}\n" "$username" "$password" "$expire_date"
        created=$((created + 1))
    done
    
    echo -e "${C_YELLOW}================================================================${C_RESET}"
    echo -e "\n${C_GREEN}✅ Created $created users. Conn Limit: ${limit} | Total BW: ${bw_display} | Daily BW: ${daily_bw_display}${C_RESET}"
    
    invalidate_banner_cache
    refresh_dynamic_banner_routing_if_enabled
}

detect_preferred_host() {
    local host_domain=""
    if [[ -f "$DNS_INFO_FILE" ]]; then
        host_domain=$(grep 'FULL_DOMAIN' "$DNS_INFO_FILE" 2>/dev/null | cut -d'"' -f2)
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(curl -s -4 --max-time 5 icanhazip.com 2>/dev/null)
    fi
    echo "$host_domain"
}

generate_client_config() {
    local user=$1
    local pass=$2
    
    local host_ip
    host_ip=$(curl -s -4 --max-time 5 icanhazip.com 2>/dev/null)
    local host_domain
    host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$host_ip"

    local ssh_port
    ssh_port=$(grep -hiE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | head -n 1)
    ssh_port=${ssh_port:-22}

    echo -e "\n${C_BOLD}${C_PURPLE}--- 📱 SSH Client Connection Configuration ---${C_RESET}"
    echo -e "${C_CYAN}Copy the details below to your clipboard:${C_RESET}\n"

    echo -e "${C_YELLOW}========================================${C_RESET}"
    echo -e "👤 ${C_BOLD}User Details${C_RESET}"
    echo -e "   • Username: ${C_WHITE}$user${C_RESET}"
    echo -e "   • Password: ${C_WHITE}$pass${C_RESET}"
    echo -e "   • Host/IP : ${C_WHITE}$host_domain${C_RESET}"
    echo -e "${C_YELLOW}========================================${C_RESET}"
    
    echo -e "\n🔹 ${C_BOLD}SSH Direct${C_RESET}:"
    echo -e "   • Host: $host_domain"
    echo -e "   • Port: $ssh_port"
    echo -e "   • Protocol: SSH"
    
    echo -e "${C_YELLOW}========================================${C_RESET}"
}


client_config_menu() {
    _select_user_interface "--- 📱 Generate Client Config ---"
    local u=$SELECTED_USER
    if [[ "$u" == "NO_USERS" || -z "$u" ]]; then return; fi
    
    # We need to find the password. It's in the DB.
    local pass=$(grep "^$u:" "$DB_FILE" | cut -d: -f2)
    generate_client_config "$u" "$pass"
}

format_rate_from_kbps() {
    local kbps=${1:-0}
    if (( kbps >= 1024 )); then
        printf "%d.%02d MB/s" $((kbps / 1024)) $((((kbps % 1024) * 100) / 1024))
    else
        printf "%d KB/s" "$kbps"
    fi
}

# Lightweight Bash Monitor (No vnStat required)
simple_live_monitor() {
    local iface=$1
    local rx_file="/sys/class/net/$iface/statistics/rx_bytes"
    local tx_file="/sys/class/net/$iface/statistics/tx_bytes"
    local interval=2
    local stop_monitor=0
    local rx1 tx1 rx2 tx2 rx_diff tx_diff rx_kbs tx_kbs rx_fmt tx_fmt

    if [[ -z "$iface" || ! -r "$rx_file" || ! -r "$tx_file" ]]; then
        echo -e "\n${C_RED}❌ Could not read interface statistics for '${iface:-unknown}'.${C_RESET}"
        return
    fi

    echo -e "\n${C_BLUE}⚡ Starting Lightweight Traffic Monitor for $iface...${C_RESET}"
    echo -e "${C_DIM}Press [Ctrl+C] to stop.${C_RESET}\n"

    read -r rx1 < "$rx_file"
    read -r tx1 < "$tx_file"

    printf "%-15s | %-15s\n" "⬇️ Download" "⬆️ Upload"
    echo "-----------------------------------"

    trap 'stop_monitor=1' INT TERM
    while (( ! stop_monitor )); do
        sleep "$interval"
        read -r rx2 < "$rx_file" || break
        read -r tx2 < "$tx_file" || break

        rx_diff=$((rx2 - rx1))
        tx_diff=$((tx2 - tx1))
        (( rx_diff < 0 )) && rx_diff=0
        (( tx_diff < 0 )) && tx_diff=0

        rx_kbs=$((rx_diff / 1024 / interval))
        tx_kbs=$((tx_diff / 1024 / interval))
        rx_fmt=$(format_rate_from_kbps "$rx_kbs")
        tx_fmt=$(format_rate_from_kbps "$tx_kbs")

        printf "\r%-15s | %-15s" "$rx_fmt" "$tx_fmt"

        rx1=$rx2
        tx1=$tx2
    done
    trap - INT TERM
    echo
}

traffic_monitor_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📈 Network Traffic Monitor ---${C_RESET}"
    
    # Find active interface
    local iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    echo -e "\nInterface: ${C_CYAN}${iface}${C_RESET}"
    
    echo -e "\n${C_BOLD}Select a monitoring option:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "⚡ Live Monitor ${C_DIM}(Lightweight, No Install)${C_RESET}"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📊 View Total Traffic Since Boot"
    printf "  ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "📅 Daily/Monthly Logs ${C_DIM}(Requires vnStat)${C_RESET}"
    
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -p "👉 Enter choice: " t_choice
    case $t_choice in
        1) 
           simple_live_monitor "$iface"
           ;;
        2)
            local rx_total=$(cat /sys/class/net/$iface/statistics/rx_bytes)
            local tx_total=$(cat /sys/class/net/$iface/statistics/tx_bytes)
            local rx_mb=$((rx_total / 1024 / 1024))
            local tx_mb=$((tx_total / 1024 / 1024))
            echo -e "\n${C_BLUE}📊 Total Traffic (Since Boot):${C_RESET}"
            echo -e "   ⬇️ Download: ${C_WHITE}${rx_mb} MB${C_RESET}"
            echo -e "   ⬆️ Upload:   ${C_WHITE}${tx_mb} MB${C_RESET}"
            press_enter
            ;;
        3) 
           # vnStat Logic
           if ! command -v vnstat &> /dev/null; then
               echo -e "\n${C_YELLOW}⚠️ vnStat is not installed.${C_RESET}"
               echo -e "   This tool provides persistent history (Daily/Monthly reports)."
               echo -e "   It is lightweight but requires installation."
               read -p "👉 Install vnStat now? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                     echo -e "\n${C_BLUE}📦 Installing vnStat...${C_RESET}"
                     ff_pkg_install vnstat >/dev/null 2>&1 || {
                         echo -e "${C_RED}❌ Failed to install vnStat.${C_RESET}"
                         sleep 1
                         return
                     }
                     systemctl enable vnstat >/dev/null 2>&1
                     systemctl restart vnstat >/dev/null 2>&1
                    local default_iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
                    vnstat --add -i "$default_iface" >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ Installed.${C_RESET}"
                    sleep 1
               else
                    return
               fi
           fi
           echo
           vnstat -i "$iface"
           echo -e "\n${C_DIM}Run 'vnstat -d' or 'vnstat -m' manually for specific views.${C_RESET}"
           press_enter
           ;;
        *) return ;;
    esac
}

torrent_block_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🚫 Torrent Blocking (Anti-Torrent) ---${C_RESET}"

    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "
${C_YELLOW}iptables haipo. Jaribu kuiweka kupitia package manager...${C_RESET}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y iptables
        elif command -v yum >/dev/null 2>&1; then
            yum install -y iptables
        elif command -v zypper >/dev/null 2>&1; then
            zypper --non-interactive install iptables
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm --needed iptables
        else
            echo -e "${C_RED}❌ Sijaweza kutambua package manager. Install iptables manually.${C_RESET}"
            press_enter; return
        fi
    fi
    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "${C_RED}❌ iptables bado haipatikani; hakuna sheria iliyobadilishwa.${C_RESET}"
        press_enter; return
    fi
    local torrent_status="${C_STATUS_I}Disabled${C_RESET}"
    if iptables -w -C FORWARD -j AMOKHAN_TORRENT 2>/dev/null ||
       iptables -w -C OUTPUT -j AMOKHAN_TORRENT 2>/dev/null; then
        torrent_status="${C_STATUS_A}Enabled${C_RESET}"
    fi

    echo -e "
${C_WHITE}Current Status: ${torrent_status}${C_RESET}"
    echo -e "${C_DIM}Huzuia baadhi ya alama za BitTorrent kwenye FORWARD/OUTPUT. Haitoi dhamana ya kuzuia kila torrent.${C_RESET}"
    echo -e "${C_YELLOW}Kumbuka: string matching inaweza kuathiri traffic isiyo torrent ikibeba maneno yanayofanana.${C_RESET}"
    echo -e "
${C_BOLD}Select an action:${C_RESET}
"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s
" "🔒 Enable Torrent Blocking"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s
" "🔓 Disable Torrent Blocking"
    echo -e "
  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -r -p "👉 Enter choice: " b_choice

    case $b_choice in
        1)
            if ! iptables -m string -h >/dev/null 2>&1; then
                echo -e "
${C_RED}❌ iptables string match haipatikani kwenye kernel/userspace hii. Hakuna sheria iliyowekwa.${C_RESET}"
                press_enter; return
            fi
            _flush_torrent_rules
            if ! iptables -w -N AMOKHAN_TORRENT 2>/dev/null; then
                iptables -w -L AMOKHAN_TORRENT >/dev/null 2>&1 || {
                    echo -e "${C_RED}❌ Imeshindikana kuunda firewall chain.${C_RESET}"
                    press_enter; return
                }
            fi
            iptables -w -F AMOKHAN_TORRENT || { echo -e "${C_RED}❌ Imeshindikana kusafisha chain.${C_RESET}"; press_enter; return; }
            local keyword
            for keyword in "BitTorrent protocol" "BitTorrent" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "info_hash" "get_peers" "find_node"; do
                iptables -w -A AMOKHAN_TORRENT -m string --string "$keyword" --algo bm -j DROP || {
                    _flush_torrent_rules
                    echo -e "${C_RED}❌ Sheria haikuweza kuwekwa; nimeondoa chain ya kipengele hiki.${C_RESET}"
                    press_enter; return
                }
            done
            iptables -w -C FORWARD -j AMOKHAN_TORRENT 2>/dev/null || iptables -w -I FORWARD 1 -j AMOKHAN_TORRENT
            iptables -w -C OUTPUT -j AMOKHAN_TORRENT 2>/dev/null || iptables -w -I OUTPUT 1 -j AMOKHAN_TORRENT
            local fw_ok=1
            iptables -w -C FORWARD -j AMOKHAN_TORRENT 2>/dev/null || fw_ok=0
            iptables -w -C OUTPUT -j AMOKHAN_TORRENT 2>/dev/null || fw_ok=0
            if [[ "$fw_ok" -eq 1 ]]; then
                if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save >/dev/null 2>&1 || true
                elif command -v service >/dev/null 2>&1 && command -v iptables-save >/dev/null 2>&1; then
                    mkdir -p /etc/iptables
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                fi
                echo -e "
${C_GREEN}✅ Torrent blocking imewezeshwa.${C_RESET}"
            else
                echo -e "
${C_RED}❌ Firewall rules hazikuthibitishwa; angalia iptables/kernel modules.${C_RESET}"
            fi
            press_enter
            ;;
        2)
            _flush_torrent_rules
            if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save >/dev/null 2>&1 || true; fi
            echo -e "
${C_GREEN}✅ Torrent blocking imezimwa; sheria nyingine za firewall zimeachwa.${C_RESET}"
            press_enter
            ;;
        0) return ;;
        *) return ;;
    esac
}

_flush_torrent_rules() {
    command -v iptables >/dev/null 2>&1 || return 0
    # Remove only this script's jump rules/chain; leave unrelated firewall rules untouched.
    while iptables -w -C FORWARD -j AMOKHAN_TORRENT 2>/dev/null; do
        iptables -w -D FORWARD -j AMOKHAN_TORRENT || break
    done
    while iptables -w -C OUTPUT -j AMOKHAN_TORRENT 2>/dev/null; do
        iptables -w -D OUTPUT -j AMOKHAN_TORRENT || break
    done
    iptables -w -F AMOKHAN_TORRENT 2>/dev/null || true
    iptables -w -X AMOKHAN_TORRENT 2>/dev/null || true
}

ssh_banner_menu() {
    while true; do
        show_banner
        local banner_mode
        local banner_status
        banner_mode=$(get_ssh_banner_mode)
        case "$banner_mode" in
            dynamic) banner_status="${C_STATUS_A}Dynamic${C_RESET}" ;;
            static) banner_status="${C_STATUS_A}Static${C_RESET}" ;;
            *) banner_status="${C_STATUS_I}Disabled${C_RESET}" ;;
        esac

        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}🎨 SSH BANNER MODE: ${banner_status} ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        echo -e "${C_DIM}Static mode uses 'Banner $SSH_BANNER_FILE'. Dynamic mode shows per-user account info.${C_RESET}"
        printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✨ Enable Dynamic Account Banner"
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "📋 Paste or Replace Static Banner"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "👁️ View Current Static Banner"
        printf "     ${C_CHOICE}[ 4]${C_RESET} %-40s\n" "📝 Preview Dynamic Banner"
        printf "     ${C_DANGER}[ 5]${C_RESET} %-40s\n" "🗑️ Disable Dynamic/Static Banners"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                if setup_ssh_login_info; then
                    echo -e "\n${C_GREEN}✅ Dynamic account banner enabled.${C_RESET}"
                    echo -e "${C_DIM}Users will now see their account info banner instead of the static banner.${C_RESET}"
                fi
                press_enter
                ;;
            2) set_ssh_banner_paste ;;
            3) view_ssh_banner ;;
            4) preview_dynamic_ssh_banner ;;
            5) remove_ssh_banner ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1 ;;
        esac
    done
}

auto_reboot_menu() {
    clear; show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Auto-Reboot Management ---${C_RESET}"

    local status="${C_STATUS_I}Disabled${C_RESET}"
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]] && systemctl is-enabled --quiet amokhan-auto-reboot.timer 2>/dev/null; then
        status="${C_STATUS_A}Active (systemd timer)${C_RESET}"
    elif command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -Fq '# amokhan-auto-reboot'; then
        status="${C_STATUS_A}Active (Cron)${C_RESET}"
    fi
    echo -e "\n${C_WHITE}Current Status: ${status}${C_RESET}"
    echo -e "${C_DIM}Hupendelea systemd timer; hutumia cron kama systemd haifanyi kazi.${C_RESET}"
    echo -e "${C_YELLOW}Ratiba hii huanzisha upya VPS kila siku saa 00:00 kwa saa za mfumo.${C_RESET}"
    echo -e "\n${C_BOLD}Select an action:${C_RESET}\n"
    printf "  ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "🕐 Enable Daily Reboot (00:00 midnight)"
    printf "  ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "❌ Disable Auto-Reboot"
    echo -e "\n  ${C_WARN}[ 0]${C_RESET} ↩️ Return"
    echo
    read -r -p "👉 Enter choice: " r_choice

    case $r_choice in
        1)
            if [[ $EUID -ne 0 ]]; then
                echo -e "\n${C_RED}❌ Endesha menu kama root (sudo).${C_RESET}"; press_enter; return
            fi
            if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
                local systemctl_bin
                systemctl_bin=$(command -v systemctl)
                mkdir -p /etc/systemd/system || { echo -e "${C_RED}❌ Imeshindikana kuandika systemd unit files.${C_RESET}"; press_enter; return; }
                cat > /etc/systemd/system/amokhan-auto-reboot.service <<EOF
[Unit]
Description=Amokhan daily VPS reboot

[Service]
Type=oneshot
ExecStart=$systemctl_bin reboot
EOF
                cat > /etc/systemd/system/amokhan-auto-reboot.timer <<'EOF'
[Unit]
Description=Amokhan daily VPS reboot timer

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true
Unit=amokhan-auto-reboot.service

[Install]
WantedBy=timers.target
EOF
                if systemctl daemon-reload && systemctl enable --now amokhan-auto-reboot.timer; then
                    # Remove only cron entries explicitly tagged by this feature; preserve all other jobs.
                    if command -v crontab >/dev/null 2>&1; then
                        (crontab -l 2>/dev/null | grep -Fv '# amokhan-auto-reboot' || true) | crontab - 2>/dev/null || true
                    fi
                    echo -e "\n${C_GREEN}✅ Auto-reboot imewezeshwa kila siku saa 00:00 (systemd timer).${C_RESET}"
                else
                    echo -e "\n${C_RED}❌ systemd timer haikuwezeshwa. Angalia: systemctl status amokhan-auto-reboot.timer${C_RESET}"
                fi
            else
                if ! command -v crontab >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cron
                    elif command -v dnf >/dev/null 2>&1; then dnf install -y cronie
                    elif command -v yum >/dev/null 2>&1; then yum install -y cronie
                    elif command -v zypper >/dev/null 2>&1; then zypper --non-interactive install cronie
                    elif command -v pacman >/dev/null 2>&1; then pacman -S --noconfirm --needed cronie
                    else echo -e "${C_RED}❌ Package manager ya cron haijatambuliwa.${C_RESET}"; press_enter; return
                    fi
                fi
                local reboot_cmd=""
                if command -v reboot >/dev/null 2>&1; then reboot_cmd=$(command -v reboot)
                elif command -v shutdown >/dev/null 2>&1; then reboot_cmd="$(command -v shutdown) -r now"
                fi
                if ! command -v crontab >/dev/null 2>&1 || [[ -z "$reboot_cmd" ]]; then
                    echo -e "\n${C_RED}❌ crontab au amri ya reboot haipatikani; ratiba haijawekwa.${C_RESET}"
                    press_enter; return
                fi
                # Start the available cron daemon where possible.
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable --now cron 2>/dev/null || systemctl enable --now crond 2>/dev/null || true
                elif command -v service >/dev/null 2>&1; then
                    service cron start 2>/dev/null || service crond start 2>/dev/null || true
                fi
                if (crontab -l 2>/dev/null | grep -Fv '# amokhan-auto-reboot' || true; printf '0 0 * * * %s # amokhan-auto-reboot\n' "$reboot_cmd") | crontab -; then
                    echo -e "\n${C_GREEN}✅ Auto-reboot imepangwa kupitia cron saa 00:00.${C_RESET}"
                else
                    echo -e "\n${C_RED}❌ Imeshindikana kuhifadhi cron job.${C_RESET}"
                fi
            fi
            press_enter
            ;;
        2)
            if [[ $EUID -ne 0 ]]; then
                echo -e "\n${C_RED}❌ Endesha menu kama root (sudo).${C_RESET}"; press_enter; return
            fi
            if command -v systemctl >/dev/null 2>&1; then
                systemctl disable --now amokhan-auto-reboot.timer >/dev/null 2>&1 || true
                rm -f /etc/systemd/system/amokhan-auto-reboot.timer /etc/systemd/system/amokhan-auto-reboot.service
                systemctl daemon-reload >/dev/null 2>&1 || true
            fi
            # Delete only our tagged cron line, never unrelated systemctl/reboot jobs.
            if command -v crontab >/dev/null 2>&1; then
                (crontab -l 2>/dev/null | grep -Fv '# amokhan-auto-reboot' || true) | crontab - 2>/dev/null || true
            fi
            echo -e "\n${C_GREEN}✅ Auto-reboot ya Amokhan imezimwa; cron jobs nyingine zimeachwa.${C_RESET}"
            press_enter
            ;;
        0) return ;;
        *) return ;;
    esac
}
press_enter() {
    echo -e "\nPress ${C_YELLOW}[Enter]${C_RESET} to return to the menu..." && read -r || true
}
invalid_option() {
    echo -e "\n${C_RED}❌ Invalid option.${C_RESET}" && sleep 1
}

main_menu() {
    while true; do
        export UNINSTALL_MODE="interactive"
        show_banner
        
        echo
        echo -e "   ${C_TITLE}═══════════════════[ ${C_BOLD}👤 USER MANAGEMENT ${C_RESET}${C_TITLE}]═══════════════════${C_RESET}"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "1" "✨ Create New User" "2" "🗑️  Delete User"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "3" "🔄 Renew User Account" "4" "🔒 Lock User Account"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "5" "🔓 Unlock User Account" "6" "✏️  Edit User Details"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "7" "📋 List Managed Users" "8" "📱 Generate Client Config"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "9" "⏱️  Create Trial Account" "10" "📊 View User Bandwidth"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "11" "👥 Bulk Create Users"
        
        echo
        echo -e "   ${C_TITLE}══════════════[ ${C_BOLD}🛠️ TOOLS ${C_RESET}${C_TITLE}]═══════════════${C_RESET}"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "12" "📈 Traffic Monitor (Lite)" "13" "🚫 Block Torrent (Anti-P2P)"

        echo
        echo -e "   ${C_TITLE}══════════════[ ${C_BOLD}⚙️ SYSTEM SETTINGS ${C_RESET}${C_TITLE}]═══════════════${C_RESET}"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "14" "🌐 Free Domain (deSEC)" "15" "🎨 SSH Banner Config"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "16" "🔄 Auto-Reboot Task" "17" "💾 Backup User Data"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "18" "📥 Restore User Data" "19" "🧹 Cleanup Expired Users"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "20" "🌐 Web Control Panel"
        printf "     ${C_CHOICE}[%2s]${C_RESET} %-28s\n" "21" "📢 Admin Message"

        echo
        echo -e "   ${C_DANGER}═══════════════════[ ${C_BOLD}🔥 DANGER ZONE ${C_RESET}${C_DANGER}]═══════════════════${C_RESET}"
        echo -e "     ${C_DANGER}[99]${C_RESET} Uninstall Script             ${C_WARN}[ 0]${C_RESET} Exit"
        echo
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            exit 0
        fi
        case $choice in
            1) create_user; press_enter ;;
            2) delete_user; press_enter ;;
            3) renew_user; press_enter ;;
            4) lock_user; press_enter ;;
            5) unlock_user; press_enter ;;
            6) edit_user; press_enter ;;
            7) list_users; press_enter ;;
            8) client_config_menu; press_enter ;;
            9) create_trial_account; press_enter ;;
            10) view_user_bandwidth; press_enter ;;
            11) bulk_create_users; press_enter ;;
            
            12) traffic_monitor_menu ;;
            13) torrent_block_menu ;;
            
            14) dns_menu; press_enter ;;
            15) ssh_banner_menu ;;
            16) auto_reboot_menu ;;
            17) backup_user_data; press_enter ;;
            18) restore_user_data; press_enter ;;
            19) cleanup_expired; press_enter ;;
            20) web_panel_menu ;;
            
            21) admin_message_menu ;;
            99) uninstall_script ;;
            0) exit 0 ;;
            *) invalid_option ;;
        esac
    done
}


migrate_legacy_install
if [[ "$1" == "--install-setup" ]]; then
    initial_setup
    exit 0
fi

require_interactive_terminal
adminmsg_bootstrap
sync_runtime_components_if_needed
main_menu
