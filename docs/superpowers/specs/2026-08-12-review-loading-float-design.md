# A loading float for starting a review

## The problem

Opening a pull request or issue buffer shows a loading float: `octo.ui.pr-loading`, put up
in `octo/init.lua` before the fetch and taken down in its callback. Starting a *review*
shows nothing, though it waits at least as long and often longer.

The review has two waits, back to back:

1. `Review:start` / `:resume` / `:start_or_resume` runs a GraphQL call —
   `addPullRequestReview` or `pending_review_threads`. Nothing is on screen at all.
2. `Review:initiate` opens the layout, then `pr:get_changed_files` fetches the file list.
   The layout is up but empty until `set_files_and_select_first` paints the first diff.

Both entry points are also fronted by `get_pr_from_buffer_or_current_branch`, which is
itself asynchronous when the PR has to be resolved from the branch.

Between pressing the key and seeing a diff, the editor looks stopped.

## What this adds

One continuous float, from the key press until the first file diff is painted, with its
message changing as the work moves on:

```
press key
  ├─ float: "owner/repo #123  starting review…"
  │    get_pr_from_buffer_or_current_branch
  │    GraphQL: addPullRequestReview / pending_review_threads
  ├─ float: "owner/repo #123  loading changed files…"
  │    Layout:open()          ← windows appear underneath, in a new tabpage
  │    pr:get_changed_files()
  └─ float hides              ← first file diff painted
```

It reports and never gates, the rule `octo.ui.pr-loading` and `octo.ui.loading` already
follow: `enter = false`, `focusable = false`, every key still reaches the buffer
underneath.

## Design

### `octo.ui.pr-loading` gains two things

Extending the existing module rather than adding one: the float, the spinner, the
highlights, the deadline and the teardown are all there and correct.

**An optional message.** `M.show(repo, kind, id, message)`, where `message` defaults to
`"fetching…"`. The existing call site in `octo/init.lua` is untouched.

**Tabpage awareness.** `M.is_open()` today is `win ~= nil and nvim_win_is_valid(win)`. A
float belongs to the tabpage it was created in, and `Layout:open()` runs `tab split` — so
after the layout opens, the float is stranded in the previous tabpage while `is_open()`
still answers true, and `M.show` would update a window nobody can see. Verified directly:

```
float opened in tabpage 1
after `tab split`, current tabpage is 2
float window still valid: true
float's tabpage: 1
float is among the NEW tab's windows: false
```

`M.is_open()` gains an "…and it is in the current tabpage" condition. `M.show` then
re-opens the float where the reader now is, which is what makes one continuous float
possible across the layout opening. It is also a latent correctness fix for the existing
description path, which would have the same problem the moment anything tab-splits under
it.

### Call sites, all in `octo/reviews/init.lua`

| Point | Action |
|---|---|
| `start_review`, `resume_review`, `start_or_resume_review`, `browse_review` | `show(…, "starting review…")`, before `get_pr_from_buffer_or_current_branch` |
| `Review:initiate`, after `Layout:open()` | `show(…, "loading changed files…")` — re-opens in the new tabpage |
| `set_files_and_select_first` | `hide()` |
| `utils.error "No pending reviews found for viewer"` | `hide()` |
| `browse_review`'s "Cannot browse when a review has been started" guard | `hide()` |
| GraphQL failure callbacks on the review queries | `hide()` |

`browse_review` is included: it waits on the same layout and file fetch, and a reader
cannot be expected to know that browsing takes a different code path from starting.

### The confirm prompt

`Review:initiate` may call `vim.fn.confirm("Currently not in PR branch, would you like to
checkout?")` before opening the layout. A spinner animating underneath a blocking prompt is
noise, and `checkout_pr_sync` blocks after it. The float hides before the confirm and is
shown again once it returns.

### Configuration

No new option. `ui.pr_loading` gates this too — someone who turned the float off did so
because they dislike the float, not because they dislike it specifically on issues.
`M.enabled()` is already consulted inside `M.show`, so the review call sites inherit the
gate without asking for it.

## Testing

`M.title` and `M.lines` are pure and already covered by `lua/tests/plenary/pr_loading_spec.lua`.
Added there:

- `M.show` with no message still says `fetching…`, so the description path is unchanged.
- A message passed to `M.show` reaches the drawn lines.
- `M.is_open()` is false after a `tab split` — the assertion that actually pins the fix,
  and the one that fails against the current code.

## Out of scope

- Any progress *fraction*. `pr:get_changed_files` answers once, with everything; there is
  no completed/total to report the way `octo.ui.loading` does for warmed previews.
- Submitting or rendering the review itself.
- The `octo.ui.loading` progress strip, which is a different surface for a different job.
