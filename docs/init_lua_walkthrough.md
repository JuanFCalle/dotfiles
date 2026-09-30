## 1. High-Level Summary

This configuration gives Neovim its colors, information bars, indentation guides, and other visual details. Native runtime files start the configuration and apply filetype-only settings; Lua modules update appearance as you move between windows, type, change themes, or return to the editor.

## 2. The Big Picture

**Neovim is the editor; Lua is the programming language this configuration uses to tell it what to do.** Neovim provides a global Lua object named `vim`, through which the configuration reads editor state, changes settings, and registers functions to run later.

This walkthrough follows the appearance configuration by file and named function, rather than line numbers that change when code moves. Paths below are relative to `nvim/.config/nvim/`. Supporting plugins and `statusline.lua` are explained where they matter.

| File | Responsibility |
|---|---|
| `init.lua` | Existing editing options and globals; no explicit appearance setup call. |
| `plugin/appearance.lua` | The automatic startup entry point. |
| `lua/buho/appearance.lua` | Setup coordination, window/focus behavior, tab/fold rendering, diagnostics, and event registration. |
| `lua/buho/theme.lua` | Saved palette validation, theme state, and highlight overrides. |
| `lua/buho/language.lua` | Parser setup and size-sensitive highlighting/indent-guide updates. |
| `lua/buho/statusline.lua` | Statusline rendering and its highlight groups. |
| `after/ftplugin/markdown.lua`, `after/ftplugin/mail.lua` | Buffer-local syntax-column overrides and their cleanup. |

### The editor concepts you need first

| Concept | Meaning here |
|---|---|
| **Buffer** | Text held in the editor, usually associated with a file. Unsaved changes live in the buffer before they reach the file on disk. |
| **Window** | An area displaying a buffer. Two windows can show the same buffer. Splitting the editor creates another window. |
| **Tab page** | A layout containing windows. Unlike a typical IDE file tab, a Neovim tab page is not necessarily one file. |
| **Normal mode** | The mode primarily used for movement and commands. |
| **Insert mode** | The mode primarily used for typing text. |
| **Colorscheme and highlight group** | A colorscheme supplies named styles. Each name, such as `Comment` or `StatusLine`, is a **highlight group** containing colors and attributes such as bold or italic. |
| **Statusline** | A window’s information bar, typically showing its filename and cursor position. |
| **Tabline** | The bar representing tab pages. |
| **Fold** | A range of text temporarily hidden behind a summary line. The text still exists. |
| **Plugin** | Additional code that extends the editor. |
| **Event callback** | A function Neovim calls when something happens, such as entering a window or saving a buffer. |
| **Diagnostic** | A message about code, such as an error, warning, informational note, or hint. |
| **LSP client** | Neovim’s connection to a language server through the Language Server Protocol. A server can supply diagnostics and other language-aware features. |
| **Tree-sitter** | A system that parses text into a syntax tree: a structured representation of things such as functions, strings, and expressions. Neovim can use that structure for highlighting. |

The startup connection is in `plugin/appearance.lua`, which Neovim sources automatically during its plugin-loading phase:

```lua
require('buho.appearance').setup()
```

Read that as two operations:

```lua
local appearance = require('buho.appearance')
appearance.setup()
```

`require` finds and evaluates the Lua module, which returns a table of functions. The second operation calls one of those functions.

```text
Neovim starts
  -> init.lua sets editing options and globals
  -> Neovim discovers plugin/appearance.lua
  -> require evaluates appearance.lua and its helper modules
  -> the startup entry calls appearance.setup()
  -> existing packages, parsers, options, and callbacks are configured
  -> guides, the initial theme, and window/language presentation are applied
  -> startup buffers load native ftplugins and matching after/ftplugin overrides
  -> later editor events call the relevant helpers again
```

**Defining a function does not run its body.** Most module code defines functions; `setup()` connects them to Neovim and performs the initial work.

Lua normally caches a module’s returned value, so later calls to `require('buho.appearance')` reuse the same table rather than evaluating the file again. However, calling `.setup()` again still runs that function again. Also, `setup` is just a conventional function name—not a Lua keyword or an automatic initialization mechanism.

### Runtime discovery is not automatic execution

`runtimepath` is a list of directories Neovim searches. Different subdirectories have different loading rules:

| Location | When code runs |
|---|---|
| `plugin/*.lua` | During normal startup, after user configuration. |
| `lua/buho/*.lua` | On the first matching `require()`, then cached. Files are not automatically executed merely because they are on `runtimepath`. |
| `after/ftplugin/<filetype>.lua` | On the relevant `FileType` event, after ordinary ftplugins, when filetype plugins are enabled. |
| `after/plugin/*.lua` | Late in the startup plugin phase, not after every later plugin action or editor event. |
| `colors/<name>.lua` | When that colorscheme is selected. |

The appearance entry uses explicit `packadd` calls for its dependencies, so it does not need `after/plugin/` or numbered startup files to coordinate them. `--noplugin` skips this entry point. It does **not** independently disable native ftplugins; Markdown/mail overrides can still run when filetype plugins are enabled. `-u NONE` skips normal configuration and automatic plugin loading, which matters for the regression check.

Highlight overrides use a `ColorScheme` callback, not an `after/colors/` hook. `:colorscheme` loads the first matching scheme; it does not source every matching file from later runtime directories.

See `:help load-plugins`, `:help lua-guide-modules`, `:help ftplugin-overrule`, and `:help :colorscheme`.

## 3. Step-by-Step Breakdown

### Module boundaries: paths, state, and lookup tables

The opening `--` line is a comment crediting the source of the appearance configuration. Lua ignores comments when executing the file.

Each Lua module returns its own `M` table. The palette path and theme state belong to `theme.lua`, which starts with:

```lua
local M = {}
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
local colors = root .. '/pack/bundle/opt/base16-nvim/colors/'
local status = require('buho.statusline')
```

`local M = {}` creates a local variable holding an empty **table**. Lua tables cover several roles that Kotlin usually separates into lists, maps, and objects. Here, `M` will hold named functions that other files can call.

It is not a class declaration. And unlike Kotlin’s `val`, Lua’s `local` does **not** make a binding immutable; it controls visibility, and the variable can be reassigned.

The long `root` expression is easier to read from the inside out:

1. `debug.getinfo(1, 'S')` requests source information for the currently executing Lua code.
2. `.source` retrieves its source name, which for a file normally begins with `@`.
3. `:sub(2)` takes the string starting at position 2, removing that marker.
4. Three `vim.fs.dirname(...)` calls walk from `theme.lua` to `buho`, then `lua`, then the Neovim configuration directory.

`vim.fs` supplies filesystem-path helpers. This derives the path from the configuration file’s location, not from whichever project you happen to be editing.

