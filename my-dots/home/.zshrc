# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnosterzak"

plugins=( 
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

# Accent colours follow the wallpaper: wallust rewrites wallust-palette.json on
# every wallpaper change; rebuild the fastfetch configs and the prompt
# colours (~/.cache/prompt-accent.zsh) only when it is newer than them.
[[ $HOME/.config/fastfetch/wallust-palette.json -nt $HOME/.config/fastfetch/config-nologo.jsonc ]] &&
  python3 $HOME/.config/fastfetch/gen_config.py >/dev/null 2>&1
source $ZSH/oh-my-zsh.sh   # after the rebuild: the theme reads prompt-accent.zsh


# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
#pokemon-colorscripts --no-title -s -r #without fastfetch
#pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# fastfetch. Will be disabled if above colorscript was chosen to install
# Logo stripped (2026-11-11; the old eye layouts are still generated, and the
# previous setup is in ~/.zshrc.bak-2026-11-11). The layout is fixed-size, so
# pick the biggest variant the window can hold, by width AND height -- a short
# window would scroll the top of the box out of view. Heights are the output
# (16 lines for either box, 7 for mini) plus the 2-line prompt and a spare row;
# widths come from gen_config.py. Too small for even mini: skip fastfetch.
# COLUMNS/LINES can be unset or 0 in a not-yet-sized shell, so fall back to tput.
_ff_cols=${COLUMNS:-0} _ff_rows=${LINES:-0}
(( _ff_cols > 0 )) || _ff_cols=$(tput cols 2>/dev/null || echo 80)
(( _ff_rows > 0 )) || _ff_rows=$(tput lines 2>/dev/null || echo 24)
if   (( _ff_rows >= 19 && _ff_cols >= 46 )); then fastfetch -c $HOME/.config/fastfetch/config-nologo.jsonc
elif (( _ff_rows >= 19 && _ff_cols >= 31 )); then fastfetch -c $HOME/.config/fastfetch/config-compact-nologo.jsonc
elif (( _ff_rows >= 10 && _ff_cols >= 24 )); then fastfetch -c $HOME/.config/fastfetch/config-mini-nologo.jsonc
fi
unset _ff_cols _ff_rows

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

export PATH="$HOME/.local/bin:$PATH"
