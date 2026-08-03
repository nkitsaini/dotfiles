# Fish completions for the kit CLI.
complete -c kit -f

complete -c kit -n __fish_use_subcommand -a help -d 'Show kit usage'
complete -c kit -n __fish_use_subcommand -a rebuild -d 'Switch this machine to the flake config'
complete -c kit -n __fish_use_subcommand -a config -d 'Inspect mutable Nix-managed config files'
complete -c kit -n __fish_use_subcommand -a unfreeze -d 'Replace a store symlink with a writable copy'

complete -c kit -n '__fish_seen_subcommand_from rebuild' -l dry-run -d 'Print the rebuild command without running it'
complete -c kit -n '__fish_seen_subcommand_from rebuild' -s h -l help -d 'Show rebuild usage'

set -l config_needs_subcommand '__fish_seen_subcommand_from config; and not __fish_seen_subcommand_from status diff'
complete -c kit -n "$config_needs_subcommand" -a status -d 'Show sync status for mutable configs'
complete -c kit -n "$config_needs_subcommand" -a diff -d 'Diff unsafe mutable-config changes'
complete -c kit -n '__fish_seen_subcommand_from config; and __fish_seen_subcommand_from diff' -l all -d 'Include safe merge and track-only changes'
