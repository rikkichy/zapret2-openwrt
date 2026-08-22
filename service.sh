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
STRATEGY_NAME="measured-2026-08-22"

PERSIST_DIR="/usr/lib/zapret2-openwrt"
SYMLINK_PATH="/usr/bin/zapret2"

register_command() {
    case "$SCRIPT_DIR" in
        /tmp/zapret2-openwrt|/tmp/zapret2-openwrt/*) ;;
        *) return 0 ;;
    esac

    print_info "$(t cmd_registering)"

    rm -rf "$PERSIST_DIR" 2>/dev/null
    if ! mkdir -p "$PERSIST_DIR" 2>/dev/null; then
        print_warn "$(t cmd_register_fail)"
        return 1
    fi
    if ! cp -r "$SCRIPT_DIR"/. "$PERSIST_DIR/" 2>/dev/null; then
        print_warn "$(t cmd_register_fail)"
        return 1
    fi
    chmod +x "$PERSIST_DIR/service.sh" 2>/dev/null

    if ! ln -sf "$PERSIST_DIR/service.sh" "$SYMLINK_PATH" 2>/dev/null; then
        print_warn "$(t cmd_register_fail)"
        return 1
    fi

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
        zapret_cmd stop >/dev/null 2>&1 || true
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
    if [ -z "$CUSTOM_D" ]; then return; fi
    for f in "$CUSTOM_D"/50-zapret2-bypass; do
        [ -f "$f" ] || continue
        ACTIVE_FILE="$f"
        ACTIVE_STRATEGY=$(sed -n 's/^# Strategy: *//p' "$f" | head -1)
        [ -z "$ACTIVE_STRATEGY" ] && ACTIVE_STRATEGY="$(basename "$f")"
        return
    done
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

copy_lists() {
    local src="$SCRIPT_DIR/lists"
    local dst="$ZAPRET_BASE/ipset"
    local copied=0
    for f in list-general.txt list-hetzner.txt list-exclude.txt; do
        if [ -f "$src/$f" ]; then
            if [ ! -f "$dst/$f" ]; then
                cp "$src/$f" "$dst/$f"
                print_ok "$(printf "$(t copied_fmt)" "$f" "$dst/")"
                copied=$((copied + 1))
            fi
        else
            print_warn "$(printf "$(t source_missing_fmt)" "$f" "$src/")"
        fi
    done
    if [ "$copied" -eq 0 ]; then
        print_info "$(t all_lists_present)"
    fi
}

action_install_strategy()
{
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_install)"

    if [ -z "$ZAPRET_BASE" ]; then
        print_fail "$(t zb_not_detected)"
        pause_prompt; return
    fi
    if [ -z "$CUSTOM_D" ]; then
        print_fail "$(printf "$(t customd_missing_in_fmt)" "$ZAPRET_BASE")"
        pause_prompt; return
    fi

    local src="$SCRIPT_DIR/custom.d/$STRATEGY_FILE"
    if [ ! -f "$src" ]; then
        print_fail "$(printf "$(t file_not_found_fmt)" "$src")"
        pause_prompt; return
    fi

    print_info "$(printf "$(t installing_strategy_fmt)" "$STRATEGY_NAME")"
    copy_lists

    rm -f "$CUSTOM_D/$STRATEGY_FILE"
    cp "$src" "$CUSTOM_D/"
    print_ok "$(printf "$(t installed_to_fmt)" "$STRATEGY_FILE" "$CUSTOM_D/")"

    printf "\n  %s" "$(t restart_q)"
    read yn </dev/tty
    case "$yn" in
        y|Y|yes|Yes|YES|'')
            print_info "$(t restarting)"
            zapret_cmd restart
            print_ok "$(t done)"
            ;;
    esac

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
        sed -n '/^NFQWS2_Z2B_OPT=/,/}"/p' "$ACTIVE_FILE" | sed 's/^/    /'
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

