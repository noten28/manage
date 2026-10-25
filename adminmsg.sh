#!/bin/bash
# amokhanTech admin message service version 2026-10-24.2
#
# Admin Message ni mfumo unaojitegemea (hautegemei Dynamic Banner).
#
# Hali (state) iko kwenye /etc/amokhanTech/admin_msg :
#   global.txt           ujumbe wa wote
#   global_enabled       ikiwepo => ujumbe wa wote unaonekana
#   users/<user>.txt     ujumbe wa mtumiaji mmoja mmoja
#   users/<user>.off     ikiwepo => ujumbe wa huyo mtumiaji umezimwa (maandishi yanabaki)
#
# Kazi ya script hii:
#   1. Inaunda banner ya mwisho ya kila mtumiaji: /etc/amokhanTech/banners/<user>.txt
#        = [Dynamic Banner, kama imewashwa]  (au Static Banner kama hiyo ndiyo inatumika)
#        + [Admin Message, kama ipo na imewashwa]
#      Dynamic Banner inaandikwa na limiter kwenye <user>.dyn - script hii haiiingilii.
#   2. Inaelekeza sshd (Match User ... Banner ...) pale tu Dynamic Banner AU
#      Admin Message inapohitajika.
#
# Matumizi:  amokhanTech-adminmsg.sh [daemon|compose|route]

DB_DIR="/etc/amokhanTech"
DB_FILE="$DB_DIR/users.db"
ADMIN_MSG_DIR="$DB_DIR/admin_msg"
BANNER_DIR="$DB_DIR/banners"
BANNERS_ENABLED="$DB_DIR/banners_enabled"
SSHD_CONF="/etc/ssh/sshd_config.d/amokhanTech.conf"
STATIC_BANNER="/etc/bannerssh"
SCAN_INTERVAL=5

shopt -s nullglob

html_escape() {
    local s="$1"
    s=${s//&/"&amp;"}
    s=${s//</"&lt;"}
    s=${s//>/"&gt;"}
    printf '%s' "$s"
}

valid_user() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

dynamic_enabled() { [[ -f "$BANNERS_ENABLED" ]]; }

static_banner_enabled() {
    [[ -f "$STATIC_BANNER" ]] && grep -q -E "^[[:space:]]*Banner[[:space:]]+$STATIC_BANNER[[:space:]]*$" /etc/ssh/sshd_config 2>/dev/null
}

global_msg_active() {
    [[ -f "$ADMIN_MSG_DIR/global_enabled" && -s "$ADMIN_MSG_DIR/global.txt" ]]
}

# Kweli ikiwa mtumiaji huyu ana ujumbe wake na haujazimwa
user_msg_active() {
    valid_user "$1" || return 1
    [[ -s "$ADMIN_MSG_DIR/users/${1}.txt" && ! -f "$ADMIN_MSG_DIR/users/${1}.off" ]]
}

# Kweli ikiwa kuna ujumbe wowote unaopaswa kuonekana (wa wote au wa mtu yeyote)
admin_active() {
    global_msg_active && return 0
    local f
    for f in "$ADMIN_MSG_DIR"/users/*.txt; do
        [[ -s "$f" && ! -f "${f%.txt}.off" ]] && return 0
    done
    return 1
}

# Hurekebisha HTML ya ujumbe: hufunga tags zote zilizofunguliwa (font, b, i, u...)
# na huondoa tag iliyokatika mwishoni, ili mstari wa chini usiharibike rangi.
html_balance() {
    printf '%s' "$1" | awk '
    BEGIN { n = 0; out = "" }
    {
        s = $0
        for (k = length(s); k > 0; k--) {
            c = substr(s, k, 1)
            if (c == ">") break
            if (c == "<") { s = substr(s, 1, k - 1); break }
        }
        while (length(s) > 0) {
            p = index(s, "<")
            if (p == 0) { out = out s; break }
            out = out substr(s, 1, p - 1)
            s = substr(s, p)
            if (match(s, /^<[^>]*>/) == 0) { out = out "&lt;"; s = substr(s, 2); continue }
            tag = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
            name = tag
            sub(/^<\/?[ \t]*/, "", name); sub(/[^A-Za-z0-9].*$/, "", name); name = tolower(name)
            if (name == "") continue
            closing = (substr(tag, 2, 1) == "/")
            if (name == "br" || name == "hr" || name == "img" || name == "meta") { out = out tag; continue }
            if (!closing) {
                if (substr(tag, length(tag) - 1, 1) == "/") { out = out tag; continue }
                stack[++n] = name; out = out tag; continue
            }
            found = 0
            for (j = n; j >= 1; j--) if (stack[j] == name) { found = j; break }
            if (found == 0) continue
            while (n > found) { out = out "</" stack[n] ">"; n-- }
            out = out tag; n--
        }
    }
    END { while (n > 0) { out = out "</" stack[n] ">"; n-- } printf "%s", out }'
}