The colon in `source:sub(2)` passes the string as the receiver. For a string, this is equivalent to `string.sub(source, 2)`. Lua strings and list-style tables conventionally use **1-based indexing**.

The `..` operator concatenates strings, so `colors` becomes the path to the local colorscheme directory. The `status` variable receives the table returned by `buho.statusline`.

Theme state remains private to `theme.lua`:

```lua
local applying, initialized = false, false
local last_warning
```

This is **multiple assignment**: two names receive two values. Window focus state stays in `appearance.lua` as `local focused = true`.

| Variable | Owner | What it remembers |
|---|---|---|
| `applying` | `theme.lua` | Whether the theme module is currently applying a colorscheme. |
| `initialized` | `theme.lua` | Whether a theme has already been successfully initialized. |
| `focused` | `appearance.lua` | Whether the editor currently has focus, according to the focus events handled later. |
| `last_warning` | `theme.lua` | The most recent rejected-selection message, so the same warning is not repeatedly shown. |

A local variable without an initial value starts as `nil`, Lua’s value for absence.

The window constants in `appearance.lua` describe presentation rules:

**`band`** is built with:

```lua
local band = '+' .. table.concat(vim.fn.range(0, 254), ',+')
```

`vim.fn` exposes Neovim’s built-in functions, including functions originally available through Vimscript, Neovim’s older configuration language. Here, `range(0, 254)` includes both endpoints, and `table.concat` joins the values into:

```text
+0,+1,+2,...,+254
```

These will be used by the `colorcolumn` option. Importantly, they are offsets from the buffer’s `textwidth`, **not absolute columns 0 through 254**. With `textwidth = 80`, they describe columns 80 through 334. If `textwidth` is zero, Neovim ignores these relative entries.

**`blurred`** joins entries such as `Normal:ColorColumn` into another comma-separated string. These entries tell an inactive window to display one highlight group using another group’s style. The remapping covers ordinary text, search highlights, the sign area, end-of-buffer markers, and the cursor-line number.

**`listchars`** maps normally invisible or structural text to visible symbols:

| Key | Display |
|---|---|
| `nbsp` | A non-breaking space appears as `?`. |
| `extends` / `precedes` | `»` / `«` indicate text extending beyond a horizontally clipped view. |
| `tab` | A tab is represented using `?` followed by `?` filling its width. |
| `trail` | Trailing spaces appear as `•`. |

**`languages`**, in `language.lua`, maps a buffer's filetype to a Tree-sitter parser name. Many names match directly, such as `kotlin = 'kotlin'`. Exceptions include `help -> vimdoc`, `sh -> bash`, and `scheme -> query`. That last entry specifically selects the query parser; it does not select a general-purpose Scheme parser.

Finally, **`signs`**, in `appearance.lua`, is a list-style table containing the symbols later used for error, warning, information, and hint diagnostics.

### `theme.lua`: `read` - reading a file without hiding failures

```lua
local function read(path, limit)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, 'Cannot read ' .. path
  end
```

`local function` defines a helper visible within this module, rather than exporting it through `M`. `~=` means “not equal,” corresponding to Kotlin’s `!=`.

The helper first checks readability. A failure returns **two values**: `nil` and an explanatory message.

The optional `limit` argument controls how many lines to read. Lua does not require a special optional-parameter declaration: an omitted argument receives `nil`.

The central operation is:

```lua
ok, lines = pcall(vim.fn.readfile, path, '', limit)
```

`pcall` means **protected call**. It calls the function supplied as its first argument using the remaining arguments:

| Outcome | First returned value | Following value |
|---|---|---|
| Successful read | `true` | The list of lines |
| An error is raised | `false` | The error value |

Notice that `vim.fn.readfile` is passed as a function, without calling it first. Writing `pcall(vim.fn.readfile(...))` would run the read before `pcall` could protect it.

When no limit is provided, the code calls `readfile` without the extra arguments. On failure, it returns `nil, message`; on success, it returns the lines.

A caller can therefore write:

```lua
local lines, problem = read(path, 3)
```

These are **multiple return values**, not an automatically constructed Kotlin-style `Pair`. On success, the absent second return value becomes `nil`.

One Lua rule matters throughout this file: **only `false` and `nil` are false-like**. Both `0` and `''` are true-like. Consequently, `if limit then` checks for a supplied truthy value, not for a positive number.

### `theme.lua`: `palette` - turning declarations into a color map

```lua
local result = {}
for _, line in ipairs(lines) do
  local role, rgb = line:match(pattern)
```

`ipairs` walks the consecutive entries of a list-style table, starting at index 1. It supplies both index and value. `_` is an ordinary variable name conventionally used to say “I am ignoring this value.”

`line:match(pattern)` searches using a **Lua pattern**. Parenthesized parts of that pattern capture values; here they capture the palette role and its RGB color.

Lua patterns are not full regular expressions. The exact patterns used by this helper are supplied by `selection()`, which we will decode next.

For each matching declaration, the helper checks:

```lua
if #rgb ~= 6 or result[role] then
  return nil, 'Invalid or duplicate ' .. label .. ' base' .. role
end
result[role] = rgb:lower()
```

A color such as `fb0120` is a six-digit hexadecimal RGB value: two digits each for red, green, and blue. Hexadecimal uses digits `0–9` and letters `A–F`.

`#rgb` measures the string’s **byte length**, not its visible width. Those are equivalent for these ASCII hexadecimal digits, but not generally for Unicode text.

`result[role]` looks up a table entry by key. If an entry already exists, this is a duplicate declaration. Otherwise, the color is converted to lowercase and stored, making RGB letter case irrelevant to later comparisons.

After reading declarations, the helper verifies that every required role exists:

```lua
for i = 0, count - 1 do
  local role = ('%02X'):format(i)
```

A numeric Lua `for` loop includes its endpoint. `%02X` is a **format string**, not a Lua pattern: it produces uppercase hexadecimal padded to at least two digits, such as `00`, `09`, `0A`, and `17`.

With `count = 16`, the required roles are `00` through `0F`; with `count = 24`, they are `00` through `17`. These role names are string keys, not list indexes.

The result is conceptually:

```lua
{ ['00'] = '000000', ['01'] = '303030', ... }
```

Lines that do not match the supplied declaration pattern are ignored. This is a reader for specific declaration formats, not a general shell or Lua parser.

### `theme.lua`: `selection` - choosing and validating a theme

This helper determines the theme name and whether its background should be treated as dark or light.

```lua
local path = vim.fn.expand('~/.zsh/.tinted')
local stat, err, code = vim.uv.fs_lstat(path)
```

`expand` resolves `~` to the home directory. `vim.uv` exposes libuv’s lower-level facilities, including filesystem inspection. `fs_lstat` inspects the path itself rather than following a final symbolic link to its target.

