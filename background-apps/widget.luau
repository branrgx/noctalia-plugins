local PANEL_ID = "branrgx/background-apps:list"

local glyph = noctalia.getConfig("glyph")
if glyph == nil or glyph == "" then
    glyph = "ghost"
end

local function refresh(apps)
    if #apps == 0 then
        barWidget.setVisible(false)
        return
    end

    barWidget.setVisible(true)
    barWidget.setGlyph(glyph)
    barWidget.setText(#apps > 1 and tostring(#apps) or "")

    local rows = {}
    for _, app in ipairs(apps) do
        table.insert(rows, { key = app.name or app.appId, value = app.message or "" })
    end
    barWidget.setTooltip(rows)
end

function onClick()
    noctalia.togglePanel(PANEL_ID)
end

noctalia.state.watch("apps", function(value)
    refresh(value or {})
end)

refresh(noctalia.state.get("apps") or {})
