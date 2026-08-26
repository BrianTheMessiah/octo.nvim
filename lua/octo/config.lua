local vim = vim
local M = {}

---@alias OctoMappingsWindow "issue" | "pull_request" | "review_thread" | "submit_win" | "review_diff" | "file_panel" | "repo" | "notification" | "runs" | "discussion"
---@alias OctoMappingsList { [string]: table}
---@alias OctoPickers "telescope" | "fzf-lua" | "snacks" | "default"
---@alias OctoSplit "right" | "left"
---@alias OctoMergeMethod "squash" | "rebase" | "merge"

---@class OctoPickerMapping
---@field lhs string
---@field desc string

---@class OctoPickerMappings
---@field open_in_browser OctoPickerMapping
---@field copy_url OctoPickerMapping
---@field checkout_pr OctoPickerMapping
---@field merge_pr OctoPickerMapping
---@field filter_mine OctoPickerMapping
---@field filter_all OctoPickerMapping
---@field filter_repo OctoPickerMapping

-- Type for a single action definition within the array
---@class OctoSnacksActionItem
---@field name string -- Mandatory identifier for the action
---@field fn function -- The function to execute
---@field lhs? string -- Optional keybinding
---@field desc? string -- Optional description
---@field mode? string[] -- Optional modes (e.g., {"n", "i"})

-- Type for the array of actions for a specific picker
---@alias OctoSnacksActionList OctoSnacksActionItem[]

---@class OctoPickerConfigSnacks
---@field actions { -- Actions are now arrays of tables
---    issues?: OctoSnacksActionList,
---    pull_requests?: OctoSnacksActionList,
---    notifications?: OctoSnacksActionList,
---    issue_templates?: OctoSnacksActionList,
---    search?: OctoSnacksActionList,
---    changed_files?: OctoSnacksActionList,
---    commits?: OctoSnacksActionList,
---    review_commits?: OctoSnacksActionList,
---  }

---@class OctoPickerConfig
---@field use_emojis boolean -- Used by fzf-lua
---@field mappings OctoPickerMappings
---@field snacks OctoPickerConfigSnacks -- Snacks specific config
---@field search_static boolean -- Whether to use static search results (true) or dynamic search (false)
---@field preview_wrap boolean -- Soft-wrap prose previews (issue/PR bodies) in the fzf-lua preview window
---@field preview_prefetch integer -- How many entries beyond the cursor to fetch previews for ahead of time (0 disables)
---@field preview_render_html boolean -- Rewrite the inline HTML in an issue or PR body as markdown in previews
---@field preview_render_markdown boolean -- Render the markdown in a preview body rather than showing its source
---@field preview_prefetch_all boolean -- Fetch a preview for every entry in a loaded list, not just around the cursor
---@field preview_prefetch_concurrency integer -- How many preview fetches may run at once
---@field preview_rate_limit_reserve integer -- GraphQL rate limit points to leave unspent by prefetching
---@field preview_loading boolean -- Show a progress strip while a picker's previews are being warmed

---@class OctoConfigColors
---@field white string
---@field grey string
---@field black string
---@field red string
---@field dark_red string
---@field green string
---@field dark_green string
---@field yellow string
---@field dark_yellow string
---@field blue string
---@field dark_blue string
---@field purple string

---@class OctoConfigFilePanel
---@field size number
---@field icons boolean|fun(name: string, ext: string): string?, string?

---@class OctoConfigUi
---@field conceallevel integer
---@field render_markdown boolean
---@field use_signcolumn boolean
---@field use_statuscolumn boolean
---@field use_foldtext boolean
---@field pr_loading boolean
---@field section_buttons boolean

---@class OctoConfigIssues
---@field order_by OctoConfigOrderBy

---@class OctoConfigReviews
---@field auto_show_threads boolean
---@field focus OctoSplit
---@field show_virtual_text boolean

---@class OctoConfigDiscussions
---@field order_by OctoConfigOrderBy

---@class OctoConfigWorkflowIcons
---@field pending string
---@field skipped string
---@field in_progress string
---@field failed string
---@field succeeded string
---@field cancelled string

---@class OctoConfigRuns
---@field icons OctoConfigWorkflowIcons

---@class OctoConfigNotifications
---@field current_repo_only boolean

---@class OctoConfigPR
---@field order_by OctoConfigOrderBy
---@field always_select_remote_on_create boolean
---@field use_branch_name_as_title boolean

---@class OctoConfigOrderBy
---@field field string
---@field direction "ASC" | "DESC"

---@class OctoMissingScopeConfig
---@field projects_v2 boolean

---@class OctoConfigPoll
---@field enabled boolean
---@field interval number
---@field notify_on_refresh boolean
---@field notify_on_change boolean

---@class OctoConfigDebug
---@field notify_missing_timeline_items boolean

---@class OctoConfigSearch
---@field completion_overrides table<string, string[]|fun(argLead: string, cmdLine: string): string[]>

---@alias OctoCommentStyle "popup" | "inline"

---@class OctoConfigDrafts
---@field enabled boolean
---@field sweep_after_days number

---@class OctoConfigComments
---@field style OctoCommentStyle
---@field style_overrides {[string]: OctoCommentStyle}
---@field drafts OctoConfigDrafts

