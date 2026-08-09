---Turns the inline HTML that GitHub bodies carry into the markdown equivalent.
---
---GitHub returns an issue or pull request `body` as the markdown its author typed,
---and that markdown may contain arbitrary HTML. Bots write a lot of it: a
---dependabot release-notes block is HTML throughout. Rendered verbatim, the reader
---sees `<p>`, `<li>` and `<a href=...>` instead of prose.
---
---Only the tags GitHub actually emits in bodies are handled. Anything outside that
---set is left exactly as it was, visible, rather than dropped: losing a tag is
---better than silently losing the text inside it. `<details>` and `<summary>` are
---preserved for the same reason plus one more, that `octo.folds` builds body folds
---from them.
local M = {}

---Named HTML entities seen in GitHub bodies. `&amp;` is decoded last so that a
---decoded `&` cannot be re-read as the start of another entity.
local ENTITIES = {
  { "&lt;", "<" },
  { "&gt;", ">" },
  { "&quot;", '"' },
  { "&#39;", "'" },
  { "&apos;", "'" },
  { "&nbsp;", " " },
  { "&mdash;", "—" },
  { "&ndash;", "–" },
  { "&hellip;", "…" },
  { "&bull;", "•" },
  { "&amp;", "&" },
}

---Inline tag pairs rewritten to their markdown wrappers.
local WRAPPERS = {
  { "strong", "**" },
  { "b", "**" },
  { "em", "*" },
  { "i", "*" },
  { "del", "~~" },
  { "s", "~~" },
  { "strike", "~~" },
  { "code", "`" },
}

---Decode the named and numeric HTML entities in one piece of text.
---@param text string text possibly containing entities
---@return string decoded
function M.decode_entities(text)
  text = text:gsub("&#(%d+);", function(digits)
    local code = tonumber(digits)
    return (code and code > 0 and code < 0x110000) and vim.fn.nr2char(code) or nil
  end)
  text = text:gsub("&#[xX](%x+);", function(hex)
    local code = tonumber(hex, 16)
    return (code and code > 0 and code < 0x110000) and vim.fn.nr2char(code) or nil
  end)
  for _, entity in ipairs(ENTITIES) do
    text = text:gsub(entity[1], entity[2])
  end
  return text
end

---Rewrite anchors and images so the link target survives the conversion.
---@param text string text possibly containing `<a>` or `<img>` tags
---@return string converted with markdown links
local function convert_links(text)
  for _, quote in ipairs { '"', "'" } do
    text = text:gsub("<[aA]%s[^>]-[hH][rR][eE][fF]=" .. quote .. "([^" .. quote .. "]*)" .. quote .. "[^>]*>(.-)</[aA]>",
      function(href, label)
        label = vim.trim(label)
        return label == "" and href or string.format("[%s](%s)", label, href)
      end)
    text = text:gsub("<[iI][mM][gG]%s[^>]-[sS][rR][cC]=" .. quote .. "([^" .. quote .. "]*)" .. quote .. "[^>]*>",
      function(src)
        return string.format("![](%s)", src)
      end)
  end
  return text
end

---Rewrite the inline emphasis and code tags to their markdown wrappers.
---@param text string text possibly containing inline formatting tags
---@return string converted
local function convert_wrappers(text)
  for _, wrapper in ipairs(WRAPPERS) do
    local tag, mark = wrapper[1], wrapper[2]
    text = text:gsub("<" .. tag .. ">(.-)</" .. tag .. ">", function(inner)
      return inner == "" and "" or mark .. inner .. mark
    end)
  end
  return text
end

---Rewrite the block-level tags. `pre` is handled before `p` because a pattern
---loose enough to match `<p class=...>` also matches `<pre>`.
---@param text string text possibly containing block tags
---@return string converted
local function convert_blocks(text)
  text = text:gsub("<[bB][rR]%s*/?>", "\n")
  text = text:gsub("<[hH][rR]%s*/?>", "---")
  text = text:gsub("</?pre[^>]*>", "```")
  for level = 1, 6 do
    text = text:gsub(string.format("<[hH]%d[^>]*>%%s*(.-)%%s*</[hH]%d>", level, level), string.rep("#", level) .. " %1")
  end
  text = text:gsub("<li[^>]*>%s*", "- ")
  text = text:gsub("</li%s*>", "")
  text = text:gsub("</?[uo]l[^>]*>", "")
  text = text:gsub("</?p>", "")
  text = text:gsub("<p%s[^>]*>", "")
  return text
end

---Convert one line's HTML, leaving anything inside backtick spans alone so that an
---example of a tag stays an example.
---@param line string a single line of body text, outside any fenced block
---@return string converted
function M.convert_line(line)
  local pieces = vim.split(line, "`", { plain = true })
  for index, piece in ipairs(pieces) do
    if index % 2 == 1 then
      pieces[index] = M.decode_entities(convert_wrappers(convert_links(convert_blocks(piece))))
    end
  end
  return table.concat(pieces, "`")
end

---Whether a line opens or closes a fenced code block.
---@param line string buffer line
---@return boolean
local function is_fence(line)
  return line:match "^%s*```" ~= nil or line:match "^%s*~~~" ~= nil
end

---How much a line changes the blockquote nesting depth, and the line with those
---tags removed.
---@param line string a converted line
---@return string line without blockquote tags
---@return integer opened count of `<blockquote>` on the line
---@return integer closed count of `</blockquote>` on the line
local function strip_blockquote(line)
  local opened, closed = 0, 0
  line = line:gsub("<blockquote[^>]*>", function()
    opened = opened + 1
    return ""
  end)
  line = line:gsub("</blockquote%s*>", function()
    closed = closed + 1
    return ""
  end)
  return line, opened, closed
end

---Convert a whole body from GitHub-flavoured markdown-with-HTML into markdown.
---
---Fenced code blocks pass through untouched, `<blockquote>` becomes the matching
---depth of `>` markers, and the `<details>`/`<summary>` tags octo folds on survive.
---@param body string? the `body` field of an issue or pull request; a nil or
---`vim.NIL` body, which is how octo represents an absent one, yields an empty string
---@return string body markdown with the handled HTML tags rewritten
function M.to_markdown(body)
  if type(body) ~= "string" or body == "" then
    return ""
  end

  local out, fenced, depth = {}, false, 0
  for raw in (body:gsub("\r\n", "\n") .. "\n"):gmatch "([^\n]*)\n" do
    if is_fence(raw) then
      fenced = not fenced
      table.insert(out, raw)
    elseif fenced then
      table.insert(out, raw)
    else
      local line, opened, closed = strip_blockquote(M.convert_line(raw))
      depth = depth + opened
      for piece in (line .. "\n"):gmatch "([^\n]*)\n" do
        local trimmed = piece:gsub("%s+$", "")
        if depth > 0 then
          local marker = string.rep("> ", depth)
          table.insert(out, trimmed == "" and vim.trim(marker) or marker .. trimmed)
        else
          table.insert(out, trimmed)
        end
      end
      depth = math.max(0, depth - closed)
    end
  end

  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return table.concat(out, "\n")
end

return M
