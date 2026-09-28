--[[--
This is a plugin to automatically log daily reading progress (pulled directly
from KOReader's own Statistics database) to a single Beeminder goal.

@module koplugin.Beeminder
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local socket = require("socket")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local logger = require("logger")
local DataStorage = require("datastorage")
local _ = require("gettext")

local Beeminder = WidgetContainer:extend{
    name = "beeminder",
    is_doc_only = false,
}

function Beeminder:init()
    local default_settings = {
        username = "",
        token = "",
        goal_slug = "reading",
    }
    self.settings = G_reader_settings:readSetting("beeminder", default_settings)

    if self.settings.goal_slug == nil then
        self.settings.goal_slug = "reading"
    end

    self.ui.menu:registerToMainMenu(self)
end

function Beeminder:setAuthToken(token)
    self.settings.token = token ~= "" and token or nil
end

function Beeminder:setUsername(username)
    self.settings.username = username
end

function Beeminder:setGoalSlug(slug)
    self.settings.goal_slug = slug ~= "" and slug or "reading"
end

-- Reads KOReader's own statistics.sqlite3 database and counts how many
-- distinct (book, page) pairs were logged as read today. This mirrors what
-- the built-in Statistics screen shows, since it relies on the same table,
-- rather than raw page-turn deltas which get inflated by skipping around
-- (table of contents, cover page, etc).
function Beeminder:getTodayPagesFromStats()
    local ok_req, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_req or not SQ3 then
        logger.dbg("Beeminder: could not load sqlite module")
        return nil
    end

    local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local ok_open, conn = pcall(SQ3.open, db_path)
    if not ok_open or not conn then
        logger.dbg("Beeminder: could not open statistics.sqlite3")
        return nil
    end

    -- KOReader has used different table names across versions
    -- (page_stat in older builds, page_stat_data in newer ones).
    local table_name = nil
    local ok_check, tables = pcall(function()
        return conn:exec([[
            SELECT name FROM sqlite_master
            WHERE type='table' AND name IN ('page_stat_data', 'page_stat');
        ]])
    end)
    if ok_check and tables and tables.name then
        if type(tables.name) == "table" then
            table_name = tables.name[1]
        else
            table_name = tables.name
        end
    end

    if not table_name then
        conn:close()
        logger.dbg("Beeminder: no known statistics table found")
        return nil
    end

    local sql = string.format([[
        SELECT COUNT(*) FROM (
            SELECT DISTINCT id_book, page FROM %s
            WHERE date(start_time, 'unixepoch', 'localtime') = date('now', 'localtime')
        );
    ]], table_name)

    local ok_query, result = pcall(function() return conn:rowexec(sql) end)
    conn:close()

    if not ok_query then
        logger.dbg("Beeminder: query against statistics.sqlite3 failed")
        return nil
    end

    return tonumber(result) or 0
end

function Beeminder:addToMainMenu(menu_items)
    menu_items.beeminder = {
        text = _("Beeminder"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Set username"),
                keep_menu_open = true,
                tap_input_func = function()
                    return {
                        title = _("Username"),
                        input = self.settings.username or "",
                        type = "text",
                        callback = function(input)
                            self:setUsername(input)
                        end,
                    }
                end,
            },
            {
                text = _("Set auth token"),
                keep_menu_open = true,
                tap_input_func = function()
                    return {
                        title = _("Auth token"),
                        input = self.settings.token or "",
                        type = "text",
                        callback = function(input)
                            self:setAuthToken(input)
                        end,
                    }
                end,
            },
            {
                text = _("Set goal name (slug)"),
                keep_menu_open = true,
                tap_input_func = function()
                    return {
                        title = _("Beeminder goal slug"),
                        input = self.settings.goal_slug or "reading",
                        type = "text",
                        callback = function(input)
                            self:setGoalSlug(input)
                        end,
                    }
                end,
            },
            {
                text_func = function()
                    local pages = self:getTodayPagesFromStats()
                    if pages == nil then
                        return _("Today's stats: unavailable")
                    end
                    return _(string.format("Today's pages (from Statistics): %d", pages))
                end,
                keep_menu_open = true,
                callback = function() end,
            },
            {
                text = _("Sync now"),
                keep_menu_open = true,
                callback = function()
                    self:syncToday(true)
                end,
            },
        }
    }
end

function Beeminder:getGoal()
    local url = "https://www.beeminder.com/api/v1/users/" .. self.settings.username ..
        "/goals/" .. self.settings.goal_slug .. ".json?auth_token=" .. self.settings.token
    local sink = {}
    local request = {
        url = url,
        sink = ltn12.sink.table(sink),
        method = "GET",
        headers = { ["Content-Type"] = "application/json" },
    }

    local status_code, resp_headers, status = socket.skip(1, http.request(request))
    local response = table.concat(sink)
    if status_code >= 300 then
        UIManager:show(InfoMessage:new{
            text = _(string.format("Communication with Beeminder failed with status code %d", status_code)), })
        logger.dbg("Beeminder GET failed " .. status_code .. ": " .. response)
        return nil
    end
    local ok, json_response = pcall(json.decode, response)
    if not ok or not json_response then
        UIManager:show(InfoMessage:new{ text = _("Failed to parse JSON from Beeminder"), })
        return nil
    end
    return json_response
end

function Beeminder:updateDatapoint(id, value, comment)
    local url = "https://www.beeminder.com/api/v1/users/" .. self.settings.username ..
        "/goals/" .. self.settings.goal_slug .. "/datapoints/" .. id .. ".json?auth_token=" .. self.settings.token
    local data = { value = value, comment = comment }
    local sink = {}
    local status_code = socket.skip(1, http.request{
        url = url,
        method = "PUT",
        headers = { ["Content-Type"] = "application/json" },
        source = ltn12.source.string(json.encode(data)),
        sink = ltn12.sink.table(sink),
    })
    local response = table.concat(sink)
    if status_code and status_code >= 300 then
        UIManager:show(InfoMessage:new{
            text = _(string.format("Update datapoint failed with status code %d", status_code)), })
        logger.dbg("Update failed: " .. response)
    end
end

function Beeminder:createDatapoint(value, comment)
    local url = "https://www.beeminder.com/api/v1/users/" .. self.settings.username ..
        "/goals/" .. self.settings.goal_slug .. "/datapoints.json?auth_token=" .. self.settings.token
    local data = { value = value, comment = comment }
    local sink = {}
    local status_code = http.request{
        url = url,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        source = ltn12.source.string(json.encode(data)),
        sink = ltn12.sink.table(sink),
    }
    local response = table.concat(sink)
    if status_code and status_code >= 300 then
        UIManager:show(InfoMessage:new{
            text = _(string.format("Create datapoint failed with status code %d", status_code)), })
        logger.dbg("Create failed: " .. response)
    end
end

-- Pulls today's real page count from KOReader's Statistics database and
-- pushes it to the single configured Beeminder goal.
function Beeminder:syncToday(manual_trigger)
    if self.settings.username == "" or not self.settings.token then
        if manual_trigger then
            UIManager:show(InfoMessage:new{ text = _("Set your username and auth token first"), })
        end
        return
    end

    local page_count = self:getTodayPagesFromStats()
    if page_count == nil then
        if manual_trigger then
            UIManager:show(InfoMessage:new{ text = _("Could not read KOReader statistics database"), })
        end
        return
    end

    if page_count <= 0 then
        return
    end

    NetworkMgr:goOnlineToRun(function()
        local goal = self:getGoal()
        if not goal then
            return
        end

        if goal.last_datapoint and goal.last_datapoint.value == page_count then
            return
        end

        local today = os.date("*t")
        local datapoint_date = goal.last_datapoint and os.date("*t", goal.last_datapoint.timestamp) or nil

        if datapoint_date and datapoint_date.year == today.year
            and datapoint_date.month == today.month
            and datapoint_date.day == today.day then
            self:updateDatapoint(goal.last_datapoint.id, page_count, "Logged from KOReader statistics")
        else
            self:createDatapoint(page_count, "Logged from KOReader statistics")
        end

        if manual_trigger then
            UIManager:show(InfoMessage:new{
                text = _(string.format("Synced %d pages to Beeminder", page_count)), })
        end
    end)
end

function Beeminder:onCloseDocument()
    self:syncToday()
end

function Beeminder:onSuspend()
    self:syncToday()
end

function Beeminder:onCloseWidget()
    self:syncToday()
end

return Beeminder
