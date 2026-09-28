# Standalone tmux integration, adapted from the Oh My Zsh tmux plugin.

if ! (( $+commands[tmux] )); then
  return
fi

# Configuration
: ${ZSH_TMUX_AUTOSTART:=false}
: ${ZSH_TMUX_AUTOSTART_ONCE:=true}
: ${ZSH_TMUX_AUTOCONNECT:=true}
: ${ZSH_TMUX_AUTOQUIT:=$ZSH_TMUX_AUTOSTART}
: ${ZSH_TMUX_AUTONAME_SESSION:=false}
: ${ZSH_TMUX_AUTOREFRESH:=false}
: ${ZSH_TMUX_DETACHED:=false}
: ${ZSH_TMUX_FIXTERM:=true}
: ${ZSH_TMUX_ITERM2:=false}
: ${ZSH_TMUX_UNICODE:=false}

if [[ -e /usr/share/terminfo/t/tmux ]]; then
  : ${ZSH_TMUX_FIXTERM_WITHOUT_256COLOR:=tmux}
else
  : ${ZSH_TMUX_FIXTERM_WITHOUT_256COLOR:=screen}
fi

if [[ -e /usr/share/terminfo/t/tmux-256color ]]; then
  : ${ZSH_TMUX_FIXTERM_WITH_256COLOR:=tmux-256color}
else
  : ${ZSH_TMUX_FIXTERM_WITH_256COLOR:=screen-256color}
fi

if [[ -e $HOME/.tmux.conf ]]; then
  : ${ZSH_TMUX_CONFIG:=$HOME/.tmux.conf}
elif [[ -e ${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf ]]; then
  : ${ZSH_TMUX_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf}
else
  : ${ZSH_TMUX_CONFIG:=$HOME/.tmux.conf}
fi
export ZSH_TMUX_CONFIG

zmodload zsh/terminfo 2>/dev/null
if (( ${terminfo[colors]:-0} >= 256 )); then
  export ZSH_TMUX_TERM=$ZSH_TMUX_FIXTERM_WITH_256COLOR
else
  export ZSH_TMUX_TERM=$ZSH_TMUX_FIXTERM_WITHOUT_256COLOR
fi

# Aliases and session-aware helper commands
function _build_tmux_alias() {
  setopt localoptions no_rc_expand_param

  eval "function $1 {
    if [[ -z \$1 ]] || [[ \${1:0:1} == '-' ]]; then
      tmux $2 \"\$@\"
    else
      tmux $2 $3 \"\$@\"
    fi
  }"

  if (( $+functions[compdef] )); then
    local completion_function="_tmux_alias_$1"
    local -a subcommand
    subcommand=(${(z)2})

    eval "function $completion_function() {
      shift words
      words=(tmux ${@:2} \$words)
      (( CURRENT += ${#subcommand[@]} + 1 ))
      _tmux
    }"
    compdef "$completion_function" "$1"
  fi
}

alias tksv='tmux kill-server'
alias tl='tmux list-sessions'
alias tls='tmux list-sessions'
alias tn='tmux new-session'
alias tmuxconf='$EDITOR $ZSH_TMUX_CONFIG'

_build_tmux_alias ta 'attach' '-t'
_build_tmux_alias tad 'attach -d' '-t'
_build_tmux_alias to 'new-session -A' '-s'
_build_tmux_alias ts 'new-session' '-s'
_build_tmux_alias tkss 'kill-session' '-t'
unfunction _build_tmux_alias

# With no arguments, attach to an existing session or create a new one. With
# arguments, behave exactly like the tmux command.
function _zsh_tmux_run() {
  if (( $# )); then
    command tmux "$@"
    return $?
  fi

  local -a tmux_cmd
  tmux_cmd=(command tmux)
  [[ $ZSH_TMUX_ITERM2 == true ]] && tmux_cmd+=(-CC)
  [[ $ZSH_TMUX_UNICODE == true ]] && tmux_cmd+=(-u)

  local detached=''
  [[ $ZSH_TMUX_DETACHED == true ]] && detached='-d'

  local session_name=$ZSH_TMUX_DEFAULT_SESSION_NAME
  if [[ $ZSH_TMUX_AUTONAME_SESSION == true ]]; then
    session_name=${PWD##*/}
    [[ $PWD == $HOME ]] && session_name=HOME
    [[ $PWD == / ]] && session_name=ROOT
  fi

  if [[ $ZSH_TMUX_AUTOCONNECT == true ]]; then
    if [[ -n $session_name ]]; then
      $tmux_cmd attach $detached -t "$session_name"
    else
      $tmux_cmd attach $detached
    fi
  else
    false
  fi

  if (( $? != 0 )); then
    if [[ -e $ZSH_TMUX_CONFIG ]]; then
      tmux_cmd+=(-f "$ZSH_TMUX_CONFIG")
    fi

    if [[ -n $session_name ]]; then
      $tmux_cmd new-session -s "$session_name"
    else
      $tmux_cmd new-session
    fi
  fi

  [[ $ZSH_TMUX_AUTOQUIT == true ]] && exit
}

(( $+functions[compdef] )) && compdef _tmux _zsh_tmux_run
alias tmux=_zsh_tmux_run

function _tmux_directory_session() {
  local directory=${PWD##*/}
  local path_hash=$(printf '%s' "$PWD" | md5sum | cut -d ' ' -f 1)
  local session_name="${directory}-${path_hash[1,6]}"
  tmux new -As "$session_name"
}
alias tds=_tmux_directory_session

function _zsh_tmux_refresh_environment() {
  eval "$(command tmux show-environment -s)"
}

if [[ -z $TMUX && $ZSH_TMUX_AUTOSTART == true && -z $INSIDE_EMACS &&
      -z $EMACS && -z $VIM && -z $INTELLIJ_ENVIRONMENT_READER && -z $ZED_TERM ]]; then
  if [[ $ZSH_TMUX_AUTOSTART_ONCE == false || $ZSH_TMUX_AUTOSTARTED != true ]]; then
    export ZSH_TMUX_AUTOSTARTED=true
    _zsh_tmux_run
  fi
fi

if [[ -n $TMUX && $ZSH_TMUX_AUTOREFRESH == true ]] && command tmux ls >/dev/null 2>&1; then
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _zsh_tmux_refresh_environment
fi