There are two importantly different situations:

| Situation | Result |
|---|---|
| The state file does not exist, reported as `ENOENT` | Return the default `bright`, `dark`. |
| The path cannot be inspected for another reason | Return `nil` and an error message. |

A dangling symbolic link is not treated like a completely absent entry: `lstat` can see the link, and the later read fails.

The expected state format is exactly two lines, for example:

```text
base16-bright
dark
```

This illustrates the format; it is **not a claim about your current saved theme**. Your personal theme files were not inspected.

The code reads up to three lines so that it can reject a third line without reading an arbitrarily long file. It requires exactly two lines and accepts only `dark` or `light` as the second line.

The first line is checked with:

```lua
'^base(%d+)%-([a-z0-9][a-z0-9_-]*)$'
```

Read the pattern as follows:

| Part | Meaning |
|---|---|
| `^` and `$` | Match the entire line, from beginning to end. |
| `base` | Literal text. |
| `(%d+)` | Capture one or more decimal digits as the family. |
| `%-` | Match a literal hyphen. `%` escapes its special pattern meaning. |
| `[a-z0-9]` | Require the theme name to begin with a lowercase letter or digit. |
| `[a-z0-9_-]*` | Allow zero or more remaining lowercase letters, digits, underscores, or hyphens. |

A separate condition accepts only families `'16'` and `'24'`. The captures are strings, so the code compares against strings here.

This excludes names containing path separators, dots, spaces, or arbitrary command text. Rejected values are shown using `vim.inspect`, which produces a readable representation of a Lua value.

The helper then reads two sources:

```text
Local reference: pack/bundle/opt/base16-nvim/colors/<name>.lua
Shell palette:   ~/.zsh/tinted-shell/scripts/<full-scheme-id>.sh
```

The local reference is parsed with:

```lua
'^local gui(%x%x) = "#(%x+)"$'
```

`%x` means a hexadecimal digit. The pattern recognizes declarations such as:

```lua
local gui0A = "#fda331"
```

It captures `0A` and `fda331`. Its spaces and double quotes are literal requirements.

The shell pattern is assembled using the selected family. For Base16, its effective form is:

```lua
'^%s*export BASE16_COLOR_(%x%x)_HEX="(%x+)"%s*$'
```

`%s*` allows optional whitespace at the beginning and end. The captured role and color are processed by the same `palette` helper. `tonumber(family)` converts `'16'` or `'24'` into the required numeric role count.

**Validation reads these files as data. It does not execute the shell script or evaluate the theme’s Lua code to discover its colors.** Applying the accepted colorscheme later is a separate operation.

The local reference always supplies 24 roles. To compare a 16-role shell palette against it, the code fills the additional roles using this mapping:

| Additional role | Copied from |
|---|---|
| `10`, `11` | `00` |
| `12` | `08` |
| `13` | `0A` |
| `14` | `0B` |
| `15` | `0C` |
| `16` | `0D` |
| `17` | `0E` |

This uses `pairs`, which iterates map entries without promising an order. Order is unimportant because each extra role copies an already-existing base role.

Finally, all 24 colors must match. A matching filename alone is insufficient. A mismatch returns a message naming the conflicting role and both colors; success returns the short theme name and the saved `dark`/`light` value.

### `theme.lua`: `highlights` - customizing the selected colorscheme

```lua
local p = require('wincent.pinnacle')
local dark = vim.o.background == 'dark'
p.merge('Comment', { italic = true })
```

`vim.o` reads or writes editor options using ordinary Lua values. Its behavior follows Neovim’s option scope: it is not simply a table of exclusively global settings. Here, `background` tells colorscheme-related code whether to use a dark or light presentation.

Pinnacle is an existing plugin that makes highlight manipulation more convenient:

| Operation | Meaning |
|---|---|
| `p.set(name, definition)` | Replace a group’s definition. |
| `p.merge(name, additions)` | Preserve its existing definition while replacing or adding specified fields. |
| `p.link(name, target)` | Make one group use another group’s style. |
| `p.dump(name)` | Retrieve a table containing the resolved style. |
| `p.clear(name)` | Clear a group’s definition. |
| `p.fg` / `p.bg` | Retrieve foreground or background color. |
| `p.embolden`, `p.italicize`, `p.decorate` | Produce styled copies for subsequent use with `p.set`. |

**Foreground** means the text or symbol color; **background** means the color behind it. In definitions, these are `fg` and `bg`. `ctermfg` specifies an indexed terminal foreground color, while `sp` specifies a special color used for effects such as underlines.

The file repeatedly uses expressions such as:

```lua
dark and 239 or 249
```

Lua’s `and` and `or` return operands, not necessarily booleans. This works like Kotlin’s `if (dark) 239 else 249` because the middle value, `239`, is truthy. The idiom would not behave like a conditional expression if that middle value were `false` or `nil`.

Here is what each group of customizations does:

| Code target | Visible purpose |
|---|---|
| `Comment` | Preserve its existing colors and add italics. |
| `Conceal` | Assign a subdued gray style for text that syntax rules conceal or replace. **Concealment changes display, not the underlying text.** |
| `IndentBlanklineChar` | Set a dark/light-dependent gray and prevent combining with other highlighting. This is not sufficient by itself for the installed v3 guide renderer. |
| `NonText ? Conceal` | Give editor-generated non-text markers the subdued conceal style. |
| `CursorLineNr` | Copy the current `DiffText` style for the line number beside the cursor. |
| `Pmenu ? Visual` | Style the completion popup using the selection style. This does not install a completion engine. |
| `VertSplit ? LineNr` | Style vertical window separators like line numbers. |
| `vimUserFunc` | Clear that Vim-script syntax group’s specific styling; it does not remove any functions. |
| `PmenuSel` | Set the selected completion entry’s blend to zero, making it opaque. |
| `DiffAdded`, `DiffFile`, `DiffNewFile`, `DiffLine`, `DiffRemoved` | Remove the `bg` field from those diff-text styles while retaining their other attributes. |
| `DiffDelete ? Conceal` | Give deleted-area presentation the subdued conceal style. |
| `DiffAdd`, `DiffText` | Set green and blue backgrounds respectively for added and changed areas in a comparison. |
| `SpellBad` | Use red for the special-color component of misspelling highlighting. |
| `QuickFixLine ? PmenuSel` | Give the selected quickfix entry the selected-menu style. Quickfix is an editor list of locations, often errors or search results. |
| `Search` | Use a bold copy of `Underlined` for search matches. |

Inside the diff-style loop:

```lua
definition.bg = nil
```

Assigning `nil` removes a table entry. The revised table is then applied to the group.

There is also a useful distinction between a **copy** and a **link**. `CursorLineNr` copies `DiffText` before the code changes `DiffText` to blue. It does not automatically inherit that later change. A linked group, by contrast, follows its target.

