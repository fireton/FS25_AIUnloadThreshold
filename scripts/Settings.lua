AIUnloadThresholdSettings = {
    VALUES = {50, 60, 70, 75, 80, 85, 90, 95, 98, 100},
    DEFAULT = 95,
    threshold = 95
}

function AIUnloadThresholdSettings:isValid(value)
    for _, candidate in ipairs(self.VALUES) do
        if value == candidate then
            return true
        end
    end
    return false
end

function AIUnloadThresholdSettings:getIndex()
    for index, value in ipairs(self.VALUES) do
        if value == self.threshold then
            return index
        end
    end
    for index, value in ipairs(self.VALUES) do
        if value == self.DEFAULT then return index end
    end
    return 1
end

function AIUnloadThresholdSettings:load()
    self.threshold = self.DEFAULT
    local directory = g_modSettingsDirectory
    if type(directory) ~= "string" or directory == "" then
        directory = getUserProfileAppPath() .. "modSettings/"
    end
    self.directory = directory:gsub("/*$", "/") .. "FS25_AIUnloadThreshold/"
    self.filename = self.directory .. "settings.xml"

    if not fileExists(self.filename) then
        self:save()
        return
    end

    local xml
    local ok, value = pcall(function()
        xml = XMLFile.load("AIUnloadThresholdSettings", self.filename)
        if xml == nil then
            return nil
        end
        return tonumber(xml:getString("aiUnloadThreshold.settings#threshold"))
    end)
    if xml ~= nil then
        xml:delete()
    end
    if ok and self:isValid(value) then
        self.threshold = value
    else
        Logging.warning("[AIUnloadThreshold] Invalid settings XML or threshold; using 95%%.")
    end
end

function AIUnloadThresholdSettings:save()
    if self.filename == nil then
        return false
    end
    local xml
    local ok, saved = pcall(function()
        createFolder(self.directory)
        xml = XMLFile.create("AIUnloadThresholdSettings", self.filename, "aiUnloadThreshold")
        if xml == nil then
            return false
        end
        xml:setInt("aiUnloadThreshold.settings#threshold", self.threshold)
        -- The engine owns XML serialization and file replacement.
        return xml:save() ~= false
    end)
    if xml ~= nil then
        xml:delete()
    end
    if not ok or not saved then
        Logging.warning("[AIUnloadThreshold] Could not save settings to %s.", self.filename)
        return false
    end
    return true
end

function AIUnloadThresholdSettings:setIndex(index)
    local value = self.VALUES[index]
    if value == nil or value == self.threshold then
        return
    end
    self.threshold = value
    self:save()
end
