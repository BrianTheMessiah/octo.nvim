---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local html = require "octo.ui.html"

describe("octo body html:", function()
  it("defaults picker_config.preview_render_html to true", function()
    eq(true, config.get_default_values().picker_config.preview_render_html)
  end)

  it("returns an empty string for a missing or empty body", function()
    eq("", html.to_markdown(nil))
    eq("", html.to_markdown "")
    eq("", html.to_markdown(vim.NIL))
  end)

  it("leaves plain markdown exactly as it was", function()
    local body = "# Title\n\nSome **bold**, some *italic* and `inline code`.\n\n- one\n- two"
    eq(body, html.to_markdown(body))
  end)

  it("keeps the link target when rewriting an anchor", function()
    eq(
      "see [the docs](https://example.com/a)",
      html.to_markdown 'see <a href="https://example.com/a">the docs</a>'
    )
  end)

  it("falls back to the bare url when an anchor has no label", function()
    eq("https://example.com", html.to_markdown '<a href="https://example.com"></a>')
  end)

  it("rewrites an image to a markdown image, keeping its source", function()
    eq("![](https://example.com/a.png)", html.to_markdown '<img src="https://example.com/a.png">')
  end)

  it("handles single-quoted attributes as well as double", function()
    eq("[x](https://example.com)", html.to_markdown "<a href='https://example.com'>x</a>")
  end)

  it("rewrites the inline formatting tags to markdown", function()
    eq("**bold**", html.to_markdown "<strong>bold</strong>")
    eq("**bold**", html.to_markdown "<b>bold</b>")
    eq("*it*", html.to_markdown "<em>it</em>")
    eq("~~gone~~", html.to_markdown "<del>gone</del>")
    eq("`x`", html.to_markdown "<code>x</code>")
  end)

  it("rewrites headings at every level", function()
    for level = 1, 6 do
      local tag = "h" .. level
      eq(string.rep("#", level) .. " T", html.to_markdown(("<%s>T</%s>"):format(tag, tag)))
    end
  end)

  it("turns list items into markdown bullets and drops the list wrapper", function()
    eq("\n- one\n- two", html.to_markdown "<ul>\n<li>one</li>\n<li>two</li>\n</ul>")
    eq("- one", html.to_markdown "<li>one</li>")
  end)

  it("turns a blockquote into matching depths of quote markers", function()
    eq("> quoted", html.to_markdown "<blockquote>quoted</blockquote>")
    eq("> > deep", html.to_markdown "<blockquote><blockquote>deep</blockquote></blockquote>")
    eq("> a\nafter", html.to_markdown "<blockquote>a</blockquote>\nafter")
  end)

  it("turns a line break into a real line break", function()
    eq("one\ntwo", html.to_markdown "one<br />two")
    eq("one\ntwo", html.to_markdown "one<br>two")
  end)

  it("decodes the named and numeric entities GitHub emits", function()
    eq("<p> & \"q\" 'a'", html.to_markdown "&lt;p&gt; &amp; &quot;q&quot; &#39;a&#39;")
    eq("a — b", html.to_markdown "a &#8212; b")
    eq("a — b", html.to_markdown "a &#x2014; b")
  end)

  it("decodes an ampersand last so an entity cannot be decoded twice", function()
    eq("&lt;", html.to_markdown "&amp;lt;")
  end)

  it("preserves the details and summary tags octo folds bodies on", function()
    local converted = html.to_markdown "<details>\n<summary>Release notes</summary>\n<p>text</p>\n</details>"
    assert.is_truthy(converted:find("<details>", 1, true), "details tag must survive: " .. converted)
    assert.is_truthy(converted:find("<summary>Release notes</summary>", 1, true), converted)
    assert.is_truthy(converted:find("</details>", 1, true), converted)
    assert.is_truthy(converted:find("text", 1, true), converted)
  end)

  it("leaves a tag outside the handled set visible instead of eating its text", function()
    eq('a <marquee dir="left">x</marquee> b', html.to_markdown 'a <marquee dir="left">x</marquee> b')
    eq("<table><tr><td>c</td></tr></table>", html.to_markdown "<table><tr><td>c</td></tr></table>")
  end)

  it("leaves the contents of a fenced code block untouched", function()
    eq("```html\n<p>keep me</p>\n```", html.to_markdown "```html\n<p>keep me</p>\n```")
    eq("~~~\n<em>keep</em>\n~~~", html.to_markdown "~~~\n<em>keep</em>\n~~~")
  end)

  it("leaves the contents of an inline code span untouched", function()
    eq("run `@dependabot ignore <dep name>`", html.to_markdown "run `@dependabot ignore <dep name>`")
    eq("see `&lt;p&gt;` here", html.to_markdown "see `&lt;p&gt;` here")
  end)

  it("converts a real dependabot release-notes block into readable markdown", function()
    local body = table.concat({
      "Updates `fast-uri` from 3.1.3 to 3.1.5",
      "<details>",
      "<summary>Release notes</summary>",
      "<blockquote>",
      "<h2>v3.1.5</h2>",
      '<p><strong>Full Changelog</strong>: <a href="https://example.com/c">https://example.com/c</a></p>',
      "</blockquote>",
      "</details>",
      "<ul>",
      '<li><a href="https://example.com/1"><code>5e179cb</code></a> Bumped v3.1.5</li>',
      "</ul>",
    }, "\n")
    local converted = html.to_markdown(body)

    assert.is_nil(converted:find "<p>", "no paragraph tags should remain: " .. converted)
    assert.is_nil(converted:find "<li>", "no list-item tags should remain: " .. converted)
    assert.is_nil(converted:find "href=", "no raw hrefs should remain: " .. converted)
    assert.is_truthy(converted:find("> ## v3.1.5", 1, true), converted)
    assert.is_truthy(converted:find("**Full Changelog**", 1, true), converted)
    assert.is_truthy(converted:find("[`5e179cb`](https://example.com/1) Bumped v3.1.5", 1, true), converted)
    assert.is_truthy(converted:find("<details>", 1, true), converted)
  end)
end)
