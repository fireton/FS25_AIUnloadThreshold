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

    local xml = XMLFile.load("AIUnloadThresholdSettings", self.filename)
    local value
    if xml ~= nil then
        value = tonumber(xml:getString("aiUnloadThreshold.settings#threshold"))
        xml:delete()
    end
    if self:isValid(value) then
        self.threshold = value
    else
        Logging.warning("[AIUnloadThreshold] Invalid settings XML or threshold; using 95%%.")
    end
end

function AIUnloadThresholdSettings:save()
    if type(self.filename) ~= "string" or self.filename == ""
        or type(self.directory) ~= "string" or self.directory == "" or not self:isValid(self.threshold) then
        return false
    end
    createFolder(self.directory)
    local xml = XMLFile.create("AIUnloadThresholdSettings", self.filename, "aiUnloadThreshold")
    if xml == nil then
        Logging.warning("[AIUnloadThreshold] Could not create settings XML at %s.", self.filename)
        return false
    end
    xml:setInt("aiUnloadThreshold.settings#threshold", self.threshold)
    -- The engine owns XML serialization and file replacement.
    local saved = xml:save() ~= false
    xml:delete()
    if not saved then
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
