AIUnloadThresholdUI = {installed = false}

local function assignFocusIds(element)
    element.focusId = FocusManager:serveAutoFocusId()
    element.focusChangeData = {}
    for _, child in ipairs(element.elements or {}) do
        assignFocusIds(child)
    end
end

function AIUnloadThresholdUI.onChanged(target, state)
    if AIUnloadThresholdLogic.isSinglePlayer(g_currentMission) then
        AIUnloadThresholdSettings:setIndex(state)
    end
end

function AIUnloadThresholdUI.createRow(page, layout)
    -- The settings frame recolors each controlsList row during navigation and
    -- closing. Its container must provide BitmapElement:setImageColor.
    local row = BitmapElement.new(page)
    -- Keep the row detached until every child has been created successfully.
    local ok, message = pcall(function()
        row.id = "aiUnloadThresholdBox"
        row.name = "aiUnloadThresholdBox"
        row:applyProfile("aiut_settingsRow")

        local target = {name = page.name, onChanged = AIUnloadThresholdUI.onChanged}
        local option = OptionSliderElement.new(target)
        row:addElement(option)
        option.id = "aiUnloadThresholdSlider"
        option.name = "aiUnloadThresholdSlider"
        option:applyProfile("aiut_settingsSlider")

        local tooltip = TextElement.new(page)
        tooltip.name = "ignore"
        option:addElement(tooltip)
        -- The stock tooltip profile is positioned relative to the option's
        -- right edge. Keep the option at the standard -10px inset so the
        -- tooltip starts beyond the settings/description column separator.
        tooltip:applyProfile("fs25_multiTextOptionTooltip")
        tooltip:setText(g_i18n:getText("aiut_tooltip"))

        -- Constructors alone do not create the native slider's visual children.
        option:addDefaultElements()
        option:setElementsByName()
        if option.sliderElement == nil then
            error("Native OptionSliderElement did not create its slider")
        end
        option:setCallback("onClickCallback", "onChanged")
        option.wrap = false
        local labels = {}
        for _, value in ipairs(AIUnloadThresholdSettings.VALUES) do
            table.insert(labels, value == 100 and g_i18n:getText("aiut_vanilla") or tostring(value) .. "%")
        end
        option:setTexts(labels)
        option:setState(AIUnloadThresholdSettings:getIndex())

        local label = TextElement.new(page)
        row:addElement(label)
        label:applyProfile("fs25_settingsMultiTextOptionTitle")
        label:setText(g_i18n:getText("aiut_label"))

        row.aiUnloadThresholdOption = option
        assignFocusIds(row)
    end)
    if not ok then
        row:delete()
        AIUnloadThresholdUI.warnOnce("Could not create native settings slider: " .. tostring(message))
        return nil
    end
    layout:addElement(row)
    if page.controlsList ~= nil then table.insert(page.controlsList, row) end
    Logging.info("[AIUnloadThreshold] Slider added to Game Settings (gameSettingsLayout).")
    return row
end

function AIUnloadThresholdUI.onOpen(page)
    -- Both sections belong to InGameMenuSettingsFrame. Never inject into
    -- generalSettingsLayout: this setting belongs under Game Settings.
    local layout = page.gameSettingsLayout
    if layout == nil or type(layout.invalidateLayout) ~= "function" then
        AIUnloadThresholdUI.warnOnce("Game Settings layout unavailable")
        return
    end
    local row = page.aiUnloadThresholdRow
    if row == nil then
        row = AIUnloadThresholdUI.createRow(page, layout)
        page.aiUnloadThresholdRow = row
        if row == nil then return end
    end
    local option = row.aiUnloadThresholdOption
    option:setState(AIUnloadThresholdSettings:getIndex())
    option:setDisabled(not AIUnloadThresholdLogic.isSinglePlayer(g_currentMission))
    local focus = FocusManager.currentFocusData
    if focus ~= nil and focus.idToElementMapping ~= nil and focus.idToElementMapping[row.focusId] ~= row then
        if not FocusManager:loadElementFromCustomValues(row, nil, nil, false, false) then
            AIUnloadThresholdUI.warnOnce("Could not register settings slider focus")
        end
    end
    layout:invalidateLayout()
    -- The base onFrameOpen already colored the old rows before our new row
    -- existed. Re-run its own striping after insertion, including on reopen.
    if type(page.updateAlternatingElements) == "function" then
        page:updateAlternatingElements(layout)
    end
end

function AIUnloadThresholdUI.warnOnce(message)
    if not AIUnloadThresholdUI.warningShown then
        AIUnloadThresholdUI.warningShown = true
        Logging.warning("[AIUnloadThreshold] %s; settings UI could not be initialized.", message)
    end
end

function AIUnloadThresholdUI.install()
    if AIUnloadThresholdUI.installed then return end
    if InGameMenuSettingsFrame == nil or type(InGameMenuSettingsFrame.onFrameOpen) ~= "function"
        or FocusManager == nil or type(FocusManager.serveAutoFocusId) ~= "function"
        or type(FocusManager.loadElementFromCustomValues) ~= "function"
        or OptionSliderElement == nil or type(OptionSliderElement.new) ~= "function"
        or BitmapElement == nil or type(BitmapElement.new) ~= "function" or TextElement == nil or g_gui == nil
        or type(g_gui.loadProfiles) ~= "function" or Utils == nil or type(Utils.appendedFunction) ~= "function" then
        AIUnloadThresholdUI.warnOnce("Native settings UI API unavailable")
        return
    end
    g_gui:loadProfiles(AIUnloadThreshold.modDirectory .. "gui/guiProfiles.xml")
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, AIUnloadThresholdUI.onOpen)
    AIUnloadThresholdUI.installed = true
end
