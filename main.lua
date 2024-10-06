-- Import modules
local menu = require("menu")
local menu_renderer = require("graphics.menu_renderer")
local revive = require("data.revive")
local explorer = require("data.explorer")
local automindcage = require("data.automindcage")
local actors = require("data.actors")
local waypoint_loader = require("functions.waypoint_loader")
local interactive_patterns = require("enums.interactive_patterns")
local Movement = require("functions.movement")
local ChestsInteractor = require("functions.chests_interactor")
local teleport = require("data.teleport")
local GameStateChecker = require("functions.game_state_checker")
local maidenmain = require("data.maidenmain")

-- Initialize variables
local PluginState = {
    IDLE = "idle",
    HELLTIDE = "helltide",
    TELEPORTING = "teleporting",
    FARMING = "farming",
    ERROR = "error"
}

local current_state = PluginState.IDLE
local plugin_enabled = false
local maidenmain_enabled = false
local was_in_helltide = false
local helltide_start_time = 0
local last_cleanup_time = get_time_since_inject()
local cleanup_interval = 300 -- 5 minutes

local function periodic_cleanup()
    local current_time = get_time_since_inject()
    if current_time - last_cleanup_time > cleanup_interval then
        collectgarbage("collect")
        ChestsInteractor.clearInteractedObjects()
        waypoint_loader.clear_cached_waypoints()
        last_cleanup_time = current_time
        console.print("Periodic cleanup performed")
    end
end

local function load_and_set_waypoints(is_maiden)
    local waypoints, _ = waypoint_loader.load_route(nil, is_maiden)
    if waypoints then
        local randomized_waypoints = {}
        for _, wp in ipairs(waypoints) do
            table.insert(randomized_waypoints, waypoint_loader.randomize_waypoint(wp))
        end
        Movement.set_waypoints(randomized_waypoints)
        Movement.set_moving(true)
        console.print("Waypoints loaded and movement activated.")
        return true
    else
        console.print("Failed to load waypoints. Check waypoint files.")
        current_state = PluginState.ERROR
        return false
    end
end

local function set_plugin_state(maiden_active, chest_active)
    maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:set(maiden_active)
    menu.plugin_enabled:set(chest_active)
    maidenmain_enabled = maiden_active
    plugin_enabled = chest_active
    console.print("Plugin states updated: Maiden = " .. tostring(maiden_active) .. ", Chest = " .. tostring(chest_active))
end

local function start_maiden_farming()
    console.print("Starting Maiden farming")
    set_plugin_state(true, false)
    maidenmain.reset_helltide_state()
    if load_and_set_waypoints(true) then
        Movement.set_moving(true)
        current_state = PluginState.FARMING
        helltide_start_time = get_time_since_inject()
    else
        console.print("Failed to load waypoints for Maiden.")
        current_state = PluginState.ERROR
    end
end

local function start_chest_farming()
    console.print("Starting Chest farming")
    set_plugin_state(false, true)
    if load_and_set_waypoints(false) then
        Movement.set_moving(true)
        current_state = PluginState.FARMING
    else
        console.print("Failed to load waypoints for Chest farming.")
        current_state = PluginState.ERROR
    end
end

local function stop_all_farming()
    set_plugin_state(false, false)
    Movement.set_moving(false)
    current_state = PluginState.IDLE
    console.print("All farming stopped.")
end

local function update_menu_states()
    local new_plugin_enabled = menu.plugin_enabled:get()
    local new_maidenmain_enabled = maidenmain.menu_elements.main_helltide_maiden_auto_plugin_enabled:get()

    if new_maidenmain_enabled ~= maidenmain_enabled or new_plugin_enabled ~= plugin_enabled then
        if new_maidenmain_enabled and new_plugin_enabled then
            console.print("Both plugins are enabled. Correcting...")
            if GameStateChecker.check_game_state() == "helltide" then
                start_maiden_farming()
            else
                start_chest_farming()
            end
        elseif new_maidenmain_enabled then
            start_maiden_farming()
        elseif new_plugin_enabled then
            start_chest_farming()
        else
            stop_all_farming()
        end
    end

    if type(maidenmain.update_menu_states) == "function" then
        maidenmain.update_menu_states()
    else
        console.print("Error: maidenmain.update_menu_states function not found")
    end
end

