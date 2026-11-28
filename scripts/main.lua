AIUnloadThreshold = {modDirectory = g_currentModDirectory}

function AIUnloadThreshold:loadMap()
    AIUnloadThresholdSettings:load()
    AIUnloadThresholdLogic.install()
    AIUnloadThresholdUI.install()
    Logging.info("[AIUnloadThreshold] Loaded v1.0.0.10; threshold=%d%%; single-player only.", AIUnloadThresholdSettings.threshold)
end

addModEventListener(AIUnloadThreshold)
