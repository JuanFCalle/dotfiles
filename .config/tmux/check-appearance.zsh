#!/bin/zsh -f
emulate -LR zsh
setopt ERR_EXIT PIPE_FAIL

ROOT=${0:A:h:h:h}
WORK=$(mktemp -d /tmp/tmux-appearance.XXXXXXXX)
SOCKET=$WORK/tmux.sock
typeset -i checks=0
exec 3>&2 2>"$WORK/errors"

cleanup() {
  local result=$?
  if [[ -S "$SOCKET" ]]; then
    tmux -S "$SOCKET" kill-server
  fi
  if [[ -s "$WORK/errors" ]]; then
    cat "$WORK/errors" >&3
    result=1
  fi
  # Only the allocated test tree; never follow its links into the repository.
  find -P "$WORK" -depth -type f -delete -o -type l -delete -o -type s -delete
  find -P "$WORK" -depth -type d -empty -delete
  return "$result"
}
trap cleanup EXIT

export HOME=$WORK/home ZDOTDIR=$WORK/home TERM=xterm-kitty TTY=/dev/null
unset TMUX TMUX_PANE KITTY_WINDOW_ID KITTY_LISTEN_ON
mkdir -p "$HOME/.config/tmux" "$HOME/.config/kitty" "$HOME/.zsh/tinted-shell/scripts" "$WORK/bin"
cp "$ROOT/.config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
cp "$ROOT/.config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
ln -s "$ROOT/vendor/tinted-tmux/colors" "$HOME/.config/tmux/colors"
ln -s "$ROOT/vendor/tinted-terminal/themes/kitty" "$HOME/.config/kitty/themes"
for scheme in base16-aztec base16-bright base16-solarized-light tinted8-gruvbox-dark; do
  ln -s "$ROOT/.zsh/tinted-shell/scripts/$scheme.sh" "$HOME/.zsh/tinted-shell/scripts/$scheme.sh"
done