local function handle_helltide()
    local current_time = get_time_since_inject()
    
    if not was_in_helltide then
        console.print("Entered Helltide. Initializing Helltide operations.")
        was_in_helltide = true
        Movement.reset(maidenmain_enabled)
        load_and_set_waypoints(maidenmain_enabled)
        ChestsInteractor.clearInteractedObjects()
        ChestsInteractor.clearBlacklist()
        helltide_start_time = current_time
    end

    if maidenmain_enabled then
        local duration = maidenmain.menu_elements.main_helltide_maiden_duration:get() * 60
        if current_time - helltide_start_time > duration then
            console.print("Maiden time expired. Starting transition to chest farming.")
            local result = maidenmain.switch_to_chest_farming(ChestsInteractor, Movement)
            if result == "teleport_success" then
                start_chest_farming()
            elseif result == "waiting" or result == "in_progress" then
                console.print("Transition to chest farming in progress...")
            else
                console.print("Failed to transition to chest farming. Result: " .. tostring(result))
                -- Don't stop farming in case of failure, continue with current state
            end
        else
            local local_player = get_local_player()
            local current_position = local_player:get_position()
            maidenmain.update(menu, current_position, ChestsInteractor, Movement, maidenmain.menu_elements.main_helltide_maiden_auto_plugin_explorer_circle_radius:get())
        end
    else
        ChestsInteractor.interactWithObjects(menu.main_openDoors_enabled:get(), interactive_patterns)
        actors.update()
    end

    Movement.pulse(plugin_enabled or maidenmain_enabled, menu.loop_enabled:get(), teleport, maidenmain_enabled)
    
    if menu.revive_enabled:get() then
        revive.check_and_revive()
    end

    if menu.profane_mindcage_toggle:get() then
        automindcage.update()
    end
end

local function handle_non_helltide()
    if was_in_helltide then
        console.print("Helltide ended. Performing cleanup.")
        Movement.reset(false)
        ChestsInteractor.clearInteractedObjects()
        ChestsInteractor.clearBlacklist()
        was_in_helltide = false
        teleport.reset()
        if maidenmain_enabled then
            maidenmain.clearBlacklist()
            set_plugin_state(false, false)
            console.print("Maiden plugin deactivated after Helltide end.")
        end
        explorer.disable()
        maidenmain.reset_helltide_state()
        helltide_start_time = 0
    end

    if current_state ~= PluginState.TELEPORTING then
        current_state = PluginState.TELEPORTING
        local teleport_result = teleport.tp_to_next(ChestsInteractor, Movement)
        if teleport_result then
            console.print("Teleport successful. Loading new waypoints...")
            if load_and_set_waypoints(false) then
                current_state = PluginState.FARMING
                set_plugin_state(false, true)
                Movement.set_moving(true)
            else
                console.print("Failed to load waypoints after teleport.")
                current_state = PluginState.ERROR
            end
        else
            local teleport_info = teleport.get_teleport_info()
            console.print("Teleport in progress. Current state: " .. teleport_info.state)
            if teleport_info.next_teleport and teleport_info.next_teleport > 0 then
                console.print("Next teleport in: " .. teleport_info.next_teleport .. " seconds")
            end
        end
    end
end

on_update(function()
    update_menu_states()

    if not plugin_enabled and not maidenmain_enabled then
        current_state = PluginState.IDLE
        return
    end

    periodic_cleanup()

    local game_state = GameStateChecker.check_game_state()
    console.print("Current game state: " .. game_state)
    console.print("Current plugin state: " .. current_state)
    console.print("Maiden enabled: " .. tostring(maidenmain_enabled) .. ", Chest enabled: " .. tostring(plugin_enabled))

    if game_state == "loading_or_limbo" then
        console.print("Loading or in Limbo. Pausing operations.")
        current_state = PluginState.IDLE
        return
    end

    if game_state == "no_player" then
        console.print("No player detected. Waiting for player.")
        current_state = PluginState.IDLE
        return
    end

    if game_state == "helltide" then
        current_state = PluginState.HELLTIDE
        handle_helltide()
    else
        handle_non_helltide()
    end

    if current_state == PluginState.FARMING and Movement.is_idle() then
        console.print("Farming state, but movement is idle. Activating movement...")
        Movement.set_moving(true)
    end
end)

on_render_menu(function()
    menu_renderer.render_menu(plugin_enabled, menu.main_openDoors_enabled:get(), menu.loop_enabled:get(), 
                              menu.revive_enabled:get(), menu.profane_mindcage_toggle:get(), menu.profane_mindcage_slider:get())
end)

on_render(function()
    if maidenmain_enabled and type(maidenmain.render) == "function" then
        maidenmain.render()
    end
end)

maidenmain.init()
console.print(">>Helltide Chests Farmer Eletroluz V1.5 with Maidenmain integration and auto rotation<<")
console.print("Initial plugin state: " .. current_state)