render_admin_message() {
    local user="$1" g="" m="" out=""
    if global_msg_active; then
        g=$(tr -d '\r' < "$ADMIN_MSG_DIR/global.txt"); g=${g//$'\n'/<br>}
    fi
    if user_msg_active "$user"; then
        m=$(tr -d '\r' < "$ADMIN_MSG_DIR/users/${user}.txt"); m=${m//$'\n'/<br>}
    fi
    [[ -z "$g" && -z "$m" ]] && return 0

    # Ujumbe unaandikwa kama HTML (haubadilishwi kuwa maandishi). Rangi ya msingi ni nyekundu.
    # Ondoa backslash kabla ya nukuu (\" -> ") ili tags zisionekane nje.
    g=${g//\\\"/\"}; g=${g//\\\'/\'}
    m=${m//\\\"/\"}; m=${m//\\\'/\'}
    g=$(html_balance "$g"); m=$(html_balance "$m")

    out="<center>"
    out+="<b><font color=\"yellow\">📢 ADMIN MESSAGE 📢</font></b><br>"
    out+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"
    if [[ -n "$g" ]]; then
        out+="${g}<br>"
    fi

    if [[ -n "$m" ]]; then
        out+="${m}<br>"
    fi
    out+="<font color=\"blue\">▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬</font><br>"
    out+="</center>"
    printf '%s' "$out"
}

write_if_changed() {
    local file="$1" content="$2" tmp="$1.tmp"
    printf '%s' "$content" > "$tmp"
    if ! cmp -s "$tmp" "$file" 2>/dev/null; then
        mv "$tmp" "$file"
        chmod 644 "$file" 2>/dev/null
    else
        rm -f "$tmp"
    fi
}

compose_user() {
    local user="$1" final="" part="" msg=""

    if dynamic_enabled; then
        if [[ -s "$BANNER_DIR/${user}.dyn" ]]; then
            final+="$(cat "$BANNER_DIR/${user}.dyn")"
        fi
    elif static_banner_enabled; then
        final+="$(cat "$STATIC_BANNER")"
    fi

    msg=$(render_admin_message "$user")
    [[ -n "$msg" ]] && final+="$msg"

    if [[ -n "$final" ]]; then
        write_if_changed "$BANNER_DIR/${user}.txt" "$final"
    else
        rm -f "$BANNER_DIR/${user}.txt"
    fi
}

compose_all() {
    [[ -f "$DB_FILE" ]] || return 0
    if ! dynamic_enabled && ! admin_active; then
        # Hakuna kinachohitajika: ondoa banner zilizojengwa
        rm -f "$BANNER_DIR"/*.txt "$BANNER_DIR"/*.dyn 2>/dev/null
        return 0
    fi
    mkdir -p "$BANNER_DIR"
    local u
    while IFS=: read -r u _rest; do
        [[ -z "$u" || "$u" == \#* ]] && continue
        valid_user "$u" || continue
        compose_user "$u"
    done < "$DB_FILE"
}

reload_sshd() {
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
}

route_once() {
    local tmp="/tmp/amokhanTech_adminmsg_route.conf" u
    if ! dynamic_enabled && ! admin_active; then
        if [[ -f "$SSHD_CONF" ]]; then
            rm -f "$SSHD_CONF"
            reload_sshd
        fi
        return 0
    fi
    [[ -f "$DB_FILE" ]] || return 0

    echo "# amokhanTech - Dynamic per-user SSH banners" > "$tmp"
    while IFS=: read -r u _rest; do
        [[ -z "$u" || "$u" == \#* ]] && continue
        valid_user "$u" || continue
        echo "Match User $u" >> "$tmp"
        echo "    Banner $BANNER_DIR/${u}.txt" >> "$tmp"
    done < "$DB_FILE"

    if ! cmp -s "$tmp" "$SSHD_CONF" 2>/dev/null; then
        mv "$tmp" "$SSHD_CONF"
        if ! grep -q "^Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
            echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
        fi
        reload_sshd
    else
        rm -f "$tmp"
    fi
}

case "${1:-daemon}" in
    route)   route_once ;;
    compose) compose_all ;;
    daemon)
        while true; do
            compose_all
            route_once
            sleep "$SCAN_INTERVAL"
        done
        ;;
    *)
        echo "Usage: $0 [daemon|compose|route]" >&2
        exit 1
        ;;
esac