action_edit_lists() {
    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t h_lists)"

    if [ -z "$ZAPRET_BASE" ]; then
        print_fail "$(t zb_not_detected)"
        pause_prompt; return
    fi

    local ipset_dir="$ZAPRET_BASE/ipset"
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

    printf "$(t list_general_fmt)\n" "$(wc -l < "$ipset_dir/list-general.txt" 2>/dev/null || echo 0)"
    printf "$(t list_hetzner_fmt)\n" "$(wc -l < "$ipset_dir/list-hetzner.txt" 2>/dev/null || echo 0)"
    printf "$(t list_exclude_fmt)\n" "$(wc -l < "$ipset_dir/list-exclude.txt" 2>/dev/null || echo 0)"
    printf "\n  0. %s\n" "$(t back)"
    printf "\n  %s" "$(t select_list)"
    read choice </dev/tty

    local target=""
    case "$choice" in
        1) target="$ipset_dir/list-general.txt" ;;
        2) target="$ipset_dir/list-hetzner.txt" ;;
        3) target="$ipset_dir/list-exclude.txt" ;;
        *) return ;;
    esac

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
    for f in list-general.txt list-hetzner.txt list-exclude.txt; do
        if [ -f "$ZAPRET_BASE/ipset/$f" ]; then
            local count=$(wc -l < "$ZAPRET_BASE/ipset/$f" 2>/dev/null)
            print_ok "$(printf "$(t file_entries_fmt)" "$f" "$count")"
        else
            print_fail "$(printf "$(t file_missing_in_fmt)" "$f" "$ZAPRET_BASE/ipset/")"
        fi
    done

    printf "\n"
    for f in quic_initial_www_google_com.bin tls_clienthello_iana_org_bigsize.bin; do
        if [ -f "$ZAPRET_BASE/files/fake/$f" ]; then
            print_ok "$f"
        else
            print_fail "$(printf "$(t file_missing_in_fmt)" "$f" "$ZAPRET_BASE/files/fake/")"
        fi
    done

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
    if [ -n "$INIT_TYPE" ]; then
        print_info "$(t stopping)"
        zapret_cmd stop >/dev/null 2>&1 || true
        print_ok "$(t stopped)"
    else
        print_info "$(t no_init)"
    fi

    if [ -n "$CUSTOM_D" ] && [ -d "$CUSTOM_D" ]; then
        local removed_any=0
        for f in "$CUSTOM_D"/50-zapret2-bypass; do
            [ -f "$f" ] || continue
            rm -f "$f" 2>/dev/null && removed_any=1
        done
        if [ "$removed_any" = "1" ]; then
            print_ok "$(t strategy_removed)"
        else
            print_info "$(t no_strategy_to_remove)"
        fi
    fi

    if [ -L "$SYMLINK_PATH" ] || [ -e "$SYMLINK_PATH" ]; then
        rm -f "$SYMLINK_PATH" 2>/dev/null
        print_ok "$(printf "$(t path_removed_fmt)" "$SYMLINK_PATH")"
    fi

    if [ -d "$PERSIST_DIR" ]; then
        rm -rf "$PERSIST_DIR" 2>/dev/null
        print_ok "$(printf "$(t path_removed_fmt)" "$PERSIST_DIR")"
    fi

    if [ -d "/tmp/zapret2-openwrt" ]; then
        print_info "$(t removing)"
        rm -rf "/tmp/zapret2-openwrt"
        print_ok "$(t removed)"
    else
        print_info "$(t nothing_remove)"
    fi

    printf "\n"
    print_ok "$(t uninstall_done)"
    printf "\n"
    exit 0
}

first_run_check()
{
    [ -z "$ZAPRET_BASE" ] && return 0

    get_active_strategy
    [ "$ACTIVE_STRATEGY" != "none" ] && return 0
    [ -f "$ZAPRET_BASE/ipset/list-general.txt" ] && return 0

    clear
    printf "\n  ${C_BOLD}%s${C_RESET}\n\n" "$(t first_setup)"
    print_info "$(t no_strategy_yet)"
    printf "  %s" "$(t run_setup_q)"
    read yn </dev/tty
    case "$yn" in
        n|N) return 0 ;;
    esac

    printf "\n"
    print_info "$(t step1)"
    copy_lists

    printf "\n"
    print_info "$(t step2)"
    if [ -n "$CUSTOM_D" ] && [ -f "$SCRIPT_DIR/custom.d/$STRATEGY_FILE" ]; then
        rm -f "$CUSTOM_D/$STRATEGY_FILE"
        cp "$SCRIPT_DIR/custom.d/$STRATEGY_FILE" "$CUSTOM_D/"
        print_ok "$(printf "$(t installed_to_fmt)" "$STRATEGY_FILE" "$CUSTOM_D/")"
    else
        print_fail "$(printf "$(t customd_missing_in_fmt)" "$ZAPRET_BASE")"
        pause_prompt; return
    fi

    printf "\n  %s" "$(t start_now_q)"
    read yn2 </dev/tty
    case "$yn2" in
        n|N) ;;
        *)
            print_info "$(t starting)"
            zapret_cmd start
            print_ok "$(t done)"
            ;;
    esac

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
