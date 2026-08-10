# PR buffer UI: rendered markdown, a loading float, keymap help and section buttons

Branch `feat/pr-buffer-ui`, worktree `/home/brianthemessiah/src/octo.nvim-prui`, off `master` (23328a9).

## The problem

Five gaps, all in what an octo buffer shows the reader:

1. Bodies and comments display raw markdown source. `**bold**` stays `**bold**`.
2. Picking a pull request from the list leaves the screen still until the fetch answers.
3. A comment popup binds four keys and advertises none of them.
4. Nothing anywhere says which keys a context has, except review mode's help bar.
5. Every action is a key you either know or do not; no section says what can be done to it.

Three of the five already have half an answer in the tree, built for a neighbouring
surface. This work generalises those halves rather than growing second copies:

| Exists | Built for | Wanted for |
|---|---|---|
| `pickers/fzf-lua/preview_markdown.lua` | picker preview buffers | live `octo://` buffers |
| `ui/loading.lua` | preview warming, corner strip | the list to buffer transition |
| `reviews/help-bar.lua` | four review contexts | popups, octo buffers, fzf |

## What is already true

Established by reading the tree and by probing nvim 0.12.4 headlessly. Each of these
was a design fork; none is an assumption.

- **Octo buffers already run `conceallevel = 2`** (`config.values.ui.conceallevel`,
  `config.lua:309`) over **legacy regex markdown syntax**, sourced by
  `after/syntax/octo.vim` via `runtime! syntax/markdown.vim`. That is precisely the
  combination `preview_markdown.lua`'s own docstring documents as broken: legacy
  `concealends` measures width without accounting for what conceal removes, so
  fixed-column content goes ragged. Bodies look half-rendered today *because* of this,
  not because rendering was never attempted.
- **Octo's own highlighting survives a treesitter switch.** Every colour octo applies
  to a buffer is an extmark or virtual text; the only `syntax match` calls in the
  codebase are in `debug/buffer.lua`, an unrelated buffer. Extmark highlights default
  to priority 4096 against treesitter's 100, so octo's bubbles, detail labels and
  usernames draw *over* the markdown highlighting rather than being lost to it.
- **The emoji conceals survive too.** `after/syntax/octo.vim`'s `matchadd('Conceal', …)`
  calls are window-local matches, not buffer syntax, so clearing `b:current_syntax`
  does not touch them.
- **Cursor-line reveal is free.** `concealcursor` defaults to `""`, so the line the
  cursor sits on already shows raw source. The requirement is to not break it.
- **`virt_lines` survive edits below them**, and a click resolves to a button row by
  `getmousepos().screenrow - vim.fn.screenpos(win, anchor_line, 1).row`.
- **Float `footer` is accepted** on nvim 0.12.4.
- **A `virt_lines` button can never hold the cursor.** It is virtual. Any design where
  a key "fires the button under the cursor" cannot work, and `<CR>` is in any case
  already `pr_options` / `issue_options`.

## Decisions

**Scope: every octo buffer kind.** `pull`, `issue`, `discussion`, `repo`, `release` all
render through `OctoBuffer` and carry the same `bodyMetadata` / `commentsMetadata`. An
issue showing raw markdown beside a rendered pull request would read as a bug.

**Markdown is region-scoped for block punctuation, buffer-wide for inline.**
`conceal_spans` runs only over metadata extents; a timeline event line opening with `-`
must not become a bullet. Treesitter's inline conceal (emphasis, backticks, link
targets) stays buffer-wide because it cannot be region-gated cheaply. Accepted residual:
a stray `*` in octo chrome may render as emphasis.

**Buttons carry their own key.** `[ ↩ Reply \cr ]`. The mouse activates them; a keyboard
reader presses the key printed on the button. No new keyboard machinery, no `<CR>`
collision, and the button doubles as the discoverability surface that made it worth
drawing.

**`g?` opens the keymap float in buffers and popups; `<C-g>` in fzf.** `?` is
backwards-search in a buffer the reader can edit, and both chosen keys are free against
every mapping in `config.lua` and every `picker_config.mappings` entry. The `⌨` symbol
stays as the visible marker; `g?` is what it tells you to press.

**Shared cores are extracted, not copied.** Each existing module hands its generic half
to a new module and delegates. One `conceal_spans`, one spinner, one `terse()`.

## Architecture

```
ui/markdown.lua      ◄── preview_markdown.lua (preview specifics)
  conceal_spans           delegates the pure core
  render_regions       ◄── octo-buffer.lua :render_markdown

ui/spinner.lua       ◄── ui/loading.lua (corner strip)
  FRAMES, frame_at        delegates frames + timer lifecycle
  controller           ◄── ui/pr-loading.lua (centered float)

ui/keymap-help.lua   ◄── reviews/help-bar.lua (winbar for review kinds)
  terse, pretty_lhs       delegates the pure formatters
  entries, truncate    ◄── ui/comment-popup.lua  (float footer)
  section, float       ◄── octo-buffer.lua       (winbar)
                       ◄── fzf-lua pickers       (--header)

ui/buttons.lua
  rows(kind, caps)     pure: what buttons a section has
  render(bufnr, secs)  virt_lines extmarks
  at_screen(win, pos)  click hit-testing
```

### `ui/markdown.lua`

Takes `BULLET`, `MAX_HEADING_LEVEL`, `fence_at`, `heading_span`, `bullet_span` and
`conceal_spans` from `preview_markdown.lua` unchanged; that module keeps `enabled`,
`available`, `start`, `decorate`, `render` and calls through for the pure part.

