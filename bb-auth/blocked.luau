local cancelSent = false


local function state(key, fallback)
    local value = noctalia.state.get(key)

    if value == nil then
        return fallback
    end

    return value
end


local function sendCancel(sessionId)
    local dataDir = noctalia.pluginDataDir()
    local pluginDir = noctalia.pluginDir()

    if dataDir == nil or pluginDir == nil then
        return false
    end

    local path =
        dataDir .. "/blocked-cancel.json"

    local ok = noctalia.writeFile(
        path,
        noctalia.json.encode({
            type = "session.cancel",
            id = sessionId,
        })
    )

    if not ok then
        return false
    end

    local started = noctalia.runAsync({
        "python3",
        pluginDir .. "/send.py",
        path,
    })

    if not started then
        noctalia.removeFile(path)
    end

    return started
end


local function cancelActiveSession()
    if cancelSent then
        return
    end

    local sessionId = state("session_id", "")

    if sessionId == "" then
        return
    end

    cancelSent = true

    noctalia.state.set(
        "cancel_session_id",
        sessionId
    )

    sendCancel(sessionId)
end


local function render()
    local info = state(
        "info",
        "Authentication is temporarily unavailable."
    )

    panel.render(
        ui.column(
            {
                padding = 20,
                gap = 14,
                fill = "surface",
                justify = "center",
            },
            {
                ui.row(
                    {
                        gap = 12,
                        align = "center",
                    },
                    {
                        ui.glyph({
                            name = "lock-exclamation",
                            size = 36,
                            color = "error",
                        }),

                        ui.column(
                            {
                                gap = 4,
                                flexGrow = 1,
                            },
                            {
                                ui.label({
                                    text = "Account temporarily locked",
                                    fontSize = 17,
                                    fontWeight = "bold",
                                    color = "on_surface",
                                }),

                                ui.label({
                                    text = info,
                                    fontSize = 12,
                                    color = "error",
                                    maxLines = 4,
                                }),
                            }
                        ),
                    }
                ),

                ui.row(
                    {
                        justify = "end",
                    },
                    {
                        ui.button({
                            text = "Close",
                            variant = "primary",
                            controlSize = "md",
                            onClick = "onCloseClicked",
                        }),
                    }
                ),
            }
        )
    )
end


function onCloseClicked()
    panel.close()
end


function onOpen()
    cancelSent = false

    noctalia.state.set(
        "blocked_panel_open",
        true
    )

    render()
end


function onClose()
    -- Keep the session alive while the warning is visible so
    -- PAM can deliver follow-up details such as the remaining
    -- lockout time. Closing the warning cancels the unusable
    -- password request.
    cancelActiveSession()

    noctalia.state.set(
        "blocked_panel_open",
        false
    )
end


noctalia.state.watch(
    "info",
    function()
        if state("blocked_panel_open", false) then
            render()
        end
    end
)
