#!/bin/sh

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
    LINK="$(readlink "$SCRIPT_PATH")"
    case "$LINK" in
        /*) SCRIPT_PATH="$LINK" ;;
        *)  SCRIPT_PATH="$(dirname "$SCRIPT_PATH")/$LINK" ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
unset SCRIPT_PATH LINK

if [ -t 1 ]; then
    C_GREEN='\033[0;32m'
    C_RED='\033[0;31m'
    C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_GREEN='' C_RED='' C_YELLOW='' C_CYAN='' C_BOLD='' C_RESET=''
fi

print_ok()   { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$1"; }
print_fail() { printf "${C_RED}[X]${C_RESET}  %s\n" "$1"; }
print_warn() { printf "${C_YELLOW}[?]${C_RESET} %s\n" "$1"; }
print_info() { printf "${C_CYAN}::${C_RESET}  %s\n" "$1"; }

LANG_CHOICE="en"
LANG_FILE="$SCRIPT_DIR/.lang"

load_language() {
    if [ -f "$LANG_FILE" ]; then
        case "$(cat "$LANG_FILE" 2>/dev/null)" in
            ru) LANG_CHOICE="ru" ;;
            en) LANG_CHOICE="en" ;;
        esac
    fi
}

save_language() {
    printf '%s\n' "$LANG_CHOICE" > "$LANG_FILE" 2>/dev/null || true
}

pick_language() {
    [ -f "$LANG_FILE" ] && return 0
    clear
    printf "\n  ${C_BOLD}Выберите язык | Choose language${C_RESET}\n\n"
    printf "     1. English\n"
    printf "     2. Русский\n\n"
    printf "  > "
    read lang_choice </dev/tty
    case "$lang_choice" in
        2) LANG_CHOICE="ru" ;;
        *) LANG_CHOICE="en" ;;
    esac
    save_language
}

load_locale() {
    local f="$SCRIPT_DIR/locale/${LANG_CHOICE}.sh"
    if [ -f "$f" ]; then
        . "$f"
    elif [ -f "$SCRIPT_DIR/locale/en.sh" ]; then
        . "$SCRIPT_DIR/locale/en.sh"
    fi
}

t() {
    eval "printf '%s' \"\${T_$1:-$1}\""
}

pause_prompt() {
    printf "\n%s" "$(t press_enter)"; read dummy </dev/tty
}

detect_zapret_base() {
    if [ -n "$ZAPRET_BASE" ] && [ -d "$ZAPRET_BASE" ]; then
        return 0
    fi
    for d in /opt/zapret2 /usr/lib/zapret2 /etc/zapret2; do
        if [ -d "$d" ] && [ -f "$d/config" -o -f "$d/config.default" ]; then
            ZAPRET_BASE="$d"
            return 0
        fi
    done
    ZAPRET_BASE=""
    return 1
}

detect_custom_d() {
    CUSTOM_D=""
    if [ -z "$ZAPRET_BASE" ]; then return 1; fi
    if [ -d "$ZAPRET_BASE/init.d/openwrt/custom.d" ]; then
        CUSTOM_D="$ZAPRET_BASE/init.d/openwrt/custom.d"
    elif [ -d "$ZAPRET_BASE/init.d/sysv/custom.d" ]; then
        CUSTOM_D="$ZAPRET_BASE/init.d/sysv/custom.d"
    fi
    [ -n "$CUSTOM_D" ]
}

detect_init_system() {
    INIT_TYPE=""
    INIT_SCRIPT=""
    if [ -x "/etc/init.d/zapret2" ]; then
        INIT_TYPE="initd"
        INIT_SCRIPT="/etc/init.d/zapret2"
    elif [ -n "$ZAPRET_BASE" ] && [ -x "$ZAPRET_BASE/init.d/openwrt/zapret2" ]; then
        INIT_TYPE="initd"
        INIT_SCRIPT="$ZAPRET_BASE/init.d/openwrt/zapret2"
    elif [ -n "$ZAPRET_BASE" ] && [ -f "$ZAPRET_BASE/init.d/openwrt/zapret2" ]; then
        INIT_TYPE="initd"
        INIT_SCRIPT="$ZAPRET_BASE/init.d/openwrt/zapret2"
        chmod +x "$INIT_SCRIPT"
    elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files zapret2.service >/dev/null 2>&1; then
        INIT_TYPE="systemd"
    elif [ -n "$ZAPRET_BASE" ] && [ -x "$ZAPRET_BASE/init.d/sysv/zapret2" ]; then
        INIT_TYPE="sysv"
        INIT_SCRIPT="$ZAPRET_BASE/init.d/sysv/zapret2"
    fi
}

fetch_url() {
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$2" "$1"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        return 1
    fi
}

STRATEGY_FILE="50-zapret2-bypass"

PERSIST_DIR="/usr/lib/zapret2-openwrt"
SYMLINK_PATH="/usr/bin/zapret2"

register_command() {
    case "$SCRIPT_DIR" in
        /tmp/zapret2-openwrt|/tmp/zapret2-openwrt/*) ;;
        *) return 0 ;;
    esac

    print_info "$(t cmd_registering)"

    local stage
    stage=$(mktemp -d "${PERSIST_DIR}.XXXXXX") || { print_warn "$(t cmd_register_fail)"; return 1; }
    if ! mkdir "$stage/new" ||
        ! cp -r "$SCRIPT_DIR"/. "$stage/new/" ||
        ! chmod +x "$stage/new/service.sh"; then
        rm -rf "$stage"
        print_warn "$(t cmd_register_fail)"
        return 1
    fi
    if [ -e "$PERSIST_DIR" ] && ! mv "$PERSIST_DIR" "$stage/old"; then
        rm -rf "$stage"
        print_warn "$(t cmd_register_fail)"
        return 1
    fi
    if ! mv "$stage/new" "$PERSIST_DIR"; then
        [ ! -d "$stage/old" ] || mv "$stage/old" "$PERSIST_DIR"
        print_warn "$(t cmd_register_fail)"
        print_warn "$(printf "$(t cmd_backup_fmt)" "$stage")"
        return 1
    fi
    if { [ -e "$SYMLINK_PATH" ] && [ ! -L "$SYMLINK_PATH" ]; } ||
        ! ln -sf "$PERSIST_DIR/service.sh" "$SYMLINK_PATH"; then
        print_warn "$(t cmd_register_fail)"
        print_warn "$(printf "$(t cmd_backup_fmt)" "$stage")"
        return 1
    fi
    rm -rf "$stage"

    print_ok "$(t cmd_registered)"
    return 0
}

ZAPRET_VERSION="v1.0.4"
ZAPRET_TARBALL_URL="https://github.com/bol-van/zapret2/releases/download/${ZAPRET_VERSION}/zapret2-${ZAPRET_VERSION}-openwrt-embedded.tar.gz"

install_zapret_base() {
    local tmpdir="/tmp/zapret-base-install.$$"
    local archive="$tmpdir/zapret.tar.gz"

    print_info "$(printf "$(t base_downloading)" "$ZAPRET_VERSION")"
    rm -rf "$tmpdir"; mkdir -p "$tmpdir"

    if ! fetch_url "$ZAPRET_TARBALL_URL" "$archive"; then
        print_fail "$(t base_download_fail)"
        rm -rf "$tmpdir"
        return 1
    fi

    print_info "$(t extracting)"
    if ! tar -xzf "$archive" -C "$tmpdir"; then
        print_fail "$(t extract_fail)"
        rm -rf "$tmpdir"
        return 1
    fi

    local extracted_dir
    extracted_dir=$(find "$tmpdir" -maxdepth 1 -type d ! -path "$tmpdir" | head -1)
    if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
        print_fail "$(t extracted_dir_missing)"
        rm -rf "$tmpdir"
        return 1
    fi

    local installer="$extracted_dir/install_easy.sh"
    if [ ! -f "$installer" ]; then
        print_fail "$(t installer_missing)"
        rm -rf "$tmpdir"
        return 1
    fi
    [ -x "$installer" ] || chmod +x "$installer"

    printf "\n"
    print_info "$(t running_installer)"
    printf "\n"
    if ! "$installer" </dev/tty; then
        print_fail "$(t installer_failed)"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    print_ok "$(t base_installed)"

    detect_zapret_base
    detect_custom_d
    detect_init_system

    if [ -n "$INIT_TYPE" ]; then
        print_info "$(t stopping_pre_setup)"
        zapret_cmd stop || { print_fail "$(t stop_failed)"; return 1; }
    fi

    return 0
}

zapret_cmd() {
    case "$INIT_TYPE" in
        initd|sysv) "$INIT_SCRIPT" "$1" ;;
        systemd)    systemctl "$1" zapret2 ;;
        *)
            print_fail "$(t init_script_missing)"
            print_info "$(printf "$(t init_searched_fmt)" "$ZAPRET_BASE")"
            return 1
            ;;
    esac
}

get_active_strategy() {
    ACTIVE_STRATEGY="none"
    ACTIVE_FILE=""
    [ -n "$CUSTOM_D" ] && [ -f "$CUSTOM_D/$STRATEGY_FILE" ] || return 0
    ACTIVE_FILE="$CUSTOM_D/$STRATEGY_FILE"
    ACTIVE_STRATEGY=$(sed -n 's/^Z2B_STRATEGY=//p' "$ACTIVE_FILE" | head -1)
    [ -n "$ACTIVE_STRATEGY" ] ||
        ACTIVE_STRATEGY=$(sed -n 's/^# Strategy: *//p' "$ACTIVE_FILE" | head -1)
    case "$ACTIVE_STRATEGY" in
        flat*|measured-2026-08-22) ACTIVE_STRATEGY=flat ;;
        sky) ;;
        *) ACTIVE_STRATEGY=unknown ;;
    esac
}