Adds `M.render_regions(bufnr, regions)` where a region is `{ first_line, last_line }`,
in its own namespace `octo_buffer_markdown` so it never clears the preview namespace.
`OctoBuffer` supplies regions from `bodyMetadata.startLine/.endLine` and each
`commentsMetadata` entry.

Gated on a new `ui.render_markdown` config value, defaulting true.

Recomputed on `TextChanged` / `TextChangedI`, debounced. Conceal extmarks shift with
edits on their own (probed), so the debounce only has to catch *newly typed* markdown,
never keep existing spans in place.

### `ui/spinner.lua` and `ui/pr-loading.lua`

`spinner.lua` takes `FRAMES`, `frame_at`, `INTERVAL_MS`, `TIMEOUT_MS` and the
start/stop/deadline timer lifecycle from `loading.lua`. `loading.lua` keeps its
corner-strip geometry, its `message`, its `lines` and its `preview_loading` gate.

`pr-loading.lua` opens a centered float over the transition, `enter = false` and
`focusable = false` so it reports and never gates — `loading.lua`'s existing rule.
Hooked into `init.lua`'s `M.load_buffer`: shown when the fetch starts, hidden on
render, on error, on buffer wipe, and on the inherited deadline.

Gated on a new `ui.pr_loading` config value, defaulting true.

### `ui/keymap-help.lua`

Takes `terse`, `pretty_lhs`, `truncate`, `CUT` and the entry-building half of `entries`
from `help-bar.lua`, which keeps `LABELS`, `ORDER`, `VARIABLE`, `EXPRESSION`, `winbar`
and `attach`.

Adds:

- `M.SYMBOL` — `⌨`, built with `nr2char` for the same reason `loading.FRAMES` is: a glyph
  that arrives empty is indistinguishable from a missing feature.
- `M.section(width)` — the ` │ ⌨ g? keys` segment, its own delimited section.
- `M.float(kind)` — a scrollable float listing every key for a context, grouped, closed
  by `q` or `<Esc>`.
- Context kinds beyond the four review ones: the octo buffer kinds, `comment_popup`,
  and the picker.

### `ui/buttons.lua`

`M.rows(kind, caps)` is pure: given a section kind and its capability flags
(`viewerCanUpdate`, `isResolved`, …) it returns `{ label, key, action, hl }` entries. It
is where the whole vocabulary lives, so the button set is asserted without a buffer.

| Section | Buttons |
|---|---|
| body | `+ Comment`, `😀 React`, `✎ Edit` when `viewerCanUpdate` |
| comment | `↩ Reply`, `😀 React`, `✎ Edit` / `🗑 Delete` when `viewerCanUpdate` |
| review thread | `↩ Reply`, `✓ Resolve` or `↺ Unresolve`, `😀 React` |
| buffer footer | `+ New Comment`, `✓ Submit`, `↺ Reload` |

`M.render(bufnr, sections)` draws them as `virt_lines` in namespace `octo_buttons`.
`M.at_screen(win, mousepos)` resolves a click. Every button dispatches to an existing
`octo.mappings` handler; this module introduces no new command behaviour.

Gated on a new `ui.section_buttons` config value, defaulting true.

### `ui/comment-popup.lua` and `ui/window.lua`

`create_centered_float` gains a `footer` option passed through to
`create_floating_window`. The popup sets its footer from `keymap_help.section` and binds
`g?` to `keymap_help.float "comment_popup"`.

### fzf pickers

`fzf_opts["--header"]` gains the `⌨ <C-g> keys` section; `<C-g>` is bound to open the
float. Added at the shared call site rather than per picker.

### Configuration

Three new values under `ui`, all defaulting true, all following the pattern the existing
`ui` block uses:

| Value | Gates |
|---|---|
| `ui.render_markdown` | markdown rendering in octo buffers |
| `ui.pr_loading` | the centered loading float |
| `ui.section_buttons` | the per-section button rows |

Each needs a `validate_type` entry in `config.lua`'s validation pass and a row in
`doc/octo.txt`, so a typo is reported rather than silently ignored and the option is
discoverable from `:help octo`.

## Error handling

Everything here is decoration over a working buffer, so nothing may take one down.

- Markdown: `available()` already tests both parsers and returns false when either is
  missing; `render_regions` returns early rather than raising. Extmark writes stay in
  `pcall`, as `decorate` already does.
- Loading float: inherits `loading.lua`'s deadline, so a fetch that never answers cannot
  leave a spinner running. `WinClosed` takes it down if anything closes it directly.
- Buttons: a section whose metadata has no `startLine` is skipped. A click that resolves
  to no button does nothing.
- Keymap help: `entries` already mirrors `utils.apply_mappings`' own test for whether a
  mapping was made, so the float and the bar can never advertise a key nothing bound.

## Testing

Plenary specs under `lua/tests/plenary/`, matching the existing
`preview_markdown_spec.lua` / `review_help_bar_spec.lua` pattern: the pure functions
asserted without opening a window.

- `conceal_spans` over region boundaries — chrome outside a region is untouched.
- `buttons.rows` for each section kind and each capability combination.
- `keymap_help.section` and `float` content, including truncation.
- `spinner.frame_at` cycling, and that `loading.lua`'s existing spec still passes
  against the extracted core.

Then a live run: open a real pull request in nvim and confirm it renders, the float
appears on the transition, the footers and winbars carry the symbol, and a click
activates a button.

## Out of scope

- Rendering markdown in the review diff or thread buffers; they show code, not prose.
- Any change to what the buttons' underlying actions do.
- A button-focus mode with `h`/`l` navigation.
