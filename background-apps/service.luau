local apps = require("./lib/apps.luau")

local loadNames -- declaración adelantada: publish() la usa antes de definirla
local triedNames = {}

local function publish()
    noctalia.runAsync({
        "busctl",
        "--user",
        "--json=short",
        "get-property",
        "org.freedesktop.background.Monitor",
        "/org/freedesktop/background/monitor",
        "org.freedesktop.background.Monitor",
        "BackgroundApps",
    }, function(result)
        if result.exitCode ~= 0 then
            noctalia.log("Failed to read BackgroundApps: " .. result.stderr)
            noctalia.state.set("apps", {})
            return
        end

        local parsed, err = apps.parseBusctl(result.stdout)

        if not parsed then
            noctalia.log("Failed to parse BackgroundApps: " .. tostring(err))
            return
        end

        noctalia.state.set("apps", parsed)

        -- App instalada después de arrancar: recargar nombres (una vez por app)
        local missing = false
        for _, app in ipairs(parsed) do
            if not apps.hasName(app.appId) and not triedNames[app.appId] then
                triedNames[app.appId] = true
                missing = true
            end
        end
        if missing then
            loadNames()
        end
    end)
end

loadNames = function()
    noctalia.runAsync({
        "flatpak", "list", "--app",
        "--columns=application,name",
    }, function(result)
        if result.exitCode ~= 0 then
            noctalia.log("Failed to read flatpak names: " .. result.stderr)
            return
        end

        local map = {}
        for line in string.gmatch(result.stdout, "[^\n]+") do
            local id, name = string.match(line, "^([^\t]+)\t(.+)$")
            if id then
                map[id] = noctalia.string.trim(name)
            end
        end

        apps.setNames(map)
        publish()
    end)
end

local function onMonitorLine(line)
    if string.find(line, "PropertiesChanged", 1, true) then
        publish()
    end
end

local function startMonitor()
    local started = noctalia.runStream(
        "gdbus monitor --session " ..
        "--dest org.freedesktop.background.Monitor " ..
        "--object-path /org/freedesktop/background/monitor",
        onMonitorLine
    )

    if not started then
        noctalia.log("Failed to start BackgroundApps D-Bus monitor")
    end
end

noctalia.state.set("apps", {})

loadNames()
publish()
startMonitor()
