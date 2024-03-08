local Path = require("grapple.path")
local Util = require("grapple.util")

---@class grapple.container_content
---@field tag_manager grapple.tag_manager
---@field hook_fn grapple.hook_fn
---@field title_fn grapple.title_fn
local ContainerContent = {}
ContainerContent.__index = ContainerContent

---@param tag_manager grapple.tag_manager
---@param hook_fn? grapple.hook_fn
---@param title_fn? grapple.title_fn
---@return grapple.container_content
function ContainerContent:new(tag_manager, hook_fn, title_fn)
    return setmetatable({
        tag_manager = tag_manager,
        hook_fn = hook_fn,
        title_fn = title_fn,
    }, self)
end

---@return boolean
function ContainerContent:modifiable()
    return false
end

---@return string | nil title
function ContainerContent:title()
    if not self.title_fn then
        return
    end

    return self.title_fn()
end

---@param window grapple.window
---@return string? error
function ContainerContent:attach(window)
    if self.hook_fn then
        local err = self.hook_fn(window)
        if err then
            return err
        end
    end

    return nil
end

---@param window grapple.window
---@return string? error
---@diagnostic disable-next-line: unused-local
function ContainerContent:detach(window) end

---@param original grapple.window.entry
---@param parsed grapple.window.entry
---@return string? error
---@diagnostic disable-next-line: unused-local
function ContainerContent:sync(original, parsed) end

---@return grapple.window.entity[] | nil, string? error
function ContainerContent:entities()
    local App = require("grapple.app")
    local app = App.get()

    local current_scope, err = app:current_scope()
    if not current_scope then
        return nil, err
    end

    ---@param cont_a grapple.tag_container
    ---@param cont_b grapple.tag_container
    local function by_id(cont_a, cont_b)
        return string.lower(cont_a.id) < string.lower(cont_b.id)
    end

    local loaded = self.tag_manager:list_loaded()
    table.sort(loaded, by_id)

    local unloaded = self.tag_manager:list_unloaded()
    table.sort(unloaded, by_id)

    local containers = Util.add(loaded, unloaded)

    local entities = {}

    for _, container in ipairs(containers) do
        ---@class grapple.container_content.entity
        local entity = {
            container = container,
            current = container.id == current_scope.id,
        }

        table.insert(entities, entity)
    end

    return entities, nil
end

---@param entity grapple.container_content.entity
---@param index integer
---@return grapple.window.entry
function ContainerContent:create_entry(entity, index)
    local App = require("grapple.app")
    local app = App.get()

    local container = entity.container

    -- A string representation of the index
    local id = string.format("/%03d", index)

    -- Don't try to modify IDs which are not paths, like "global"
    local rel_id
    if Path.is_absolute(container.id) then
        rel_id = vim.fn.fnamemodify(container.id, ":~")
    else
        rel_id = container.id
    end

    -- In compliance with "grapple" syntax
    local line = string.format("%s %s", id, rel_id)
    local min_col = assert(string.find(line, "%s")) -- width of id

    -- Define line highlights for display and extmarks
    ---@type grapple.vim.highlight[]
    local highlights = {}

    local sign_highlight
    if app.settings.status and entity.current then
        sign_highlight = "GrappleCurrent"
    end

    local unloaded_highlight
    if not self.tag_manager:is_loaded(container.id) then
        unloaded_highlight = {
            hl_group = "GrappleHint",
            line = index - 1,
            col_start = min_col,
            col_end = -1,
        }
    end

    highlights = vim.tbl_filter(Util.not_nil, {
        unloaded_highlight,
    })

    -- Define line extmarks
    ---@type grapple.vim.extmark[]
    local extmarks = {}

    ---@type grapple.vim.mark
    local sign_mark
    if index < 10 then
        sign_mark = {
            sign_text = string.format("%d", index),
            sign_hl_group = sign_highlight,
        }
    end

    local count_mark
    if self.tag_manager:is_loaded(container.id) then
        local count = container:len()
        local count_text = count == 1 and "tag" or "tags"
        count_mark = {
            virt_text = { { string.format("[%d %s]", count, count_text) } },
            virt_text_pos = "eol",
        }
    end

    extmarks = vim.tbl_filter(Util.not_nil, {
        sign_mark,
        count_mark,
    })

    extmarks = vim.tbl_map(function(mark)
        return {
            line = index - 1,
            col = 0,
            opts = mark,
        }
    end, extmarks)

    ---@type grapple.window.entry
    local entry = {
        ---@class grapple.scope_content.data
        data = {
            id = container.id,
        },

        line = line,
        index = index,
        min_col = min_col,

        ---@type grapple.vim.highlight[]
        highlights = highlights,

        ---@type grapple.vim.extmark[]
        extmarks = extmarks,
    }

    return entry
end

---Safety: assume that the content is unmodifiable and the ID
---can always be parsed
---@param line string
---@param original_entries grapple.window.entry[]
---@return grapple.window.parsed_entry
function ContainerContent:parse_line(line, original_entries)
    local id, _ = string.match(line, "^/(%d+) (%S+)")
    local index = assert(tonumber(id))

    ---@type grapple.window.parsed_entry
    ---@diagnostic disable-next-line: assign-type-mismatch
    local entry = vim.deepcopy(original_entries[index])

    return entry
end

---@param action grapple.action
---@param opts? grapple.action.options
---@return string? error
function ContainerContent:perform(action, opts)
    return action(opts)
end

return ContainerContent
