# Shared theming

How one command — `color base16-ocean` — recolors the shell, Kitty, tmux, Vim
and Neovim at the same time, and how the Neovim half of that was built.

This document assumes **no Neovim knowledge**. Every Neovim concept is
explained the first time it comes up.

---

## 1. The problem

A terminal session is a stack of programs drawn on top of each other:

```
Kitty          the terminal window  (draws the actual pixels)
└── tmux       the pane/window manager
    └── Zsh    the shell
        └── Neovim
```

Each of them has its own idea of what colors to use. Change the theme in one
and the others keep their old colors, so you end up with, say, a light editor
inside a dark tmux status bar inside a dark terminal. The goal of *shared
theming* is that one command changes all of them at once, consistently.

The organising idea, borrowed from [wincent/wincent]:

> **Zsh owns theme selection; everyone else reads it.**

There is exactly one writer and several readers. That avoids the classic mess
where each program has its own theme setting that has to be kept in sync by
hand.

---

## 2. The contract

Zsh records the current selection in a plain text file:

**`~/.zsh/.tinted`** — exactly two lines:

```
base16-default-dark
dark
```

| Line | Meaning |
| --- | --- |
| 1 | The **scheme slug** — the shared name for the theme. Kitty, tmux and Neovim all use this exact string. |
| 2 | `dark` or `light` — whether the scheme's background is dark or light. |

The file is deliberately **git-ignored**: it is machine state, not
configuration.

### Why a file and not an environment variable?

An environment variable is copied into a process when it starts. If you change
it afterwards, every program that is *already running* keeps the old value.
Neovim is usually already running when you switch themes, so it would never see
the change. A file can be re-read at any moment, so a long-running program can
pick up the new value whenever it likes.

### Why two lines, when line 2 is derivable from line 1?

Working out "is this theme dark or light?" means parsing the scheme's palette
and doing arithmetic on it. Zsh already does that work (see below). Writing the
answer down means every reader gets it for free instead of reimplementing the
calculation.

---

## 3. The Zsh half (this already existed)

All of it lives in [`.zsh/color.zsh`](../.zsh/color.zsh), which defines the
`color` command:

```
color                      show the current scheme
color base16-ocean         switch to a scheme
color ls [pattern]         list available schemes
color rand [pattern]       pick a random one
color -                    go back to the previous one
color help                 show this list
```

What `color <scheme>` does, in order:

1. **Checks the scheme exists everywhere.** It needs a shell script
   (`~/.zsh/tinted-shell/scripts/<scheme>.sh`), a Kitty theme and a tmux theme.
   A few schemes exist in one source but not the others; those are rejected up
   front rather than leaving you half-themed.
2. **Extracts the palette** from the shell script — background, foreground,
   border and accent colors as `RRGGBB` hex strings.
3. **Computes the luma** of the background color — its perceived brightness on
   a 0–255 scale, using the ITU-R BT.709 weights
   (`0.2126·R + 0.7152·G + 0.0722·B`; human eyes are far more sensitive to
   green than to blue). If luma is **greater than 127.5** the background counts
   as `light`, otherwise `dark`. That one number is what ends up on line 2 of
   the state file.
