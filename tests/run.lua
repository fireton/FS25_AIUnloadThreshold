-- Local contract tests. The vanilla stub models the documented latch/timer
-- behavior; this suite is not a substitute for testing GIANTS Engine in-game.
local passed = 0
local function check(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end
Logging = {warning = function() end, info = function() end}
dofile("scripts/Settings.lua")
dofile("scripts/UnloadThreshold.lua")
dofile("scripts/SettingsUI.lua")
local logic, settings = AIUnloadThresholdLogic, AIUnloadThresholdSettings
local function unit(level, capacity)
    return {fillLevel = level, freeCapacity = capacity - level}
end
for _, case in ipairs({{0, false}, {7599, false}, {7600, true}, {7920, true}, {8000, true}}) do
    check("8000 L at " .. case[1], function()
        equal(logic.calculate({unit(case[1], 8000)}, 95), case[2])
    end)
end
check("weighted capacity, not average percentage", function()
    equal(logic.calculate({unit(1000, 1000), unit(7000, 9000)}, 90), false)
    equal(logic.calculate({unit(1000, 1000), unit(8500, 9000)}, 95), true)
    equal(logic.calculate({unit(1000, 1000), unit(8499, 9000)}, 95), false)
end)
check("empty, zero, missing, nonfinite and negative data", function()
    equal(logic.calculate({unit(0, 8000)}, 80), false)
    for _, units in ipairs({{}, {unit(0, 0)}, {{fillLevel = 1}}, {{fillLevel = 1, freeCapacity = -1}},
        {{fillLevel = 0/0, freeCapacity = 100}}, {{fillLevel = 1, freeCapacity = math.huge}}}) do
        equal(logic.calculate(units, 95), nil)
    end
    equal(logic.calculate({unit(8000, 8000)}, 100), nil)
end)
check("roundoff tolerance does not swallow one liter", function()
    equal(logic.calculate({unit(7600 - 1e-9, 8000)}, 95), true)
    equal(logic.calculate({unit(7599, 8000)}, 95), false)
end)
check("50 percent boundary and all new lower thresholds", function()
    equal(logic.calculate({unit(0, 8000)}, 50), false)
    equal(logic.calculate({unit(3999, 8000)}, 50), false)
    equal(logic.calculate({unit(4000, 8000)}, 50), true)
    equal(logic.calculate({unit(4799, 8000)}, 60), false)
    equal(logic.calculate({unit(4800, 8000)}, 60), true)
    equal(logic.calculate({unit(5600, 8000)}, 70), true)
    equal(logic.calculate({unit(6000, 8000)}, 75), true)
end)

g_currentMission = {missionDynamicInfo = {isMultiplayer = false}}
g_time = 1000
FillType = {UNKNOWN = 0}
AIJobDeliver = {}
Utils = {prependedFunction = function(original, prepended)
    return function(...)
        prepended(...)
        return original(...)
    end
end, appendedFunction = function(original, appended)
    return function(...)
        original(...)
        appended(...)
    end
end}
local vanillaCalls, errors = 0, 0
AITaskWaitForFilling = {
start = function(task) task.isFullyLoaded = false; task.isFinished = false end,
stop = function() end,
reset = function(task) task.isFullyLoaded = false; task.isFinished = false; task.waitTime = 0 end,
update = function(task)
    vanillaCalls = vanillaCalls + 1
    if not task.isServer then return end
    if task.isFullyLoaded then
        if g_time > task.waitTime then task.isFinished = true end
        return
    end
    local valid, full = false, true
    for _, info in ipairs(task.fillUnitInfo) do
        local vehicle, index = info.vehicle, info.fillUnitIndex
        local level = vehicle:getFillUnitFillLevel(index)
        valid = valid or level == 0 or (level > 0 and task.fillTypes[vehicle:getFillUnitFillType(index)])
        full = full and vehicle:getFillUnitFreeCapacity(index) <= 0
    end
    if not valid then errors = errors + 1; return end
    if full then task.isFullyLoaded = true; task.waitTime = g_time + task.waitDuration end
end}
local function taskWith(level, capacity, fillType)
    local vehicle = {level = level, capacity = capacity, fillType = fillType or 1}
    function vehicle:getFillUnitFillLevel() return self.level end
    function vehicle:getFillUnitFillType() return self.fillType end
    function vehicle:getFillUnitFreeCapacity() return self.capacity - self.level end
    local task = {isServer = true, isFullyLoaded = false, isFinished = false,
        waitTime = 0, waitDuration = 3000, fillTypes = {[1] = true},
        fillUnitInfo = {{vehicle = vehicle, fillUnitIndex = 1}}}
    task.job = {waitForFillingTask = task, isa = function(_, class) return class == AIJobDeliver end}
    return task, vehicle
end
check("install once", function()
    logic.install()
    local installed = AITaskWaitForFilling.update
    logic.install()
    equal(AITaskWaitForFilling.update, installed)
end)
check("threshold, exact vanilla delay, no duplicate transition", function()
    local task = taskWith(7600, 8000)
    settings.threshold = 95; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    equal(task.isFullyLoaded, true); equal(task.waitTime, 4000); equal(task.isFinished, false)
    g_time = 4000; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, false)
    g_time = 4001; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, true)
    equal(task.waitTime, 4000)
