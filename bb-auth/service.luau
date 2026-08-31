local PLUGIN_ID = "branrgx/bb-auth"
local PANEL_ID = PLUGIN_ID .. ":prompt"
local BLOCKED_PANEL_ID = PLUGIN_ID .. ":blocked"

local PINENTRY_GRACE_MS = 1000

local pluginDir = noctalia.pluginDir()

if pluginDir == nil then
    error("BB Auth: plugin directory unavailable")
end

local bridgePath = pluginDir .. "/bridge.py"

local pendingCloseAt = nil
local pendingCloseSessionId = nil
local pendingCloseResult = nil


local function set(key, value)
    noctalia.state.set(key, value)
end


local function clearPendingClose()
    pendingCloseAt = nil
    pendingCloseSessionId = nil
    pendingCloseResult = nil
end


local function resetSession()
    set("active", false)
    set("session_id", "")
    set("source", "")

    set("message", "")
    set("description", "")

    set("requestor_name", "")
    set("requestor_icon", "")

    set("prompt", "")
    set("error", "")
    set("info", "")

    set("echo", false)
    set("confirm_only", false)
    set("auth_blocked", false)

    set("cur_retry", 0)
    set("max_retries", 0)

    set("result", "")

    --
    -- ID de una sesión que el usuario está cancelando.
    --
    -- Mientras coincida con la sesión actual, sus updates
    -- no deben volver a abrir el panel.
    --
    set("cancel_session_id", "")

    clearPendingClose()
end


local function requestorTitle()
    local name =
        noctalia.state.get(
            "requestor_name"
        )

    if name ~= nil
        and name ~= ""
        and name ~= "unknown"
        and name ~= "Unknown"
    then
        return name
    end

    local source =
        noctalia.state.get("source")

    if source == "polkit" then
        return "System"
    elseif source == "keyring" then
        return "Keyring"
    end

    return "Authentication"
end


local function isCancelling(sessionId)
    local cancelled =
        noctalia.state.get(
            "cancel_session_id"
        )

    return cancelled ~= nil
        and cancelled ~= ""
        and cancelled == sessionId
end


local function openPanel()
    local sessionId =
        noctalia.state.get(
            "session_id"
        )

    if sessionId == nil
        or sessionId == ""
        or isCancelling(sessionId)
    then
        return
    end

    if noctalia.state.get("panel_open") then
        return
    end

    set("panel_open", true)

    noctalia.togglePanel(
        PANEL_ID
    )
end


local function isBlockedMessage(value)
    if value == nil then
        return false
    end

    local text =
        string.lower(tostring(value))

    return string.find(
        text,
        "locked",
        1,
        true
    ) ~= nil
        or string.find(
            text,
            "bloquead",
            1,
            true
        ) ~= nil
end


local function openBlockedPanel()
    if noctalia.state.get(
        "blocked_panel_open"
    ) then
        return
    end

    noctalia.togglePanel(
        BLOCKED_PANEL_ID
    )
end


local function finishSession(result)
    local title =
        requestorTitle()

    set("result", result or "")
    set("active", false)

    if result == "success" then
        noctalia.notify(
            title,
            "Authentication successful"
        )
    end
end


local function handleCreated(message)
    local context =
        message.context or {}

    local requestor =
        context.requestor or {}

    clearPendingClose()

    --
    -- Si es una sesión realmente nueva, ya no pertenece
    -- a la cancelación anterior.
    --
    local cancelledId =
        noctalia.state.get(
            "cancel_session_id"
        )

    if cancelledId ~= nil
        and cancelledId ~= ""
        and cancelledId ~= message.id
    then
        set(
            "cancel_session_id",
            ""
        )
    end

    set("active", true)

    set(
        "session_id",
        message.id or ""
    )

    set(
        "source",
        message.source or ""
    )

    set(
        "message",
        context.message or ""
    )

    set(
        "description",
        context.description or ""
    )

    set(
        "requestor_name",
        requestor.name or ""
    )

    set(
        "requestor_icon",
        requestor.icon or ""
    )

    set(
        "confirm_only",
        context.confirmOnly == true
    )

    set("auth_blocked", false)

    set(
        "cur_retry",
        context.curRetry or 0
    )

    set(
        "max_retries",
        context.maxRetries or 0
    )

    set("prompt", "")
    set("error", "")
    set("info", "")
    set("echo", false)
    set("result", "")
end


