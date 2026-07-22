# Dynamic completions for karo: task names come from `karo --complete-tasks`,
# which delegates discovery to the project's own runners.

complete -c karo -f

# Only complete the first argument; anything after the task name is
# task-specific and forwarded verbatim.
complete -c karo -n 'test (count (commandline -opc)) -eq 1' \
    -a '(karo --complete-tasks 2>/dev/null)'

complete -c karo -n 'test (count (commandline -opc)) -eq 1' -s l -l list -d 'List tasks from all runners'
complete -c karo -n 'test (count (commandline -opc)) -eq 1' -s h -l help -d 'Show help'
complete -c karo -n 'test (count (commandline -opc)) -eq 1' -s V -l version -d 'Show version'