end)
check("switching to 100 percent preserves an already started countdown", function()
    local task, vehicle = taskWith(7600, 8000)
    settings.threshold = 95; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    vehicle.level = 100; settings.threshold = 100; g_time = 4001
    AITaskWaitForFilling.update(task, 16); equal(task.isFinished, true)
end)
check("continuous incoming grain postpones departure beyond the old deadline", function()
    local task, vehicle = taskWith(4000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    for time = 2000, 7000, 1000 do
        g_time = time; vehicle.level = vehicle.level + 100
        AITaskWaitForFilling.update(task, 16)
        equal(task.isFinished, false); equal(task.waitTime, time + 3000)
    end
    g_time = 10000; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, false)
    g_time = 10001; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, true)
end)
check("loading resumed during a brief pause resets the countdown", function()
    local task, vehicle = taskWith(4000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    g_time = 3500; AITaskWaitForFilling.update(task, 16); equal(task.waitTime, 4000)
    vehicle.level = 4100; g_time = 4001
    AITaskWaitForFilling.update(task, 16)
    equal(task.isFinished, false); equal(task.waitTime, 7001)
end)
check("falling below the threshold cancels only the mod countdown", function()
    local task, vehicle = taskWith(4000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    vehicle.level = 3999; g_time = 4001
    AITaskWaitForFilling.update(task, 16)
    equal(task.isFullyLoaded, false); equal(task.isFinished, false)
    equal(task.aiUnloadThresholdLoadingWatch, nil)
    vehicle.level = 4000; g_time = 5000
    AITaskWaitForFilling.update(task, 16); equal(task.waitTime, 8000)
end)
check("raising the threshold during a provisional countdown keeps waiting", function()
    local task = taskWith(4000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    settings.threshold = 95; g_time = 4001
    AITaskWaitForFilling.update(task, 16)
    equal(task.isFullyLoaded, false); equal(task.isFinished, false)
end)
check("invalid cargo during the countdown returns to vanilla validation", function()
    local task, vehicle = taskWith(4000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    vehicle.fillType = 2; g_time = 4001
    local before = errors
    AITaskWaitForFilling.update(task, 16)
    equal(errors, before + 1); equal(task.isFinished, false)
end)
check("inflow in one unit is detected even if total cargo does not increase", function()
    local task, first = taskWith(3000, 4000)
    local other, second = taskWith(2000, 4000)
    table.insert(task.fillUnitInfo, other.fillUnitInfo[1])
    settings.threshold = 60; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    first.level = 3100; second.level = 1900; g_time = 4001
    AITaskWaitForFilling.update(task, 16)
    equal(task.isFinished, false); equal(task.waitTime, 7001)
end)
check("native full loading countdown and lifecycle remain intact", function()
    local task = taskWith(8000, 8000)
    settings.threshold = 50; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    equal(task.aiUnloadThresholdLoadingWatch, nil)
    g_time = 4001; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, true)
    for _, method in ipairs({"start", "stop", "reset"}) do
        task.aiUnloadThresholdLoadingWatch = {}
        AITaskWaitForFilling[method](task)
        equal(task.aiUnloadThresholdLoadingWatch, nil)
    end
end)
check("95 to 90 takes effect on next check", function()
    local task = taskWith(7200, 8000)
    settings.threshold = 95; g_time = 1000
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, false)
    settings.threshold = 90
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, true)
end)
check("100 percent delegates without trailer reads from mod", function()
    settings.threshold = 100
    local task = taskWith(7920, 8000)
    task.aiUnloadThresholdLoadingWatch = {deadline = 123, units = {}}
    local saved = logic.readUnits
    logic.readUnits = function() error("mod must not inspect trailers") end
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, false)
    task.fillUnitInfo[1].vehicle.level = 8000
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, true)
    logic.readUnits = saved
