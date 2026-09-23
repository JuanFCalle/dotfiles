# Color theme (Kitty + tmux)

The `color` zsh function (`.zsh/color.zsh`) switches the color scheme of the shell, **Kitty** and **tmux** in one go and remembers the choice across new shells, Kitty restarts and new tmux servers.

It is a port of [wincent's `color()`](https://github.com/wincent/wincent/blob/main/aspects/dotfiles/files/.zsh/color.zsh), limited to Kitty and tmux. Vim/Nvim integration is planned but not done yet.

Schemes come from three [tinted-theming](https://github.com/tinted-theming) git submodules that use the same file names, so a single scheme ID (for example `base16-default-dark`) works everywhere:

| Submodule | Path in repo | Provides |
| --- | --- | --- |
| [tinted-shell](https://github.com/tinted-theming/tinted-shell) | `.zsh/tinted-shell` | `scripts/<scheme>.sh`: sets the terminal palette with OSC escapes; also the source of the background color used for light/dark detection |
| [tinted-terminal](https://github.com/tinted-theming/tinted-terminal) | `vendor/tinted-terminal` | `themes/kitty/<scheme>.conf`: Kitty themes |
| [tinted-tmux](https://github.com/tinted-theming/tinted-tmux) | `vendor/tinted-tmux` | `colors/<scheme>.conf`: tmux status bar, border and message styles |

Scheme IDs are the file names without the extension, prefixed `base16-` or `base24-`. That gives 544 usable schemes.

---

## Changes

Changes made when migrating from the old base16-shell/iTerm setup.

### Added

| Path | Purpose |
| --- | --- |
| `.zsh/color.zsh` | The `luma` and `color` functions, plus a startup hook |
| `.zsh/tinted-shell` | Submodule (shallow) |
| `vendor/tinted-terminal` | Submodule (shallow) |
| `vendor/tinted-tmux` | Submodule (shallow) |
| `.config/kitty/kitty.conf` | Minimal Kitty config: turns on remote control and includes the default theme and `colors.conf` |
| `.config/kitty/themes` | Symlink → `../../vendor/tinted-terminal/themes/kitty` |
| `.config/tmux/colors` | Symlink → `../../vendor/tinted-tmux/colors` |
| `docs/COLOR_THEME.md` | This document |

### Moved

| From | To | Notes |
| --- | --- | --- |
| `.tmux.conf` | `.config/tmux/tmux.conf` | XDG location, read by tmux ≥ 3.1. Two lines were appended at the end: `source-file -q ~/.config/tmux/theme.conf` and `source-file -q ~/.config/tmux/colors.conf` |

### Removed

| Path | Reason |
| --- | --- |
| `.zsh/colors` | Old base16-shell `color()`. It was no longer sourced and depended on an undefined `$__BASE16_CONFIG` |
| `.zsh/base16-shell/base16-shell` (submodule) | Replaced by tinted-shell |
| `vendor/base16-iterm2` (submodule) | iTerm is no longer used for theming |

### Modified

| Path | Change |
| --- | --- |
| `.zshrc` | `typeset -A __BUHO` in the GLOBAL block; `source $HOME/.zsh/color.zsh` in the SOURCE block. `__STASHINGVARS` is unchanged |
| `.gitmodules` | Added the 3 tinted submodules (`shallow = true`); removed the base16-shell/base16-iterm2 entries, including the ones keyed by absolute paths |
| `.gitignore` | Ignores the generated state files (see below) |

### Renames

wincent's `__WINCENT` associative array became `__BUHO`. The only key used is `__BUHO[TINTED_CONFIG]`, the path of the saved-scheme file.

### Outside the repo

| Path | Now |
| --- | --- |
| `~/.config/kitty` | Symlink → `~/code/dotfiles/.config/kitty` (replaces an empty `kitty.conf`) |
| `~/.config/tmux` | Symlink → `~/code/dotfiles/.config/tmux` |
| `~/.zsh` | Unchanged (already a symlink → `~/code/dotfiles/.zsh`) |

### Generated files (gitignored)

`color` writes these files. They land inside the repo because the directories are symlinked there:

| File | Content |
| --- | --- |
| `.zsh/.tinted` | Line 1: scheme ID, line 2: `dark` or `light` |
| `.zsh/.tinted.previous` | Previous `.tinted`, used by `color -` |
| `.config/kitty/colors.conf` | Symlink → `themes/<scheme>.conf` |
| `.config/tmux/theme.conf` | Symlink → `colors/<scheme>.conf` |
| `.config/tmux/colors.conf` | Window and pane background overrides derived from the scheme |

---

## How it works

### `color <scheme>` step by step

1. **Validate.** Check that all three files exist: `~/.zsh/tinted-shell/scripts/<scheme>.sh`, `~/.config/kitty/themes/<scheme>.conf` and `~/.config/tmux/colors/<scheme>.conf`. If any is missing, it prints an error and returns 1.
2. **Detect light/dark.** Read `color_background` from the shell script and compute its luma (ITU-R BT.709, 0–255) with `luma`. A luma above 127.5 counts as `light`, anything else as `dark`.
3. **Save state.** Copy `~/.zsh/.tinted` to `~/.zsh/.tinted.previous`, then write the scheme ID and `dark`/`light` to `~/.zsh/.tinted`.
4. **Recolor the current terminal.** Run `sh <scheme>.sh`, which sends OSC escape sequences for the palette, foreground, background and cursor. It wraps them in DCS passthrough when inside tmux.
5. **Point the symlinks at the new scheme:**
   - `~/.config/kitty/colors.conf` → `themes/<scheme>.conf`
   - `~/.config/tmux/theme.conf` → `colors/<scheme>.conf`
6. **Kitty live update.** If `$KITTY_WINDOW_ID` and `$KITTY_LISTEN_ON` are set and `kitten` is on `PATH`, it runs:
   ```sh
   kitten @ set-colors --all --configured ~/.config/kitty/colors.conf
   ```
   `--all` recolors every window. `--configured` also changes the configured colors, so windows opened later use the new scheme.
7. **tmux live update** (only when `$TMUX` is set):
   - `tmux source-file ~/.config/tmux/theme.conf` updates the status bar, borders and messages.
   - It then reads `color18` (base01) and `color08` (base03) from the scheme script and sets:
     - `window-active-style bg=<background>`
     - `window-style bg=<color18>` (inactive panes get a slightly different background)
     - `pane-active-border-style` / `pane-border-style bg=<color18>,fg=<color08>`
8. **Persist the tmux overrides.** The same window and pane styles are written to `~/.config/tmux/colors.conf`, so new tmux servers pick them up.

### How the settings survive restarts

| Tool | Mechanism |
| --- | --- |
| Shell | The startup hook re-runs `color <saved scheme>` (see below) |
| Kitty | `kitty.conf` does `include themes/base16-default-dark.conf`, then `include colors.conf`. The second include overrides the default with the saved scheme |
| tmux | `tmux.conf` ends with `source-file -q theme.conf` and `source-file -q colors.conf`. Because they come last, the theme overrides the hard-coded status and border colors earlier in the file |

### Startup hook

When `.zsh/color.zsh` is sourced, an anonymous function runs if `$SHLVL == 1` (a new terminal window) **or** `~/.config/tmux/colors.conf` is missing or empty:

- If `~/.zsh/.tinted` exists, it warns when line 2 is neither `dark` nor `light`, then runs `color <line 1>`.
- Otherwise it runs `color base16-default-dark` (the default).

Nested shells, including new tmux panes, skip the hook. tmux's config sets `SHLVL` to 1 in its global environment; the zsh started inside a pane then runs with `SHLVL` 2, so the hook is skipped there. The pane is already themed through tmux and Kitty.

### Difference from wincent's version

wincent only runs the Kitty update if `~/.config/kitty/kitty.sock` is readable. Kitty appends `-<PID>` to the `listen_on` socket path, so that exact file never exists. This port checks `$KITTY_LISTEN_ON`, which Kitty exports with the real socket address and which `kitten @` uses automatically. The jj color handling from wincent was dropped. Missing Kitty or tmux theme files are now caught before anything is written.

### Kitty config (`.config/kitty/kitty.conf`)

```conf
allow_remote_control socket-only
listen_on unix:/tmp/kitty
include themes/base16-default-dark.conf
include colors.conf
```

- `socket-only`: remote control is accepted only over the socket, not via escape sequences from arbitrary programs.
- `/tmp/kitty` keeps the socket files (`/tmp/kitty-<PID>`) out of the repo.

---

## Usage

```sh
color                         # print the saved scheme (name + dark/light) and re-apply it
color base16-solarized-light  # switch to a scheme
color ls                      # list all schemes
color ls gruvbox              # list schemes matching a grep pattern
color rand                    # random scheme (prints its name)
color rand -q dark            # random scheme matching "dark", without printing the name
color -                       # go back to the previous scheme
color help                    # show help
```

`luma RRGGBB` is also available on its own, for example `luma fdf6e3` → `246.1164`.

---

## New-machine setup

```sh
# 1. Clone and fetch submodules (shallow).
git clone https://github.com/JuanFCalle/dotfiles.git ~/code/dotfiles
cd ~/code/dotfiles
git submodule update --init --depth 1

# 2. Symlinks (move any existing files out of the way first).
ln -s ~/code/dotfiles/.zsh          ~/.zsh
ln -s ~/code/dotfiles/.zshrc        ~/.zshrc
ln -s ~/code/dotfiles/.config/kitty ~/.config/kitty
ln -s ~/code/dotfiles/.config/tmux  ~/.config/tmux

# 3. Make sure ~/.tmux.conf does NOT exist (it would take precedence over ~/.config/tmux/tmux.conf).

# 4. Restart Kitty (remote-control settings are only read at startup), then:
tmux kill-server   # or: tmux source-file ~/.config/tmux/tmux.conf
```

To update the schemes later:

```sh
git submodule update --remote --depth 1 .zsh/tinted-shell vendor/tinted-terminal vendor/tinted-tmux
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Kitty colors don't change live, but do after a restart | Remote control isn't active. Check `echo $KITTY_LISTEN_ON`; it should print `unix:/tmp/kitty-<PID>`. If it's empty, fully quit and restart Kitty, because `listen_on` is not reloadable. |
| Kitty doesn't change from inside an old tmux session | A tmux server started before the Kitty restart holds stale or missing `KITTY_*` variables. Run `tmux kill-server`, or run `color <scheme>` in a plain Kitty window. The `colors.conf` symlink is still updated, so the scheme applies at the next Kitty start. |
| `Scheme 'x' not found (...)` | Typo, or the scheme is missing in one of the three submodules. Use `color ls <pattern>`. Scheme IDs include the `base16-`/`base24-` prefix. |
| tmux ignores the theme | `~/.tmux.conf` exists and shadows `~/.config/tmux/tmux.conf`. Remove it, or check `ls -la ~/.config/tmux`. |
| `tmux show -g window-style` shows a long `bg=…,bg=…` list | Expected. `set -ga` appends each time you switch (same as wincent); tmux uses the last value. It resets when the server restarts. |
| `warning: unknown background type in ~/.zsh/.tinted` | The file was edited by hand or is corrupt. Run `color <scheme>` to rewrite it. |
| Submodule folders are empty after cloning | Run `git submodule update --init --depth 1`. |
| Vim/Nvim colors don't follow | Not integrated yet. `~/.zsh/.tinted` (scheme + `dark`/`light`) is the intended source for that future work. `.vim/after/plugin/color.vim` still reads `~/.vim/.base16`. |
