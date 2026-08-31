local password = ""
local inputRevision = 0
local submitted = false


local function state(key, fallback)
    local value =
        noctalia.state.get(key)

    if value == nil then
        return fallback
    end

    return value
end


local function sendMessage(
    message,
    filename
)
    local dataDir, dirError =
        noctalia.pluginDataDir()

    if dataDir == nil then
        noctalia.notifyError(
            "Authentication",
            tostring(dirError)
        )

        return false
    end

    local path =
        dataDir
        .. "/"
        .. filename

    local payload =
        noctalia.json.encode(
            message
        )

    local ok, writeError =
        noctalia.writeFile(
            path,
            payload
        )

    if not ok then
        noctalia.notifyError(
            "Authentication",
            tostring(writeError)
        )

        return false
    end

    local pluginDir =
        noctalia.pluginDir()

    if pluginDir == nil then
        noctalia.removeFile(path)
        return false
    end

    local started =
        noctalia.runAsync({
            "python3",
            pluginDir .. "/send.py",
            path,
        })

    if not started then
        noctalia.removeFile(path)

        noctalia.notifyError(
            "Authentication",
            "Could not send authentication response"
        )

        return false
    end

    return true
end


local function requestorName()
    local name =
        state(
            "requestor_name",
            ""
        )

    if name ~= ""
        and name ~= "unknown"
        and name ~= "Unknown"
    then
        return name
    end

    local source =
        state(
            "source",
            ""
        )

    if source == "polkit" then
        return "System"
    elseif source == "keyring" then
        return "Keyring"
    end

    return "Authentication"
end


local function resolveRequestorIcon()
    local icon =
        state(
            "requestor_icon",
            ""
        )

    if icon == "" then
        return nil
    end

    if string.sub(icon, 1, 1) == "/" then
        if noctalia.fileExists(icon) then
            return icon
        end

        return nil
    end

    return noctalia.appIconPath(
        icon,
        48
    )
end


local function statusText()
    local errorText =
        state(
            "error",
            ""
        )

    if errorText ~= "" then
        return errorText
    end

    return "Authentication required"
end


local function render()
    local iconPath =
        resolveRequestorIcon()

    local name =
        requestorName()

    local prompt =
        state(
            "prompt",
            "Password"
        )

    local echo =
        state(
            "echo",
            false
        )

    local confirmOnly =
        state(
            "confirm_only",
            false
        )

    local errorText =
        state(
            "error",
            ""
        )

    local children = {}

    ------------------------------------------------------------
    -- HEADER
    ------------------------------------------------------------

    local headerChildren = {}

    if iconPath ~= nil
        and iconPath ~= ""
    then
        table.insert(
            headerChildren,
            ui.image({
                path = iconPath,
                width = 42,
                height = 42,
                radius = 9,
                fit = "contain",
            })
        )
    end

    table.insert(
        headerChildren,
        ui.column(
            {
                gap = 2,
                flexGrow = 1,
            },
            {
                ui.label({
                    text = name,

                    fontSize = 17,
                    fontWeight = "bold",

                    color =
                        "on_surface",

                    maxLines = 1,
                }),

                ui.label({
                    text =
                        statusText(),

                    fontSize = 12,

                    color =
                        errorText ~= ""
                            and "error"
                            or "on_surface_variant",

                    maxLines = 1,
                }),
            }
        )
    )

    table.insert(
        children,
        ui.row(
            {
                gap = 12,
                align = "center",
            },
            headerChildren
        )
    )

    ------------------------------------------------------------
    -- INPUT
    ------------------------------------------------------------

    if not confirmOnly then
        table.insert(
            children,
            ui.input({
                key =
                    "auth-input-"
                    .. tostring(
                        inputRevision
                    ),

                placeholder =
                    prompt ~= ""
                        and prompt
                        or "Password",

                password =
                    not echo,

                focus = true,

                controlSize = "lg",

                submitOnEnter = true,

                onChange =
                    "onPasswordChanged",

                onSubmit =
                    "onSubmit",
            })
        )
    end

    ------------------------------------------------------------
    -- BUTTONS
    ------------------------------------------------------------

    table.insert(
        children,
        ui.row(
            {
                gap = 10,
                justify = "end",
                align = "center",
            },
            {
                ui.button({
                    text = "Cancel",

                    --
                    -- Ghost puede perderse con ciertos temas.
                    -- Outline mantiene contraste sin competir
                    -- visualmente con la acción principal.
                    --
                    variant = "outline",

                    controlSize = "md",

                    onClick =
                        "onCancel",
                }),

                ui.button({
                    text =
                        confirmOnly
                            and "Confirm"
                            or "Authenticate",

                    glyph =
                        confirmOnly
                            and "check"
                            or "lock-open",

                    variant = "primary",

                    controlSize = "md",

                    onClick =
                        "onSubmit",
                }),
            }
        )
    )

    panel.render(
        ui.column(
            {
                padding = 18,
                gap = 14,
                fill = "surface",
                justify = "center",
            },
            children
        )
    )