---@class OctoConfig Octo configuration settings
---@field picker OctoPickers
---@field picker_config OctoPickerConfig
---@field default_remote table
---@field default_merge_method OctoMergeMethod
---@field default_delete_branch boolean
---@field ssh_aliases {[string]:string}
---@field reaction_viewer_hint_icon string
---@field commands table
---@field users string
---@field user_icon string
---@field ghost_icon string
---@field copilot_icon string
---@field dependabot_icon string
---@field comment_icon string
---@field outdated_icon string
---@field resolved_icon string
---@field timeline_marker string
---@field timeline_indent number
---@field use_timeline_icons boolean
---@field timeline_icons table
---@field right_bubble_delimiter string
---@field left_bubble_delimiter string
---@field github_hostname string
---@field use_local_fs boolean
---@field enable_builtin boolean
---@field snippet_context_lines number
---@field gh_cmd string
---@field gh_env (table<string, string|integer>)|(fun(): table<string, string|integer>)
---@field timeout number
---@field default_to_projects_v2 boolean
---@field suppress_missing_scope OctoMissingScopeConfig
---@field ui OctoConfigUi
---@field issues OctoConfigIssues
---@field reviews OctoConfigReviews
---@field runs OctoConfigRuns
---@field pull_requests OctoConfigPR
---@field file_panel OctoConfigFilePanel
---@field colors OctoConfigColors
---@field mappings { [OctoMappingsWindow]: OctoMappingsList}
---@field mappings_disable_default boolean
---@field discussions OctoConfigDiscussions
---@field notifications OctoConfigNotifications
---@field poll OctoConfigPoll
---@field search OctoConfigSearch
---@field debug OctoConfigDebug
---@field comments OctoConfigComments
---@field submit_on_write boolean

