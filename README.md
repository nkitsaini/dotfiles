Uses chezmoi to manage dotfiles

```
chezmoi init <path-to-repo>
chezmoi cd
chezmoi diff
chezmoi apply
chezmoi add ~/.new_config
chezmoi add --template ~/.new_config
```

Put all the files that _should not_ be tracked by chezmoi (like firefox extensions) in `non_files` dir
