# FS25 AI Unload Threshold

A mod for FS25 single-player on macOS. The built-in **Deliver** worker departs to unload once the selected fill level is reached and loading has stopped. The default threshold is **95%**.

## Installation and configuration

1. Copy `FS25_AIUnloadThreshold.zip` to `~/Library/Application Support/FarmingSimulator2025/mods/`.
2. Enable **AI Unload Threshold** in the mod list when starting a map.
3. Open **Game Settings** in the pause menu. **AI unloading threshold** is in **AI Workers**, immediately after **AI Worker Refill - Manure**.
4. Move the built-in slider with the mouse or keyboard arrow keys: **50%, 60%, 70%, 75%, 80%, 85%, 90%, 95%, 98%, 100% (Vanilla)**. The positions correspond to ten discrete options, rather than a linear percentage scale.

The setting takes effect on the next update of the waiting task. Your selection is saved immediately to `modSettings/FS25_AIUnloadThreshold/settings.xml` in the game's user data folder and applies to all maps. A missing or corrupted XML file, or a value outside the supported list, falls back to 95%. If saving fails, the selected value remains active until you exit the game, and a warning is written to the log.

## Behavior

Only the built-in `AITaskWaitForFilling` task belonging to `AIJobDeliver` is supported. The mod does not change **Load and Deliver**, fieldwork, regular driving, or routes. AutoDrive and Courseplay are not required.

The calculation is `sum(fillLevel) / sum(fillLevel + freeCapacity)`, using the current task's `fillUnitInfo`. Fill units of different sizes are weighted accordingly; empty participating fill units are included in the denominator. Duplicate references to the same fill unit are counted only once. The available capacity reported by the API is used, including weight limits. If the data is invalid, the mod does not trigger an early departure.

For example, 7,600 L in an available capacity of 8,000 L reaches 95%, while 7,599 L does not. A positive load is required. Every nonempty compartment must contain a known fill type from the game's built-in collection of allowed fill types; the mod does not bypass the game's built-in error checks.

At a threshold below 100%, reaching the threshold starts the game's built-in waiting countdown. As long as the fill level of at least one participating compartment is increasing, the mod postpones departure: the trailer leaves after approximately **three seconds without receiving any load**. A brief pause followed by resumed loading resets the countdown. If the load drops below the threshold before departure, or a higher threshold is selected, the task continues waiting.

Fill-unit snapshots use two reusable buffers per task; repeated reads reuse both the arrays and their unit records. Incoming load is checked before the built-in `update`, so loading that resumes just as the timer expires does not cause a departure. This check applies only to a countdown started by the mod. Stage completion, `aiPrepareLoading`, `aiFinishLoading`, unloading, and repeat trips remain under the game's control. A completely full trailer uses the built-in logic: there is no room for any more grain.

Loading is detected by an actual increase in fill level, separately for each compartment. A pipe positioned over the trailer does not by itself prevent departure; a pause of more than three seconds without incoming grain is treated as the end of loading. This also works without a special flag on the load source.

At **100% (Vanilla)**, the mod does not read fill units or modify AI fields: the game's original method runs. Any delay already in progress is preserved.

## Compatibility and API

The installed version is FS25 **1.25.1.0**, with `ModDesc Version: 116`. The descriptor is validated against the XSD from the installed game. The AI and menu Lua code is packaged in `dataS.gar`; the installed version's source code is not available as ordinary files. The public GIANTS documentation describes **Script v1.20.0.0**, so compatibility with the internal behavior of 1.25 requires in-game testing; its status is recorded in `TEST_REPORT.md`.

The UI creates a separate `OptionSliderElement` using the `fs25_optionSlider` styling from the installed SDK. The row container is a `BitmapElement`, which supports the game's built-in row coloring during navigation and when the menu is closed. The row is added to `InGameMenuSettingsFrame.gameSettingsLayout`, i.e. Game Settings, without searching for an existing slider or modifying General Settings. The mod's profiles are in `gui/guiProfiles.xml`. Missing UI classes or methods are detected during installation. If a constructor returns nil or the native slider child is missing, a warning is logged and the detached row is removed when present. Unexpected engine errors remain visible in the log. The core logic continues to work with the saved value or 95%.

Hooks are installed once; the row is stored on the page instance and is not created again. The description and UI text are localized in English and German through the standard `l10n` mechanism in `modDesc.xml`. Multiplayer is not declared as supported; the setting is unavailable and the logic is not applied in multiplayer. Support for custom trailers is best effort.

Official sources: [waiting for loading](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=81&class=849&version=script), [Deliver](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=54&class=537&version=script), [built-in slider](https://gdn.giants-software.com/documentation_scripting_fs25.php?category=43&class=473&version=script).

## Diagnostics and removal

Log: `~/Library/Application Support/FarmingSimulator2025/log.txt`. Search for `[AIUnloadThreshold]` to find the current threshold, slider creation, and compatibility warnings. Invalid trailer data is logged once per task object, rather than every frame. When reporting a problem, include the game version, vehicle name, and relevant log excerpt.

To remove the mod, exit the game and remove the ZIP from `mods`. Optionally, delete only the `modSettings/FS25_AIUnloadThreshold/` folder. The mod does not modify savegames or game installation files.

## Build and local tests

```sh
./build.sh
lua tests/run.lua
```

Building requires Python 3; tests require Lua 5.4. The ZIP is created at `release/FS25_AIUnloadThreshold.zip`, with `modDesc.xml` directly at the archive root. The `release` folder is created automatically if needed. The ZIP contains only the descriptor, Lua scripts, profile XML, and DDS icon. The README, reports, tests, screenshots, and build tools remain in the project. Local tests do not verify actual in-game trips.

The mod icon is `icon_aiUnloadThreshold.dds`: 512×512, BC3/DXT5 with transparency, without mipmaps. The project also retains `icon.png` for previews and the vector source `assets/icon.svg`. The build script reads the name of the ready-made icon from `modDesc.xml`; no format conversion is performed during the build.