end


function onPasswordChanged(value)
    password = value
end


function onSubmit()
    if submitted then
        return
    end

    local sessionId =
        state(
            "session_id",
            ""
        )

    if sessionId == "" then
        return
    end

    local confirmOnly =
        state(
            "confirm_only",
            false
        )

    if not confirmOnly
        and password == ""
    then
        return
    end

    submitted = true

    noctalia.state.set(
        "error",
        ""
    )

    local response =
        confirmOnly
            and ""
            or password

    local ok =
        sendMessage(
            {
                type =
                    "session.respond",

                id =
                    sessionId,

                response =
                    response,
            },
            "response.json"
        )

    password = ""

    if not ok then
        submitted = false
        render()

        return
    end

    panel.close()
end


function onCancel()
    if submitted then
        return
    end

    local sessionId =
        state(
            "session_id",
            ""
        )

    submitted = true
    password = ""

    if sessionId ~= "" then
        --
        -- Marcamos la sesión ANTES de cerrar o enviar el
        -- mensaje para evitar la carrera con Polkit.
        --
        noctalia.state.set(
            "cancel_session_id",
            sessionId
        )

        sendMessage(
            {
                type =
                    "session.cancel",

                id =
                    sessionId,
            },
            "cancel.json"
        )
    end

    panel.close()
end


function onOpen()
    password = ""
    submitted = false

    inputRevision =
        inputRevision + 1

    noctalia.state.set(
        "panel_open",
        true
    )

    render()
end


function onClose()
    password = ""

    noctalia.state.set(
        "panel_open",
        false
    )

    ------------------------------------------------------------
    -- Si submitted=true:
    --
    -- - pulsamos Authenticate, o
    -- - pulsamos Cancel.
    --
    -- En ambos casos ya gestionamos explícitamente la sesión.
    --
    -- Si submitted=false, el cierre vino de Escape u otro
    -- cierre manual del panel.
    ------------------------------------------------------------

    if state("active", false)
        and not submitted
    then
        local sessionId =
            state(
                "session_id",
                ""
            )

        if sessionId ~= "" then
            --
            -- Importantísimo: establecer esto antes de mandar
            -- session.cancel.
            --
            noctalia.state.set(
                "cancel_session_id",
                sessionId
            )

            sendMessage(
                {
                    type =
                        "session.cancel",

                    id =
                        sessionId,
                },
                "cancel.json"
            )
        end
    end

    submitted = false
end


noctalia.state.watch(
    "session_id",
    function()
        password = ""

        inputRevision =
            inputRevision + 1
    end
)


local function rerenderIfOpen()
    if state(
        "panel_open",
        false
    ) then
        render()
    end
end


noctalia.state.watch(
    "error",
    rerenderIfOpen
)

noctalia.state.watch(
    "prompt",
    rerenderIfOpen
)

noctalia.state.watch(
    "requestor_name",
    rerenderIfOpen
)

noctalia.state.watch(
    "requestor_icon",
    rerenderIfOpen
)
