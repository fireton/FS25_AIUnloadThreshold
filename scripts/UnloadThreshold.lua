AIUnloadThresholdLogic = {installed = false}

local function isFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Returns nil for unusable data, false below the threshold, and true at it.
-- Capacity is the currently available volume, including weight restrictions.
function AIUnloadThresholdLogic.calculate(units, threshold)
    if not isFinite(threshold) or threshold < 50 or threshold >= 100 or type(units) ~= "table" or #units == 0 then
        return nil
    end
    local totalLevel, totalCapacity = 0, 0
    for _, unit in ipairs(units) do
        local level, free = unit.fillLevel, unit.freeCapacity
        if not isFinite(level) or not isFinite(free) or level < 0 or free < 0 then
            return nil
        end
        local capacity = level + free
        if not isFinite(capacity) or capacity <= 0 then
            return nil
        end
        totalLevel = totalLevel + level
        totalCapacity = totalCapacity + capacity
    end
    if not isFinite(totalLevel) or not isFinite(totalCapacity) then
        return nil
    end
    -- Tolerance only covers floating-point roundoff, far below one liter.
    return totalLevel > 0 and totalLevel + totalCapacity * 1e-10 >= totalCapacity * threshold / 100
end

function AIUnloadThresholdLogic.isSinglePlayer(mission)
    return mission ~= nil and mission.missionDynamicInfo ~= nil
        and mission.missionDynamicInfo.isMultiplayer == false
end

function AIUnloadThresholdLogic.readUnits(task)
    if type(task.fillUnitInfo) ~= "table" or type(task.fillTypes) ~= "table" then
        return nil, "Missing fill unit collection or allowed fill types"
    end
    local units, seen = {}, {}
    for _, info in ipairs(task.fillUnitInfo) do
        local vehicle, index = info.vehicle, info.fillUnitIndex
        if vehicle == nil or index == nil or type(vehicle.getFillUnitFillType) ~= "function"
            or type(vehicle.getFillUnitFillLevel) ~= "function" or type(vehicle.getFillUnitFreeCapacity) ~= "function" then
            return nil, "Missing fill unit API"
        end
        seen[vehicle] = seen[vehicle] or {}
        if not seen[vehicle][index] then
            seen[vehicle][index] = true
            local level = vehicle:getFillUnitFillLevel(index)
            local fillType = vehicle:getFillUnitFillType(index)
            if not isFinite(level) then
                return nil, "Invalid fill level"
            end
            -- An empty unit still contributes capacity. Every nonempty unit
            -- must be deliverable; mixed invalid cargo must not trigger early departure.
            if level > 0 and (fillType == nil or (FillType ~= nil and fillType == FillType.UNKNOWN)
                or not task.fillTypes[fillType]) then
                return nil
            end
            table.insert(units, {vehicle = vehicle, fillUnitIndex = index,
                fillLevel = level, freeCapacity = vehicle:getFillUnitFreeCapacity(index)})
        end
    end
    return units
end

local function isDeliverWait(task)
    local job = task.job
    return job ~= nil and type(job.isa) == "function" and job:isa(AIJobDeliver)
        and job.waitForFillingTask == task
end

function AIUnloadThresholdLogic.clearLoadingWatch(task)
    task.aiUnloadThresholdLoadingWatch = nil
end