--- Returns the default octo config values
---@return OctoConfig
function M.get_default_values()
  -- BEGIN_CONFIG
  return {
    picker = "telescope", -- or "fzf-lua" or "snacks" or "default"
    picker_config = {
      use_emojis = false, -- only used by "fzf-lua" picker for now
      search_static = true, -- Whether to use static search results (true) or dynamic search (false)
      preview_wrap = true, -- soft-wrap prose previews (issue/PR bodies) in the fzf-lua preview window
      preview_prefetch = 5, -- how many entries beyond the cursor to fetch previews for ahead of time (0 disables)
      preview_render_html = true, -- rewrite the inline HTML in an issue or PR body as markdown in previews
      preview_render_markdown = true, -- render the markdown in a preview body rather than showing its source
      preview_prefetch_all = true, -- fetch a preview for every entry in a loaded list, not just around the cursor
      preview_prefetch_concurrency = 6, -- how many preview fetches may run at once
      preview_rate_limit_reserve = 500, -- GraphQL rate limit points to leave unspent by prefetching
      preview_loading = true, -- show a progress strip while a picker's previews are being warmed
      mappings = { -- mappings for the pickers
        open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        copy_sha = { lhs = "<C-e>", desc = "copy commit SHA to system clipboard" },
        checkout_pr = { lhs = "<C-o>", desc = "checkout pull request" },
        merge_pr = { lhs = "<C-r>", desc = "merge pull request" },
        filter_mine = { lhs = "<A-m>", desc = "narrow to pull requests you opened" },
        filter_all = { lhs = "<A-a>", desc = "widen to all open pull requests" },
        filter_repo = { lhs = "<A-r>", desc = "narrow the loaded pull requests to one repository" },
      },
      snacks = { -- snacks specific config
        -- Initialize actions as empty arrays
        actions = { -- custom actions for specific snacks pickers (array of tables)
          issues = { -- actions for the issues picker
            -- { name = "my_issue_action", fn = function(picker, item) print("Issue action:", vim.inspect(item)) end, lhs = "<leader>a", desc = "My custom issue action" },
          },
          pull_requests = { -- actions for the pull requests picker
            -- { name = "my_pr_action", fn = function(picker, item) print("PR action:", vim.inspect(item)) end, lhs = "<leader>b", desc = "My custom PR action" },
          },
          notifications = {}, -- actions for the notifications picker
          issue_templates = {}, -- actions for the issue templates picker
          search = {}, -- actions for the search picker
          -- ... add actions for other pickers as needed
          changed_files = {},
          commits = {},
          review_commits = {},
        },
      },
    },
    default_remote = { "upstream", "origin" }, -- order to try remotes
    default_merge_method = "merge", -- default merge method which should be used for both `Octo pr merge` and merging from picker, could be `merge`, `rebase` or `squash`
    default_delete_branch = false, -- whether to delete branch when merging pull request with either `Octo pr merge` or from picker (can be overridden with `delete`/`nodelete` argument to `Octo pr merge`)
    ssh_aliases = {}, -- SSH aliases. e.g. `ssh_aliases = {["github.com-work"] = "github.com"}`. The key part will be interpreted as an anchored Lua pattern.
    reaction_viewer_hint_icon = " ", -- marker for user reactions
    commands = {}, -- additional subcommands made available to `Octo` command
    users = "search", -- Users for assignees or reviewers. Values: "search" | "mentionable" | "assignable"
    user_icon = " ", -- user icon
    ghost_icon = "󰊠 ", -- ghost icon
    copilot_icon = " ", -- copilot icon
    dependabot_icon = " ",
    comment_icon = "▎",
    outdated_icon = "󰅒 ",
    resolved_icon = " ",
    timeline_marker = " ",
    timeline_indent = 2,
    use_timeline_icons = true,
    timeline_icons = {
      auto_squash = "  ",
      blocking = "  ",
      commit_push = "  ",
      comment_deleted = "  ",
      duplicate = "  ",
      force_push = "  ",
      draft = "  ",
      ready = " ",
      commit = "  ",
      deployed = "  ",
      issue_type = "  ",
      label = "  ",
      reference = "  ",
      project = "  ",
      connected = "  ",
      subissue = "  ",
      cross_reference = "  ",
      transferred = "  ",
      parent_issue = "  ",
      head_ref = "  ",
      pinned = "  ",
      milestone = "  ",
      renamed = "  ",
      automatic_base_change_succeeded = "  ",
      base_ref_changed = "  ",
      merged = { "  ", "OctoPurple" },
      closed = {
        closed = { "  ", "OctoRed" },
        completed = { "  ", "OctoPurple" },
        not_planned = { "  ", "OctoWhite" },
        duplicate = { "  ", "OctoWhite" },
      },
      reopened = { "  ", "OctoGreen" },
      assigned = "  ",
      locked = "  ",
      merge_queue = "  ",
      review_requested = "  ",
    },
    right_bubble_delimiter = "", -- bubble delimiter
    left_bubble_delimiter = "", -- bubble delimiter
    github_hostname = "", -- GitHub Enterprise host
    use_local_fs = false, -- use local files on right side of reviews
    enable_builtin = false, -- shows a list of builtin actions when no action is provided
    snippet_context_lines = 4, -- number of lines around commented lines
    gh_cmd = "gh", -- Command to use when calling Github CLI
    gh_env = {}, -- extra environment variables to pass on to GitHub CLI, can be a table or function returning a table
    timeout = 5000, -- timeout for requests between the remote server
    default_to_projects_v2 = false, -- use projects v2 for the `Octo card ...` command by default. Both legacy and v2 commands are available under `Octo cardlegacy ...` and `Octo cardv2 ...` respectively.
    suppress_missing_scope = {
      projects_v2 = false,
    },
    ui = {
      conceallevel = 2, -- conceallevel for octo buffers
      render_markdown = true, -- render the markdown in bodies and comments rather than showing its source
      use_signcolumn = false, -- show "modified" marks on the sign column
      use_statuscolumn = true, -- show "modified" marks on the status column
      use_foldtext = true,
      pr_loading = true, -- show a loading float while a picked issue or pull request is fetched
      section_buttons = true, -- draw a row of actions under each body, comment and thread
    },
    issues = {
      order_by = { -- criteria to sort results of `Octo issue list`
        field = "CREATED_AT", -- either COMMENTS, CREATED_AT or UPDATED_AT (https://docs.github.com/en/graphql/reference/enums#issueorderfield)
        direction = "DESC", -- either DESC or ASC (https://docs.github.com/en/graphql/reference/enums#orderdirection)
      },
    },
    discussions = {
      order_by = {
        field = "CREATED_AT",
        direction = "DESC",
      },
    },
    notifications = {
      current_repo_only = false, -- show notifications for current repo only
    },
    reviews = {
      auto_show_threads = true, -- automatically show comment threads on cursor move
      focus = "right", -- focus right buffer on diff open
      show_virtual_text = true, -- show virtual text with comment count and date
    },
    runs = {
      icons = {
        pending = "󰥔",
        in_progress = "󰦖",
        failed = "",
        succeeded = "",
        skipped = "",
        cancelled = "✖",
      },
    },
    pull_requests = {
      order_by = { -- criteria to sort the results of `Octo pr list`
        field = "CREATED_AT", -- either COMMENTS, CREATED_AT or UPDATED_AT (https://docs.github.com/en/graphql/reference/enums#issueorderfield)
        direction = "DESC", -- either DESC or ASC (https://docs.github.com/en/graphql/reference/enums#orderdirection)
      },
      always_select_remote_on_create = false, -- always give prompt to select base remote repo when creating PRs
      use_branch_name_as_title = false, -- sets branch name to be the name for the PR
    },
    file_panel = {
      size = 10, -- changed files panel rows
      icons = true, -- true = nvim-web-devicons, false = disabled, function = custom provider
    },
    colors = { -- used for highlight groups (see Colors section below)
      white = "#ffffff",
      grey = "#2A354C",
      black = "#000000",
      red = "#fdb8c0",
      dark_red = "#da3633",
      green = "#acf2bd",
      dark_green = "#238636",
      yellow = "#d3c846",
      dark_yellow = "#735c0f",
      blue = "#58A6FF",
      dark_blue = "#0366d6",
      purple = "#6f42c1",
    },
    mappings_disable_default = false, -- disable default mappings if true, but will still adapt user mappings
    mappings = {
      discussion = {
        discussion_options = { lhs = "<CR>", desc = "show discussion options" },
        open_in_browser = { lhs = "<C-b>", desc = "open discussion in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        add_reply = { lhs = "<localleader>cr", desc = "add reply" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        edit_comment = { lhs = "<localleader>cu", desc = "edit your own comment" },
        comment_edits = { lhs = "<localleader>ce", desc = "show comment edit history" },
        reference_in_new_issue = { lhs = "<localleader>ri", desc = "reference comment in new issue" },
        add_label = { lhs = "<localleader>la", desc = "add label" },
        remove_label = { lhs = "<localleader>ld", desc = "remove label" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 󱁖 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove 󰋑 reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 󰈈 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 󰔓 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 󰔑 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove  reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 󰱱 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 󱃞 reaction" },
        close_buffer = { lhs = "<C-c>", desc = "close this buffer and go back" },
      },
      runs = {
        expand_step = { lhs = "o", desc = "expand workflow step" },
        next_step = { lhs = "]s", desc = "next workflow step" },
        prev_step = { lhs = "[s", desc = "previous workflow step" },
        next_job = { lhs = "]j", desc = "next workflow job" },
        prev_job = { lhs = "[j", desc = "previous workflow job" },
        open_in_browser = { lhs = "<C-b>", desc = "open workflow run in browser" },
        refresh = { lhs = "<C-r>", desc = "refresh workflow" },
        rerun = { lhs = "<C-o>", desc = "rerun workflow" },
        rerun_failed = { lhs = "<C-f>", desc = "rerun failed workflow" },
        cancel = { lhs = "<C-x>", desc = "cancel workflow" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
      },
      issue = {
        issue_options = { lhs = "<CR>", desc = "show issue options" },
        close_issue = { lhs = "<localleader>ic", desc = "close issue" },
        reopen_issue = { lhs = "<localleader>io", desc = "reopen issue" },
        list_issues = { lhs = "<localleader>il", desc = "list open issues on same repo" },
        reload = { lhs = "<C-r>", desc = "reload issue" },
        open_in_browser = { lhs = "<C-b>", desc = "open issue in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        add_assignee = { lhs = "<localleader>aa", desc = "add assignee" },
        remove_assignee = { lhs = "<localleader>ad", desc = "remove assignee" },
        create_label = { lhs = "<localleader>lc", desc = "create label" },
        add_label = { lhs = "<localleader>la", desc = "add label" },
        remove_label = { lhs = "<localleader>ld", desc = "remove label" },
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        add_reply = { lhs = "<localleader>cr", desc = "add reply" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        edit_comment = { lhs = "<localleader>cu", desc = "edit your own comment" },
        comment_edits = { lhs = "<localleader>ce", desc = "show comment edit history" },
        reference_in_new_issue = { lhs = "<localleader>ri", desc = "reference comment in new issue" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 󱁖 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove 󰋑 reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 󰈈 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 󰔓 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 󰔑 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove  reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 󰱱 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 󱃞 reaction" },
        close_buffer = { lhs = "<C-c>", desc = "close this buffer and go back" },
      },
      pull_request = {
        pr_options = { lhs = "<CR>", desc = "show PR options" },
        checkout_pr = { lhs = "<localleader>po", desc = "checkout PR" },
        merge_pr = { lhs = "<localleader>pm", desc = "merge commit PR" },
        squash_and_merge_pr = { lhs = "<localleader>psm", desc = "squash and merge PR" },
        rebase_and_merge_pr = { lhs = "<localleader>prm", desc = "rebase and merge PR" },
        merge_pr_queue = {
          lhs = "<localleader>pq",
          desc = "merge commit PR and add to merge queue (Merge queue must be enabled in the repo)",
        },
        squash_and_merge_queue = {
          lhs = "<localleader>psq",
          desc = "squash and add to merge queue (Merge queue must be enabled in the repo)",
        },
        rebase_and_merge_queue = {
          lhs = "<localleader>prq",
          desc = "rebase and add to merge queue (Merge queue must be enabled in the repo)",
        },
        list_commits = { lhs = "<localleader>pc", desc = "list PR commits" },
        list_changed_files = { lhs = "<localleader>pf", desc = "list PR changed files" },
        show_pr_diff = { lhs = "<localleader>pd", desc = "show PR diff" },
        add_reviewer = { lhs = "<localleader>va", desc = "add reviewer" },
        remove_reviewer = { lhs = "<localleader>vd", desc = "remove reviewer request" },
        close_issue = { lhs = "<localleader>ic", desc = "close PR" },
        reopen_issue = { lhs = "<localleader>io", desc = "reopen PR" },
        list_issues = { lhs = "<localleader>il", desc = "list open issues on same repo" },
        reload = { lhs = "<C-r>", desc = "reload PR" },
        approve_pr = { lhs = "<leader>qa", desc = "approve PR" },
        open_in_browser = { lhs = "<C-b>", desc = "open PR in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy url to system clipboard" },
        copy_sha = { lhs = "<C-e>", desc = "copy commit SHA to system clipboard" },
        goto_file = { lhs = "gf", desc = "go to file" },
        add_assignee = { lhs = "<localleader>aa", desc = "add assignee" },
        remove_assignee = { lhs = "<localleader>ad", desc = "remove assignee" },
        create_label = { lhs = "<localleader>lc", desc = "create label" },
        add_label = { lhs = "<localleader>la", desc = "add label" },
        remove_label = { lhs = "<localleader>ld", desc = "remove label" },
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        add_reply = { lhs = "<localleader>cr", desc = "add reply" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        edit_comment = { lhs = "<localleader>cu", desc = "edit your own comment" },
        comment_edits = { lhs = "<localleader>ce", desc = "show comment edit history" },
        reference_in_new_issue = { lhs = "<localleader>ri", desc = "reference comment in new issue" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 󱁖 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove 󰋑 reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 󰈈 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 󰔓 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 󰔑 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove  reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 󰱱 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 󱃞 reaction" },
        review_start = { lhs = "<localleader>vs", desc = "start a review for the current PR" },
        review_resume = { lhs = "<localleader>vr", desc = "resume a pending review for the current PR" },
        resolve_thread = { lhs = "<localleader>rt", desc = "resolve PR thread" },
        unresolve_thread = { lhs = "<localleader>rT", desc = "unresolve PR thread" },
        close_buffer = { lhs = "<C-c>", desc = "close this buffer and go back" },
      },
      review_thread = {
        goto_issue = { lhs = "<localleader>gi", desc = "navigate to a local repo issue" },
        add_comment = { lhs = "<localleader>ca", desc = "add comment" },
        add_reply = { lhs = "<localleader>cr", desc = "add reply" },
        add_suggestion = { lhs = "<localleader>sa", desc = "add suggestion" },
        delete_comment = { lhs = "<localleader>cd", desc = "delete comment" },
        edit_comment = { lhs = "<localleader>cu", desc = "edit your own comment" },
        comment_edits = { lhs = "<localleader>ce", desc = "show comment edit history" },
        reference_in_new_issue = { lhs = "<localleader>ri", desc = "reference comment in new issue" },
        next_comment = { lhs = "]c", desc = "go to next comment" },
        prev_comment = { lhs = "[c", desc = "go to previous comment" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        select_next_unviewed_entry = { lhs = "]u", desc = "move to next unviewed file" },
        select_prev_unviewed_entry = { lhs = "[u", desc = "move to previous unviewed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        react_hooray = { lhs = "<localleader>rp", desc = "add/remove 󱁖 reaction" },
        react_heart = { lhs = "<localleader>rh", desc = "add/remove 󰋑 reaction" },
        react_eyes = { lhs = "<localleader>re", desc = "add/remove 󰈈 reaction" },
        react_thumbs_up = { lhs = "<localleader>r+", desc = "add/remove 󰔓 reaction" },
        react_thumbs_down = { lhs = "<localleader>r-", desc = "add/remove 󰔑 reaction" },
        react_rocket = { lhs = "<localleader>rr", desc = "add/remove  reaction" },
        react_laugh = { lhs = "<localleader>rl", desc = "add/remove 󰱱 reaction" },
        react_confused = { lhs = "<localleader>rc", desc = "add/remove 󱃞 reaction" },
        resolve_thread = { lhs = "<localleader>rt", desc = "resolve PR thread" },
        unresolve_thread = { lhs = "<localleader>rT", desc = "unresolve PR thread" },
      },
      submit_win = {
        approve_review = { lhs = "<C-a>", desc = "approve review", mode = { "n" } },
        comment_review = { lhs = "<C-m>", desc = "comment review", mode = { "n" } },
        request_changes = { lhs = "<C-r>", desc = "request changes review", mode = { "n" } },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab", mode = { "n" } },
      },
      review_diff = {
        submit_review = { lhs = "<localleader>vs", desc = "submit review" },
        discard_review = { lhs = "<localleader>vd", desc = "discard review" },
        add_review_comment = { lhs = "<localleader>ca", desc = "add a new review comment", mode = { "n", "x" } },
        add_review_suggestion = { lhs = "<localleader>sa", desc = "add a new review suggestion", mode = { "n", "x" } },
        focus_files = { lhs = "<localleader>e", desc = "move focus to changed file panel" },
        toggle_files = { lhs = "<localleader>b", desc = "hide/show changed files panel" },
        next_thread = { lhs = "]t", desc = "move to next thread" },
        prev_thread = { lhs = "[t", desc = "move to previous thread" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        select_next_unviewed_entry = { lhs = "]u", desc = "move to next unviewed file" },
        select_prev_unviewed_entry = { lhs = "[u", desc = "move to previous unviewed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        toggle_viewed = { lhs = "<localleader><space>", desc = "toggle viewer viewed state" },
        goto_file = { lhs = "gf", desc = "go to file" },
        copy_sha = { lhs = "<C-e>", desc = "copy commit SHA to system clipboard" },
        review_commits = { lhs = "<localleader>C", desc = "review PR commits" },
      },
      file_panel = {
        submit_review = { lhs = "<localleader>vs", desc = "submit review" },
        discard_review = { lhs = "<localleader>vd", desc = "discard review" },
        next_entry = { lhs = "j", desc = "move to next changed file" },
        prev_entry = { lhs = "k", desc = "move to previous changed file" },
        select_entry = { lhs = "<cr>", desc = "show selected changed file diffs" },
        refresh_files = { lhs = "R", desc = "refresh changed files panel" },
        focus_files = { lhs = "<localleader>e", desc = "move focus to changed file panel" },
        toggle_files = { lhs = "<localleader>b", desc = "hide/show changed files panel" },
        select_next_entry = { lhs = "]q", desc = "move to next changed file" },
        select_prev_entry = { lhs = "[q", desc = "move to previous changed file" },
        select_first_entry = { lhs = "[Q", desc = "move to first changed file" },
        select_last_entry = { lhs = "]Q", desc = "move to last changed file" },
        select_next_unviewed_entry = { lhs = "]u", desc = "move to next unviewed file" },
        select_prev_unviewed_entry = { lhs = "[u", desc = "move to previous unviewed file" },
        close_review_tab = { lhs = "<C-c>", desc = "close review tab" },
        toggle_viewed = { lhs = "<localleader><space>", desc = "toggle viewer viewed state" },
        review_commits = { lhs = "<localleader>C", desc = "review PR commits" },
      },
      notification = {
        read = { lhs = "<localleader>nr", desc = "mark notification as read" },
        done = { lhs = "<localleader>nd", desc = "mark notification as done" },
        unsubscribe = { lhs = "<localleader>nu", desc = "unsubscribe from notifications" },
      },
      repo = {
        repo_options = { lhs = "<CR>", desc = "show repo options" },
        create_issue = { lhs = "<localleader>ic", desc = "create issue" },
        create_discussion = { lhs = "<localleader>dc", desc = "create discussion" },
        contributing_guidelines = { lhs = "<localleader>cg", desc = "view contributing guidelines" },
        open_in_browser = { lhs = "<C-b>", desc = "open repo in browser" },
        close_buffer = { lhs = "<C-c>", desc = "close this buffer and go back" },
      },
      release = {
        open_in_browser = { lhs = "<C-b>", desc = "open release in browser" },
        close_buffer = { lhs = "<C-c>", desc = "close this buffer and go back" },
      },
    },
    poll = {
      enabled = false, -- opt-in polling for remote changes
      interval = 10000, -- polling interval in milliseconds (default: 10s)
      notify_on_refresh = true, -- notify when a buffer is auto-refreshed
      notify_on_change = true, -- notify when remote changed but buffer has local edits
    },
    search = {
      completion_overrides = {}, -- key is a qualifier, value is an array table or a function returning a table
    },
    debug = {
      notify_missing_timeline_items = false,
    },
    comments = {
      style = "popup",
      style_overrides = {
        issue = nil,
        pull_request = nil,
        review_thread = nil,
        discussion = nil,
      },
      drafts = {
        enabled = true,
        sweep_after_days = 30,
      },
    },
    submit_on_write = false,
  }
  -- END_CONFIG
end

M.values = M.get_default_values()

---Validates the config
---@return { [string]: string } all error messages emitted during validation
function M.validate_config()
  local config = M.values

  ---@type { [string]: string }
  local errors = {}
  local function err(value, msg)
    errors[value] = msg
  end

  ---Checks if a variable is the correct type if not it calls err with an error string
  ---@param value any
  ---@param name string
  ---@param expected_types type | type[]
  local function validate_type(value, name, expected_types)
    if type(expected_types) == "table" then
      if not vim.tbl_contains(expected_types, type(value)) then
        err(
          name,
          string.format(
            "Expected `%s` to be one of types '%s', got '%s'",
            name,
            table.concat(expected_types, ", "),
            type(value)
          )
        )
        return false
      end
      return true
    end

    if type(value) ~= expected_types then
      err(name, string.format("Expected `%s` to be of type '%s', got '%s'", name, expected_types, type(value)))
      return false
    end
    return true
  end

  ---Checks if a variable is one of the allowed string value
  ---@param value any
  ---@param name string
  ---@param expected_strings string[]
  local function validate_string_enum(value, name, expected_strings)
    -- First check that the value is indeed a string
    if validate_type(value, name, "string") then
      -- Then check it matches one of the expected values
      if not vim.tbl_contains(expected_strings, value) then
        err(
          name .. "." .. value,
          string.format(
            "Received '%s', which is not supported! Valid values: %s",
            value,
            table.concat(expected_strings, ", ")
          )
        )
      end
    end
  end

  local function validate_pickers()
    validate_string_enum(config.picker, "picker", { "telescope", "fzf-lua", "snacks", "default" })

    if not validate_type(config.picker_config, "picker_config", "table") then
      return
    end

    validate_type(config.picker_config.use_emojis, "picker_config.use_emojis", "boolean")
    validate_type(config.picker_config.search_static, "picker_config.search_static", "boolean")
    validate_type(config.picker_config.preview_wrap, "picker_config.preview_wrap", "boolean")
    validate_type(config.picker_config.preview_prefetch, "picker_config.preview_prefetch", "number")
    validate_type(config.picker_config.preview_render_html, "picker_config.preview_render_html", "boolean")
    validate_type(config.picker_config.preview_render_markdown, "picker_config.preview_render_markdown", "boolean")
    validate_type(config.picker_config.preview_prefetch_all, "picker_config.preview_prefetch_all", "boolean")
    validate_type(
      config.picker_config.preview_prefetch_concurrency,
      "picker_config.preview_prefetch_concurrency",
      "number"
    )
    validate_type(config.picker_config.preview_rate_limit_reserve, "picker_config.preview_rate_limit_reserve", "number")
    validate_type(config.picker_config.preview_loading, "picker_config.preview_loading", "boolean")
    if validate_type(config.picker_config.mappings, "picker_config.mappings", "table") then
      ---Checks that no two picker mappings convert to the same fzf key.
      ---
      ---The fzf-lua pickers (e.g. `octo.pickers.fzf-lua.pickers.prs`) build one
      ---Lua table constructor keyed by `utils.convert_vim_mapping_to_fzf(lhs)`.
      ---Two mappings that convert to the same key collide silently and Lua
      ---keeps only the last table entry, so this must run against the merged
      ---runtime config (`config.picker_config.mappings`), not just the
      ---defaults, since a user's own `setup()` can introduce the collision.
      ---@param mappings OctoPickerMappings
      local function validate_picker_mapping_distinctness(mappings)
        local utils = require "octo.utils"
        ---@type { [string]: string }
        local seen_by_fzf_key = {}
        ---@diagnostic disable-next-line: no-unknown
        for action, map in pairs(mappings) do
          if type(map) == "table" and type(map.lhs) == "string" then
            local fzf_key = utils.convert_vim_mapping_to_fzf(map.lhs)
            local other_action = seen_by_fzf_key[fzf_key]
            if other_action then
              err(
                string.format("picker_config.mappings.%s", action),
                string.format(
                  "`picker_config.mappings.%s` (%q) collides with `picker_config.mappings.%s` on fzf key %q; "
                    .. "rebind one of them so the picker can tell them apart",
                  action,
                  map.lhs,
                  other_action,
                  fzf_key
                )
              )
            else
              seen_by_fzf_key[fzf_key] = action
            end
          end
        end
      end

      ---@diagnostic disable-next-line: no-unknown
      for action, map in pairs(config.picker_config.mappings) do
        if validate_type(map, string.format("picker_config.mappings.%s", action), "table") then
          validate_type(map.lhs, string.format("picker_config.mappings.%s.lhs", action), "string")
          validate_type(map.desc, string.format("picker_config.mappings.%s.desc", action), "string")
        end
      end
      validate_picker_mapping_distinctness(config.picker_config.mappings)
    end

    -- Snacks specific validation
    if validate_type(config.picker_config.snacks, "picker_config.snacks", "table") then
      -- Validate actions (new array structure)
      if validate_type(config.picker_config.snacks.actions, "picker_config.snacks.actions", "table") then -- Optional table
        ---@diagnostic disable-next-line: no-unknown
        for picker_type, actions_array in pairs(config.picker_config.snacks.actions) do
          local base_name = string.format("picker_config.snacks.actions.%s", picker_type)
          if validate_type(actions_array, base_name, "table") then -- Should be an array (table)
            for i, action_item in ipairs(actions_array) do
              local item_name = string.format("%s[%d]", base_name, i)
              if validate_type(action_item, item_name, "table") then
                -- Validate mandatory fields
                validate_type(action_item.name, item_name .. ".name", "string")
                validate_type(action_item.fn, item_name .. ".fn", "function")
                -- Validate optional fields
                validate_type(action_item.lhs, item_name .. ".lhs", "string")
                validate_type(action_item.desc, item_name .. ".desc", "string")
                if validate_type(action_item.mode, item_name .. ".mode", "table") then -- Optional mode table
                  for j, mode_val in ipairs(action_item.mode) do
                    validate_type(mode_val, string.format("%s.mode[%d]", item_name, j), "string")
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  local function validate_aliases()
    if not validate_type(config.ssh_aliases, "ssh_aliases", "table") then
      return
    end
    for name, alias in pairs(config.ssh_aliases) do
      validate_type(alias, string.format("ssh_aliases.%s", name), "string")
    end
  end

  local function validate_issues()
    if not validate_type(config.issues, "issues", "table") then
      return
    end
    if validate_type(config.issues.order_by, "issues.order_by", "table") then
      validate_type(config.issues.order_by.field, "issues.order_by.field", "string")
      validate_type(config.issues.order_by.direction, "issues.order_by.direction", "string")
    end
  end

  local function validate_reviews()
    if not validate_type(config.reviews, "reviews", "table") then
      return
    end

    validate_type(config.reviews.auto_show_threads, "reviews.auto_show_threads", "boolean")
    validate_string_enum(config.reviews.focus, "reviews.focus", { "right", "left" })
  end

  local function validate_pull_requests()
    if not validate_type(config.pull_requests, "pull_requests", "table") then
      return
    end
    if validate_type(config.pull_requests.order_by, "pull_requests.order_by", "table") then
      validate_type(config.pull_requests.order_by.field, "pull_requests.order_by.field", "string")
      validate_type(config.pull_requests.order_by.direction, "pull_requests.order_by.direction", "string")
    end
    validate_type(config.pull_requests.always_select_remote_on_create, "always_select_remote_on_create", "boolean")
    validate_type(config.pull_requests.use_branch_name_as_title, "use_branch_name_as_title", "boolean")
  end

  local function validate_notifications()
    if not validate_type(config.notifications, "notifications", "table") then
      err("notifications", "Expected notifications to be a table")
      return
    end
    validate_type(config.notifications.current_repo_only, "notifications.current_repo_only", "boolean")
  end

  local function validate_mappings()
    -- TODO(jarviliam): Validate each keymap
    if not validate_type(config.mappings, "mappings", "table") then
      return
    end
  end

  local function validate_poll()
    if not validate_type(config.poll, "poll", "table") then
      return
    end
    validate_type(config.poll.enabled, "poll.enabled", "boolean")
    validate_type(config.poll.interval, "poll.interval", "number")
    validate_type(config.poll.notify_on_refresh, "poll.notify_on_refresh", "boolean")
    validate_type(config.poll.notify_on_change, "poll.notify_on_change", "boolean")
  end

  local function validate_debug()
    if not validate_type(config.debug, "debug", "table") then
      return
    end
    validate_type(config.debug.notify_missing_timeline_items, "debug.notify_missing_timeline_items", "boolean")
  end

  local comment_styles = { "popup", "inline" }

  local function validate_comments()
    if not validate_type(config.comments, "comments", "table") then
      return
    end
    validate_string_enum(config.comments.style, "comments.style", comment_styles)
    if validate_type(config.comments.style_overrides, "comments.style_overrides", "table") then
      ---@diagnostic disable-next-line: no-unknown
      for kind, style in pairs(config.comments.style_overrides) do
        validate_string_enum(style, string.format("comments.style_overrides.%s", kind), comment_styles)
      end
    end
    if validate_type(config.comments.drafts, "comments.drafts", "table") then
      validate_type(config.comments.drafts.enabled, "comments.drafts.enabled", "boolean")
      validate_type(config.comments.drafts.sweep_after_days, "comments.drafts.sweep_after_days", "number")
    end
  end

  if validate_type(config, "base config", "table") then
    validate_type(config.use_local_fs, "use_local_fs", "boolean")
    validate_type(config.enable_builtin, "enable_builtin", "boolean")
    validate_type(config.snippet_context_lines, "snippet_context_lines", "number")
    validate_type(config.timeout, "timeout", "number")
    validate_type(config.default_to_projects_v2, "default_to_projects_v2", "boolean")
    if validate_type(config.search, "search", "table") then
      if validate_type(config.search.completion_overrides, "search.completion_overrides", "table") then
        for name, value in pairs(config.search.completion_overrides) do
          validate_type(value, "search.completion_overrides." .. name, { "table", "function" })
        end
      end
    end
    if validate_type(config.suppress_missing_scope, "suppress_missing_scope", "table") then
      validate_type(config.suppress_missing_scope.projects_v2, "suppress_missing_scope.projects_v2", "boolean")
    end
    validate_type(config.gh_cmd, "gh_cmd", "string")
    validate_type(config.gh_env, "gh_env", { "table", "function" })
    validate_type(config.reaction_viewer_hint_icon, "reaction_viewer_hint_icon", "string")
    validate_string_enum(config.users, "users", { "search", "mentionable", "assignable" })
    validate_type(config.user_icon, "user_icon", "string")
    validate_type(config.ghost_icon, "ghost_icon", "string")
    validate_type(config.copilot_icon, "copilot_icon", "string")
    validate_type(config.comment_icon, "comment_icon", "string")
    validate_type(config.outdated_icon, "outdated_icon", "string")
    validate_type(config.resolved_icon, "resolved_icon", "string")
    validate_type(config.timeline_marker, "timeline_marker", "string")
    validate_type(config.timeline_indent, "timeline_indent", "number")
    validate_type(config.right_bubble_delimiter, "right_bubble_delimiter", "string")
    validate_type(config.left_bubble_delimiter, "left_bubble_delimiter", "string")
    validate_type(config.github_hostname, "github_hostname", "string")
    if validate_type(config.default_remote, "default_remote", "table") then
      ---@diagnostic disable-next-line: no-unknown
      for _, v in ipairs(config.default_remote) do
        validate_type(v, "remote", "string")
      end
    end
    validate_type(config.default_merge_method, "default_merge_method", "string")
    validate_string_enum(config.default_merge_method, "default_merge_method", { "merge", "rebase", "squash" })
    if validate_type(config.ui, "ui", "table") then
      validate_type(config.ui.render_markdown, "ui.render_markdown", "boolean")
      validate_type(config.ui.use_signcolumn, "ui.use_signcolumn", "boolean")
      validate_type(config.ui.use_statuscolumn, "ui.use_statuscolumn", "boolean")
      validate_type(config.ui.use_foldtext, "ui.use_foldtext", "boolean")
      validate_type(config.ui.pr_loading, "ui.pr_loading", "boolean")
      validate_type(config.ui.section_buttons, "ui.section_buttons", "boolean")
    end
    if validate_type(config.colors, "colors", "table") then
      ---@diagnostic disable-next-line: no-unknown
      for k, v in pairs(config.colors) do
        validate_type(v, string.format("colors.%s", k), "string")
      end
    end

    validate_issues()
    validate_reviews()
    validate_pull_requests()
    validate_notifications()
    if validate_type(config.file_panel, "file_panel", "table") then
      validate_type(config.file_panel.size, "file_panel.size", "number")
      validate_type(config.file_panel.icons, "file_panel.icons", { "boolean", "function" })
      if rawget(config.file_panel, "use_icons") ~= nil then
        err("file_panel.use_icons", "`file_panel.use_icons` is no longer supported; use `file_panel.icons = false`")
      end
      if rawget(config.file_panel, "get_icon") ~= nil then
        err(
          "file_panel.get_icon",
          "`file_panel.get_icon` is no longer supported; use `file_panel.icons = function(name, ext) ... end`"
        )
      end
    end
    validate_aliases()
    validate_pickers()
    validate_mappings()
    validate_poll()
    validate_debug()
    validate_comments()
    validate_type(config.submit_on_write, "submit_on_write", "boolean")
  end

  return errors
end

function M.setup(opts)
  if opts ~= nil then
    if opts.mappings_disable_default == true then
      -- clear default mappings before merging user mappings
      M.values.mappings = {
        issue = {},
        discussion = {},
        pull_request = {},
        review_thread = {},
        submit_win = {},
        review_diff = {},
        file_panel = {},
        repo = {},
        release = {},
      }
    end
    -- Use deep extend. For arrays ('actions' here), 'force' mode usually replaces the whole array,
    -- which is the desired behavior - users define the full list of actions they want.
    M.values = vim.tbl_deep_extend("force", M.values, opts or {})
  end
  local config_errs = M.validate_config()
  if vim.tbl_count(config_errs) > 0 then
    local header = "====Octo Configuration Errors===="
    local header_message = {
      "You have a misconfiguration in your octo setup!",
      'Validate that your configuration passed to `require("octo").setup()` is valid!',
    }
    local header_sep = ""
    for _ = 0, string.len(header), 1 do
      header_sep = header_sep .. "-"
    end

    local config_errs_message = {}
    for config_key, err in pairs(config_errs) do
      table.insert(config_errs_message, string.format("Config value: `%s` had error -> %s", config_key, err))
    end
    error(
      string.format(
        "\n%s\n%s\n%s\n%s",
        header,
        table.concat(header_message, "\n"),
        header_sep,
        table.concat(config_errs_message, "\n")
      ),
      vim.log.levels.ERROR
    )
  end
  M.values.ui.use_statuscolumn = M.values.ui.use_statuscolumn and vim.fn.has "nvim-0.9" == 1
  M.values.ui.use_foldtext = M.values.ui.use_foldtext and vim.fn.has "nvim-0.10" == 1
end

return M
