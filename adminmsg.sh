#!/bin/bash
# Amokhan Tech - ADMIN MESSAGE module version 2026-10-25.1
#
# FAILI HII NI YA ADMIN MESSAGE PEKE YAKE. Haitegemei Dynamic Banner.
#   * Inaweza ku-sourced na menu (menu functions)  ->  source adminmsg.sh
#   * Inaweza kuendeshwa kama huduma (daemon)      ->  adminmsg.sh --daemon
#
# Data (zote ni zake peke yake):
#   /etc/AmokhanTech/admin_msg/enabled          -> swichi kuu ya Admin Message (ON/OFF)
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
AM_MAXLEN=1000
AM_INTERVAL=5
AM_LINE_CHARS='▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬'
AM_HEADING_COLOR="yellow"

# ---------------------------------------------------------------------------
# Hali na uhifadhi
# ---------------------------------------------------------------------------
is_admin_message_system_enabled() { [[ -f "$AM_DIR/enabled" ]]; }
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
    local master=false dyn=false g="" static="" user frag umsg content f
    local -A valid=()

    [[ -f "$AM_DIR/enabled" ]] && master=true
    [[ -f "$AM_ROOT/banners_enabled" ]] && dyn=true

    shopt -s nullglob
    if ! $master; then
        # Admin Message imezimwa: ondoa vipande vyake tu. Dynamic Banner haiguswi.
        for f in "$AM_RENDER_DIR/"*.html; do rm -f "$f"; done
        shopt -u nullglob
        return 0
    fi
    shopt -u nullglob

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

_admin_msg_master_note() {
    if ! is_admin_message_system_enabled; then
        echo -e "${C_YELLOW}⚠️ Admin Message kuu ni OFF, kwa hiyo hakuna anayeona bado. Iwashe kwenye menu ya Admin Message [1].${C_RESET}"
    else
        echo -e "${C_DIM}Banner inasasishwa ndani ya sekunde chache (user anaiona anapoconnect tena).${C_RESET}"
    fi
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
                    _admin_msg_master_note
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
                    _admin_msg_master_note
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
    local choice new sys_status g_status gmsg
    while true; do
        clear; show_banner
        if is_admin_message_system_enabled; then
            sys_status="${C_STATUS_A}ON${C_RESET}"
        else
            sys_status="${C_STATUS_I}OFF${C_RESET}"
        fi
        if is_global_admin_message_enabled; then
            g_status="${C_STATUS_A}ENABLED (all users)${C_RESET}"
        else
            g_status="${C_STATUS_I}DISABLED${C_RESET}"
        fi
        gmsg=$(get_global_admin_message)
        echo -e "\n   ${C_TITLE}═════════════════[ ${C_BOLD}📢 ADMIN MESSAGE: ${sys_status} ${C_RESET}${C_TITLE}]═════════════════${C_RESET}"
        echo -e "   ${C_DIM}Inafanya kazi yenyewe. Haitegemei Dynamic Banner.${C_RESET}"
        echo -e "   Global message: $g_status"
        if [[ -n "$gmsg" ]]; then
            echo -e "   Text:           $gmsg"
        else
            echo -e "   Text:           ${C_DIM}(not set)${C_RESET}"
        fi
        echo -e "   Users with their own message: ${C_YELLOW}$(count_user_admin_messages)${C_RESET}\n"
        if is_admin_message_system_enabled; then
            printf "     ${C_DANGER}[ 1]${C_RESET} %-40s\n" "⛔ Turn Admin Message OFF (hide all)"
        else
            printf "     ${C_CHOICE}[ 1]${C_RESET} %-40s\n" "✅ Turn Admin Message ON"
        fi
        printf "     ${C_CHOICE}[ 2]${C_RESET} %-40s\n" "✏️ Set / Change Global Message"
        printf "     ${C_CHOICE}[ 3]${C_RESET} %-40s\n" "📢 Enable Global Message (all users)"
        printf "     ${C_DANGER}[ 4]${C_RESET} %-40s\n" "🔕 Disable Global Message"
        printf "     ${C_DANGER}[ 5]${C_RESET} %-40s\n" "🧹 Delete Global Message"
        printf "     ${C_CHOICE}[ 6]${C_RESET} %-40s\n" "📋 List User Messages"
        printf "     ${C_CHOICE}[ 7]${C_RESET} %-40s\n" "💬 User Admin Message (one user)"
        echo -e "   ${C_DIM}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${C_RESET}"
        echo -e "     ${C_WARN}[ 0]${C_RESET} ↩️ Return\n"
        if ! read -r -p "$(echo -e ${C_PROMPT}"👉 Select an option: "${C_RESET})" choice; then
            echo
            return
        fi
        case $choice in
            1)
                mkdir -p "$AM_DIR"
                if is_admin_message_system_enabled; then
                    rm -f "$AM_DIR/enabled"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Admin Message sasa ni OFF. Hakuna anayeiona (ujumbe umehifadhiwa).${C_RESET}"
                else
                    touch "$AM_DIR/enabled"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Admin Message sasa ni ON.${C_RESET}"
                    echo -e "${C_DIM}Banner zinasasishwa ndani ya sekunde chache.${C_RESET}"
                fi
                press_enter
                ;;
            2)
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
                    is_global_admin_message_enabled || echo -e "${C_YELLOW}ℹ️ Global message imezimwa. Chagua [3] iwaonyeshe watumiaji wote.${C_RESET}"
                fi
                press_enter
                ;;
            3)
                if [[ -z "$(get_global_admin_message)" ]]; then
                    echo -e "\n${C_RED}❌ Weka Global Admin Message kwanza (option 2).${C_RESET}"
                else
                    mkdir -p "$AM_DIR"
                    touch "$AM_DIR/global_enabled"
                    admin_message_apply
                    echo -e "\n${C_GREEN}✅ Global message imewashwa kwa watumiaji wote.${C_RESET}"
                    is_admin_message_system_enabled || echo -e "${C_YELLOW}⚠️ Admin Message ni OFF, kwa hiyo haionekani bado. Chagua [1] kuiwasha.${C_RESET}"
                fi
                press_enter
                ;;
            4)
                rm -f "$AM_DIR/global_enabled"
                admin_message_apply
                echo -e "\n${C_GREEN}✅ Global message imezimwa. Ujumbe wa user mmoja mmoja unaendelea kufanya kazi.${C_RESET}"
                press_enter
                ;;
            5)
                rm -f "$AM_DIR/global.txt" "$AM_DIR/global_enabled"
                admin_message_apply
                echo -e "\n${C_GREEN}✅ Global message imefutwa.${C_RESET}"
                press_enter
                ;;
            6) list_user_admin_messages; press_enter ;;
            7) user_admin_message_menu ;;
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