nfqws_describe() {
    local pids
    pids=$(pidof nfqws2 2>/dev/null)
    [ -z "$pids" ] && { echo "none"; return; }

    local n_pids=0 n_parents=0 parent_pid=""
    for pid in $pids; do
        n_pids=$((n_pids + 1))
        local ppid
        ppid=$(awk '/^PPid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null)
        local is_child=0
        for other in $pids; do
            [ "$other" = "$ppid" ] && { is_child=1; break; }
        done
        if [ "$is_child" = "0" ]; then
            n_parents=$((n_parents + 1))
            parent_pid="$pid"
        fi
    done

    if [ "$n_pids" = "1" ]; then
        echo "single $pids"
    elif [ "$n_parents" = "1" ] && [ "$n_pids" = "2" ]; then
        local worker=""
        for pid in $pids; do
            [ "$pid" = "$parent_pid" ] || worker="$pid"
        done
        echo "pair $parent_pid $worker"
    elif [ "$n_parents" = "1" ]; then
        local n_workers=$((n_pids - 1))
        echo "complex $parent_pid $n_workers"
    else
        echo "multi $n_parents"
    fi
}

select_strategy() {
    get_active_strategy
    SELECTED_STRATEGY="$ACTIVE_STRATEGY"
    case "$SELECTED_STRATEGY" in flat|sky) ;; *) SELECTED_STRATEGY=flat ;; esac
    print_info "$(t current_active_fmt)$ACTIVE_STRATEGY"
    print_info "$(t strategy_limits)"
    print_info "$(t override_precedence)"
    printf "\n  1. flat\n  2. sky\n  0. %s\n" "$(t cancel)"
    while true; do
        printf "\n  $(t select_strategy_fmt)" "$SELECTED_STRATEGY"
        read choice </dev/tty || return 1
        case "$choice" in
            '') return 0 ;;
            1|flat) SELECTED_STRATEGY=flat; return 0 ;;
            2|sky) SELECTED_STRATEGY=sky; return 0 ;;
            0|q|Q) print_info "$(t cancelled)"; return 1 ;;
            *) print_warn "$(t invalid_choice)" ;;
        esac
    done
}