4. **Writes out the tmux theme**, saves a copy of the previous state to
   `~/.zsh/.tinted.previous` (that's what `color -` uses), and **writes
   `~/.zsh/.tinted`**.
5. **Notifies the live programs:** sources the shell script (recolors the
   current shell), tells Kitty to reload its colors over its remote-control
   socket, and tells tmux to re-source its theme files.

**The ordering in steps 4 and 5 matters.** The state file is written *before*
Kitty and tmux are told anything. When Kitty repaints, Neovim receives a focus
event (more on that below) and immediately re-reads the file — so it is
guaranteed to find the *new* slug already there, not the old one.

There is also a small startup hook at the bottom of the file: when you open a
brand-new terminal window, it replays the saved scheme, or falls back to
`base16-bright` the very first time. Those two fallback values are important
later.

---

## 4. The Neovim half (what was built)

Four new files, plus one new block in `init.lua`:

```
.config/nvim/
├── init.lua                      SECTION 6 — installs the colorschemes
├── lua/buho/color.lua            reads and validates ~/.zsh/.tinted
├── lua/buho/nvim/augroup.lua     small helper for event handlers
├── after/plugin/color.lua        applies the theme  ← the actual feature
└── test/color-test.lua           the runnable check
```

Why four files instead of one? Because the parsing logic can then be tested
without starting a real editor — see step 8.

### A 60-second Neovim primer

You only need five ideas to follow the rest of this document.

| Term | What it means |
| --- | --- |
| **Lua** | The language Neovim is configured in. `init.lua` is the entry point, run at startup. |
| **runtimepath** | The list of directories Neovim searches for configuration and plugins. Think `$PATH`, but for editor files. |
| **colorscheme** | A named set of colors, e.g. `base16-default-dark`. Applied with `:colorscheme <name>`. |
| **highlight group** | A named style (`Comment`, `Normal`, `Search`, …). A colorscheme is essentially a long list of highlight group definitions. |
| **autocmd** | "When *event* happens, run *this*." The only way to react to something after startup. Events used here: `VimEnter` (startup finished) and `FocusGained` (the window got focus). |

---

### Step 1 — Get the colorschemes into Neovim

**File:** `.config/nvim/init.lua`, *SECTION 6: SHARED THEMING*

```lua
vim.pack.add { gh 'tinted-theming/tinted-vim' }
```

**What:** `vim.pack` is Neovim's built-in plugin manager (0.12+). It clones the
given repository, adds it to the runtimepath, and pins the exact commit in
`nvim-pack-lock.json` so the same version is installed everywhere.

**Why it's needed:** `:colorscheme base16-default-dark` only works if a file
defining that colorscheme is somewhere on the runtimepath. Neovim ships with
about a dozen built-in schemes; none of them are base16 ones. `tinted-vim`
provides 580 — 362 base16 and 218 base24.

**Why `tinted-vim` specifically**, and not e.g. `wincent/base16-nvim`:
tinted-vim's colorscheme names are *prefixed* — `base16-default-dark` — which
is byte-for-byte the same string Zsh writes to the state file. So Neovim can
pass the slug straight through. Other plugins name the same scheme
`default-dark` without the prefix, which would have required a translation
layer and a fallback for when translation fails. Zero code beats some code.

**Why not reuse the copy already in this repo?** The repo vendors tinted-vim as
a git submodule at `.vim/pack/bundle/opt/base16-vim` for plain Vim. Neovim
can't reach it: only some directories of this repo are symlinked into `$HOME`
(`.zsh`, `.zshrc`, `.zshenv`, `.ideavimrc`, `.config/kitty`, `.config/tmux`,
`.config/nvim`) and `.vim` is **not** one of them, so the path doesn't exist
from Neovim's point of view. Trying it produces
`E919: Directory not found in 'packpath'`. A second, lockfile-pinned copy is
cheap and consistent with every other plugin in this config.

> ⚠️ **Do not set `g:tinted_shell_path`.** Every tinted-vim colorscheme
> contains, in effect, `if exists('g:tinted_shell_path') | silent !sh
> <path>/base16/<name>.sh`. Setting that variable makes *every* `:colorscheme`
> fork a shell and re-run the tinted-shell script — work `color()` has already
> done — which both wastes time and risks the two of them fighting over the
> terminal palette.

---

### Step 2 — Read and validate the state file

**File:** `.config/nvim/lua/buho/color.lua`

**What:** a module with no side effects. It exports the three constants and one
function:

```lua
M.CONFIG_FILE        = '~/.zsh/.tinted'
M.DEFAULT_SCHEME     = 'base16-bright'
M.DEFAULT_BACKGROUND = 'dark'

M.read_state(path) -> scheme, background, warnings
```

**Why it's a separate file:** this is the only part with real logic, and it is
the part most likely to break. Keeping it pure — in, out, no editor state
touched — means it can be run and asserted on in a test (step 8). The file that
*does* things is kept deliberately dumb.

**Design decisions worth knowing:**

- **A malformed value returns `nil`, which means "leave the current setting
  alone"** — not "force a fallback". If line 2 is garbage but line 1 names a
  perfectly good scheme, you get the scheme you asked for and a warning about
  the background. Blowing away a deliberate choice because an unrelated line is
  malformed would be worse than doing nothing.
- **A missing file is not an error.** It returns `base16-bright` / `dark` with
  *no* warning, because that is the normal state before you have ever run
  `color`. Those two values are copied from the startup hook in `color.zsh`;
  **if you change the default there, change it here too.** They are the one
  piece of duplication in the design.
- **Checking whether a scheme exists** uses
  `vim.fn.getcompletion(scheme, 'color')` — literally "what would tab-completion
  after `:colorscheme` offer?". That finds schemes written in either Vimscript
  or Lua, anywhere on the runtimepath, without hardcoding a directory.
- **Neovim never writes to the file.** If the state is broken, it says so and
  carries on. The shell owns it; a second writer would reintroduce exactly the
  sync problem this design exists to avoid.

> 🐛 One upstream bug was fixed in passing. The reference implementation writes
> `if vim.fn.filereadable(path) then`. `filereadable` returns `0` or `1`, and in
> Lua **`0` is truthy** — so that branch is always taken, even when the file is
> missing. This version compares explicitly: `if ... ~= 1 then`.

---

### Step 3 — Apply the theme

**File:** `.config/nvim/after/plugin/color.lua`

**What:** the `check()` function. It calls `read_state`, shows any warnings with
`vim.notify`, then:

```lua
if background then vim.o.background = background end
if scheme     then vim.cmd.colorscheme(scheme)   end
```

`vim.o.background` tells Neovim whether it is drawing on a dark or light
surface. Plugins read it to pick appropriate shades, so it must be set
**before** the colorscheme, not after.

**Why the file lives in `after/plugin/`:** Neovim automatically runs every
`.lua` file in a `plugin/` directory at startup. The `after/` prefix means
"load this directory *last*, once everything else is done". Colors must be
applied after all plugins have loaded, because a plugin that defines its own
highlight groups at load time would otherwise overwrite ours. Putting the file
here gets that ordering for free, with no explicit sequencing code.

---

### Step 4 — Apply the local overrides

Still in `after/plugin/color.lua`:

```lua
local has_pinnacle, pinnacle = pcall(require, 'wincent.pinnacle')
if has_pinnacle then
  pinnacle.merge('Comment', { italic = true })
  -- …floating-window tweaks…
end
```

**What:** [pinnacle] is a small library for *deriving* highlight groups from
existing ones, rather than hardcoding hex values. `merge('Comment', {italic =
true})` means "whatever `Comment` currently looks like, add italics".
`adjust_lightness('Normal', 0.1)` means "take the normal background and lighten
it by 10%".

**Why derive instead of hardcode:** there are 580 schemes. A hardcoded
`#1a1a1a` would look right in one of them and wrong in the other 579. Deriving
from the active scheme means the overrides follow whatever theme is in effect.
That's also why the floating-window tweak flips direction based on `background`
— on a light scheme you *darken* to make a float stand out, not lighten.

**Why `pcall`:** `pcall` is Lua's "try". If pinnacle isn't installed yet — a
fresh clone, a failed plugin download — `require` would throw and abort the rest
of the file, leaving you with no colorscheme at all. Guarding only the override
block means a missing optional library costs you italic comments, not your
entire theme.

The override set is deliberately minimal for now: italic comments, and
better-looking floating windows.

---

### Step 5 — Re-announce the change

```lua
vim.cmd.doautocmd('ColorScheme')
```

**What:** `doautocmd` fires an event manually. `ColorScheme` is the event
Neovim emits when the colorscheme changes.

**Why:** running `:colorscheme` already fired this event once — but that was
*before* step 4's overrides, and before any other plugin's own highlight
customisation could run. Firing it again at the very end gives everyone a
chance to reapply their styling on top of the final result. A statusline, for
instance, would use it to re-set its `User1`, `User3`, … groups, and any plugin
that restyles `Search` or `QuickFixLine` hangs off the same event.

Without this line, anything that styles itself in response to a theme change
would silently keep stale colors after every switch.

---

### Step 6 — Decide *when* to run

```lua
augroup('buho.color', function(autocmd)
  autocmd('FocusGained', '*', check)
  autocmd('VimEnter', '*', check)
end)
```

**What:** register `check()` to run on two events.

- **`VimEnter`** — fired once, when startup is finished. This paints the right
  colors when Neovim opens.
- **`FocusGained`** — fired whenever the Neovim window becomes the focused one.
  This is the interesting one: when you run `color base16-ocean` in a *different*
  tmux pane, Neovim gets a focus event as the terminal repaints, re-reads the
  file, and recolors itself. No message passing, no IPC, no plugin — just "check
  the file whenever something happens".

**Why both, given that focus events also fire at startup?** Because they don't,
reliably. Outside tmux there is no focus event on launch at all. Inside tmux,
there usually is — but not when Neovim is started in a pane that isn't focused
(e.g. via `tmux send-keys`). Registering both means the common case runs
`check()` twice, which is harmless and cheap: reading two lines from a file.
Correct-and-slightly-redundant beats clever-and-occasionally-unthemed.

**What an augroup is, and why use one:** an *autocommand group* is a named
bucket of event handlers. `nvim_create_augroup(name, {clear = true})` deletes
any handlers already in that bucket before adding new ones. Without it,
re-sourcing the config (or `:source $MYVIMRC`) would register a *second* copy of
each handler, then a third, and `check()` would run once per reload on every
focus change. The helper in `lua/buho/nvim/augroup.lua` just wraps that
create-clear-populate pattern so it reads as one block.

---

### Step 7 — The `vi` escape hatch

```lua
if vim.v.progname ~= 'vi' then
  ...
end
```

**What:** `v:progname` is the name the binary was invoked under. If you symlink
`vi` to `nvim`, `vi foo.txt` gives you Neovim with `progname == 'vi'`.

**Why:** that invocation is the "get in, edit a config file, get out" mode —
often as another user, or over a slow connection, or inside a tool like
`sudoedit`. It shouldn't spend time loading a colorscheme or touching your home
directory. Skipping registration entirely (rather than bailing out inside
`check`) means the event handlers are never even created.

---

### Step 8 — Leave a runnable check behind

**File:** `.config/nvim/test/color-test.lua`

```sh
nvim -l ~/.config/nvim/test/color-test.lua   # prints: ok
```

`nvim -l <file>` runs a Lua file and exits — no UI, no config loaded. The test
is plain `assert` calls, no test framework. It passes a fake `exists` function
to `read_state`, so it doesn't depend on which colorschemes happen to be
installed.

Five cases, one per state `color()` can leave on disk:

| Case | What it protects |
| --- | --- |
| valid state | the happy path is applied as-is, with no warning |
| bad background | **the scheme survives** — one bad line doesn't discard the other |
| unknown scheme | **the background survives**, and we warn instead of silently repairing |
| missing second line | a truncated file is malformed, not an empty slug |
| no file at all | falls back to the shell's own defaults, and does *not* warn |

The middle three are the ones worth having. They encode the "a `nil` means
leave it alone" decision from step 2 — the kind of thing that is easy to
"simplify" away six months later without realising it was deliberate.

---

## 5. Verifying it works

```sh
# 1. The parser.
nvim -l ~/.config/nvim/test/color-test.lua          # -> ok

# 2. What Zsh currently thinks the theme is.
cat ~/.zsh/.tinted

# 3. What Neovim thinks, at startup.
nvim --headless -c 'au VimEnter * lua
  print(vim.g.colors_name, vim.o.background) vim.cmd.quit()'
```

Those two should agree.

> ⚠️ Note that the probe is wrapped in `au VimEnter *`. Plain `-c` commands run
> *before* `VimEnter` fires, so `-c 'lua …'` would show you the state from
> *before* the theme was applied — which looks exactly like a bug. (It is also
> why the quit has to happen inside the autocmd: a trailing `-c 'q'` would exit
> before `VimEnter` ever fired.)

**End to end:** open Neovim in one tmux pane, run `color base16-solarized-light`
in another, then click or switch back to the Neovim pane. It should repaint,
including flipping to a light background.

---

## 6. Changing things

**Add a highlight override** — add it to the `if has_pinnacle` block in
`after/plugin/color.lua`. Derive it from an existing group (`merge`,
`adjust_lightness`, `embolden`, `italicize`, …) rather than hardcoding a hex
value, so it works across all 580 schemes.

**Change the default scheme** — change it in **both**
`.zsh/color.zsh` (the startup hook at the bottom) and `M.DEFAULT_SCHEME` in
`lua/buho/color.lua`. These are the only two places the design duplicates a
value.

**Add a new consumer** (another editor, a prompt, anything) — read the two lines
of `~/.zsh/.tinted` and re-read them on some "I might have been away" event.
Don't write to it.

---

## 7. Known limits

- **No statusline integration.** `lua/buho/statusline/` is empty. The
  `doautocmd ColorScheme` from step 5 is the hook it will need when it's built.
- **Minimal overrides.** The reference implementation also restyles `Conceal`,
  `NonText`, `Pmenu`, `VertSplit`, `CursorLineNr`, the diff groups, `SpellBad`
  and the completion-match groups. Those weren't ported; add them as the need
  shows up.
- **`FocusGained` has only been exercised indirectly.** It calls the same
  `check()` that `VimEnter` does, so the logic is covered, but the live
  Kitty-plus-tmux focus path isn't tested automatically.

---

[wincent/wincent]: https://github.com/wincent/wincent
[pinnacle]: https://github.com/wincent/pinnacle