end)
check("loop reentry resets vanilla latch and waits for new cargo", function()
    local task, vehicle = taskWith(7920, 8000)
    settings.threshold = 95; g_time = 1000
    AITaskWaitForFilling.update(task, 16)
    g_time = 4001; AITaskWaitForFilling.update(task, 16); equal(task.isFinished, true)
    task.isFullyLoaded = false; task.isFinished = false; vehicle.level = 0
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, false)
    vehicle.level = 7600
    AITaskWaitForFilling.update(task, 16); equal(task.waitTime, 7001)
end)
check("invalid cargo keeps vanilla error path", function()
    local task = taskWith(7920, 8000, 2)
    local before = errors
    AITaskWaitForFilling.update(task, 16)
    equal(errors, before + 1); equal(task.isFullyLoaded, false)
end)
check("mixed invalid cargo and empty units cannot force departure", function()
    local task = taskWith(7920, 8000, 2)
    local other = taskWith(0, 1)
    table.insert(task.fillUnitInfo, other.fillUnitInfo[1])
    AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, false)
end)
check("duplicate discharge nodes do not double count a fill unit", function()
    local task = taskWith(7600, 8000)
    table.insert(task.fillUnitInfo, task.fillUnitInfo[1])
    equal(#logic.readUnits(task), 1)
end)
check("other jobs, client and multiplayer are untouched", function()
    for _, mode in ipairs({"otherJob", "otherTask", "client", "multiplayer"}) do
        local task = taskWith(7920, 8000)
        if mode == "otherJob" then task.job.isa = function() return false end end
        if mode == "otherTask" then task.job.waitForFillingTask = {} end
        if mode == "client" then task.isServer = false end
        if mode == "multiplayer" then g_currentMission.missionDynamicInfo.isMultiplayer = true end
        AITaskWaitForFilling.update(task, 16); equal(task.isFullyLoaded, false)
        g_currentMission.missionDynamicInfo.isMultiplayer = false
    end
end)

check("fill snapshots and records are reused without changing the previous frame", function()
    local task, vehicle = taskWith(1000, 8000)
    local first = logic.readUnits(task)
    local record = first[1]
    vehicle.level = 2000
    local second = logic.readUnits(task)
    assert(first ~= second)
    equal(first[1].fillLevel, 1000)
    equal(second[1].fillLevel, 2000)
    for i = 1, 1000 do
        local current = logic.readUnits(task)
        equal(current, i % 2 == 1 and first or second)
    end
    equal(first[1], record)
    -- Both buffers must drop removed units, including their old capacity.
    task.fillUnitInfo = {}
    equal(#logic.readUnits(task), 0)
    equal(#logic.readUnits(task), 0)
    task.fillUnitInfo = {{vehicle = vehicle, fillUnitIndex = 1}}
    equal(logic.readUnits(task)[1], record)
end)
check("invalid task collections, entries and indexes are guarded", function()
    equal(logic.readUnits(nil), nil)
    equal(logic.readUnits({}), nil)
    local task = taskWith(1000, 8000)
    task.fillUnitInfo = {false}
    equal(logic.readUnits(task), nil)
    for _, index in ipairs({0, -1, 1.5, "1", 0/0}) do
        task.fillUnitInfo = {{vehicle = {}, fillUnitIndex = index}}
        equal(logic.readUnits(task), nil)
    end
end)
check("unexpected vehicle getter errors remain visible", function()
    local task, vehicle = taskWith(7920, 8000)
    vehicle.getFillUnitFreeCapacity = function() error("getter failure") end
    settings.threshold = 95
    local ok, message = pcall(logic.afterUpdate, task)
    equal(ok, false)
    assert(message:find("getter failure", 1, true))
end)

local stored, existing, corrupt, failedSave
g_modSettingsDirectory = "/profile/modSettings/"
getUserProfileAppPath = function() return "/profile/" end
fileExists = function() return existing end
createFolder = function() end
XMLFile = {
    load = function()
        if corrupt then return nil end
        return {getString = function() return stored end, delete = function() end}
    end,
    create = function()
        return {setInt = function(_, _, value) stored = value end,
            save = function() return not failedSave end, delete = function() end}
    end
}
check("default, persistence, exact allowed values and damaged XML", function()
    settings:load(); equal(settings.threshold, 95); equal(stored, 95)
    existing = true
    settings:setIndex(6); equal(stored, 85)
    settings.threshold = 95; settings:load(); equal(settings.threshold, 85)
    for _, value in ipairs({"94", "NaN", "95.5", "101", "garbage"}) do
        stored = value; settings:load(); equal(settings.threshold, 95)
    end
    corrupt = true; settings:load(); equal(settings.threshold, 95)
    corrupt = false; failedSave = true; equal(settings:save(), false)
end)
check("exact ten options persist with the unchanged 95 percent default", function()
    equal(table.concat(settings.VALUES, ","), "50,60,70,75,80,85,90,95,98,100")
    for index, value in ipairs(settings.VALUES) do
        equal(settings:isValid(value), true)
        stored = tostring(value); settings:load()
        equal(settings.threshold, value); equal(settings:getIndex(), index)
    end
    equal(settings:isValid(55), false); equal(settings:isValid(65), false)
    stored = "55"; settings:load(); equal(settings.threshold, 95)
    equal(settings:getIndex(), 8)
end)
check("malformed trailer data falls back without repeated warnings", function()
    local task, vehicle = taskWith(7920, 8000)
    vehicle.getFillUnitFreeCapacity = nil
    local warnings = 0
    local saved = Logging.warning
    Logging.warning = function() warnings = warnings + 1 end
    -- Invoke the extension directly: vanilla requires this API too.
    settings.threshold = 95
    logic.afterUpdate(task); logic.afterUpdate(task)
    equal(task.isFullyLoaded, false); equal(warnings, 1)
    Logging.warning = saved
end)

check("XML creation failure and invalid save inputs are guarded", function()
    local create = XMLFile.create
    XMLFile.create = function() return nil end
    equal(settings:save(), false)
    XMLFile.create = function() error("must not create XML for invalid inputs") end
    local directory, filename, threshold = settings.directory, settings.filename, settings.threshold
    settings.directory = nil; equal(settings:save(), false)
    settings.directory = directory; settings.filename = ""; equal(settings:save(), false)
    settings.filename = filename; settings.threshold = 55; equal(settings:save(), false)
    settings.threshold = threshold; XMLFile.create = create
end)

local focusId = 0
FocusManager = {
    currentFocusData = {idToElementMapping = {}},
    serveAutoFocusId = function() focusId = focusId + 1; return focusId end,
    loadElementFromCustomValues = function(self, element)
        local function register(node)
            self.currentFocusData.idToElementMapping[node.focusId] = node
            for _, child in ipairs(node.elements or {}) do register(child) end
        end
        register(element)
        return true
    end
}
-- Minimal GUI contract model: verifies construction and placement, not rendering.
local function element()
    return {
        elements = {},
        applyProfile = function(self, profile) self.profile = profile end,
        addElement = function(self, child)
            table.insert(self.elements, child); child.parent = self
        end,
        delete = function(self) self.deleted = true end,
        setText = function(self, text) self.text = text end
    }
end
GuiElement = {new = element}
BitmapElement = {new = function()
    local bitmap = element()
    bitmap.setImageColor = function(self, state, r, g, b, a)
        self.imageColor = {r, g, b, a}
    end
    return bitmap
end}
TextElement = {new = element}
OptionSliderElement = {new = function(target)
    local slider = element()
    slider.target = target
    slider.callbacks = {}
    slider.setCallback = function(self, key, value) self.callbacks[key] = value end
    slider.setTexts = function(self, values) self.texts = values end
    slider.setState = function(self, value) self.state = value end
    slider.setDisabled = function(self, value) self.disabled = value end
    slider.addDefaultElements = function(self) self.defaultsCreated = true end
    slider.setElementsByName = function(self)
        assert(self.defaultsCreated)
        self.sliderElement = {}
    end
    return slider
end}
g_i18n = {getText = function(_, key) return key end}
g_gui = {loadProfiles = function(self, filename) self.profilesLoaded = filename end}
AIUnloadThreshold = {modDirectory = "/mod/"}
local function makePage()
    local function layout()
        local result = element()
        result.invalidateLayout = function(self) self.invalidated = true end
        return result
    end
    local workersRow = element()
    workersRow:addElement({id = "multiHelperManure"})
    local gameLayout = layout()
    gameLayout:addElement(workersRow)
    return {name = "InGameMenuSettings", controlsList = {},
        generalSettingsLayout = layout(), gameSettingsLayout = gameLayout,
        updateAlternatingElements = function(self, targetLayout)
            self.stripedLayout = targetLayout
            self.stripeCalls = (self.stripeCalls or 0) + 1
        end}
end
local page
check("constructs native slider in Game Settings without an existing template", function()
    page = makePage(); settings.threshold = 95
    AIUnloadThresholdUI.onOpen(page); AIUnloadThresholdUI.onOpen(page)
    equal(#page.controlsList, 1); equal(#page.gameSettingsLayout.elements, 2)
    equal(#page.generalSettingsLayout.elements, 0)
    local row = page.aiUnloadThresholdRow
    local slider = row.aiUnloadThresholdOption
    equal(row.parent, page.gameSettingsLayout)
    equal(slider.profile, "aiut_settingsSlider")
    equal(slider.state, 8); equal(#slider.texts, 10); equal(slider.wrap, false)
    equal(table.concat(slider.texts, ","), "50%,60%,70%,75%,80%,85%,90%,95%,98%,aiut_vanilla")
    equal(slider.target.name, page.name); equal(slider.disabled, false)
    equal(slider.elements[1].text, "aiut_tooltip")
    equal(row.elements[2].text, "aiut_label")
    slider.target[slider.callbacks.onClickCallback](slider.target, 6)
    equal(settings.threshold, 85)
end)
check("menu refresh after map change and focus context reset", function()
    settings.threshold = 98
    FocusManager.currentFocusData = {idToElementMapping = {}}
    AIUnloadThresholdUI.onOpen(page)
    equal(page.aiUnloadThresholdRow.aiUnloadThresholdOption.state, 9)
    equal(FocusManager.currentFocusData.idToElementMapping[page.aiUnloadThresholdRow.focusId], page.aiUnloadThresholdRow)
    local second = makePage(); AIUnloadThresholdUI.onOpen(second)
    equal(#second.controlsList, 1); assert(second.aiUnloadThresholdRow ~= page.aiUnloadThresholdRow)
end)
check("settings rows support the vanilla recoloring contract on menu close", function()
    -- Regression for InGameMenuSettingsFrame.lua:481. A plain GuiElement
    -- does not implement this operation and aborts the menu event handler.
    for _, row in ipairs(page.controlsList) do
        row:setImageColor(nil, 0.1, 0.1, 0.1, 1)
        equal(row.imageColor[4], 1)
    end
end)
check("native row striping runs after insertion and on reopening", function()
    local striped = makePage()
    AIUnloadThresholdUI.onOpen(striped)
    equal(striped.stripedLayout, striped.gameSettingsLayout)
    equal(striped.stripeCalls, 1)
    AIUnloadThresholdUI.onOpen(striped)
    equal(striped.stripeCalls, 2)
    equal(#striped.gameSettingsLayout.elements, 2)
end)
check("stays under AI Workers before other mods regardless of insertion order", function()
    for _, addedBefore in ipairs({true, false}) do
        local target = makePage()
        local layout = target.gameSettingsLayout
        local workersRow = layout.elements[1]
        target.controlsList = {workersRow}
        local heading, transport, contractor = element(), element(), element()
        heading.id = "moveHusbandryAnimals_sectionHeader"
        local function addOtherMods()
            layout:addElement(heading)
            layout:addElement(transport)
            layout:addElement(contractor)
            table.insert(target.controlsList, transport)
            table.insert(target.controlsList, contractor)
        end
        if addedBefore then addOtherMods() end
        AIUnloadThresholdUI.onOpen(target)
        if not addedBefore then addOtherMods() end
        AIUnloadThresholdUI.onOpen(target)
        local row = target.aiUnloadThresholdRow
        equal(layout.elements[1], workersRow)
        equal(layout.elements[2], row)
        equal(layout.elements[3], heading)
        equal(layout.elements[4], transport)
        equal(layout.elements[5], contractor)
        equal(target.controlsList[2], row)
        equal(#layout.elements, 5)
        equal(#target.controlsList, 4)
        -- A later mod can reorder existing elements; reopening restores placement.
        table.remove(layout.elements, 2)
        table.insert(layout.elements, row)
        table.remove(target.controlsList, 2)
        table.insert(target.controlsList, row)
        AIUnloadThresholdUI.onOpen(target)
        equal(layout.elements[2], row)
        equal(target.controlsList[2], row)
    end
end)
check("missing AI Workers anchor never appends to another mod section", function()
    local target = makePage()
    target.gameSettingsLayout.elements[1].elements[1].id = "unrelatedModSetting"
    AIUnloadThresholdUI.onOpen(target)
    equal(target.aiUnloadThresholdRow, nil)
    equal(#target.gameSettingsLayout.elements, 1)
    equal(#target.controlsList, 0)
end)
check("multiplayer disables slider and ignores callbacks", function()
    g_currentMission.missionDynamicInfo.isMultiplayer = true
    AIUnloadThresholdUI.onOpen(page)
    equal(page.aiUnloadThresholdRow.aiUnloadThresholdOption.disabled, true)
    AIUnloadThresholdUI.onChanged({}, 1); equal(settings.threshold, 98)
    g_currentMission.missionDynamicInfo.isMultiplayer = false
end)
check("missing Game Settings never falls back to General Settings", function()
    local missing = makePage(); missing.gameSettingsLayout = nil
    AIUnloadThresholdUI.onOpen(missing)
    equal(#missing.controlsList, 0); equal(#missing.generalSettingsLayout.elements, 0)
end)
check("failed slider creation cleans up without adding a row", function()
    local broken = makePage()
    local saved = OptionSliderElement.new
    local detached
    OptionSliderElement.new = function(target)
        local slider = saved(target)
        detached = slider
        slider.setElementsByName = function() end
        return slider
    end
    AIUnloadThresholdUI.onOpen(broken)
    equal(#broken.controlsList, 0); equal(#broken.gameSettingsLayout.elements, 1)
    equal(broken.aiUnloadThresholdRow, nil)
    equal(detached.parent.deleted, true)
    OptionSliderElement.new = saved
end)
check("menu hook and profile loading are installed once", function()
    InGameMenuSettingsFrame = {onFrameOpen = function() end}
    AIUnloadThresholdUI.install()
    equal(g_gui.profilesLoaded, "/mod/gui/guiProfiles.xml")
    local original = InGameMenuSettingsFrame.onFrameOpen
    AIUnloadThresholdUI.install(); equal(InGameMenuSettingsFrame.onFrameOpen, original)
end)
print(string.format("All %d tests passed; vanilla update called %d times.", passed, vanillaCalls))