# Never let a regression invoke the real Kitty remote-control client.
export COLOR_TEST_ARGS="$WORK/kitten-args" COLOR_TEST_STATUS=0
: > "$COLOR_TEST_ARGS"
cat > "$WORK/bin/kitten" <<'EOF'
#!/bin/zsh -f
printf '%s\n' "$@" >> "$COLOR_TEST_ARGS"
address=$KITTY_LISTEN_ON
[[ "$1" == @ && "$2" == --to ]] && address=$3
if [[ "$address" == unix:/* && ! -S "${address#unix:}" ]]; then
  print -u2 -- "test kitten: missing socket $address"
  exit 1
fi
if (( COLOR_TEST_STATUS )); then
  print -u2 -- 'test kitten: simulated connection failure'
fi
exit "$COLOR_TEST_STATUS"
EOF
chmod +x "$WORK/bin/kitten"
export PATH="$WORK/bin:$PATH"

eq() {
  if [[ "$2" != "$3" ]]; then
    print -u2 -r -- "FAIL: $1 (after $checks passing assertions)"
    print -u2 -r -- "expected: ${(qqq)3}"
    print -u2 -r -- "actual:   ${(qqq)2}"
    exit 1
  fi
  (( ++checks ))
}

t() { command tmux -S "$SOCKET" "$@"; }
option() { t show-options -gv "$1"; }
start_server() {
  t -f /dev/null new-session -d -s appearance -n shell -x 100 -y 30 /bin/cat
  export TMUX="$SOCKET,$(t display-message -p '#{pid}'),0"
  export TMUX_PANE=$(t display-message -p -t appearance '#{pane_id}')
  t set-option -ag update-environment COLOR_TEST_PRESERVED
  UPDATE_ENV_BEFORE=$(option update-environment)
  t source-file "$HOME/.config/tmux/tmux.conf" 2> "$WORK/load-errors"
  eq 'configuration loads without errors' "$(cat "$WORK/load-errors")" ''
  eq 'Kitty refresh preserves existing entries' "$(option update-environment)" "$UPDATE_ENV_BEFORE"$'\nKITTY_LISTEN_ON\nKITTY_WINDOW_ID'
  t move-window -r -t appearance
}

typeset -A __BUHO
zmodload zsh/zutil
eq 'test PATH resolves remote-control stub' "$(command -v kitten)" "$WORK/bin/kitten"
source "$ROOT/.zsh/color.zsh"
eq 'first-run default' "$(cat "$HOME/.zsh/.tinted")" $'base16-bright\ndark'
start_server

layout() {
  eq status "$(option status)" on
  eq position "$(option status-position)" bottom
  eq justification "$(option status-justify)" left
  eq left-limit "$(option status-left-length)" 40
  eq right-limit "$(option status-right-length)" 40
  eq interval "$(option status-interval)" 60
  eq left "$(option status-left)" '#[fg=yellow,bold,italics]#{session_name} § '
  eq right "$(option status-right)" "#[fg=yellow,bold,italics]$USER@#{host_short} #[fg=magenta]%l:%M %p"
  eq active-format "$(option window-status-current-format)" '#[reverse] #{window_index}:#{window_name}#{window_flags} '
  eq inactive-format "$(option window-status-format)" ' #{window_index}:#{window_name}#{?#{==:#{window_flags},},  ,#{window_flags} }'
  eq separator "$(option window-status-separator)" ' '
  eq border "$(option pane-border-status)" bottom
  eq border-lines "$(option pane-border-lines)" single
  eq prefix "$(option prefix)" C-b
  eq history "$(option history-limit)" 10000
  eq mouse "$(option mouse)" on
  eq numbering "$(option base-index)" 1
  eq titles "$(option set-titles-string)" '#{session_name} • #{pane_title}'
  eq passthrough "$(option allow-passthrough)" all
  eq 'vendor layout disabled' "$(t show-environment -g TINTED_TMUX_OPTION_STATUSBAR)" TINTED_TMUX_OPTION_STATUSBAR=0
  eq 'legacy layout disabled' "$(t show-environment -g BASE16_TMUX_OPTION_STATUSBAR)" BASE16_TMUX_OPTION_STATUSBAR=0
}

palette() {
  local bg=$1 surface=$2 message=$3 label=$4 fg=$5 message_fg=$6 accent=$7 border=$8 blue=$9 red=${10}
  local name expected
  local -A styles=(
    status-style "fg=$label,bg=$surface"
    window-status-style "fg=$label,bg=$surface"
    window-status-current-style "fg=$accent,bg=$surface"
    window-status-activity-style "fg=$fg,bg=$surface"
    message-style "fg=$message_fg,bg=$message"
    message-command-style "fg=$message_fg,bg=$message"
    mode-style "fg=$label,bg=$message"
    window-active-style "bg=$bg"
    window-style "bg=$surface"
    pane-border-style "fg=$border,bg=$surface"
    pane-active-border-style "fg=$border,bg=$surface"
    display-panes-active-colour "$label"
    display-panes-colour "$surface"
    clock-mode-colour "$blue"
    window-status-bell-style "fg=$bg,bg=$red"
  )
  for name expected in "${(@kv)styles}"; do
    eq "$name" "$(option "$name")" "$expected"
  done
}

bright() {
  palette '#000000' '#303030' '#505050' '#d0d0d0' '#e0e0e0' '#f5f5f5' '#fda331' '#b0b0b0' '#6fb3d2' '#fb0120'
}

layout
bright
keys=$(t list-keys)
eq 'non-Kitty startup makes no remote calls' "$(cat "$COLOR_TEST_ARGS")" ''

zmodload zsh/net/socket
zsocket -l "$WORK/kitty current.sock"
CURRENT_FD=$REPLY
zsocket -l "$WORK/kitty next.sock"
NEXT_FD=$REPLY
export KITTY_LISTEN_ON="unix:$WORK/kitty old.sock" KITTY_WINDOW_ID=1
t set-environment -g KITTY_LISTEN_ON "$KITTY_LISTEN_ON"
t set-environment -g KITTY_WINDOW_ID "$KITTY_WINDOW_ID"
attach_kitty() {
  printf 'detach-client\n' | env -u TMUX -u TMUX_PANE KITTY_LISTEN_ON="$1" KITTY_WINDOW_ID=2 \
    tmux -S "$SOCKET" -C attach-session -t appearance > "$WORK/attach-output"
}
attach_kitty "unix:$WORK/kitty current.sock"
eq 'attachment refreshes session socket' "$(t show-environment -t appearance KITTY_LISTEN_ON)" "KITTY_LISTEN_ON=unix:$WORK/kitty current.sock"
eq 'attachment refreshes window ID' "$(t show-environment -t appearance KITTY_WINDOW_ID)" KITTY_WINDOW_ID=2
t new-session -d -s unrelated /bin/cat
t set-environment -t unrelated KITTY_LISTEN_ON "unix:$WORK/wrong-session.sock"
t set-environment -t unrelated KITTY_WINDOW_ID 3
eq 'remote control resolves to test stub' "$(command -v kitten)" "$WORK/bin/kitten"
color base16-aztec
eq 'stale pane uses its own session socket' "$(cat "$COLOR_TEST_ARGS")" "$(printf '%s\n' @ --to "unix:$WORK/kitty current.sock" set-colors --all --configured "$HOME/.config/kitty/colors.conf")"
eq 'Aztec saved selection' "$(cat "$HOME/.zsh/.tinted")" $'base16-aztec\ndark'
eq 'Aztec Kitty selection' "$(readlink "$HOME/.config/kitty/colors.conf")" themes/base16-aztec.conf
palette '#101600' '#1a1e01' '#242604' '#ffd129' '#ffda51' '#ffe178' '#eebb00' '#2e2e05' '#5b4a9f' '#ee2e00'
eq 'caller environment is not rewritten' "$KITTY_LISTEN_ON/$KITTY_WINDOW_ID" "unix:$WORK/kitty old.sock/1"
t kill-session -t unrelated

zsocket -l "$WORK/kitty old.sock"
OLD_FD=$REPLY
attach_kitty "unix:$WORK/kitty next.sock"
: > "$COLOR_TEST_ARGS"
color base16-aztec
eq 'reattachment wins even when inherited socket exists' "$(cat "$COLOR_TEST_ARGS")" "$(printf '%s\n' @ --to "unix:$WORK/kitty next.sock" set-colors --all --configured "$HOME/.config/kitty/colors.conf")"
t new-window -d -t appearance -n metadata /bin/sh -c 'printf "%s\n%s\n" "$KITTY_LISTEN_ON" "$KITTY_WINDOW_ID" > "$HOME/kitty-child-env"; tmux wait-for -S kitty-child-ready'
t wait-for kitty-child-ready
eq 'new panes inherit refreshed metadata' "$(cat "$HOME/kitty-child-env")" "unix:$WORK/kitty next.sock"$'\n2'

t set-environment -t appearance KITTY_LISTEN_ON "unix:$WORK/missing.sock"
: > "$COLOR_TEST_ARGS"
result=0
color base16-solarized-light 2> "$WORK/expected-error" || result=$?
eq 'missing socket returns failure' "$result" 1
eq 'missing socket avoids remote call' "$(cat "$COLOR_TEST_ARGS")" ''
eq 'missing socket reports saved-but-incomplete update' "$([[ $(cat "$WORK/expected-error") == *"Kitty socket does not exist: unix:$WORK/missing.sock; theme saved, but Kitty was not updated."* ]] && print yes)" yes
eq 'missing socket still saves selection' "$(cat "$HOME/.zsh/.tinted")" $'base16-solarized-light\nlight'
palette '#fdf6e3' '#eee8d5' '#93a1a1' '#657b83' '#586e75' '#073642' '#b58900' '#839496' '#268bd2' '#dc322f'
result=0
color - 2> "$WORK/expected-error" || result=$?
eq 'previous-theme dispatch preserves failure' "$result" 1
eq 'previous theme still saved' "$(cat "$HOME/.zsh/.tinted")" $'base16-aztec\ndark'
eq 'previous theme still applied to tmux' "$(option window-active-style)" bg=#101600
result=0
color > "$WORK/current-theme" 2> "$WORK/expected-error" || result=$?
eq 'no-argument dispatch preserves failure' "$result" 1
eq 'no-argument dispatch still prints selection' "$(cat "$WORK/current-theme")" $'base16-aztec\ndark'
result=0
color rand -q aztec 2> "$WORK/expected-error" || result=$?
eq 'random-theme dispatch preserves failure' "$result" 1

t set-environment -t appearance KITTY_LISTEN_ON "unix:$WORK/kitty current.sock"
export COLOR_TEST_STATUS=7
result=0
color base16-solarized-light 2> "$WORK/expected-error" || result=$?
eq 'remote failure returns failure' "$result" 1
eq 'remote failure retains underlying diagnostic' "$([[ $(cat "$WORK/expected-error") == *'test kitten: simulated connection failure'* ]] && print yes)" yes
eq 'remote failure reports incomplete update' "$([[ $(cat "$WORK/expected-error") == *'theme saved, but Kitty was not updated.'* ]] && print yes)" yes
eq 'remote failure still updates tmux' "$(option window-active-style)" bg=#fdf6e3
export COLOR_TEST_STATUS=0

t set-environment -u -t appearance KITTY_LISTEN_ON
t set-environment -u -t appearance KITTY_WINDOW_ID
: > "$COLOR_TEST_ARGS"
result=0
color base16-bright 2> "$WORK/expected-error" || result=$?
eq 'unsynchronized Kitty session returns failure' "$result" 1
eq 'unsynchronized session gives recovery instructions' "$([[ $(cat "$WORK/expected-error") == *'reattach from a current Kitty shell'* ]] && print yes)" yes
eq 'unsynchronized session never falls back to global or pane socket' "$(cat "$COLOR_TEST_ARGS")" ''
bright

printf 'detach-client\n' | env -u TMUX -u TMUX_PANE -u KITTY_LISTEN_ON -u KITTY_WINDOW_ID \
  tmux -S "$SOCKET" -C attach-session -t appearance > "$WORK/attach-output"
eq 'non-Kitty attachment removes socket metadata' "$(t show-environment -t appearance KITTY_LISTEN_ON)" -KITTY_LISTEN_ON
eq 'non-Kitty attachment removes window metadata' "$(t show-environment -t appearance KITTY_WINDOW_ID)" -KITTY_WINDOW_ID
color base16-bright
eq 'removed metadata never uses inherited socket' "$(cat "$COLOR_TEST_ARGS")" ''
t set-environment -t appearance KITTY_LISTEN_ON ''
t set-environment -t appearance KITTY_WINDOW_ID ''
color base16-bright
eq 'empty metadata never uses inherited socket' "$(cat "$COLOR_TEST_ARGS")" ''
t set-environment -t appearance KITTY_WINDOW_ID 2
result=0
color base16-bright 2> "$WORK/expected-error" || result=$?
eq 'incomplete metadata returns failure' "$result" 1
eq 'incomplete metadata is diagnosed' "$([[ $(cat "$WORK/expected-error") == *'incomplete Kitty connection metadata'* ]] && print yes)" yes
eq 'incomplete metadata makes no remote call' "$(cat "$COLOR_TEST_ARGS")" ''
t set-environment -r -t appearance KITTY_WINDOW_ID
t set-environment -gu KITTY_LISTEN_ON
t set-environment -gu KITTY_WINDOW_ID

(
  unset TMUX TMUX_PANE
  export KITTY_LISTEN_ON="unix:$WORK/kitty current.sock"
  color base16-bright
)
eq 'plain Kitty uses its exported address' "$(cat "$COLOR_TEST_ARGS")" "$(printf '%s\n' @ --to "unix:$WORK/kitty current.sock" set-colors --all --configured "$HOME/.config/kitty/colors.conf")"
: > "$COLOR_TEST_ARGS"
(
  unset TMUX TMUX_PANE
  export KITTY_LISTEN_ON=tcp:localhost:65432
  color base16-bright
)
eq 'non-filesystem address is passed to Kitty without a file check' "$(cat "$COLOR_TEST_ARGS")" "$(printf '%s\n' @ --to tcp:localhost:65432 set-colors --all --configured "$HOME/.config/kitty/colors.conf")"
exec {CURRENT_FD}>&- {NEXT_FD}>&- {OLD_FD}>&-
unset KITTY_LISTEN_ON KITTY_WINDOW_ID
: > "$COLOR_TEST_ARGS"

color base16-solarized-light
eq 'light state' "$(cat "$HOME/.zsh/.tinted")" $'base16-solarized-light\nlight'
eq 'Kitty light selection' "$(readlink "$HOME/.config/kitty/colors.conf")" themes/base16-solarized-light.conf
palette '#fdf6e3' '#eee8d5' '#93a1a1' '#657b83' '#586e75' '#073642' '#b58900' '#839496' '#268bd2' '#dc322f'
color -
bright
eq 'previous scheme' "$(cat "$HOME/.zsh/.tinted")" $'base16-bright\ndark'

t set-environment -g TINTED_TMUX_OPTION_STATUSBAR 1
t set-environment -g BASE16_TMUX_OPTION_STATUSBAR 1
color base16-bright
layout
for repeat in 1 2; do
  t source-file "$HOME/.config/tmux/tmux.conf"
  bright
  eq 'Kitty refresh entries do not duplicate on reload' "$(option update-environment)" "$UPDATE_ENV_BEFORE"$'\nKITTY_LISTEN_ON\nKITTY_WINDOW_ID'
done
eq 'bindings survive switching/reloading' "$(t list-keys)" "$keys"

t new-window -d -n idle /bin/cat
t new-window -d -n idle2 /bin/cat
eq 'active label width' "$(t display-message -p -t appearance:1 '#{E:window-status-current-format}')" '#[reverse] 1:shell* '
eq 'inactive label padding' "$(t display-message -p -t appearance:2 '#{E:window-status-format}')" ' 2:idle  '
t split-window -d -t appearance:1 /bin/cat
t resize-pane -Z -t appearance:1.1
eq 'zoom label' "$(t display-message -p -t appearance:1 '#{E:window-status-current-format}')" '#[reverse] 1:shell*Z '
t resize-pane -Z -t appearance:1.1
t select-window -t appearance:2
eq 'last-window flag spacing' "$(t display-message -p -t appearance:1 '#{E:window-status-format}')" ' 1:shell- '
t select-window -t appearance:1

t respawn-pane -k -t appearance:1.1 /bin/sh -c 'printf "single-match\nrepeat-match\nrepeat-match\n"; tmux wait-for -S appearance-ready; exec /bin/cat'
t wait-for appearance-ready
t copy-mode -t appearance:1.1
eq 'copy mode entered' "$(t display-message -p -t appearance:1.1 '#{pane_mode}')" copy-mode
copy_format=$(t display-message -p -t appearance:1.1 '#{E:pane-border-format}')
eq 'copy marker shown' "$([[ $copy_format == '#[align=left,fg=green,bg=black]  -- COPY --  #[default]'* ]] && print yes)" yes
t send-keys -t appearance:1.1 -X search-backward single-match
eq 'singular search count' "$(t display-message -p -t appearance:1.1 '#{search_count}')" 1
search_display=$(t display-message -p -t appearance:1.1 '#{E:pane-border-format}')
eq "singular label in $search_display (present=$(t display-message -p -t appearance:1.1 '#{search_present}'))" "$([[ $search_display == *'(1 result)'* ]] && print yes)" yes
t send-keys -t appearance:1.1 -X history-bottom
t send-keys -t appearance:1.1 -X search-backward repeat-match
eq 'plural search count' "$(t display-message -p -t appearance:1.1 '#{search_count}')" 2
eq 'plural label present' "$([[ $(t display-message -p -t appearance:1.1 '#{E:pane-border-format}') == *'(2 results)'* ]] && print yes)" yes
t send-keys -t appearance:1.1 -X search-backward no-match-here
eq 'no misleading search count' "$([[ $(t display-message -p -t appearance:1.1 '#{E:pane-border-format}') != *'result'* ]] && print yes)" yes
t send-keys -t appearance:1.1 -X cancel
eq 'normal mode border is empty' "$(t display-message -p -t appearance:1.1 '#{E:pane-border-format}')" ''

vendor_before=$(cksum "$ROOT/vendor/tinted-tmux/colors/tinted8-gruvbox-dark.conf")
color tinted8-gruvbox-dark
eq 'reduced palette status' "$(option status-style)" 'fg=#ebdbb2,bg=#282828'
eq 'reduced palette border' "$(option pane-border-style)" 'fg=#3c3836,bg=#3c3836'
eq 'repaired reduced palette field' "$(option display-panes-active-colour)" '#3c3836'
eq 'vendor not modified' "$(cksum "$ROOT/vendor/tinted-tmux/colors/tinted8-gruvbox-dark.conf")" "$vendor_before"
color base16-bright

saved=$(cksum "$HOME/.zsh/.tinted" "$HOME/.config/tmux/theme.conf" "$HOME/.config/tmux/colors.conf")
result=0
color missing-scheme 2> "$WORK/expected-error" || result=$?
eq 'missing theme fails' "$result" 1
eq 'missing theme reports error' "$([[ -s "$WORK/expected-error" ]] && print yes)" yes
eq 'missing theme preserves files' "$(cksum "$HOME/.zsh/.tinted" "$HOME/.config/tmux/theme.conf" "$HOME/.config/tmux/colors.conf")" "$saved"
# Replace only a test-owned link, then corrupt the copied palette.
rm "$HOME/.zsh/tinted-shell/scripts/base16-bright.sh"
sed 's|color18="30/30/30"|color18="invalid"|' "$ROOT/.zsh/tinted-shell/scripts/base16-bright.sh" > "$HOME/.zsh/tinted-shell/scripts/base16-bright.sh"
result=0
color base16-bright 2> "$WORK/expected-error" || result=$?
eq 'invalid palette fails' "$result" 1
eq 'invalid palette reports error' "$([[ -s "$WORK/expected-error" ]] && print yes)" yes
eq 'invalid palette preserves files' "$(cksum "$HOME/.zsh/.tinted" "$HOME/.config/tmux/theme.conf" "$HOME/.config/tmux/colors.conf")" "$saved"
sed '/^color1[89]=/d; /^color2[01]=/d' "$ROOT/.zsh/tinted-shell/scripts/base16-bright.sh" > "$HOME/.zsh/tinted-shell/scripts/base16-bright.sh"
result=0
color base16-bright 2> "$WORK/expected-error" || result=$?
eq 'broken full palette is not treated as tinted8' "$result" 1
eq 'missing extended palette preserves files' "$(cksum "$HOME/.zsh/.tinted" "$HOME/.config/tmux/theme.conf" "$HOME/.config/tmux/colors.conf")" "$saved"

t kill-server
unset TMUX TMUX_PANE
start_server
layout
bright

kitty_result=$(kitty +runpy '
import os
from kitty.config import load_config
from kitty.fonts.common import get_font_files

errors = []
actual = load_config(os.path.expanduser("~/.config/kitty/kitty.conf"), accumulate_bad_lines=errors)
assert not errors, errors
settings = [
    "font_size 14.0", "disable_ligatures always",
    "font_features SourceCodePro-ExtraLight -liga", "font_features SourceCodePro-Medium -liga",
    "font_features SourceCodePro-ExtraLightItalic -liga", "font_features SourceCodePro-MediumItalic -liga",
    "modify_font underline_position 2", "modify_font cell_height 2px",
    "undercurl_style thick-sparse", "url_style double",
    "window_padding_width 0", "placement_strategy top",
    "tab_bar_edge top", "tab_bar_margin_height 0.0 1.0",
    "tab_bar_style powerline", "inactive_tab_font_style italic",
    "hide_window_decorations yes",
    "allow_remote_control socket-only", "shell_integration disabled",
    "background #000000", "foreground #e0e0e0",
]
expected = load_config(overrides=settings)
for name in {line.split()[0] for line in settings}:
    assert getattr(actual, name) == getattr(expected, name), name
assert actual.tab_title_template == "  {fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{tab.last_focused_progress_percent}{title}  "
assert actual.active_tab_title_template == "  {fmt.bold}{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{tab.last_focused_progress_percent}{title}{fmt.nobold}  "
fonts = get_font_files(actual)
for role, face in {
    "medium": "ExtraLight", "bold": "Medium",
    "italic": "ExtraLightItalic", "bi": "MediumItalic",
}.items():
    assert fonts[role]["family"] == "Source Code Pro", (role, fonts[role])
    assert fonts[role]["postscript_name"] == "SourceCodePro-" + face, (role, fonts[role])
print("Kitty appearance and four font faces match")
')
eq 'Kitty configuration and fonts' "$kitty_result" 'Kitty appearance and four font faces match'
eq 'non-Kitty checks never invoke remote control' "$(cat "$COLOR_TEST_ARGS")" ''
eq 'no unexpected warnings or errors' "$(cat "$WORK/errors")" ''

print -- "PASS: $checks assertions; 0 failed, 0 skipped."
