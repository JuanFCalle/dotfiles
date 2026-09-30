#
# Colors
#
# Ported from https://github.com/wincent/wincent (aspects/dotfiles/files/.zsh/color.zsh).
# Scheme sources (git submodules):
#   - Shell:  ~/.zsh/tinted-shell/scripts/<scheme>.sh
#   - Kitty:  ~/.config/kitty/themes/<scheme>.conf  (-> vendor/tinted-terminal/themes/kitty)
#   - tmux:   ~/.config/tmux/colors/<scheme>.conf   (-> vendor/tinted-tmux/colors)
#

__BUHO[TINTED_CONFIG]=~/.zsh/.tinted

# Takes a hex color in the form of "RRGGBB" and outputs its luma (0-255, where
# 0 is black and 255 is white).
#
# Based on: https://github.com/lencioni/dotfiles/blob/b1632a04/.shells/colors
luma() {
  emulate -L zsh

  local COLOR_HEX=$1

  if [ -z "$COLOR_HEX" ]; then
    echo "Missing argument hex color (RRGGBB)"
    return 1
  fi

  # Extract hex channels from background color (RRGGBB).
  local COLOR_HEX_RED="${COLOR_HEX[1,2]}"
  local COLOR_HEX_GREEN="${COLOR_HEX[3,4]}"
  local COLOR_HEX_BLUE="${COLOR_HEX[5,6]}"

  # Convert hex colors to decimal.
  local COLOR_DEC_RED=$((16#$COLOR_HEX_RED))
  local COLOR_DEC_GREEN=$((16#$COLOR_HEX_GREEN))
  local COLOR_DEC_BLUE=$((16#$COLOR_HEX_BLUE))

  # Calculate perceived brightness of background per ITU-R BT.709
  # https://en.wikipedia.org/wiki/Rec._709#Luma_coefficients
  # http://stackoverflow.com/a/12043228/18986
  local COLOR_LUMA_RED=$((0.2126 * $COLOR_DEC_RED))
  local COLOR_LUMA_GREEN=$((0.7152 * $COLOR_DEC_GREEN))
  local COLOR_LUMA_BLUE=$((0.0722 * $COLOR_DEC_BLUE))

  local COLOR_LUMA=$(($COLOR_LUMA_RED + $COLOR_LUMA_GREEN + $COLOR_LUMA_BLUE))

  echo "$COLOR_LUMA"
}

color() {
  emulate -L zsh

  local SCHEME
  local SHELL_COLORS_DIR=~/.zsh/tinted-shell/scripts
  local TINTED_CONFIG_PREVIOUS="${__BUHO[TINTED_CONFIG]}.previous"
  local STATUS=0

  # Helper function to extract a hex value (eg. "abc0123") from a color scheme
  # and avoid forking:
  #
  #     $(grep ... | cut ... | sed ...)
  #
  # by instead using Zsh parameter expansion.
  __extract() {
    local COLOR=$1
    local FILE=$2
    local HEX=$(grep "^${COLOR}=" "$FILE")

    # Remove up to and including first ".
    HEX=${HEX#*\"}

    # Remove after and including last ".
    HEX=${HEX%\"*}

    # Remove slashes.
    HEX=${HEX//\//}

    echo $HEX
  }

  __color() {
    SCHEME=$1
    local FILE="$SHELL_COLORS_DIR/$SCHEME.sh"
    # A few schemes exist in tinted-shell but not in tinted-terminal/tinted-tmux.
    if [[ -e "$FILE" && -e ~/.config/kitty/themes/$SCHEME.conf && -e ~/.config/tmux/colors/$SCHEME.conf ]]; then
      local BG=$(__extract color_background "$FILE")
      local FG=$(__extract color_foreground "$FILE")
      local BORDER=$(__extract color08 "$FILE")
      local ACCENT=$(__extract color03 "$FILE")
      local CC=$(__extract color18 "$FILE")
      local MESSAGE_BG=$(__extract color19 "$FILE")
      local LABEL_FG=$(__extract color20 "$FILE")
      local MESSAGE_FG=$(__extract color21 "$FILE")
      local VALUE
      for VALUE in "$BG" "$FG" "$BORDER" "$ACCENT"; do
        if ! [[ "$VALUE" =~ '^[[:xdigit:]]{6}$' ]]; then
          print -u2 -- "color: invalid palette value '$VALUE' in $FILE"
          return 1
        fi
      done

      local FULL_PALETTE=1
      if [[ -z "$CC$MESSAGE_BG$LABEL_FG$MESSAGE_FG" ]] && grep -q '^export TINTED8_THEME=' "$FILE"; then
        # ponytail: tinted8 has no extended shades; retain its vendor styles.
        # Exact Wincent palette roles require a full Base16/Base24 scheme.
        FULL_PALETTE=0
        CC=$BORDER
      else
        for VALUE in "$CC" "$MESSAGE_BG" "$LABEL_FG" "$MESSAGE_FG"; do
          if ! [[ "$VALUE" =~ '^[[:xdigit:]]{6}$' ]]; then
            print -u2 -- "color: incomplete or invalid extended palette in $FILE"
            return 1
          fi
        done
      fi

      local LUMA=$(luma "$BG")
      local LIGHT=$((LUMA > 127.5))
      local BACKGROUND=dark
      if [ "$LIGHT" -eq 1 ]; then
        BACKGROUND=light
      fi

      local STAGE
      STAGE=$(mktemp -d "$HOME/.config/tmux/.color.XXXXXXXX") || return 1
      {
        # Stage a copy, never patch through a symlink into vendor/.
        cp ~/.config/tmux/colors/$SCHEME.conf "$STAGE/theme.conf" || return 1

        # ponytail: repair only the known blank tinted8 border/accent fields.
        # New upstream placeholders will need an explicit additional mapping.
        sed -i '' -E \
          -e "s/fg=#\"/fg=#${BORDER}\"/g" \
          -e "s/colour \"#\"/colour \"#${BORDER}\"/g" \
          "$STAGE/theme.conf" || return 1

        cat > "$STAGE/colors.conf" <<EOF || return 1
set -g window-active-style "bg=#$BG"
set -g window-style "bg=#$CC"
set -g pane-active-border-style "fg=#$BORDER,bg=#$CC"
set -g pane-border-style "fg=#$BORDER,bg=#$CC"
EOF
        if (( FULL_PALETTE )); then
          # Wincent uses the extended shades for UI surfaces, not the pane BG.
          cat >> "$STAGE/colors.conf" <<EOF || return 1
set -g status-style "fg=#$LABEL_FG,bg=#$CC"
set -g window-status-style "fg=#$LABEL_FG,bg=#$CC"
set -g window-status-current-style "fg=#$ACCENT,bg=#$CC"
set -g window-status-activity-style "fg=#$FG,bg=#$CC"
set -g message-style "fg=#$MESSAGE_FG,bg=#$MESSAGE_BG"
set -g message-command-style "fg=#$MESSAGE_FG,bg=#$MESSAGE_BG"
set -g mode-style "fg=#$LABEL_FG,bg=#$MESSAGE_BG"
EOF
        fi

        if [ -e "$__BUHO[TINTED_CONFIG]" ]; then
          cp "$__BUHO[TINTED_CONFIG]" "$TINTED_CONFIG_PREVIOUS" || return 1
        fi
        mv -f "$STAGE/theme.conf" ~/.config/tmux/theme.conf || return 1
        mv -f "$STAGE/colors.conf" ~/.config/tmux/colors.conf || return 1
        ln -sf "themes/$SCHEME.conf" ~/.config/kitty/colors.conf || return 1
        printf '%s\n%s\n' "$SCHEME" "$BACKGROUND" >! "$__BUHO[TINTED_CONFIG]" || return 1
        sh "$FILE" || return 1

        local KITTY_ADDRESS=$KITTY_LISTEN_ON KITTY_ID=$KITTY_WINDOW_ID
        local KITTY_ERROR= APPLY_STATUS=0
        if [[ -n "$TMUX" ]]; then
          # ponytail: one Kitty client per session; shared clients need explicit routing.
          local SESSION SESSION_ENV ENTRY KITTY_METADATA=0
          KITTY_ADDRESS=
          KITTY_ID=
          if SESSION=$(command tmux display-message -p -t "${TMUX_PANE:-}" '#{session_id}') &&
              SESSION_ENV=$(command tmux show-environment -t "$SESSION"); then
            for ENTRY in "${(@f)SESSION_ENV}"; do
              case "$ENTRY" in
                KITTY_LISTEN_ON=*) KITTY_ADDRESS=${ENTRY#*=}; KITTY_METADATA=1 ;;
                KITTY_WINDOW_ID=*) KITTY_ID=${ENTRY#*=}; KITTY_METADATA=1 ;;
                -KITTY_LISTEN_ON|-KITTY_WINDOW_ID) KITTY_METADATA=1 ;;
              esac
            done
            if (( ! KITTY_METADATA )) && [[ -n "$KITTY_LISTEN_ON$KITTY_WINDOW_ID" ]]; then
              KITTY_ERROR="Kitty metadata has not been refreshed in this tmux session"
            fi
          else
            KITTY_ERROR="cannot read the current tmux session's Kitty environment"
          fi
        fi

        if [[ -z "$KITTY_ERROR" && -n "$KITTY_ADDRESS$KITTY_ID" ]]; then
          if [[ -z "$KITTY_ADDRESS" || -z "$KITTY_ID" ]]; then
            KITTY_ERROR="incomplete Kitty connection metadata"
          elif [[ "$KITTY_ADDRESS" == unix:/* && ! -S "${KITTY_ADDRESS#unix:}" ]]; then
            KITTY_ERROR="Kitty socket does not exist: $KITTY_ADDRESS"
          elif ! command kitten @ --to "$KITTY_ADDRESS" set-colors --all --configured ~/.config/kitty/colors.conf; then
            KITTY_ERROR="Kitty remote-control command failed"
          fi
        fi
        if [[ -n "$KITTY_ERROR" ]]; then
          print -u2 -- "color: $KITTY_ERROR; theme saved, but Kitty was not updated."
          print -u2 -- "color: check Kitty's listener; in tmux, reload tmux.conf and reattach from a current Kitty shell."
          APPLY_STATUS=1
        fi

        if [ -n "$TMUX" ]; then
          command tmux set-environment -g TINTED_TMUX_OPTION_STATUSBAR 0 \; \
            set-environment -g BASE16_TMUX_OPTION_STATUSBAR 0 \; \
            source-file "$HOME/.config/tmux/theme.conf" \; \
            source-file "$HOME/.config/tmux/colors.conf" || APPLY_STATUS=1
        fi
        return "$APPLY_STATUS"
      } always {
        rm -f -- "$STAGE/theme.conf" "$STAGE/colors.conf"
        rmdir -- "$STAGE"
      }
    else
      print -u2 -- "Scheme '$SCHEME' not found (need $SHELL_COLORS_DIR/$SCHEME.sh plus Kitty and tmux themes)"
      return 1
    fi
  }

  zparseopts -D -E -- q=QUIET -quiet=QUIET

  if [ $# -eq 0 ]; then
    if [ -s "$__BUHO[TINTED_CONFIG]" ]; then
      cat "$__BUHO[TINTED_CONFIG]"
      SCHEME=$(head -1 "$__BUHO[TINTED_CONFIG]")
      __color "$SCHEME" || STATUS=$?
      unfunction __color __extract
      return $STATUS
    else
      SCHEME=help
    fi
  else
    SCHEME=$1
  fi

  local ALL_SCHEMES=($(find "$SHELL_COLORS_DIR" -name '*.sh' | \
        sed -E 's|.+/||' | \
        sed -E 's/\.sh//' | \
        grep "${2:-.}" | \
        sort
        ))

  case "$SCHEME" in
  help)
    echo 'color                                                     (show current scheme)'
    echo 'color base16-bright|base16-solarized-light|...           (switch to scheme)'
    echo 'color help                                                (show this help)'
    echo 'color ls [pattern]                                        (list available schemes)'
    echo 'color rand [-q/--quiet] [pattern]                         (choose a random scheme)'
    echo 'color -                                                   (switch to previous scheme)'
    ;;
  ls)
    printf '%s\n' "${ALL_SCHEMES[@]}" | \
      column
      ;;
  rand)
    local RANDOM_COLOR=${ALL_SCHEMES[$(($RANDOM % ${#ALL_SCHEMES[@]} + 1))]}
    if [[ ${#QUIET} -eq 0 ]]; then
      echo "$RANDOM_COLOR"
    fi
    __color "$RANDOM_COLOR" || STATUS=$?
    ;;
  -)
    if [[ -s "$TINTED_CONFIG_PREVIOUS" ]]; then
      local PREVIOUS_SCHEME=$(head -1 "$TINTED_CONFIG_PREVIOUS")
      __color "$PREVIOUS_SCHEME" || STATUS=$?
    else
      echo "warning: no previous config found at $TINTED_CONFIG_PREVIOUS"
      STATUS=1
    fi
    ;;
  *)
    __color "$SCHEME" || STATUS=$?
    ;;
  esac

  unfunction __color __extract
  return $STATUS
}

function () {
  emulate -L zsh

  if [[ $SHLVL -eq 1 || ! -s ~/.config/tmux/colors.conf ]]; then
    # New terminal window, or haven't written tmux config yet.
    if [[ -s "$__BUHO[TINTED_CONFIG]" ]]; then
      local SCHEME=$(head -1 "$__BUHO[TINTED_CONFIG]")
      local BACKGROUND=$(sed -n -e '2 p' "$__BUHO[TINTED_CONFIG]")
      if [ "$BACKGROUND" != 'dark' -a "$BACKGROUND" != 'light' ]; then
        echo "warning: unknown background type in $__BUHO[TINTED_CONFIG]"
      fi
      color "$SCHEME"
    else
      # Default.
      color base16-bright
    fi
  fi
}