-- Run before vanilla can finish an elapsed timer. Only a countdown started by
-- this mod may be extended or cancelled; vanilla full-load waits are untouched.
function AIUnloadThresholdLogic.beforeUpdate(task)
    local watch = task.aiUnloadThresholdLoadingWatch
    local threshold = AIUnloadThresholdSettings.threshold
    if watch == nil or threshold == 100 or not task.isServer
        or not AIUnloadThresholdLogic.isSinglePlayer(g_currentMission) or not isDeliverWait(task) then
        return
    end
    if task.isFullyLoaded ~= true or task.isFinished ~= false or task.waitTime ~= watch.deadline then
        AIUnloadThresholdLogic.clearLoadingWatch(task)
        return
    end
    local ok, units = pcall(AIUnloadThresholdLogic.readUnits, task)
    local reached = ok and units ~= nil and AIUnloadThresholdLogic.calculate(units, threshold)
    if not reached then
        -- The new requirement makes this countdown provisional: a load below
        -- the threshold or invalid cargo returns to normal vanilla validation.
        task.isFullyLoaded = false
        task.waitTime = 0
        AIUnloadThresholdLogic.clearLoadingWatch(task)
        return
    end
    local flowing = false
    for _, current in ipairs(units) do
        local previous
        for _, old in ipairs(watch.units) do
            if old.vehicle == current.vehicle and old.fillUnitIndex == current.fillUnitIndex then
                previous = old
                break
            end
        end
        -- Track each unit separately: loading one trailer while unloading
        -- another must not hide incoming grain behind a constant total.
        if previous == nil or current.fillLevel > previous.fillLevel then flowing = true end
    end
    watch.units = units
    if flowing then
        watch.deadline = g_time + task.waitDuration
        task.waitTime = watch.deadline
    end
end

function AIUnloadThresholdLogic.afterUpdate(task)
    local threshold = AIUnloadThresholdSettings.threshold
    if threshold == 100 or not task.isServer or not AIUnloadThresholdLogic.isSinglePlayer(g_currentMission)
        or task.isFullyLoaded ~= false or task.isFinished ~= false then
        return
    end
    if not isDeliverWait(task) then return end
    if not isFinite(task.waitDuration) or task.waitDuration < 0 or not isFinite(g_time) then
        AIUnloadThresholdLogic.warnOnce(task, "Unsupported wait timer API")
        return
    end
    local ok, units, reason = pcall(AIUnloadThresholdLogic.readUnits, task)
    if not ok then
        AIUnloadThresholdLogic.warnOnce(task, "Could not read trailer data; using vanilla behavior")
        return
    end
    if units == nil then
        if reason ~= nil then
            AIUnloadThresholdLogic.warnOnce(task, reason)
        end
        return
    end
    local reached = AIUnloadThresholdLogic.calculate(units, threshold)
    if reached == nil then
        AIUnloadThresholdLogic.warnOnce(task, "Invalid trailer capacity; using vanilla behavior")
    elseif reached then
        -- Vanilla owns completion. Our pre-update guard extends only this
        -- countdown while grain is still arriving.
        task.isFullyLoaded = true
        task.waitTime = g_time + task.waitDuration
        task.aiUnloadThresholdLoadingWatch = {units = units, deadline = task.waitTime}
    end
end

function AIUnloadThresholdLogic.warnOnce(task, message)
    if not task.aiUnloadThresholdWarning then
        task.aiUnloadThresholdWarning = true
        Logging.warning("[AIUnloadThreshold] %s.", message)
    end
end

function AIUnloadThresholdLogic.install()
    if AIUnloadThresholdLogic.installed then
        return true
    end
    if AITaskWaitForFilling == nil or AIJobDeliver == nil or Utils == nil
        or type(AITaskWaitForFilling.update) ~= "function" or type(Utils.appendedFunction) ~= "function"
        or type(Utils.prependedFunction) ~= "function" then
        Logging.warning("[AIUnloadThreshold] Deliver wait API unavailable; leaving vanilla behavior unchanged.")
        return false
    end
    -- Append after vanilla validation. No vehicle getters or global AI methods are replaced.
    AITaskWaitForFilling.update = Utils.appendedFunction(AITaskWaitForFilling.update, AIUnloadThresholdLogic.afterUpdate)
    AITaskWaitForFilling.update = Utils.prependedFunction(AITaskWaitForFilling.update, AIUnloadThresholdLogic.beforeUpdate)
    for _, name in ipairs({"start", "stop", "reset"}) do
        if type(AITaskWaitForFilling[name]) == "function" then
            AITaskWaitForFilling[name] = Utils.appendedFunction(AITaskWaitForFilling[name], AIUnloadThresholdLogic.clearLoadingWatch)
        end
    end
    AIUnloadThresholdLogic.installed = true
    return true
end
