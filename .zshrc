# START GLOBAL
#
typeset -A __STASHINGVARS
__STASHINGVARS[ITALIC_ON]=$'\e[3m'
__STASHINGVARS[ITALIC_OFF]=$'\e[23m'
#
# END GLOBAL


# START COMPLETION
# 
autoload -U compinit 
compinit -u

zstyle ':completion:*' expand prefix suffix
zstyle ':completion:*' list-suffixes
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'
zstyle ':completion:*' list-colors ''
zstyle -e ':completion:*' special-dirs '[[ $PREFIX = (../)#(..) ]] && reply=(..)'
zstyle ':completion:*:complete:(cd|pushd):*' tag-order 'local-directories named-directories'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format %F{default}%B%{$__STASHINGVARS[ITALIC_ON]%}--- %d ---%{$__STASHINGVARS[ITALIC_OFF]%}%b%f
zstyle ':completion:*' menu select
#
# END COMPLETION


# START PROMPTS
#
autoload -Uz vcs_info

function () {
  local TMUXING=$([[ "$TERM" =~ "tmux" ]] && echo tmux)
  if [ -n "$TMUXING" -a -n "$TMUX" ]; then
    local LVL=$(($SHLVL - 1))
  else
    local LVL=$SHLVL
  fi
  if [[ $EUID -eq 0 ]]; then
    local SUFFIX='%F{yellow}%n%f'$(printf '%%F{yellow}\u0023%.0s%%f' {1..$LVL})
  else
    local SUFFIX=$(printf '%%F{red}\u0024%.0s%%f' {1..$LVL})
  fi
  PROMPT="%F{blue}%B%1/%b%F{yellow}%B%(?..!)%b%f% %B${SUFFIX}%b "
  if [[ -n "$TMUXING" ]]; then
    export ZLE_RPROMPT_INDENT=0
  fi
}

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr "%F{green}●%f" 
zstyle ':vcs_info:*' unstagedstr "%F{red}●%f" 
zstyle ':vcs_info:*' use-simple true
zstyle ':vcs_info:git+set-message:*' hooks git-untracked
zstyle ':vcs_info:git*:*' formats '[%b%m%c%u]' 
zstyle ':vcs_info:git*:*' actionformats '[%b|%a%m%c%u]' 

function +vi-git-untracked() {
  emulate -L zsh
  if [[ -n $(git ls-files --exclude-standard --others 2> /dev/null) ]]; then
    hook_com[unstaged]+="%F{blue}●%f"
  fi
}

RPROMPT_BASE="\${vcs_info_msg_0_}"
setopt PROMPT_SUBST

autoload -U add-zsh-hook

typeset -F SECONDS
function -record-start-time() {
  emulate -L zsh
  ZSH_START_TIME=${ZSH_START_TIME:-$SECONDS}
}
add-zsh-hook preexec -record-start-time

function -report-start-time() {
  emulate -L zsh
  if [ $ZSH_START_TIME ]; then
    local DELTA=$(($SECONDS - $ZSH_START_TIME))
    local DAYS=$((~~($DELTA / 86400)))
    local HOURS=$((~~(($DELTA - $DAYS * 86400) / 3600)))
    local MINUTES=$((~~(($DELTA - $DAYS * 86400 - $HOURS * 3600) / 60)))
    local SECS=$(($DELTA - $DAYS * 86400 - $HOURS * 3600 - $MINUTES * 60))
    local ELAPSED=''
    test "$DAYS" != '0' && ELAPSED="${DAYS}d"
    test "$HOURS" != '0' && ELAPSED="${ELAPSED}${HOURS}h"
    test "$MINUTES" != '0' && ELAPSED="${ELAPSED}${MINUTES}m"
    if [ "$ELAPSED" = '' ]; then
      SECS="$(print -f "%.2f" $SECS)s"
    elif [ "$DAYS" != '0' ]; then
      SECS=''
    else
      SECS="$((~~$SECS))s"
    fi
    ELAPSED="${ELAPSED}${SECS}"
    RPROMPT="%F{cyan}%{$__STASHINGVARS[ITALIC_ON]%}${ELAPSED}%{$__STASHINGVARS[ITALIC_OFF]%}%f $RPROMPT_BASE"
    unset ZSH_START_TIME
  else
    RPROMPT="$RPROMPT_BASE"
  fi
}
add-zsh-hook precmd -report-start-time