# Stage only missing user assets; existing lists and fake packets are never replaced.
stage_asset() {
    local rel="$1" src="$2"
    [ -f "$ZAPRET_BASE/$rel" ] && [ -r "$ZAPRET_BASE/$rel" ] && return 0
    [ ! -e "$ZAPRET_BASE/$rel" ] && [ ! -L "$ZAPRET_BASE/$rel" ] || return 1
    [ -r "$src" ] || { print_fail "$(printf "$(t file_not_found_fmt)" "$src")"; return 1; }
    mkdir -p "$stage/new/$(dirname "$rel")" &&
        cp "$src" "$stage/new/$rel" || return 1
    assets="$assets $rel"
}

# Match nfqws2's Lua loader: prefer the requested file, then its gzip variant.
resolve_asset_file() {
    case "$1" in
        lua/*.lua)
            if [ ! -r "$ZAPRET_BASE/$1" ] && [ -r "$ZAPRET_BASE/$1.gz" ]; then
                printf '%s.gz\n' "$1"
                return
            fi
            ;;
    esac
    printf '%s\n' "$1"
}

strip_discord_dns_config() {
    sed '/^# BEGIN zapret2-openwrt Discord DNS$/,/^# END zapret2-openwrt Discord DNS$/d' "$1"
}

prepare_strategy() {
    local f rel base_escaped
    mkdir -p "$stage/new" "$stage/old" || return 1
    sed -e "s/^# Strategy: flat$/# Strategy: $SELECTED_STRATEGY/" \
        -e "s/^Z2B_STRATEGY=flat$/Z2B_STRATEGY=$SELECTED_STRATEGY/" \
        "$SCRIPT_DIR/custom.d/$STRATEGY_FILE" > "$stage/new/entrypoint" || return 1
    grep -qx "# Strategy: $SELECTED_STRATEGY" "$stage/new/entrypoint" &&
        grep -qx "Z2B_STRATEGY=$SELECTED_STRATEGY" "$stage/new/entrypoint" || return 1
    chmod 644 "$stage/new/entrypoint" || return 1
    [ ! -e "$CUSTOM_D/$STRATEGY_FILE" ] ||
        cp -p "$CUSTOM_D/$STRATEGY_FILE" "$stage/old/entrypoint" || return 1
    stage_asset ipset/list-exclude.txt "$SCRIPT_DIR/lists/list-exclude.txt" || return 1
    stage_asset files/fake/quic_initial_steamcommunity_com.bin \
        "$SCRIPT_DIR/files/fake/quic_initial_steamcommunity_com.bin" || return 1
    for f in lua/zapret-lib.lua lua/zapret-antidpi.lua lua/zapret-auto.lua files/fake/quic_initial_www_google_com.bin; do
        f=$(resolve_asset_file "$f")
        [ -s "$ZAPRET_BASE/$f" ] && [ -r "$ZAPRET_BASE/$f" ] ||
            { print_fail "$(printf "$(t file_not_found_fmt)" "$ZAPRET_BASE/$f")"; return 1; }
    done
    if [ "$SELECTED_STRATEGY" = sky ]; then
        for f in youtube.txt discord.txt proton.txt anime.txt shared.txt; do
            stage_asset "strategies/sky/$f" "$SCRIPT_DIR/strategies/sky/$f" || return 1
        done
        rel=strategies/sky/strategy.args
        mkdir -p "$stage/new/strategies/sky" "$stage/old/strategies/sky" || return 1
        base_escaped=$(printf '%s\n' "$ZAPRET_BASE" | sed 's/[\\&|]/\\&/g')
        sed -e '/^--qnum=/d' -e '/^--fwmark=/d' -e '/^--lua-init=/d' \
            -e "s|/opt/zapret2/|$base_escaped/|g" \
            -e "s|^--hostlist=/sky/|--hostlist=$base_escaped/strategies/sky/|" \
            "$SCRIPT_DIR/strategies/sky/strategy.args" |
            sed "/^--filter-l7=\\(tls\\|quic\\)$/a\\
--hostlist-exclude=$base_escaped/ipset/list-exclude.txt
" > "$stage/new/$rel" || return 1
        [ -s "$stage/new/$rel" ] &&
            grep -q '^--filter-l7=tls$' "$stage/new/$rel" &&
            grep -q '^--filter-l7=quic$' "$stage/new/$rel" || return 1
        [ ! -e "$ZAPRET_BASE/$rel" ] ||
            cp -p "$ZAPRET_BASE/$rel" "$stage/old/$rel" || return 1
        assets="$assets $rel"
        rel=strategies/sky/discord-dns.sh
        cp "$SCRIPT_DIR/$rel" "$stage/new/$rel" || return 1
        [ ! -e "$ZAPRET_BASE/$rel" ] ||
            cp -p "$ZAPRET_BASE/$rel" "$stage/old/$rel" || return 1
        assets="$assets $rel"
    else
        for f in list-general.txt list-hetzner.txt zapret-hosts-user-ipban.txt; do
            stage_asset "ipset/$f" "$SCRIPT_DIR/lists/$f" || return 1
        done
        [ -s "$ZAPRET_BASE/files/fake/tls_clienthello_iana_org_bigsize.bin" ] ||
            { print_fail "$(printf "$(t file_not_found_fmt)" "$ZAPRET_BASE/files/fake/tls_clienthello_iana_org_bigsize.bin")"; return 1; }
    fi
    # The native firewall hooks cover boot, restart and procd stop as well as
    # manager actions. Stage config with the strategy so rollback restores both.
    cp -p "$ZAPRET_BASE/config" "$stage/old/config" &&
        cp -p "$ZAPRET_BASE/config" "$stage/new/config" &&
        strip_discord_dns_config "$stage/old/config" > "$stage/new/config" || return 1
    if [ "$SELECTED_STRATEGY" = sky ]; then
        cat >> "$stage/new/config" <<'DNS_CONFIG'

# BEGIN zapret2-openwrt Discord DNS
. "$ZAPRET_BASE/strategies/sky/discord-dns.sh"
# END zapret2-openwrt Discord DNS
DNS_CONFIG
    fi
    assets="$assets config"
}

restore_strategy() {
    local rel failed=0
    for rel in $assets; do
        if [ -f "$stage/old/$rel" ]; then
            cp -p "$stage/old/$rel" "$ZAPRET_BASE/$rel" || failed=1
        else
            rm -f "$ZAPRET_BASE/$rel" || failed=1
        fi
    done
    if [ -f "$stage/old/entrypoint" ]; then
        cp -p "$stage/old/entrypoint" "$CUSTOM_D/$STRATEGY_FILE" || failed=1
    else
        rm -f "$CUSTOM_D/$STRATEGY_FILE" || failed=1
    fi
    [ "$failed" = 0 ]
}

deploy_strategy() {
    local stage assets="" rel failed=0 was_running=0 start_now=0
    [ -n "$ZAPRET_BASE" ] && [ -n "$CUSTOM_D" ] && [ -n "$INIT_TYPE" ] ||
        { print_fail "$(t install_prerequisites)"; return 1; }
    # nfqws options are whitespace-delimited by upstream do_nfqws.
    case "$ZAPRET_BASE" in *[[:space:]]*) print_fail "$(t base_path_invalid)"; return 1 ;; esac
    stage=$(mktemp -d "$ZAPRET_BASE/.z2b-install.XXXXXX") || return 1
    if ! prepare_strategy; then
        print_fail "$(t prepare_failed)"
        rm -rf "$stage"
        return 1
    fi
    printf "\n  %s" "$(t start_now_q)"
    read yn </dev/tty || { rm -rf "$stage"; return 1; }
    case "$yn" in y|Y|yes|Yes|YES|'') start_now=1 ;; esac
    pidof nfqws2 >/dev/null 2>&1 && was_running=1
    print_info "$(t stopping)"
    # Stop while the old entrypoint and options still describe the old firewall.
    if ! zapret_cmd stop; then
        print_fail "$(t stop_failed)"
        rm -rf "$stage"
        return 1
    fi
    for rel in $assets; do
        mkdir -p "$ZAPRET_BASE/$(dirname "$rel")" &&
            mv -f "$stage/new/$rel" "$ZAPRET_BASE/$rel" || { failed=1; break; }
    done
    if [ "$failed" = 0 ]; then
        mv -f "$stage/new/entrypoint" "$CUSTOM_D/$STRATEGY_FILE" || failed=1
    fi
    if [ "$failed" = 0 ] && [ "$start_now" = 1 ]; then
        print_info "$(t starting)"
        if ! zapret_cmd start; then
            print_fail "$(t start_failed)"
            if ! zapret_cmd stop; then
                print_fail "$(printf "$(t recovery_required_fmt)" "$stage")"
                return 1
            fi
            failed=1
        fi
    fi
    if [ "$failed" = 1 ]; then
        if restore_strategy; then
            print_warn "$(t install_restored)"
            if [ "$was_running" = 1 ] && ! zapret_cmd start; then
                print_fail "$(t start_failed)"
                print_fail "$(printf "$(t recovery_required_fmt)" "$stage")"
                return 1
            fi
            rm -rf "$stage"
        else
            print_fail "$(printf "$(t recovery_required_fmt)" "$stage")"
        fi
        return 1
    fi
    rm -rf "$stage"
    print_ok "$(printf "$(t installed_to_fmt)" "$SELECTED_STRATEGY" "$CUSTOM_D/$STRATEGY_FILE")"
    [ "$start_now" = 1 ] || print_info "$(t installed_stopped)"
}

action_install_strategy() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_install)"
    if select_strategy; then
        deploy_strategy
    fi
    pause_prompt
}

action_show_active() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_active)"

    get_active_strategy

    if [ "$ACTIVE_STRATEGY" = "none" ]; then
        print_warn "$(t no_strategy_installed)"
        if [ -n "$CUSTOM_D" ]; then
            print_info "$(printf "$(t customd_dir_fmt)" "$CUSTOM_D")"
        fi
    else
        print_ok "$(printf "$(t strategy_fmt)" "$ACTIVE_STRATEGY")"
        print_info "$(printf "$(t file_fmt)" "$ACTIVE_FILE")"
        printf "\n  ${C_BOLD}%s${C_RESET}\n" "$(t nfqws_options)"
        if [ "$ACTIVE_STRATEGY" = sky ]; then
            if [ -r "$ZAPRET_BASE/strategies/sky/strategy.args" ]; then
                sed 's/^/    /' "$ZAPRET_BASE/strategies/sky/strategy.args"
            else
                print_fail "$(printf "$(t file_not_found_fmt)" "$ZAPRET_BASE/strategies/sky/strategy.args")"
            fi
        else
            sed -n '/^[[:space:]]*NFQWS2_Z2B_OPT="${NFQWS2_Z2B_OPT:-$/,/}"/p' "$ACTIVE_FILE" | sed 's/^/    /'
        fi
        print_info "$(t override_precedence)"
        if [ -r "$ZAPRET_BASE/config" ]; then
            sed -n '/^[[:space:]]*NFQWS2_Z2B_/p' "$ZAPRET_BASE/config"
        fi
        print_info "$(t strategy_limits)"
    fi

    pause_prompt
}

action_start() {
    clear
    print_info "$(t starting)"
    zapret_cmd start
    pause_prompt
}

action_stop() {
    clear
    print_info "$(t stopping)"
    zapret_cmd stop
    pause_prompt
}

action_restart() {
    clear
    print_info "$(t restarting)"
    zapret_cmd restart
    pause_prompt
}

action_status() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_status)"

    set -- $(nfqws_describe)
    case "$1" in
        none)
            print_fail "$(t nfqws_not_running)"
            ;;
        single)
            print_ok "$(printf "$(t nfqws_running_one_pid_fmt)" "$2")"
            ;;
        pair)
            print_ok "$(printf "$(t nfqws_running_pair_fmt)" "$2" "$3")"
            ;;
        complex)
            print_ok "$(printf "$(t nfqws_running_complex_fmt)" "$2" "$3")"
            ;;
        multi)
            print_ok "$(printf "$(t nfqws_running_multi_fmt)" "$2")"
            ;;
    esac

    get_active_strategy
    if [ "$ACTIVE_STRATEGY" = "none" ]; then
        print_warn "$(t no_strategy_installed)"
    else
        print_ok "$(printf "$(t active_strategy_fmt)" "$ACTIVE_STRATEGY")"
    fi

    if [ -n "$INIT_TYPE" ]; then
        print_info "$(printf "$(t init_system_fmt)" "$INIT_TYPE")"
    fi

    printf "\n"
    case "$INIT_TYPE" in
        initd|sysv)
            "$INIT_SCRIPT" status 2>/dev/null || true
            ;;
        systemd)
            systemctl status zapret2 --no-pager -l 2>/dev/null | head -10
            ;;
    esac

    pause_prompt
}

strategy_lists() {
    if [ "$ACTIVE_STRATEGY" = sky ]; then
        printf '%s\n' strategies/sky/youtube.txt strategies/sky/discord.txt \
            strategies/sky/proton.txt strategies/sky/anime.txt strategies/sky/shared.txt ipset/list-exclude.txt
    else
        printf '%s\n' ipset/list-general.txt ipset/list-hetzner.txt ipset/list-exclude.txt
    fi
}

action_edit_lists() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_lists)"

    if [ -z "$ZAPRET_BASE" ]; then
        print_fail "$(t zb_not_detected)"
        pause_prompt; return
    fi

    get_active_strategy
    local list_files="$(strategy_lists)" f n=0 count
    local editor=""
    if [ -n "$EDITOR" ]; then
        editor="$EDITOR"
    elif command -v nano >/dev/null 2>&1; then
        editor="nano"
    elif command -v vi >/dev/null 2>&1; then
        editor="vi"
    else
        print_fail "$(t no_editor)"
        pause_prompt; return
    fi

    print_info "$(printf "$(t active_strategy_fmt)" "$ACTIVE_STRATEGY")"
    for f in $list_files; do
        n=$((n + 1))
        count=0
        [ ! -f "$ZAPRET_BASE/$f" ] || count=$(wc -l < "$ZAPRET_BASE/$f")
        printf "     %s. %s (%s)\n" "$n" "$(basename "$f")" "$count"
    done
    printf "\n  0. %s\n" "$(t back)"
    printf "\n  %s" "$(t select_list)"
    read choice </dev/tty

    local target=""
    n=0
    for f in $list_files; do
        n=$((n + 1))
        [ "$choice" != "$n" ] || target="$ZAPRET_BASE/$f"
    done
    [ -n "$target" ] || return

    if [ ! -f "$target" ]; then
        print_fail "$(printf "$(t file_not_found_fmt)" "$target")"
        printf "  %s\n" "$(t copy_lists_first)"
        pause_prompt; return
    fi

    print_info "$(printf "$(t editing_fmt)" "$target")"
    "$editor" "$target" </dev/tty >/dev/tty
    printf "\n  $(t file_lines_fmt)\n" "$(wc -l < "$target")"
    head -5 "$target" | sed 's/^/    /'
    [ "$(wc -l < "$target")" -gt 5 ] && printf "    ...\n"
    printf "\n"
    print_info "$(t restart_to_apply)"
    pause_prompt
}

action_diagnostics() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_diag)"

    if [ -n "$ZAPRET_BASE" ]; then
        print_ok "$(printf "$(t zb_fmt)" "$ZAPRET_BASE")"
    else
        print_fail "$(t zb_not_detected)"
        pause_prompt; return
    fi

    local nfqws_bin="$ZAPRET_BASE/nfq2/nfqws2"
    if [ -x "$nfqws_bin" ]; then
        print_ok "$(printf "$(t nfqws_bin_found_fmt)" "$nfqws_bin")"
    else
        nfqws_bin=$(command -v nfqws2 2>/dev/null)
        if [ -n "$nfqws_bin" ]; then
            print_ok "$(printf "$(t nfqws_in_path_fmt)" "$nfqws_bin")"
        else
            print_fail "$(t nfqws_bin_missing)"
        fi
    fi

    if [ -n "$CUSTOM_D" ]; then
        print_ok "$(printf "$(t customd_fmt)" "$CUSTOM_D")"
    else
        print_fail "$(t customd_missing)"
    fi

    printf "\n"
    get_active_strategy
    local files="$(strategy_lists)" count
    if [ "$ACTIVE_STRATEGY" = sky ]; then
        files="$files strategies/sky/strategy.args"
    else
        files="$files ipset/zapret-hosts-user-ipban.txt files/fake/tls_clienthello_iana_org_bigsize.bin"
    fi
    files="$files files/fake/quic_initial_www_google_com.bin files/fake/quic_initial_steamcommunity_com.bin lua/zapret-lib.lua lua/zapret-antidpi.lua lua/zapret-auto.lua"
    for f in $files; do
        f=$(resolve_asset_file "$f")
        if [ -r "$ZAPRET_BASE/$f" ]; then
            count=$(wc -l < "$ZAPRET_BASE/$f")
            print_ok "$(printf "$(t file_entries_fmt)" "$f" "$count")"
        else
            print_fail "$(printf "$(t file_missing_in_fmt)" "$f" "$ZAPRET_BASE")"
        fi
    done
    print_info "$(t strategy_limits)"
    print_info "$(t override_precedence)"

    printf "\n"
    set -- $(nfqws_describe)
    case "$1" in
        none)
            print_fail "$(t nfqws_not_running)"
            ;;
        single)
            print_ok "$(printf "$(t nfqws_running_one_pid_fmt)" "$2")"
            ;;
        pair)
            print_ok "$(printf "$(t nfqws_running_pair_fmt)" "$2" "$3")"
            ;;
        complex)
            print_ok "$(printf "$(t nfqws_running_complex_fmt)" "$2" "$3")"
            ;;
        multi)
            print_ok "$(printf "$(t nfqws_running_multi_fmt)" "$2")"
            ;;
    esac

    printf "\n"
    if command -v iptables >/dev/null 2>&1; then
        if iptables -t mangle -L -n 2>/dev/null | grep -q NFQUEUE; then
            print_ok "$(t iptables_found)"
        else
            print_warn "$(t iptables_missing)"
        fi
    fi
    if command -v nft >/dev/null 2>&1; then
        if nft list ruleset 2>/dev/null | grep -q queue; then
            print_ok "$(t nftables_found)"
        else
            print_warn "$(t nftables_missing)"
        fi
    fi

    printf "\n"
    get_active_strategy
    if [ "$ACTIVE_STRATEGY" != "none" ]; then
        print_ok "$(printf "$(t active_strategy_fmt)" "$ACTIVE_STRATEGY")"
    else
        print_warn "$(t no_strategy_in_customd)"
    fi

    if [ -n "$CUSTOM_D" ]; then
        local others=""
        for f in "$CUSTOM_D"/*; do
            [ -f "$f" ] || continue
            case "$(basename "$f")" in
                50-zapret2-bypass|.keep) continue ;;
                *) others="$others $(basename "$f")" ;;
            esac
        done
        if [ -n "$others" ]; then
            print_warn "$(printf "$(t other_customd_fmt)" "$others")"
        fi
    fi

    pause_prompt
}

action_uninstall() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t uninstall_title)"
    print_info "$(t uninstall_will)"
    print_info "$(t uninstall_stop)"
    print_info "$(t uninstall_strategy)"
    print_info "$(t uninstall_wipe)"
    print_info "$(t uninstall_unlink)"
    printf "\n"
    print_warn "$(t uninstall_warn)"
    printf "\n  %s" "$(t uninstall_proceed)"
    read yn </dev/tty
    case "$yn" in
        y|Y|yes|Yes|YES) ;;
        *) print_info "$(t cancelled)"; pause_prompt; return ;;
    esac

    printf "\n"
    get_active_strategy
    if [ -n "$ACTIVE_FILE" ]; then
        print_info "$(t stopping)"
        if ! zapret_cmd stop; then
            print_fail "$(t stop_failed)"
            pause_prompt; return 1
        fi
        if ! rm -f "$ACTIVE_FILE"; then
            print_fail "$(printf "$(t remove_failed_fmt)" "$ACTIVE_FILE")"
            pause_prompt; return 1
        fi
        print_ok "$(t strategy_removed)"
    fi
    if [ -n "$ZAPRET_BASE" ] && grep -q '^# BEGIN zapret2-openwrt Discord DNS$' "$ZAPRET_BASE/config"; then
        local config_tmp
        config_tmp=$(mktemp "$ZAPRET_BASE/.z2b-config.XXXXXX") || return 1
        if ! cp -p "$ZAPRET_BASE/config" "$config_tmp" ||
            ! strip_discord_dns_config "$ZAPRET_BASE/config" > "$config_tmp" ||
            ! mv -f "$config_tmp" "$ZAPRET_BASE/config"; then
            rm -f "$config_tmp"
            print_fail "$(printf "$(t remove_failed_fmt)" "$ZAPRET_BASE/config")"
            pause_prompt; return 1
        fi
    fi
    if [ -n "$ZAPRET_BASE" ] && ! rm -f "$ZAPRET_BASE/strategies/sky/strategy.args" "$ZAPRET_BASE/strategies/sky/discord-dns.sh"; then
        print_fail "$(printf "$(t remove_failed_fmt)" "$ZAPRET_BASE/strategies/sky")"
        pause_prompt; return 1
    fi

    if [ -L "$SYMLINK_PATH" ] && [ "$(readlink "$SYMLINK_PATH")" = "$PERSIST_DIR/service.sh" ]; then
        rm -f "$SYMLINK_PATH" || { print_fail "$(printf "$(t remove_failed_fmt)" "$SYMLINK_PATH")"; pause_prompt; return 1; }
        print_ok "$(printf "$(t path_removed_fmt)" "$SYMLINK_PATH")"
    fi

    if [ -d "$PERSIST_DIR" ]; then
        rm -rf "$PERSIST_DIR" || { print_fail "$(printf "$(t remove_failed_fmt)" "$PERSIST_DIR")"; pause_prompt; return 1; }
        print_ok "$(printf "$(t path_removed_fmt)" "$PERSIST_DIR")"
    fi

    if [ -d "/tmp/zapret2-openwrt" ]; then
        print_info "$(t removing)"
        rm -rf "/tmp/zapret2-openwrt" || { print_fail "$(printf "$(t remove_failed_fmt)" "/tmp/zapret2-openwrt")"; pause_prompt; return 1; }
        print_ok "$(t removed)"
    else
        print_info "$(t nothing_remove)"
    fi

    printf "\n"
    print_ok "$(t uninstall_done)"
    printf "\n"
    exit 0
}

first_run_check() {
    [ -z "$ZAPRET_BASE" ] && return 0
    get_active_strategy
    [ "$ACTIVE_STRATEGY" != "none" ] && return 0
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t first_setup)"
    print_info "$(t no_strategy_yet)"
    printf "  %s" "$(t run_setup_q)"
    read yn </dev/tty || return 0
    case "$yn" in n|N) return 0 ;; esac
    if select_strategy; then
        deploy_strategy
    fi
    pause_prompt
}

main_menu() {
    load_language
    pick_language
    load_locale
    register_command

    detect_zapret_base

    if [ -z "$ZAPRET_BASE" ]; then
        printf "\n"
        print_warn "$(t base_missing)"
        printf "  $(t base_install_q)" "$ZAPRET_VERSION"
        read install_choice </dev/tty
        case "$install_choice" in
            ''|y|Y|yes|Yes|YES)
                install_zapret_base || print_warn "$(t base_install_fail)"
                pause_prompt
                ;;
            *)
                print_info "$(printf "$(t base_install_skip)" "$ZAPRET_TARBALL_URL")"
                pause_prompt
                ;;
        esac
    fi

    detect_custom_d
    detect_init_system

    first_run_check

    while true; do
        clear
        get_active_strategy

        printf "\n"
        printf "  ${C_BOLD}%s${C_RESET}\n" "$(t menu_title)"
        printf "  ────────────────────────────────\n"
        printf "\n"
        printf "  ${C_CYAN}%s${C_RESET}\n" "$(t sec_strategy)"
        printf "     1. %s   ${C_CYAN}[%s]${C_RESET}\n" "$(t m_install)" "$ACTIVE_STRATEGY"
        printf "     2. %s\n" "$(t m_show_active)"
        printf "\n"
        printf "  ${C_CYAN}%s${C_RESET}\n" "$(t sec_service)"
        printf "     3. %s\n" "$(t m_start)"
        printf "     4. %s\n" "$(t m_stop)"
        printf "     5. %s\n" "$(t m_restart)"
        printf "     6. %s\n" "$(t m_status)"
        printf "\n"
        printf "  ${C_CYAN}%s${C_RESET}\n" "$(t sec_lists)"
        printf "     7. %s\n" "$(t m_lists)"
        printf "\n"
        printf "  ${C_CYAN}%s${C_RESET}\n" "$(t sec_tools)"
        printf "     8. %s\n" "$(t m_diag)"
        printf "     9. %s\n" "$(t m_uninstall)"
        printf "\n"
        printf "  ────────────────────────────────\n"
        printf "     0. %s\n" "$(t m_exit)"
        printf "\n"

        if [ -z "$ZAPRET_BASE" ]; then
            print_fail "$(t no_zapret_base)"
            printf "\n"
        fi

        printf "  %s" "$(t select_option)"
        read menu_choice </dev/tty

        case "$menu_choice" in
            1) action_install_strategy ;;
            2) action_show_active ;;
            3) action_start ;;
            4) action_stop ;;
            5) action_restart ;;
            6) action_status ;;
            7) action_edit_lists ;;
            8) action_diagnostics ;;
            9) action_uninstall ;;
            0|q|Q) printf "\n"; exit 0 ;;
        esac
    done
}

main_menu
