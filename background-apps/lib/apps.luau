local M = {}

local names = {}

function M.setNames(map)
    names = map
end

function M.hasName(appId)
    return names[appId] ~= nil
end

local function group(entries)
    local byAppId = {}
    local result = {}

    for _, entry in ipairs(entries) do
        local appId = entry.appId

        if appId then
            local app = byAppId[appId]

            if not app then
                app = {
                    appId = appId,
                    name = names[appId] or appId,
                    message = nil,
                    instances = {},
                }

                byAppId[appId] = app
                table.insert(result, app)
            end

            table.insert(app.instances, {
                id = entry.instance,
                message = entry.message,
            })

            if not app.message and entry.message then
                app.message = entry.message
            end
        end
    end

    table.sort(result, function(a, b)
        return a.appId < b.appId
    end)

    return result
end

function M.parseBusctl(raw)
    local decoded, err = noctalia.json.decode(raw)

    if not decoded then
        return nil, err
    end

    if decoded.type ~= "aa{sv}" then
        return nil, "Unexpected D-Bus type: " .. tostring(decoded.type)
    end

    if type(decoded.data) ~= "table" then
        return nil, "BackgroundApps data is not a table"
    end

    local entries = {}

    for _, item in ipairs(decoded.data) do
        local appId = item.app_id and item.app_id.data
        local instance = item.instance and item.instance.data
        local message = item.message and item.message.data

        if appId then
            table.insert(entries, {
                appId = appId,
                instance = instance,
                message = message,
            })
        end
    end

    return group(entries)
end

return M
