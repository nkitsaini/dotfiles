# Dynamic completions for karo: task names come from `karo --complete-tasks`.

_karo() {
    local cur
    # Task names may contain ':' (qualified runner:task, go-task namespaces);
    # use the bash-completion helpers to not split on it when available.
    if declare -F _get_comp_words_by_ref >/dev/null 2>&1; then
        _get_comp_words_by_ref -n : cur
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
    fi

    if [[ ${COMP_CWORD} -ne 1 ]]; then
        return 0
    fi

    if [[ ${cur} == -* ]]; then
        COMPREPLY=( $(compgen -W "--list --help --version -l -h -V" -- "$cur") )
        return 0
    fi

    local IFS=$'\n'
    COMPREPLY=( $(compgen -W "$(karo --complete-tasks 2>/dev/null | cut -f1)" -- "$cur") )

    if declare -F __ltrim_colon_completions >/dev/null 2>&1; then
        __ltrim_colon_completions "$cur"
    fi
    return 0
}

complete -F _karo karo
