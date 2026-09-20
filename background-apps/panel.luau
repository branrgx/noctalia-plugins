local apps = noctalia.state.get("apps") or {}
local isOpen = false
local iconCache = {}
local render

local canStop = {}   -- appId -> true/false; nil = aún sin comprobar
local checking = {}

local PANEL_HEIGHT = 360 -- igual que `height` en plugin.toml
local CHROME_HEIGHT = 70
local LIST_HEIGHT = PANEL_HEIGHT - CHROME_HEIGHT
local MAX_VISIBLE_ROWS = 5

-- org.foo.Bar-Baz -> /org/foo/Bar_Baz
local function objectPath(appId)
    local path = appId:gsub("%.", "/")
    path = path:gsub("%-", "_")
    return "/" .. path
end

local function iconFor(appId)
    local cached = iconCache[appId]
    if cached == nil then
        cached = noctalia.appIconPath(appId, 32) or false
        iconCache[appId] = cached
    end
    return cached or nil
end

local function checkStop(app)
    if canStop[app.appId] ~= nil or checking[app.appId] then
        return
    end
    checking[app.appId] = true

    noctalia.runAsync({
        "gdbus", "call", "--session",
        "--dest", app.appId,
        "--object-path", objectPath(app.appId),
        "--method", "org.gtk.Actions.List",
    }, function(result)
        checking[app.appId] = nil
        canStop[app.appId] = result.exitCode == 0
            and string.find(result.stdout, "'quit'", 1, true) ~= nil
        if isOpen then
            render()
        end
    end)
end

local function stop(app)
    noctalia.runAsync({
        "gdbus", "call", "--session",
        "--dest", app.appId,
        "--object-path", objectPath(app.appId),
        "--method", "org.freedesktop.Application.ActivateAction",
        "quit", "@av []", "@a{sv} {}",
    }, function(result)
        if result.exitCode == 0 then
            return
        end

        noctalia.log("Stop " .. app.appId .. " exit=" .. tostring(result.exitCode) .. " stderr=" .. result.stderr)

        -- La app cerró antes de responder: el quit funcionó.
        local err = result.stderr or ""
        if string.find(err, "NoReply", 1, true)
            or string.find(err, "disconnected", 1, true)
            or string.find(err, "ServiceUnknown", 1, true) then
            return
        end

        noctalia.notifyError(
            app.name or app.appId,
            noctalia.tr("notify.stop_failed", { app = app.name or app.appId })
        )
    end)
end

local function forceStop(app)
    noctalia.runAsync({ "flatpak", "kill", app.appId })
end

local function appRow(app)
    local icon = iconFor(app.appId)

    local texts = {
        ui.label({ text = app.name or app.appId, fontWeight = "bold", maxLines = 1, maxWidth = 190 }),
    }
    if app.message and app.message ~= "" then
        table.insert(texts, ui.label({
            text = app.message,
            fontSize = 11,
            color = "on_surface_variant",
            maxLines = 1,
            maxWidth = 190,
        }))
    end

    local children = {}
    if icon then
        table.insert(children, ui.image({ path = icon, width = 32, height = 32, fit = "contain" }))
    else
        table.insert(children, ui.glyph({ name = "ghost", size = 28 }))
    end
    table.insert(children, ui.column({ gap = 2, align = "start", flexGrow = 1 }, texts))

    local stopSupported = canStop[app.appId] ~= false

    table.insert(children, ui.button({
        glyph = "x",
        variant = "ghost",
        controlSize = "sm",
        enabled = stopSupported,
        tooltip = stopSupported and noctalia.tr("action.stop")
            or noctalia.tr("tooltip.stop_unsupported"),
        onClick = function() stop(app) end,
    }))

    table.insert(children, ui.button({
        glyph = "skull",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("action.force_stop"),
        onClick = function() forceStop(app) end,
    }))

    return ui.row({ key = "app-" .. app.appId, gap = 10, align = "center", padding = 6 }, children)
end

render = function()
    local rows = {}
    for _, app in ipairs(apps) do
        table.insert(rows, appRow(app))
    end
    if #rows == 0 then
        table.insert(rows, ui.label({ text = noctalia.tr("panel.empty"), color = "on_surface_variant" }))
    end

    local list
    if #rows > MAX_VISIBLE_ROWS then
        list = ui.scroll({ key = "list-scroll", gap = 4, height = LIST_HEIGHT }, rows)
    else
        list = ui.column({ key = "list-column", gap = 4 }, rows)
    end

    panel.render(ui.column({ gap = 12 }, {
        ui.row({ gap = 10, align = "center" }, {
            ui.glyph({ name = "ghost", size = 26, color = "primary" }),
            ui.column({ gap = 2, align = "start" }, {
                ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold" }),
                ui.label({ text = noctalia.tr("panel.subtitle"), fontSize = 11, color = "on_surface_variant" }),
            }),
        }),
        ui.separator({}),
        list,
    }))
end

function onOpen()
    isOpen = true
    apps = noctalia.state.get("apps") or {}
    for _, app in ipairs(apps) do
        checkStop(app)
    end
    render()
end

function onClose()
    isOpen = false
end

noctalia.state.watch("apps", function(value)
    apps = value or {}
    if isOpen then
        for _, app in ipairs(apps) do
            checkStop(app)
        end
        render()
    end
end)
