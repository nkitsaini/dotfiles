# ~/.config/fish/config.fish
alias ll="ls -lh"

# Save a lot of typing for common commands
alias gs="git status"
alias gc="git checkout"
alias v="nvim"
alias vi="nvim"
alias vim="nvim"

# Save you from mistyping
alias sl=ls

# Overwrite existing commands for better defaults
alias mv="mv -i"           # -i prompts before overwrite
alias mkdir="mkdir -p"     # -p make parent dirs as needed
alias df="df -h"           # -h prints human readable format

# Alias can be composed
alias la="ls -A"
alias lla="la -l"
alias llt="lla -t"
alias tree='tree -I "venv|target|node_modules|__pycache__"'
alias dc="docker-compose"

alias da="direnv allow"


#
# Reinvented wheels
# alias cat="/home/ankit/code/tools/target/release/cat"
# alias rgrep="/home/ankit/code/tools/target/release/rgrep"
# alias tac="/home/ankit/code/tools/target/release/tac"
# alias head="/home/ankit/code/tools/target/release/head"

# function fish_greeting
# 	echo
# 	echo -e (uname -ro | awk '{print " \\\\e[1mOS: \\\\e[0;32m"$0"\\\\e[0m"}')
# 	echo -e (uptime -p | sed 's/^up //' | awk '{print " \\\\e[1mUptime: \\\\e[0;32m"$0"\\\\e[0m"}')
# 	echo -e (uname -n | awk '{print " \\\\e[1mHostname: \\\\e[0;32m"$0"\\\\e[0m"}')
# 
# 	echo
# 	set_color normal
# end

setenv FZF_CTRL_T_COMMAND 'fdfind --type file --follow'
setenv FZF_DEFAULT_OPTS '--height 20%'

function fish_user_key_bindings
    bind \cz 'fg>/dev/null ^/dev/null'
    # Execute this once per mode that emacs bindings should be used in
    fish_default_key_bindings -M insert
    bind -M insert \cc kill-whole-line repaint
    # Without an argument, fish_vi_key_bindings will default to
    # resetting all bindings.
    # The argument specifies the initial mode (insert, "default" or visual).
    fish_vi_key_bindings insert
end

# Emulates vim's cursor shape behavior
# Set the normal and visual mode cursors to a block
set fish_cursor_default block
# Set the insert mode cursor to a line
set fish_cursor_insert line
# Set the replace mode cursor to an underscore
set fish_cursor_replace_one underscore
# The following variable can be used to configure cursor shape in
# visual mode, but due to fish_cursor_default, is redundant here
set fish_cursor_visual block
#if status --is-interactive
#    task
    #
#end
set -g man_blink -o red
set -g man_bold -o green
set -g man_standout -b black 93a1a1
set -g man_underline -u 93a1a1


#automatically load .envrc
#install package (direnv), apt-get install direnv
# eval (direnv hook fish)
starship init fish | source