#### Floating-window and diagnostic styles

A **floating window** is an overlay rather than an ordinary tiled split—often used for documentation or diagnostic messages.

```lua
local float = p.adjust_lightness('Normal', dark and 0.1 or -0.1)
p.set('NormalFloat', float)
```

Pinnacle creates a copy of the normal text style with its RGB foreground and background lightness adjusted. Here, `0.1` means an increase of 10 lightness points on a 0–100 scale, not “multiply the existing brightness by 1.1.” A light theme gets the corresponding decrease.

The variable `float` contains a **style table**, not a window. After applying it to `NormalFloat`, the code changes the table’s foreground to white or black, adds the current `winblend` value, and applies that version to `FloatBorder`.

The diagnostic loop handles `Error`, `Warn`, `Info`, and `Hint`:

| Presentation | Style |
|---|---|
| Signs beside the text | Severity foreground on the `ColorColumn` background. |
| Virtual lines | Italic severity style. These are extra displayed rows, not file contents. |
| Virtual text | Italic and underlined severity style. This is annotation displayed alongside text, not inserted into it. |
| Floating messages | Italic; errors additionally use bold. |

Styling virtual text does not itself enable that presentation. The configuration later explicitly enables virtual **lines**.

`status.update_highlight()` then refreshes the statusline’s named styles. In `statusline.lua`, `User1` is an italic statusline style, `User3` is bold, and `User4`, `User7`, and `User5` color the separators and information sections. The accent comes from `ModeMsg` when the current buffer has unsaved changes, and from `Identifier` otherwise. The inactive statusline group is linked to the italic style.

Finally, the code sets `IblIndent` and `IblWhitespace` from `Whitespace`, and `IblScope` from `LineNr`. These are the groups relevant to the installed indentation-guide plugin. `vim.api.nvim_get_hl` retrieves highlight definitions through Neovim’s core API; its `0` here denotes the standard global highlight namespace.

Rebuilding the plugin’s highlight setup and calling `refresh_all()` makes already-rendered guides use the new colors.

### `theme.lua`: `M.refresh` - applying a selection safely

```lua
function M.refresh()
  local name, background = selection()
```

This function is attached to `M`, making it available to callers of the module. The dot denotes ordinary table-field access; there is no implicit receiver argument as there would be with a colon-style method.

`appearance.lua` preserves its existing public name with `M.refresh_theme = theme.refresh`. This assigns the same function to another table field; it does not call it or duplicate its state.

On success, `selection()` returns a name and background. On failure, it returns `nil` and a message—so the variable called `background` temporarily contains that message.

The resulting policy is:

| Selection result | Behavior |
|---|---|
| State file absent | Apply Bright/dark without an invalid-state warning. |
| Invalid selection before any successful initialization | Warn and apply Bright/dark. |
| Invalid selection after initialization | Warn and leave the current theme **and background** unchanged. |
| Valid selection | Apply the requested theme and background, and clear the remembered warning. |

`last_warning` suppresses repeated notifications containing the same rejection. It does not stop later attempts to read and validate the selection.

Application is protected like this:

```lua
applying = true
local ok, err = pcall(function()
  vim.o.background = background
  vim.cmd.colorscheme(name)
end)
applying = false
```

`function() ... end` creates an anonymous function, similar to a Kotlin lambda. It captures the surrounding `name` and `background` variables.

`vim.cmd` runs Neovim editor commands. For example, `vim.cmd.colorscheme('bright')` corresponds to entering `:colorscheme bright` in the editor’s command line.

Changing a colorscheme raises a `ColorScheme` event. `appearance.lua` registers `theme.on_colorscheme` as its callback. That exported callback checks the private `applying` flag in `theme.lua` and skips duplicate customization during an internal application. After the command completes, `highlights()` applies those customizations once.

The flag is reset even when the protected operation fails. In that case, the function raises an explicit error. **This is different from an invalid saved selection: a colorscheme-application failure is not silently converted into a successful fallback, and there is no rollback implementation here.**

After successful customization, `initialized` becomes `true`.

The focus-return flow will be:

```text
FocusGained -> appearance.refresh_theme / theme.refresh -> select/validate/apply -> refresh windows
```

### `appearance.lua`: `M.tablabel` and `M.tabline` - labels and clickable tab regions

The nested expression in `tablabel` performs these operations:

| Operation | Result |
|---|---|
| `tabpagebuflist(number)` | Buffers displayed by that tab page’s windows. |
| `tabpagewinnr(number)` | The active window’s number within that tab page. |
| Indexing the buffer list | The buffer shown by that window. |
| `bufname(...)` | That buffer’s name. |
| `fnamemodify(..., ':~:.')` | Use home-relative or current-directory-relative notation where applicable. |
| `pathshorten(...)` | Abbreviate directory components. |

For example, a path like `src/main/Main.kt` can become `s/m/Main.kt`. An unnamed buffer can produce an empty label; this function does not invent a replacement name.

The tabline builder then appends one formatted region per tab:

```lua
line = line .. (i == vim.fn.tabpagenr() and '%#TabLineSel#' or '%#TabLine#')
  .. '%' .. i .. 'T %{v:lua.require("buho.appearance").tablabel(' .. i .. ')} '
```

This is not just display text. Neovim interprets special formatting sequences:

| Sequence | Meaning |
|---|---|
| `%#TabLineSel#` | Use the selected-tab highlight group. |
| `%#TabLine#` | Use the ordinary tab highlight group. |
| `%1T`, `%2T`, and so on | Associate that region with the numbered tab’s native click target. |
| `%{...}` | Evaluate an expression and insert its result. |
| `v:lua...` | Call Lua from Neovim’s expression language. |
| `%#TabLineFill#` | Style the remaining bar area. |
| `%T` | Reset the explicit numbered tab target. |

`tabpagenr('$')` means “the last tab number,” while `tabpagenr()` gives the current one. The surrounding spaces provide label padding.

The label is inserted as an expression result rather than pasted directly into the formatting instructions, so a filename containing `%` remains label text instead of becoming a formatting directive.

### `appearance.lua`: `M.foldtext` - describing hidden lines

```lua
local count = vim.v.foldend - vim.v.foldstart + 1
local first = vim.fn.getline(vim.v.foldstart)
local whitespace = first:match('^%s*')
```

`vim.v` exposes predefined Neovim variables. While Neovim is evaluating a fold summary, `foldstart` and `foldend` identify its boundaries. The `+ 1` makes the line count inclusive.

The function reads the first folded line and captures its leading whitespace. In `^%s*`, `^` means the start of the string, `%s` means whitespace, and `*` means zero or more occurrences.

Its indentation calculation uses two substitutions:

