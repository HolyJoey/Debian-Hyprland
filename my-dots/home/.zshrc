# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnosterzak"

plugins=( 
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh


# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
#pokemon-colorscripts --no-title -s -r #without fastfetch
#pokemon-colorscripts --no-title -s -r | fastfetch -c $HOME/.config/fastfetch/config-pokemon.jsonc --logo-type file-raw --logo-height 10 --logo-width 5 --logo -

# fastfetch. Will be disabled if above colorscript was chosen to install
# Logo stripped (2026-11-11; the old eye layouts are still generated, and the
# previous setup is in ~/.zshrc.bak-2026-11-11). The layout is fixed-width, so
# pick the widest variant the window can hold: the full box needs 58 columns,
# the compact box 48; narrower than that, skip it rather than let it wrap.
# COLUMNS can be unset or 0 in a not-yet-sized shell, so fall back to tput.
_ff_cols=${COLUMNS:-0}
(( _ff_cols > 0 )) || _ff_cols=$(tput cols 2>/dev/null || echo 80)
if   (( _ff_cols >= 58 )); then fastfetch -c $HOME/.config/fastfetch/config-nologo.jsonc
elif (( _ff_cols >= 48 )); then fastfetch -c $HOME/.config/fastfetch/config-boxes.jsonc
fi
unset _ff_cols

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

export PATH="$HOME/.local/bin:$PATH"