local function handleUpdated(message)
    if message.id
        ~= noctalia.state.get(
            "session_id"
        )
    then
        return
    end

    --
    -- Muy importante para Escape/Cancel:
    --
    -- Polkit puede enviar uno o más updates mientras procesa
    -- la cancelación. No permitimos que esos updates vuelvan
    -- a abrir el panel.
    --
    if isCancelling(message.id) then
        return
    end

    clearPendingClose()

    if message.prompt ~= nil then
        set(
            "prompt",
            message.prompt
        )
    end

    if message.error ~= nil then
        set(
            "error",
            message.error
        )
    end

    if message.info ~= nil
        and message.info ~= ""
    then
        local currentInfo =
            noctalia.state.get("info")

        local newInfo =
            tostring(message.info)

        -- PAM may send the lock reason and the remaining
        -- time as separate updates. Preserve both until the
        -- session ends instead of discarding the first one
        -- when the password prompt arrives.
        if currentInfo == nil
            or currentInfo == ""
        then
            set("info", newInfo)
        elseif not string.find(
            currentInfo,
            newInfo,
            1,
            true
        ) then
            set(
                "info",
                currentInfo
                    .. "\n"
                    .. newInfo
            )
        end


        if isBlockedMessage(newInfo) then
            set("auth_blocked", true)
            openBlockedPanel()
            return
        end
    end

    if noctalia.state.get("auth_blocked") then
        return
    end

    if message.echo ~= nil then
        set(
            "echo",
            message.echo == true
        )
    end

    if message.curRetry ~= nil then
        set(
            "cur_retry",
            message.curRetry
        )
    end

    if message.maxRetries ~= nil then
        set(
            "max_retries",
            message.maxRetries
        )
    end

    openPanel()
end


local function handleClosed(message)
    if message.id
        ~= noctalia.state.get(
            "session_id"
        )
    then
        return
    end

    --
    -- Esta era una cancelación iniciada por nuestra UI.
    -- Simplemente terminamos la sesión y no reabrimos nada.
    --
    if isCancelling(message.id) then
        clearPendingClose()

        set(
            "cancel_session_id",
            ""
        )

        set(
            "result",
            message.result or "cancelled"
        )

        set("active", false)

        return
    end

    local result =
        message.result or ""

    local source =
        noctalia.state.get(
            "source"
        )

    --
    -- Pinentry puede cerrar correctamente la conversación
    -- antes de que el consumidor valide el secreto.
    --
    if source == "pinentry"
        and result == "success"
    then
        pendingCloseSessionId =
            message.id

        pendingCloseResult =
            result

        pendingCloseAt =
            noctalia.nowMs()
            + PINENTRY_GRACE_MS

        return
    end

    finishSession(result)
end


local function handleMessage(line)
    local message =
        noctalia.json.decode(line)

    if message == nil then
        return
    end

    if message._bridge == true then
        if message.type == "bridge.log" then
            noctalia.log(
                "BB Auth: "
                    .. tostring(
                        message.message
                    )
            )
        end

        return
    end

    local messageType =
        message.type

    if messageType == "ui.registered" then
        set(
            "provider_active",
            message.active == true
        )

        return
    end

    if messageType == "ui.active" then
        set(
            "provider_active",
            message.active == true
        )

        return
    end

    if messageType == "session.created" then
        handleCreated(message)
        return
    end

    if messageType == "session.updated" then
        handleUpdated(message)
        return
    end

    if messageType == "session.closed" then
        handleClosed(message)
        return
    end

    if messageType == "error" then
        noctalia.log(
            "BB Auth daemon error: "
                .. tostring(
                    message.message
                )
        )
    end
end


noctalia.setUpdateInterval(100)


function update()
    if pendingCloseAt == nil then
        return
    end

    if noctalia.nowMs()
        < pendingCloseAt
    then
        return
    end

    if pendingCloseSessionId
        ~= noctalia.state.get(
            "session_id"
        )
    then
        clearPendingClose()
        return
    end

    local result =
        pendingCloseResult

    clearPendingClose()

    finishSession(result)
end


resetSession()

set("panel_open", false)
set("blocked_panel_open", false)
set("provider_active", false)


local started =
    noctalia.runStream(
        "python3 "
            .. string.format(
                "%q",
                bridgePath
            ),
        handleMessage
    )


if not started then
    noctalia.notifyError(
        "Authentication",
        "Could not start authentication provider"
    )
end


function onExit()
    resetSession()

    set("panel_open", false)
    set("blocked_panel_open", false)
    set("provider_active", false)
end