```lua
local indent = #whitespace:gsub(' +', '') * vim.bo.tabstop
  + #whitespace:gsub('\t', '')
```

`gsub` replaces matching occurrences. For ordinary spaces and tabs, the first part removes spaces and counts the remaining tabs, assigning each `tabstop` columns; the second removes tabs and counts spaces.

`vim.bo` accesses **buffer options**, here the current buffer’s tab width. This calculation treats each tab as a fixed `tabstop` contribution; it is not a general display-width calculation for every mixture of tabs and spaces.

The result contains the number of hidden lines, padding dots, and the first line without leading whitespace. For the example represented in the existing checks:

```text
»··[3?]·: nested()
```

`('·'):rep(n)` repeats the dot string. `math.max(..., 0)` prevents a negative repetition count, and `#tostring(count)` measures how many ASCII digits the line count occupies.

The final pattern, `^%s*(.-)$`, consumes leading whitespace and captures the remaining text. `.-` is Lua’s minimal-repetition form; the end anchor requires the capture to extend through the remaining line. It does not remove trailing spaces.

Remember that Unicode symbols can occupy multiple bytes even when they display in one cell. Lua’s `#` is not a screen-width calculator.

**This function only formats a fold that already exists. It does not decide which lines fold or create folding rules.**

### `appearance.lua`: `floating` and `window` - styling each editing area

```lua
local function floating(win)
  local config = vim.api.nvim_win_get_config(win)
  return config.relative ~= '' or config.external
end
```

`vim.api` provides core editor operations. Window APIs take numeric window identifiers; in this call, `0` means the current window. That meaning is specific to the API argument—unlike the highlight namespace `0` encountered earlier.

A nonempty `relative` field indicates a floating window, and externally presented windows are also treated specially. `window(active)` immediately returns for either case, keeping ordinary split-window styling out of overlays.

This does not prevent the global `NormalFloat` and `FloatBorder` styles from applying to floating windows.

#### Options and stored variables are different things

| Interface | What it accesses |
|---|---|
| `vim.o` | Option values with normal Neovim setting semantics. |
| `vim.go` | The global value or default of an option. |
| `vim.bo` | Current-buffer options; `vim.bo[buf]` targets a specific buffer. |
| `vim.wo` | Current-window options; `vim.wo[win]` targets a specific window. |
| `vim.opt` | An option interface supporting Lua tables and operations such as `:append`. |
| `vim.opt_local` | That convenient option interface restricted to local settings. |
| `vim.g` | Global variables, not options. |
| `vim.b` | Buffer variables; `vim.b[buf]` targets a specific buffer. |
| `vim.w` | Window variables. |
| `vim.v` | Neovim’s predefined variables, such as the fold boundaries. |

For example, `vim.wo.signcolumn` is a real editor option. `vim.w.buho_signcolumn` is this configuration’s saved bookkeeping value.

The **sign column** is the gutter beside the text where diagnostic or other marker symbols appear. If the buffer has the module’s LSP-attached flag, the function saves the original sign-column setting once, then forces `signcolumn = 'yes'` to reserve space. When that flag is no longer set, it restores the saved setting and removes the saved variable.

The remaining settings distinguish normal files from help, diff, and quickfix views. **Diff mode** displays differences between versions; a `diff` filetype can also represent a textual patch. A quickfix buffer, with filetype `qf`, displays a list of locations. A **location list** is a similar list associated with a particular window.

| Setting | Behavior |
|---|---|
| `number`, `relativenumber` | Ordinary file buffers get line numbers. Active windows also show relative distances from the cursor; inactive ones keep absolute numbers. Help and special buffers retain their native numbering behavior. |
| `winhighlight` | Inactive ordinary windows receive the earlier `blurred` remapping. Active, diff, and quickfix windows do not. |
| `colorcolumn` | Ordinary windows receive the relative column band; diff and quickfix windows do not. |
| `list` | Whitespace markers appear only in active windows, excluding help and mail. |
| `conceallevel` | Help uses level 2: conceal-marked text is hidden unless a replacement character is supplied. Other filetypes use level 0, showing the text normally. |
| `cursorline` | Emphasize the cursor’s row only in an active window and outside modes whose name starts with `i`, meaning Insert mode. |
| `listchars` | Markdown, `hgcommit`, and `arc` use only the trailing-space marker; other filetypes use the full marker set. |
| `concealcursor` | For those prose-oriented types and Vim script, use `nc`: conceal on the cursor line in Normal and command-line modes. Otherwise, use the global setting. |
| `breakindent` | Enable indented display of wrapped continuation lines for Markdown. |
| `breakindentopt` | For Markdown, place the continuation marker before the added indentation and shift by `shiftwidth`; otherwise use the global value. |

`concealcursor` only matters when concealment is otherwise enabled. Setting it to `nc` does not override the `conceallevel = 0` assigned to non-help files.

Likewise, the special-buffer exceptions are selective: diff and quickfix avoid inactive shading and the column band, but they still participate in active/inactive statusline selection.

These rules deliberately remain in the window lifecycle. A filetype plugin alone cannot update an inactive window when focus changes, restore an LSP gutter when the displayed buffer changes, or recalculate the current mode's cursor-line emphasis.

#### What the supporting statusline module contributes

The final branch selects `status.focus_statusline()` or `status.blur_statusline()`.

For an active ordinary window, the helper uses the global statusline format installed by `status.set()`. For a quickfix or location-list window, it supplies a format containing the list label and title. Inactive windows get a simpler filename-or-list-title presentation.

The active ordinary format contains:

| Part | Source of its information |
|---|---|
| Left padding | Number-column width, total line-count digits, and supported sign-column states. |
| Modified marker | `?` when the buffer has unsaved changes. |
| File information | A shortened directory prefix and emphasized filename, with read-only, filetype, and non-default encoding details when applicable. |
| Right-side position | Current line / total lines, and virtual cursor column / end-of-line position. |

A **virtual column** is a displayed column accounting for things such as tab expansion, not simply a byte index. The position section appears only when the window is **wider than 80 columns**; at 80 or less it is reduced to a space.

Symbols such as `?` and `?` separate the colored sections. The formatting strings also use `%=` to separate left and right content and `%<` to mark where shortening may occur when space is limited.

`status.check_modified` is another name for `status.update_highlight`: assigning the function to another field does not call it. Later events use that alias to refresh the current buffer’s modified-state accent.

### `appearance.lua`: `windows` - applying rules in each window's context

```lua
local current = vim.api.nvim_get_current_win()
for _, win in ipairs(vim.api.nvim_list_wins()) do
  vim.api.nvim_win_call(win, function() window(focused and win == current) end)
end
```

The function records the current window, then visits Neovim’s windows.

