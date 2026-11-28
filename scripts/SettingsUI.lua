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

local function isManureControl(element)
    -- Use the native control's identifier, never translated display text or
    -- the position of the last section (which other mods can extend).
    for _, key in ipairs({"id", "name"}) do
        local identifier = element[key]
        if type(identifier) == "string" then
            identifier = identifier:lower()
            if identifier == "multimanure" or identifier == "multibuymanure"
                or identifier:match("^multihelper.*manure$") then
                return true
            end
        end
    end
    for _, child in ipairs(element.elements or {}) do
        if isManureControl(child) then return true end
    end
    return false
end

function AIUnloadThresholdUI.findWorkersRow(layout)
    for _, row in ipairs(layout.elements or {}) do
        if isManureControl(row) then return row end
    end
    return nil
end

local function moveAfter(elements, row, anchor)
    if elements == nil then return end
    local rowIndex, anchorIndex
    for index, element in ipairs(elements) do
        if element == row then rowIndex = index end
        if element == anchor then anchorIndex = index end
    end
    if rowIndex == nil or anchorIndex == nil or rowIndex == anchorIndex + 1 then return end
    table.remove(elements, rowIndex)
    if rowIndex < anchorIndex then anchorIndex = anchorIndex - 1 end
    table.insert(elements, anchorIndex + 1, row)
end

function AIUnloadThresholdUI.createRow(page, layout)
    -- The settings frame recolors each controlsList row during navigation and
    -- closing. Its container must provide BitmapElement:setImageColor.
    local row = BitmapElement.new(page)
    if row == nil then
        AIUnloadThresholdUI.warnOnce("Could not create settings row")
        return nil
    end
    -- Keep the row detached until every child has been created successfully.
    row.id = "aiUnloadThresholdBox"
    row.name = "aiUnloadThresholdBox"
    row:applyProfile("aiut_settingsRow")

    local target = {name = page.name, onChanged = AIUnloadThresholdUI.onChanged}
    local option = OptionSliderElement.new(target)
    if option == nil then
        row:delete()
        AIUnloadThresholdUI.warnOnce("Could not create settings option")
        return nil
    end
    row:addElement(option)
    option.id = "aiUnloadThresholdSlider"
    option.name = "aiUnloadThresholdSlider"
    option:applyProfile("aiut_settingsSlider")

    local tooltip = TextElement.new(page)
    if tooltip == nil then
        row:delete()
        AIUnloadThresholdUI.warnOnce("Could not create settings tooltip")
        return nil
    end
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
        row:delete()
        AIUnloadThresholdUI.warnOnce("Native OptionSliderElement did not create its slider")
        return nil
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
    if label == nil then
        row:delete()
        AIUnloadThresholdUI.warnOnce("Could not create settings label")
        return nil
    end
    row:addElement(label)
    label:applyProfile("fs25_settingsMultiTextOptionTitle")
    label:setText(g_i18n:getText("aiut_label"))

    row.aiUnloadThresholdOption = option
    assignFocusIds(row)
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
    local workersRow = AIUnloadThresholdUI.findWorkersRow(layout)
    if workersRow == nil then
        AIUnloadThresholdUI.warnOnce("AI Workers manure setting unavailable")
        return
    end
    local row = page.aiUnloadThresholdRow
    if row == nil then
        row = AIUnloadThresholdUI.createRow(page, layout)
        page.aiUnloadThresholdRow = row
        if row == nil then return end
    end
    -- Reapply on every opening so rows added by other mods cannot leave this
    -- setting under their heading. Keep the frame's control order in sync.
    moveAfter(layout.elements, row, workersRow)
    moveAfter(page.controlsList, row, workersRow)
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
        or BitmapElement == nil or type(BitmapElement.new) ~= "function" or TextElement == nil or type(TextElement.new) ~= "function" or g_gui == nil
        or type(g_gui.loadProfiles) ~= "function" or Utils == nil or type(Utils.appendedFunction) ~= "function" then
        AIUnloadThresholdUI.warnOnce("Native settings UI API unavailable")
        return
    end
    g_gui:loadProfiles(AIUnloadThreshold.modDirectory .. "gui/guiProfiles.xml")
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, AIUnloadThresholdUI.onOpen)
    AIUnloadThresholdUI.installed = true
end