function -record-command() {
  __STASHINGVARS[LAST_COMMAND]="$2"
}
add-zsh-hook preexec -record-command

function -maybe-show-vcs-info() {
  local LAST="$__STASHINGVARS[LAST_COMMAND]"

  __STASHINGVARS[LAST_COMMAND]="<unset>"

  case "$LAST[(w)1]" in
    cd|cp|git|rm|touch|mv)
      vcs_info
      ;;
    *)
      ;;
  esac
}
add-zsh-hook precmd -maybe-show-vcs-info

SPROMPT="zsh: correct %F{red}'%R'%f to %F{red}'%r'%f [%B%Uy%u%bes, %B%Un%u%bo, %B%Ue%u%bdit, %B%Ua%u%bbort]? "

# Change cursor shape for different vi modes.
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.
#
# END PROMPTS


# START HISTORY     
#
HISTFILE="$HOME/.history"
HISTSIZE=10000 
SAVEHIST=10000 

setopt INC_APPEND_HISTORY		# Write immediately
setopt APPEND_HISTORY			# Append to history file
setopt HIST_EXPIRE_DUPS_FIRST		# Expire duplicate first
setopt HIST_FIND_NO_DUPS		# Don't show dups when searching
setopt HIST_IGNORE_DUPS			# Filter contiguous dups
setopt HIST_IGNORE_ALL_DUPS 		# Don't filter non-contiguous duplicates
setopt HIST_IGNORE_SPACE		# Don't record commands starting with space 
setopt HIST_VERIFY			# Confirm history expansion
setopt HIST_SAVE_NO_DUPS		# Don't write duplicates to history
setopt SHARE_HISTORY			# Share history across shells
#
# END HISTORY


# START OPTIONS
#
setopt AUTO_CD				# Shortcut for cd
setopt AUTO_PARAM_SLASH			# Directory appends a slash
setopt AUTO_PUSHD			# Pushes old dir onto dir stack
setopt AUTO_RESUME			# Allow simple commands to resume background jobs
setopt CLOBBER				# Allow clobbering with >
setopt CORRECT				# Command auto-correction
setopt CORRECT_ALL			# Argument auto-correction
setopt NO_FLOW_CONTROL			# Disable start and stop characters
setopt IGNORE_EOF			# Prevent accidental C-d from exiting shell
setopt INTERACTIVE_COMMENTS		# Allow comments, even in interactive shells
setopt LIST_PACKED			# Make completion lists more densely packed
setopt MENU_COMPLETE			# Auto-insert first possible ambiguous complation
setopt NO_NOMATCH			# Unmatched patterns are left unchanged
setopt PUSHD_IGNORE_DUPS		# Don't push multiple copies of same dir onto stack
setopt PUSHD_SILENT			# Don't print dir stack after pushing/popping
#
# END OPTIONS


# START BINDINGS
#
bindkey -v

autoload -U edit-command-line
zle -N edit-command-line

bindkey -M vicmd '^x^x' edit-command-line
bindkey -M vicmd "^r" history-incremental-pattern-search-backward
bindkey -M vicmd "^s" history-incremental-pattern-search-forward
#
# END BINDINGS


# START SOURCE
#
source $HOME/.zsh/aliases
source $HOME/.zsh/common
source $HOME/.zsh/colors
source $HOME/.zsh/exports
source $HOME/.zsh/functions
source $HOME/.zsh/path
#
# END SOURCE


# START PLUGINS
#
source ~/.zsh/zsh-autosuggestions/suggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=59'
#
# END PLUGINS
eval "$(rbenv init -)"