`nvim_win_call` temporarily makes each window current while running the callback. Consequently, `vim.wo`, `vim.bo`, `vim.w`, and `vim.b` inside `window()` refer to the correct window and its displayed buffer.

The anonymous function captures `focused`, `win`, and `current`, much as a Kotlin lambda can capture surrounding variables.

A window is active only when **both** the editor is focused and that window is the recorded current window. Thus, losing application focus makes even the previously active editing window use the inactive presentation.

After updating the windows, the function refreshes the current buffer’s statusline colors.

```text
Leave old window -> style it inactive
Enter new window -> revisit windows -> style the current one active
```

### `language.lua`: `large` and `M.refresh` - controlling language-related presentation

The size guard considers two measurements:

```lua
return (stat and stat.size > 1024 * 1024)
  or vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > 1024 * 1024
```

The first is the file’s size on disk, obtained through `vim.uv.fs_stat`. The second is the buffer’s byte count, obtained by asking for the byte offset just after its last line.

Unlike the earlier `lstat`, `fs_stat` follows a symbolic link to the file. If there is no disk result—for example, for an unnamed buffer—the in-memory measurement still matters.

The threshold is **strictly greater than 1,048,576 bytes, or 1 MiB**. Exactly that size does not satisfy `>`. The in-memory count includes line-ending bytes according to Neovim’s API; it is not merely a count of visible characters.

Using both measurements means unsaved growth can trigger protection. Conversely, if the on-disk file is still oversized, shrinking only the unsaved buffer does not make the disk condition false.

`language.refresh(buf)` first maps the buffer's filetype to a parser and computes this size condition. Then it configures indentation guides:

```lua
require('ibl').setup_buffer(buf, {
  enabled = vim.bo[buf].expandtab and not oversized,
})
```

`expandtab` means the editor uses spaces when inserting tab-style indentation. The code checks that option; it does not inspect every line to prove that the file contains no tab characters.

The two features have **different conditions**:

| Feature | Conditions imposed here |
|---|---|
| Indentation guides | `expandtab` enabled and buffer not oversized, with plugin exclusions also applying. |
| Tree-sitter highlighting | A filetype in the `languages` map and buffer not oversized. It does not depend on `expandtab`. |

Markdown is explicitly excluded from guides later in setup, even if its buffer-level `enabled` value is true.

If there is no mapped language, the function returns **after** configuring guides. It takes no Tree-sitter action for that filetype.

For a mapped language, an oversized buffer has Tree-sitter highlighting stopped. Otherwise, highlighting starts only if no Tree-sitter highlighter is already active for that buffer.

`vim.treesitter` is Neovim’s built-in Tree-sitter interface; `ibl` is the module name exposed by the indentation-guide plugin. Basic indentation guides and syntax-aware scope emphasis are related but distinct—the latter relies on parsed structure.

```text
Text changes -> recalculate size -> update guides -> start/stop supported highlighting
```

This does not reload the theme on every edit, and stopping highlighting is not a claim that every possible Tree-sitter consumer has been disabled.

### `appearance.setup` and `language.setup` - loading existing dependencies

```lua
for _, package in ipairs({ 'base16-nvim', 'pinnacle', 'nvim-treesitter', 'indent-blankline.nvim' }) do
  vim.cmd.packadd(package)
end
```

Neovim has a native package system. Packages under `pack/.../opt/` are loaded explicitly with `packadd`; “optional” describes how they are loaded, not a promise that this configuration can work without them.

| Package | Its role here |
|---|---|
| `base16-nvim` | Supplies the local colorschemes. |
| `pinnacle` | Supplies highlight-manipulation helpers. |
| `nvim-treesitter` | Supplies parser-management support and language queries. |
| `indent-blankline.nvim` | Draws indentation and scope guides through `ibl`. |

**Loading these packages is not downloading or installing them.**

After loading these packages, `appearance.setup()` calls `language.setup()`. The latter specifies Neovim's standard data directory plus `/site` as the Tree-sitter installation location. `vim.fn.stdpath('data')` asks Neovim for the appropriate data path rather than hardcoding an operating-system-specific one.

The following registrations associate `sh` and `bash` with the Bash parser, and `query` and `scheme` with the query parser. They do not install those parsers or start a language server.

Setup then requires these parser names:

```text
c, lua, markdown, markdown_inline, query, vim, vimdoc,
kotlin, python, yaml, json, zsh, bash
```

For each one, it loads the parser and checks for a `highlights` query. A **query** describes which parts of the syntax tree should receive particular highlighting. The separate `markdown_inline` parser supports inline Markdown constructs within a Markdown document.

Failures use `assert` with explanatory messages. Lua’s `assert` is active whenever executed; it is closer to an always-enforced Kotlin `check` than to JVM assertions that can be disabled.

There is no automatic installer fallback in this function.

### `appearance.lua`: `M.setup` - editor options and diagnostic presentation

#### Display options

```lua
vim.opt.fillchars = { diff = '?', eob = ' ', fold = '·', vert = '?' }
vim.opt.listchars = listchars
vim.opt.linebreak = true
vim.opt.showbreak = '? '
```

`vim.opt` converts suitable Lua tables into the option format Neovim expects. For instance, a table with `trail` and `tab` fields becomes a correctly formatted `listchars` setting.

| Option | Effect |
|---|---|
| `fillchars.diff = '?'` | Use diagonal marks for filler rows used to align compared text. |
| `fillchars.eob = ' '` | Use a blank-looking non-breaking space for the unused rows beyond the buffer, instead of visible end-of-buffer markers. |
| `fillchars.fold = '·'` | Use dots for fold filler. |
| `fillchars.vert = '?'` | Use a vertical stroke for split separators. |
| `listchars` | Establish the whitespace symbols explained earlier. |
| `linebreak = true` | When wrapping is enabled, prefer word-friendly screen breaks rather than splitting words arbitrarily. This does not insert newline characters into the file. |
| `showbreak = '? '` | Mark wrapped continuation rows. |
| `pumheight = 20` | Limit the popup completion menu to 20 rows. |
| `showcmd = false` | Hide the display of a partially entered command; it does not disable the command line itself. |
| `sidescrolloff = 3` | Keep a horizontal margin of three columns around the cursor when applicable. |
| `synmaxcol = 200` | Limit traditional syntax processing on long lines. This is not the Tree-sitter size guard. |
| `vim.g.vim_json_syntax_conceal = 0` | Tell the JSON syntax support not to conceal its text. This is a global variable consumed by that support, not a built-in option assignment. |

The message configuration appends flags rather than replacing existing ones:

```lua
vim.opt.shortmess:append('AIOTWacot')
```

Each flag has a separate meaning:

