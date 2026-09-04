# Sdílené funkce pro bitwarden-generate a bitwarden-add. Sourcovat, nespouštět přímo.

bw_ask() {
    walker -d -I -p "$1" < /dev/null
}

bw_choose() {
    walker -d -p "$1"
}

# Jako bw_ask, ale vstup je maskovaný (-x) pro ruční zadání hesla.
bw_ask_password() {
    walker -d -I -x -p "$1" < /dev/null
}

# Vyplní globální pole BW_GEN_ARGS argumenty pro `rbw generate` (bez NAME/USER/--folder).
# Vrací 1, pokud uživatel zrušil nebo zadal neplatnou hodnotu.
bw_prompt_generate_args() {
    BW_GEN_ARGS=()
    local kind
    kind=$(printf 'Náhodné znaky\nDiceware (slova)\n' | bw_choose "Typ hesla:") || return 1

    if [[ "$kind" == "Diceware (slova)" ]]; then
        local words
        words=$(bw_ask "Počet slov (např. 4):")
        [[ -z "$words" ]] && words=4
        if ! [[ "$words" =~ ^[0-9]+$ ]] || (( words < 1 )); then
            notify-send "Bitwarden" "Neplatný počet slov"
            return 1
        fi
        BW_GEN_ARGS=(--diceware "$words")
        return 0
    fi

    local charset
    charset=$(printf 'Písmena + čísla + symboly\nPísmena + čísla (bez symbolů)\nJen čísla (PIN)\nBez podobných znaků (0/O, 1/l)\n' \
        | bw_choose "Sada znaků:") || return 1

    local length
    length=$(bw_ask "Délka hesla (počet znaků):")
    [[ -z "$length" ]] && length=20
    if ! [[ "$length" =~ ^[0-9]+$ ]] || (( length < 1 )); then
        notify-send "Bitwarden" "Neplatná délka hesla"
        return 1
    fi

    case "$charset" in
        "Písmena + čísla (bez symbolů)") BW_GEN_ARGS+=(--no-symbols) ;;
        "Jen čísla (PIN)") BW_GEN_ARGS+=(--only-numbers) ;;
        "Bez podobných znaků (0/O, 1/l)") BW_GEN_ARGS+=(--nonconfusables) ;;
    esac
    BW_GEN_ARGS+=("$length")
    return 0
}
