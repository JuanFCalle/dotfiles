# Color theme (Kitty + tmux + Neovim)

The `color` zsh function (`.zsh/color.zsh`) switches the color scheme of the shell, **Kitty** and **tmux** in one go and remembers the choice across new shells, Kitty restarts and new tmux servers.

It is a port of [wincent's `color()`](https://github.com/wincent/wincent/blob/main/aspects/dotfiles/files/.zsh/color.zsh). Neovim reads the same saved selection on startup and focus, subject to the palette compatibility checks below. Vim is unchanged and still reads `~/.vim/.base16`.

## Appearance

The appearance follows Wincent's tmux configuration, Kitty template, and external theme files at reference commit `824beaea9`. The Wincent checkout is not needed at runtime.

- **Default:** `base16-bright` (Wincent's `bright`). Light/dark selection is manual, not linked to macOS appearance. `base16-solarized-light` is a verified light counterpart.
- **tmux:** one bottom status line, bold/italic session and user/host labels, a magenta 12-hour clock, precisely padded window names, and reverse-video active-window highlighting. There is no forced red active-window background.
- **Copy mode:** a bottom pane-border indicator shows history position and available search counts instead of the top-right position overlay. Missing search formats are omitted without parsing version numbers such as `3.7c`.
- **Kitty:** 14 pt, zero window padding, top placement, 2 px extra cell height, adjusted underlines, disabled ligatures, and the reference's padded top tab bar.
- **Intentional font exception:** Source Code Pro is retained, using exact PostScript names for ExtraLight, Medium, ExtraLight Italic, and Medium Italic. The old abbreviated italic names fell back to Menlo. This is not a pixel-identical reproduction of Wincent's MonoLisaCode font.

Existing tmux prefixes, keybindings, clipboard commands, mouse actions, and history settings are unchanged. The terminal appearance requires no additional tools or fonts. The terminal configuration and regression check have been exercised with tmux 3.7c and Kitty 0.48.2 on macOS.

## Theme sources

Terminal schemes come from three [tinted-theming](https://github.com/tinted-theming) git submodules that use the same file names, so a single scheme ID (for example `base16-bright`) works across these three sources. Neovim additionally checks the complete palette against its pinned reference themes:

| Submodule | Path in repo | Provides |
| --- | --- | --- |
| [tinted-shell](https://github.com/tinted-theming/tinted-shell) | `.zsh/tinted-shell` | `scripts/<scheme>.sh`: sets the terminal palette with OSC escapes; also the source of the background color used for light/dark detection |
| [tinted-terminal](https://github.com/tinted-theming/tinted-terminal) | `vendor/tinted-terminal` | `themes/kitty/<scheme>.conf`: Kitty themes |
| [tinted-tmux](https://github.com/tinted-theming/tinted-tmux) | `vendor/tinted-tmux` | `colors/<scheme>.conf`: tmux status bar, border and message styles |

Scheme IDs are the file names without the extension, prefixed `base16-`, `base24-`, or `tinted8-`. A scheme must be available in all three sources.

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
| `.config/kitty/kitty.conf` | Kitty configuration, including fonts, layout, remote control, the default theme and `colors.conf` |
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
| `.config/tmux/theme.conf` | Copy of `colors/<scheme>.conf`, with known empty tinted8 fields repaired |
| `.config/tmux/colors.conf` | Wincent-style UI palette roles and complete window/pane overrides |

---

## How it works

### `color <scheme>` step by step

1. **Validate.** Check that all three files exist: `~/.zsh/tinted-shell/scripts/<scheme>.sh`, `~/.config/kitty/themes/<scheme>.conf` and `~/.config/tmux/colors/<scheme>.conf`. If any is missing, it prints an error and returns 1.
2. **Validate palette and detect light/dark.** Read the required colors and reject malformed hex values before changing the saved selection or generated files. Compute background luma (ITU-R BT.709, 0–255): above 127.5 means `light`, otherwise `dark`.
3. **Stage tmux configuration.** Copy the vendor theme into a temporary directory, repair known blank tinted8 border/accent fields, and generate `colors.conf`. No vendor files are edited, even if an older `theme.conf` was a symlink.
4. **Persist selection.** Save `.tinted.previous`, replace the two generated tmux files, point Kitty's `colors.conf` link at `themes/<scheme>.conf`, and save the scheme ID and `dark`/`light`. Write/apply errors are reported and return failure.
5. **Recolor the current terminal.** Run `sh <scheme>.sh`, which sends OSC escape sequences for the palette, foreground, background and cursor. tmux passthrough allows the DCS-wrapped sequences to reach Kitty.
6. **Kitty live update.** Outside tmux, use Kitty's exported `$KITTY_WINDOW_ID` and `$KITTY_LISTEN_ON`. Inside tmux, read those values from the calling pane's current session environment, not its inherited environment or the server-global snapshot. Pass the resolved address explicitly to the `kitten` command included with Kitty:
   ```sh
   kitten @ --to "$address" set-colors --all --configured ~/.config/kitty/colors.conf
   ```
   `--all` recolors every window in that Kitty instance. `--configured` also changes its configured colors, so windows opened later use the new scheme. A missing Unix socket, incomplete metadata, or failed remote command produces a diagnostic; no other socket is guessed. A non-Kitty context skips remote control.
7. **tmux live update** (only when `$TMUX` is set): disable both modern and legacy vendor Powerline-status opt-ins, then source `theme.conf` followed by `colors.conf`, even if the Kitty update failed. Startup uses the same order. Background styles replace previous values instead of accumulating `bg=...` entries.

If a live update fails, `color` returns nonzero after attempting the tmux update. The selection and generated files remain saved; the diagnostic explicitly identifies an incomplete Kitty update instead of claiming full success. Invalid themes/palettes and persistence errors still stop processing early.

The vendored Kitty Bright and Solarized Light palettes already match Wincent. The vendored tmux files use different UI shades, so `colors.conf` corrects these roles:

| UI | Foreground | Background |
| --- | --- | --- |
| Status bar and inactive window labels | `color20` | `color18` |
| Active window label (before reverse video) | `color03` | `color18` |
| Activity window label | `color_foreground` | `color18` |
| Messages and command prompts | `color21` | `color19` |
| Copy-mode selection | `color20` | `color19` |
| Active / inactive panes | Terminal default | `color_background` / `color18` |
| Both pane borders | `color08` | `color18` |

For example, Bright's status background is `#303030`, while the active pane is `#000000`. Persisting full border styles also avoids a difference between live switching and a freshly started server.

Reduced `tinted8-` palettes have no extended `color18`-`color21` shades. They retain their vendor UI styles and use `color08` for inactive-pane/border backgrounds. They remain usable but are not claimed to match the reference's full-palette roles.

### How the settings survive restarts

| Tool | Mechanism |
| --- | --- |
| Shell | The startup hook re-runs `color <saved scheme>` (see below) |
| Kitty | `kitty.conf` does `include themes/base16-bright.conf`, then `include colors.conf`. The second include overrides the default with the saved scheme |
| tmux | `tmux.conf` defines the layout, then loads the vendor-theme copy and generated palette corrections in that order |
| Neovim | The native appearance entry initializes `buho.theme`, which reads `.zsh/.tinted` on startup and `FocusGained`; it never writes shell state or recolors the terminal |

### Startup hook

When `.zsh/color.zsh` is sourced, an anonymous function runs if `$SHLVL == 1` (a new terminal window) **or** `~/.config/tmux/colors.conf` is missing or empty:

- If `~/.zsh/.tinted` exists, it warns when line 2 is neither `dark` nor `light`, then runs `color <line 1>`.
- Otherwise it runs `color base16-bright` (the default).

Nested shells, including new tmux panes, skip the hook. tmux's config sets `SHLVL` to 1 in its global environment; the zsh started inside a pane then runs with `SHLVL` 2, so the hook is skipped there. The pane is already themed through tmux and Kitty.

### Difference from wincent's version

Wincent only runs the Kitty update if `~/.config/kitty/kitty.sock` is readable. Kitty appends `-<PID>` to the `listen_on` socket path, so that exact file never exists. This port uses Kitty's exported socket address, refreshed through the current tmux session when applicable, and passes it explicitly with `--to`. An old pane's inherited address is not authoritative: its original Kitty process may have exited. The jj color handling from Wincent was dropped. Missing theme files and malformed palette values are caught before the saved selection changes.

tmux's `update-environment` list includes `KITTY_LISTEN_ON` and `KITTY_WINDOW_ID`, preserving existing entries without duplicating these additions on reload. Session creation/attachment copies the client's current values; attachment from a non-Kitty terminal marks absent variables for removal. `color` respects removed/empty session values and does not fall back to stale pane/global metadata. It reads the session values each time, so existing panes benefit without restarting their shells.

This targets **one Kitty client per tmux session**. Concurrent clients share the session environment, so the most recently attached client's metadata wins; there is no per-client routing or broadcast to other Kitty processes.

The copy-mode hook tests the pane-mode format directly, and search-count visibility depends on available formats rather than a floating-point version comparison. This avoids literal-variable and release-suffix issues in the reference configuration.

### Kitty config (`.config/kitty/kitty.conf`)

```conf
allow_remote_control socket-only
listen_on unix:~/.config/kitty/kitty.sock
include themes/base16-bright.conf
include colors.conf
```

- `socket-only`: remote control is accepted only over the socket, not via escape sequences from arbitrary programs.
- Kitty exports the actual socket address in `$KITTY_LISTEN_ON`, with its process ID appended.

---

## Neovim appearance

Neovim automatically sources `nvim/.config/nvim/plugin/appearance.lua` after `init.lua`; that entry calls `require('buho.appearance').setup()`. `init.lua` retains editing defaults and globals without an explicit appearance setup call. The appearance-only port follows Wincent commit `824beaea95693da30588188e32777164bde4bbc0`, using native packages rather than a plugin manager. Neither startup nor the regression check needs a Wincent checkout.

Paths below are relative to `nvim/.config/nvim/`:

| File | Responsibility |
| --- | --- |
| `plugin/appearance.lua` | Single native startup entry point |
| `lua/buho/appearance.lua` | Ordered package/setup coordination, window/focus state, tab/fold rendering, diagnostics, and event registration |
| `lua/buho/theme.lua` | Palette validation, theme state, and highlight overrides |
| `lua/buho/language.lua` | Parser setup/validation and size-sensitive highlighting/guide updates |
| `lua/buho/statusline.lua` | Existing statusline rendering and highlight helpers |
| `after/ftplugin/markdown.lua`, `after/ftplugin/mail.lua` | Buffer-local `synmaxcol=0` overrides with native ftplugin cleanup |

`lua/` modules are discovered through `runtimepath` but execute on `require()`, not automatically. Startup loads the four optional packages explicitly before configuring their consumers. Highlight overrides remain attached to `ColorScheme`, rather than an `after/colors/` file, so later manual theme changes receive the same customization. Dynamic focus/window rules remain event-driven rather than being reduced to one-time ftplugin settings.

`--noplugin` skips the appearance bootstrap; it does not independently disable filetype plugins. Markdown/mail after-ftplugins append to native `b:undo_ftplugin`, restoring `synmaxcol` to the global default (normally `200`) when the buffer changes filetype. This intentionally replaces the old behavior that left the local limit at zero after such a change. The public appearance `setup`, `refresh_theme`, `tablabel`, `tabline`, and `foldtext` functions remain available.

The port includes per-window Powerline statuslines (position details only above **80 columns**), shortened clickable tab labels, focused/inactive shading and numbering, whitespace and fold glyphs, the `+0` through `+254` color-column band, menus, search/matching-parenthesis colors, yank highlighting, diagnostic signs/virtual lines/floats, and indent/scope guides. Native quickfix/location-list ftplugins remain enabled. Floating windows are not shaded as inactive editing windows, and LSP sign-column reservation is confined to attached buffers.

Editing options, mappings, undo storage, hard-wrap widths, spell settings, and native filetype behavior are retained. Only fold **text** is replaced: no reference fold algorithm, view persistence, Tree-sitter indentation, text-object mappings, LSP servers, completion engine, explorer, picker, or Git UI is added. Native Neovim ftplugins can still supply their existing language-specific folding/indentation settings.

### Theme selection and compatibility

- Supported inputs are safe `base16-<name>` or `base24-<name>` tokens followed by exactly `dark` or `light` on the second line of `~/.zsh/.tinted`.
- The loader reads fixed RGB declarations from the shell script and pinned Neovim theme as **data**. It never executes the shell script or evaluates Lua to validate a palette. All 24 roles must match, ignoring hexadecimal letter case; Base16's extra roles are expanded using the reference template.
- A name match is not sufficient. For example, `base16-ayu-dark` conflicts in its extended roles, while `base24-0x96f` is compatible. Reduced `tinted8-` schemes remain available to the shell, but cannot reproduce the Neovim reference palette.
- Missing state selects **Bright/dark**. Empty, truncated, unreadable, unsafe, unsupported, missing-theme, or conflicting state warns and retains the current Neovim theme **and background**. On first startup, invalid state warns and uses Bright/dark. An unchanged rejection does not repeatedly warn; subsequent focus events retry the input.
- Startup and `FocusGained` refresh the selection. There is no background watcher, shell RPC, or restriction on `color`, `color rand`, or `color -`. Explicit `:colorscheme` changes receive the same highlight overrides; the next focus refresh returns to a valid saved shell selection.

Reference comparisons cover `base16-default-dark`, `base16-bright`, `base16-solarized-light` and `base24-0x96f`. Support is decided from the actual installed palettes, not a frozen allowlist. A future update of the existing shell-theme submodule may change compatibility.

### Pinned packages and setup

The four submodule paths are relative to the dotfiles repository:

| Package | Path below `nvim/.config/nvim/pack/bundle/opt/` | Revision |
| --- | --- | --- |
| [wincent/base16-nvim](https://github.com/wincent/base16-nvim) | `base16-nvim` | `12d13ab893cddbdc11891eac9f7f599050bc00ce` |
| [wincent/pinnacle](https://github.com/wincent/pinnacle) | `pinnacle` | `6849357c9cf1138894e26d87b6721946fb193406` |
| [lukas-reineke/indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | `indent-blankline.nvim` | `d28a3f70721c79e3c5f6693057ae929f3d9c0a03` |
| [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | `nvim-treesitter` | `427e9222363d07c32d6db6169e4049c28d58d141` |

```sh
cd ~/code/dotfiles
git submodule update --init -- \
  nvim/.config/nvim/pack/bundle/opt/base16-nvim \
  nvim/.config/nvim/pack/bundle/opt/pinnacle \
  nvim/.config/nvim/pack/bundle/opt/indent-blankline.nvim \
  nvim/.config/nvim/pack/bundle/opt/nvim-treesitter

# Only if the Neovim configuration link does not already exist:
ln -s ~/code/dotfiles/nvim/.config/nvim ~/.config/nvim
```

Neovim **0.12.5** and Tree-sitter CLI **0.26.8** were used for the comparison. The pinned parser package requires Neovim 0.12 and CLI >=0.26.1, plus `cc`, `tar`, and `curl`. No Neovim upgrade is part of this setup. The CLI is installed separately; do not use npm for this package's CLI requirement. For macOS Apple Silicon, the exact tested release can be installed from the official binary:

```sh
tmp=$(mktemp -d)
curl -fL https://github.com/tree-sitter/tree-sitter/releases/download/v0.26.8/tree-sitter-macos-arm64.gz \
  -o "$tmp/tree-sitter.gz" &&
gzip -dc "$tmp/tree-sitter.gz" > "$tmp/tree-sitter" &&
mkdir -p ~/.local/bin &&
install -m 755 "$tmp/tree-sitter" ~/.local/bin/tree-sitter
rm -f "$tmp/tree-sitter.gz" "$tmp/tree-sitter"
rmdir "$tmp"
# Ensure ~/.local/bin is on PATH.
tree-sitter --version
```

Use the corresponding [0.26.8 release asset](https://github.com/tree-sitter/tree-sitter/releases/tag/v0.26.8) on other architectures. Install just the approved **Kotlin, Python, YAML, JSON, Zsh, and Bash** grammars, using the revisions in the pinned package's `parsers.lua`:

```sh
cd ~/code/dotfiles
nvim --headless -u NONE -i NONE -n -l /dev/stdin <<'LUA'
vim.opt.packpath:prepend(vim.fn.getcwd() .. '/nvim/.config/nvim')
vim.o.loadplugins = true
vim.cmd.packadd('nvim-treesitter')
local ts = require('nvim-treesitter')
ts.setup({ install_dir = vim.fn.stdpath('data') .. '/site' })
local languages = { 'kotlin', 'python', 'yaml', 'json', 'zsh', 'bash' }
assert(ts.install(languages):wait(300000), 'Parser installation failed; inspect :TSLog')
for _, lang in ipairs(languages) do
  assert(vim.treesitter.language.add(lang))
  assert(vim.treesitter.query.get(lang, 'highlights'), 'Missing queries: ' .. lang)
end
LUA
```

Compiled parsers and query links live under `~/.local/share/nvim/site/` (or the corresponding XDG data directory), not in Git. C, Lua, Markdown/Markdown inline, query, Vimscript, and Vim help continue using the bundled parsers. Bash activates for `sh`/`bash`; Zsh uses its own parser. Kotlin is a requested extension using the same reference queries/style, not an existing language activation in Wincent's configuration.

All approved grammars and queries are checked at startup; missing packages/parsers and broken queries are visible errors, not silent skips. **Nothing is downloaded or updated automatically.** Do not run a blanket `:TSUpdate` to replace the bundled parsers. Dependency upgrades and any additional injected-language parsers are separate decisions.

Guides use the reference `│` glyph and scope behavior, excluding Markdown and the plugin's default special buffers. They follow each buffer's `expandtab` setting independently. The rendered v3 groups are `IblIndent`/`IblScope`, not the legacy `IndentBlanklineChar`. Highlighting and guides stop above 1 MiB, including an unsaved buffer that grows past the limit.

### Neovim regression check and visual limits

```sh
cd ~/code/dotfiles/nvim/.config/nvim
nvim --headless -u NONE -i NONE -n -l check-appearance.lua
```

The single native Lua check creates temporary HOME/XDG state and reads the installed parsers without replacing them. Its controlled child uses explicit package/runtime paths, including `after/`, and manually sources the entry because `-u NONE` disables automatic loading. Separate ordinary-startup children discover the config through an isolated configuration link, without directly calling setup or sourcing the plugin. They verify entry discovery, initial Lua/Markdown/mail files, `--noplugin`, first-start fallback, and startup errors/warnings.

The check also covers exact bar text, display-cell widths and highlight boundaries, four theme palettes and styles, malformed state and last-good behavior, focus/buffer/mode transitions, native ftplugin cleanup, special buffers, diagnostics and multiwindow LSP gutters, folds, parser captures, real guide/scope extmarks, strict 1 MiB disk/buffer boundaries, and preserved editing settings. It does not recolor Kitty/tmux or modify the saved shell theme.

The actual terminal configuration retains **Source Code Pro ExtraLight/Medium and their italic faces, 14 pt, and 4 pt Kitty padding**. This differs intentionally from Wincent's MonoLisaCode/zero-padding environment. The earlier terminal-only section/check still describes zero padding; that pre-existing discrepancy is not repaired by the Neovim work.

Same-binary automated reference comparisons have been performed. An isolated 120x40 tmux comparison also produced identical terminal text and ANSI styling for the reference and port, including tabs, active/inactive splits, statuslines and guides. Actual Kitty window capture was unsuccessful during implementation, so glyph fallback, physical positioning and final menu/guide rendering still need visual inspection at equal grid dimensions and display scale, both directly and inside tmux. These checks do not establish pixel-identical rendering or parity for excluded plugin screens.

---

## Usage

```sh
color                         # print the saved scheme (name + dark/light) and re-apply it
color base16-bright           # reference dark appearance
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

# 4. In a Kitty shell, load the color function and initialize the theme:
source ~/.zsh/color.zsh
color base16-bright

# 5. Reload an existing tmux session without terminating it:
tmux source-file ~/.config/tmux/tmux.conf
kitten @ load-config
```

When enabling Kitty remote control for the first time, reopen Kitty only after preserving ongoing work; `listen_on` requires a new process. Appearance changes can otherwise be applied with `kitten @ load-config` from a current plain Kitty shell. Unlike `color`, a standalone `kitten @` command does not resolve tmux session metadata. Existing tmux sessions need the reattachment procedure below to initialize their refreshed values; do not guess sockets from an unrelated shell.

To update the schemes later:

```sh
git submodule update --remote --depth 1 .zsh/tinted-shell vendor/tinted-terminal vendor/tinted-tmux
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Kitty colors don't change live, but do after a restart | In a plain Kitty shell, check `echo $KITTY_LISTEN_ON`; the configured address ends in `.config/kitty/kitty.sock-<PID>`. Inside tmux, the current session values are authoritative; see the recovery steps below. Enabling `listen_on` for the first time still requires reopening Kitty after preserving work. |
| Missing `kitty.sock-<PID>` / Kitty metadata has not been refreshed | tmux or an old pane retained metadata from an earlier Kitty process. Reload the configuration, then reattach from a current plain Kitty shell as described below. Configuration reload alone does not refresh an already-attached client's metadata. |
| `color` returns nonzero but shell/tmux colors changed | Kitty's live update was incomplete; the saved selection and tmux update are retained. Check the diagnostic and refresh the session metadata. An existing socket can still reject a connection; its presence alone does not prove the listener is reachable. |
| `Scheme 'x' not found (...)` | Typo, or the scheme is missing in one of the three submodules. Use `color ls <pattern>`. IDs include the `base16-`/`base24-`/`tinted8-` prefix. |
| tmux ignores the theme | `~/.tmux.conf` exists and shadows `~/.config/tmux/tmux.conf`. Remove it, or check `ls -la ~/.config/tmux`. |
| Red active-window background or accumulated `bg=...` values | Load the updated color function, re-apply the scheme, and reload tmux configuration. Both startup and live switching now replace these styles. |
| Italics look like another font | The configuration uses exact Source Code Pro PostScript names. Verify those fonts are installed and reload Kitty; no MonoLisaCode font is required. |
| `warning: unknown background type in ~/.zsh/.tinted` | The file was edited by hand or is corrupt. Run `color <scheme>` to rewrite it. |
| Submodule folders are empty after cloning | Run `git submodule update --init --depth 1`. |
| Neovim warns about a theme/palette | The saved state is invalid, a source is unreadable/missing, or the complete palette differs from the reference. Neovim keeps its current theme/background. Choose a compatible scheme such as `color base16-bright`, then refocus Neovim. `:messages` contains the rejection reason. |
| Neovim reports a missing package/parser/query | Initialize the four pinned submodules and run the explicit six-language installation above. Check `tree-sitter --version` and `:TSLog`; startup does not install dependencies. |
| Vim colors don't follow | Vim integration is unchanged: `.vim/after/plugin/color.vim` still reads `~/.vim/.base16`. |

### Recover an existing tmux session without terminating it

In the affected session, note its name and load the updated configuration:

```sh
tmux display-message -p '#{session_name}'
tmux source-file ~/.config/tmux/tmux.conf
tmux detach-client
```

From a **current plain Kitty shell**, where `$KITTY_LISTEN_ON` names the current listener, reattach to that session:

```sh
tmux attach-session -t '<session-name>'
```

For a non-default tmux server, use its original `-L` or `-S` option when reattaching. Do not use `attach-session -E`, which disables environment refresh.

In existing panes, reload the function and retry:

```sh
source ~/.zsh/color.zsh
color base16-aztec
```

The pane's exported `$KITTY_LISTEN_ON` may still show the old value; `color` now reads the refreshed session environment instead. No tmux server termination or Kitty restart is needed when the current Kitty listener is already enabled.

## Regression check

From the repository root:

```sh
zsh -n .zsh/color.zsh && zsh -n .config/tmux/check-appearance.zsh
zsh -f .config/tmux/check-appearance.zsh
```

The check uses a temporary HOME and its own tmux socket; it does not recolor Kitty or change normal sessions. A test-only `kitten` executable and Unix sockets cover explicit targeting, stale pane/global metadata, native session reattachment, removed/empty metadata, missing sockets, and remote failures that must not block tmux. It also verifies exact formats and spacing, Aztec/Bright/Solarized Light palettes, dark/light persistence, idempotent reloads, copy-mode search counts, reduced palettes, invalid input, unchanged keybindings, Kitty settings, and all four installed font faces. Expected failure diagnostics are captured separately; unexpected stderr makes it fail. Existing Zsh, tmux, Kitty, fonts, and initialized theme submodules are required.

For a visual comparison, use equal window dimensions and display scale, and the same Source Code Pro faces on both sides. Inspect the actual status bar, pane borders, copy mode, selection, and Kitty tabs; pane text capture alone does not establish status-bar or font-rendering parity.