| Flag | Effect |
|---|---|
| `A` | Suppress the “ATTENTION” message about an existing swap file, a file Neovim can use for recovery. |
| `I` | Suppress the startup introduction. |
| `O` | Allow file-read and quickfix messages to replace previous messages. |
| `T` | Shorten other overlong messages in the middle. |
| `W` | Suppress the “written” message after saving. |
| `a` | Use shorter forms such as line/byte abbreviations, `[+]`, and `[RO]`. |
| `c` | Suppress completion-status chatter. |
| `o` | Allow a following read message to replace a write message. |
| `t` | Shorten an overlong file message at its beginning. |

The tabline and foldtext settings contain expressions rather than immediate function calls:

```lua
vim.o.tabline = '%!v:lua.require("buho.appearance").tabline()'
vim.o.foldtext = 'v:lua.require("buho.appearance").foldtext()'
```

For `tabline`, `%!` means the expression produces the entire formatting string. `foldtext` is already an expression-valued option, so it does not need that prefix.

Neovim evaluates these expressions when it needs the presentation. The quoted strings do not execute the Lua calls at assignment time. `status.set()`, by contrast, is an immediate call that installs the default statusline format.

#### Diagnostic options

Two new tables associate severity numbers with highlight choices:

```lua
numhl[i], texthl[i] = 'DiagnosticSign' .. severity, ''
```

The ordered severities are Error, Warn, Info, and Hint. `numhl` chooses a line-number highlight for each severity; the empty `texthl` entries specify no explicit sign-text highlight group.

The nested configuration table then requests:

| Setting | Effect |
|---|---|
| `severity_sort = true` | Use severity-aware ordering. |
| `virtual_lines = true` | Display diagnostic messages using additional visual rows. |
| `signs.text = signs` | Use `?`, `?`, `??`, and `?` as the severity symbols. |
| `signs.numhl`, `signs.texthl` | Apply the per-severity highlight choices just built. |
| `float.border = 'single'` | Give diagnostic floating windows a single-line border. |
| `float.header = 'Diagnostics'` | Give those windows that header. |

The floating-message prefix is a callback:

```lua
prefix = function(diagnostic)
  return (signs[diagnostic.severity] or '•') .. ' ', ''
end
```

It returns two values: the prefix text and its highlight-group name. The text is the severity symbol plus a space, with `•` as a fallback; the group name is empty.

`vim.diagnostic` controls the presentation and handling of diagnostics. **Configuring it does not produce diagnostics, install a server, or automatically open a diagnostic window.**

### `appearance.lua`: `M.setup` - reacting to editor events

An **autocommand**, usually shortened to **autocmd**, is Neovim’s mechanism for running code in response to an event.

```lua
local group = vim.api.nvim_create_augroup('buho.appearance', { clear = true })
local function on(events, callback, pattern)
  vim.api.nvim_create_autocmd(events, { group = group, pattern = pattern, callback = callback })
end
```

The named group keeps this module’s event registrations together. `clear = true` removes previous registrations in that group, so repeating setup does not accumulate duplicate copies of these handlers. It does not remove other groups’ handlers.

The local `on` function is a shorthand used only inside setup. Its optional `pattern` narrows which occurrences trigger the callback. With no value supplied, there is no extra specific pattern filter.

Passing `windows` as a callback passes the function itself. Passing `windows()` would instead run it immediately and pass its return value.

#### Theme and focus events

| Event | Response |
|---|---|
| `ColorScheme` | Run `theme.on_colorscheme`: unless the theme module is already applying a theme, reapply custom highlights and mark initialization successful. |
| `FocusGained` | Mark the editor focused, refresh the saved theme selection, then refresh windows. |
| `FocusLost` | Mark the editor unfocused and refresh windows into their inactive presentation. |

The semicolons in the compact focus callbacks simply separate statements on one line.

A manually entered colorscheme command receives the same custom highlight layer. On the next focus regain, a valid saved shell selection can replace that manual choice again. There is no continuously running filesystem watcher.

#### Window and buffer transitions

| Event | Meaning and response |
|---|---|
| `VimEnter` | Startup has reached the editor-entry stage: refresh windows and language presentation for the current buffer. |
| `BufEnter` | A buffer becomes current: perform the same refresh. |
| `BufWinEnter` | A buffer is displayed in a window: perform the same refresh. |
| `WinEnter` | A window becomes current: perform the same refresh. |
| `WinLeave` | Style the departing window as inactive. |
| `BufLeave` | Restore any saved sign-column setting before the window moves away from that buffer, then clear the saved value. |

Several enter events can occur during one user action. The handlers recalculate current state rather than assuming that every action produces exactly one callback.

The `BufLeave` restoration matters because LSP attachment belongs to a **buffer**, while the reserved gutter setting belongs to a **window**. Without restoration, a window moving to an unrelated buffer could retain the previous buffer’s reservation.

#### Filetype detection

The `FileType` callback receives an event table containing `event.buf`, the buffer affected by the event. It does not have to assume that every operation concerns the currently displayed buffer.

The central callback calls `language.refresh(event.buf)` and updates windows. It no longer owns the Markdown/mail syntax-column exception; that setting belongs to the after-ftplugins described below.

Finally, it schedules another window refresh:

```lua
vim.schedule(function()
  if vim.api.nvim_buf_is_valid(event.buf) then windows() end
end)
```

A **filetype plugin**, or **ftplugin**, is configuration Neovim runs for a particular filetype. Built-in ftplugins also change presentation settings, such as the quickfix statusline. The deferred refresh is retained so the window rules are applied after filetype processing completes.

`vim.schedule` queues the function for later processing on Neovim’s event loop. It does not create a background thread. The delayed refresh lets later filetype configuration finish first, and the validity check avoids acting on behalf of a buffer that has since been deleted.

```text
FileType -> native ftplugins and matching after/ftplugin overrides
         -> language.refresh + window refresh
         -> scheduled window refresh
```

#### `after/ftplugin/markdown.lua` and `mail.lua`: filetype-only overrides

Both files contain:

```lua
vim.bo.synmaxcol = 0
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\n setlocal synmaxcol<'
```

Setting `synmaxcol` to zero removes the traditional syntax-column limit only for that buffer. This is separate from the Tree-sitter size guard.

The `after/` runtime entry places these files after the ordinary ftplugins. They do not set `b:did_ftplugin` or replace built-in Markdown/mail configuration.

`b:undo_ftplugin` contains commands Neovim executes before loading another filetype's plugin for the buffer. Appending to it preserves native cleanup. `setlocal synmaxcol<` resets the local option to the global value, currently `200`. This intentionally fixes the previous behavior in which changing a Markdown/mail buffer's filetype left `synmaxcol=0` behind.

Only this filetype-only option moved here. The focus-sensitive Markdown wrapping display rules and mail whitespace-marker exemption still belong to `window()`.

#### Typing, saving, and option changes

