local n = require("nui-components")

local renderer = n.create_renderer({
  width = 80,
  height = 20,
})

local function splitByNewline(str)
  local result = {}
  for line in str:gmatch("([^%c\r\n]*)[\r\n]*") do
    table.insert(result, line)
  end
  return result
end

local signal = n.create_signal({
  chat = "",
  entries = {
  },
  selected = nil,
})

local buf = vim.api.nvim_create_buf(false, true)
local obs = nil

local function indexing()
  vim.notify("Indexing...")
  vim.fn.jobstart({ "chopgrep", "index" }, {
    on_exit = function(job_id, code, event)
      if code == 0 then
        vim.notify("Indexing has been completed.")
      else
        -- コマンドの実行が失敗
        vim.notify("Failed to index" .. code, vim.log.levels.ERROR)
      end
    end
  })
end



local function get_json_output(query, on_success)
  local output_data = {}

  vim.fn.jobstart({ "chopgrep", "query", query, "10", "-j" }, {
    on_stdout = function(job_id, data, event)
      -- 受信したデータを行ごとに保存
      for _, line in ipairs(data) do
        table.insert(output_data, line)
      end
    end,

    on_exit = function(job_id, code, event)
      if code == 0 then
        local json_string = table.concat(output_data, "\n")
        local success, result = pcall(vim.fn.json_decode, json_string)
        if success then
          on_success(result)
        else
          -- パース失敗
          vim.notify("Faile to parse chopgrep output JSON\n" .. result, vim.log.levels.ERROR)
        end
      else
        -- コマンドの実行が失敗
        vim.notify("Failed to execute chopgrep" .. code, vim.log.levels.ERROR)
      end
    end
  })
end

local function replacePreview(content)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, content)
end

local body = function()
  return n.rows(
    n.prompt({
      prefix = " > ",
      autofocus = true,
      value = signal.chat,
      --placeholder = "Shift-Tab to submit",
      border_label = {
        text = "Query",
        align = "center",
      },
      on_change = function(value)
        signal.chat = value
      end,
      on_unmount = function()
        if (obs) then
          obs:unsubscribe()
          renderer:close()
        end
      end
    }),
    n.columns(
      n.select({
        flex = 3,
        border_label = "Chunks",
        selected = signal.selected,
        data = signal.entries,
        on_select = function(nodes)
          print(nodes.text)
          signal.selected = nodes

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
          vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, splitByNewline(nodes.content))
        end,
      }),
      n.buffer({
        id = "preview",
        flex = 5,
        buf = buf,
        autoscroll = true,
        border_label = "Preview",
        filetype = "typescript"
      })

    )
  )
end

vim.api.nvim_create_user_command(
  "ChopgrepIndex",
  indexing, {}
)

vim.api.nvim_create_user_command(
  "Chopgrep",
  function()
    obs = signal:observe(function(current, next)
      renderer:set_size({ height = 20 })
      if (current.chat ~= next.chat) then
        replacePreview({ "Serching... :", next.chat })
        get_json_output(next.chat, function(j)
          local entries = {}
          local results = j["results"]
          for i = 1, #results do
            table.insert(entries,
              n.option(results[i]["fileName"] .. ": " .. results[i]["entity"], {
                id = results[i]["rank"],
                content = results[i]["contentSnippet"]
              })
            )
          end
          signal.entries = entries
          replacePreview({ "Completed." })
        end)
      end
    end, 1000)
    renderer:render(body)
  end, {})