| Event | Response |
|---|---|
| `InsertEnter` | Disable cursor-line emphasis in a non-floating current window. |
| `InsertLeave` | Refresh all windows, including appropriate cursor-line emphasis. |
| `BufModifiedSet` | When the modified flag changes, refresh status colors and size-sensitive language presentation. |
| `BufWritePost` | After writing a buffer, do that same refresh. |
| `TextChanged` | After relevant text changes outside Insert mode, do that same refresh. |
| `TextChangedI` | After relevant text changes in Insert mode, do that same refresh. |
| `OptionSet`, pattern `expandtab` | Recalculate the affected buffer’s guide/highlighting conditions. |
| `OptionSet`, pattern `diff` | Recalculate window presentation for the changed comparison state. |

The `OptionSet` patterns are option names, not filename patterns in this usage. The modified-state event is not synonymous with every keystroke; it concerns changes to the buffer’s modified flag.

#### Language-server attachment and detachment

On `LspAttach`, the code sets:

```lua
vim.b[event.buf].buho_lsp_attached = true
```

It then refreshes windows, allowing `window()` to reserve a sign column for windows showing that buffer.

On `LspDetach`, the code schedules a check for later. Once the buffer is confirmed valid, it asks:

```lua
#vim.lsp.get_clients({ bufnr = event.buf }) > 0
```

`vim.lsp` is Neovim’s LSP interface. `get_clients` returns clients attached to that buffer; `#` measures the returned list’s length.

Deferring this query lets detachment bookkeeping finish before checking the remaining clients. If one server detaches while another remains, the flag stays true. Only when no clients remain does the next window refresh restore the saved gutter setting.

These handlers react to servers managed elsewhere. They do not start any servers.

#### Copy feedback

In Vim terminology, **yank** means copy text.

```lua
on('TextYankPost', function()
  vim.hl.on_yank({ higroup = 'Substitute', timeout = 200 })
end)
```

The native highlighting helper briefly marks the copied region using the `Substitute` style for 200 milliseconds. This gives visual confirmation of the copied range; it is not clipboard configuration.

### `appearance.lua`: `M.setup` - the first application

After registering the event handlers, setup finishes with:

```lua
require('ibl').setup({ indent = { char = '│' }, exclude = { filetypes = { 'markdown' } } })
M.refresh_theme()
windows()
language.refresh(vim.api.nvim_get_current_buf())
```

The nested `ibl` table chooses `│` as the indentation-guide character and explicitly excludes Markdown. Its setup remains in the coordinator because both theme customization and language refresh depend on initialized guides.

The order then establishes the initial presentation:

1. Configure the guide plugin, so the theme customizations can refresh its styles.
2. Select and apply the theme.
3. Apply current-window and inactive-window presentation.
4. Configure guides and supported Tree-sitter highlighting for the current buffer.

Registering future events is not enough on its own: these direct calls make the current editor state look correct immediately.

### `return M` - handing each module to its caller

```lua
return M
```

This gives `require('buho.appearance')` the table containing the public functions:

```text
refresh_theme, tablabel, tabline, foldtext, setup
```

`theme.lua` exports `refresh` and `on_colorscheme`; its `read`, `palette`, `selection`, and `highlights` helpers remain local. `language.lua` exports `setup` and `refresh`, with `large` local to that module. `window` and `windows` remain local to `appearance.lua`. Exported functions and registered callbacks can use their own module's private state through Lua closures.

When `plugin/appearance.lua` receives the appearance table and calls `.setup()`, the previously defined setup body runs. The final `return M` itself does not call setup.

## 4. Analogy

Think of `appearance.lua` as a **stage manager preparing a workspace and responding to cues**, with theme and language helpers responsible for their own work.

| Stage-manager responsibility | Literal code responsibility |
|---|---|
| Prepare the workspace before use | `setup()` loads existing packages, sets options, registers callbacks, and performs the first refresh. |
| Check that everyone has the same color chart | `selection()` inside `theme.lua` compares the shell palette with the local Neovim reference palette before accepting it. |
| Emphasize the area receiving attention | `window(active)` changes numbering, markers, shading, and the statusline according to focus and window identity. |
| React to cues rather than repeat all preparation constantly | Event callbacks perform the relevant updates after focus changes, edits, filetype detection, theme changes, and server attachment. |

The literal implementation is ordinary Lua functions plus Neovim event registrations. The analogy explains their coordination; it does not imply a separate process watching everything continuously.

## 5. Neovim Flows: A Reference

| What happens | Flow through this configuration |
|---|---|
| **Neovim starts** | `init.lua` sets editing defaults -> native `plugin/appearance.lua` calls `appearance.setup()` -> packages, parser validation, options/events -> initial guide, theme, window, and language setup. |
| **You return to the editor** | `FocusGained` -> mark focused -> `theme.refresh()` validates and applies or retains/falls back -> refresh windows. |
| **You leave the editor** | `FocusLost` -> mark unfocused -> refresh ordinary windows into inactive presentation. |
| **You switch windows or buffers** | Leave events style the departing window and restore its saved gutter -> enter events refresh windows and `language.refresh()` for the current buffer. |
| **You type or save** | Insert-mode events adjust cursor-line emphasis -> text/modified/save events update status colors and size-sensitive guides/highlighting. |
| **A filetype is detected** | Native ftplugins and matching after-ftplugins apply -> the central `FileType` callback refreshes language/windows -> scheduled window refresh. |
| **A buffer changes filetype** | Native ftplugin cleanup runs, including `synmaxcol<` for Markdown/mail -> the new filetype's plugins and appearance callbacks run. |
| **A colorscheme changes** | `ColorScheme` -> `theme.on_colorscheme()` reapplies custom styles unless its private `applying` flag marks an internal change. |
| **A language server attaches or detaches** | Attachment marks buffer state and reserves the gutter -> deferred detachment checks remaining clients -> retain or restore each window's saved gutter. |
| **You copy text** | `TextYankPost` -> briefly highlight the copied region with `Substitute`. |

## 6. Checking the Runtime Layout

From the repository root:

```sh
nvim --headless -u NONE -i NONE -n -l nvim/.config/nvim/check-appearance.lua
```

The controlled check explicitly loads the entry point because its `-u NONE` child skips automatic startup. Its runtime path includes the configuration's `after/` directory. Separate isolated children start normally, without a direct setup call or manual plugin source, to verify actual native entry discovery, initial files, `--noplugin`, and first-start theme behavior. Startup errors and unexpected warnings fail the check.

The same check retains exact rendering/style assertions and exercises filetype cleanup, repeated setup, window/LSP transitions, parser/guide behavior, and the exact 1 MiB boundary. HOME/XDG fixtures are temporary; the check does not change the real saved shell theme or recolor the terminal.
