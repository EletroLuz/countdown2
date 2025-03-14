local circular_movement = {}

-- Variáveis locais relacionadas ao movimento circular
local run_explorer = 0
local explorer_points = nil
local explorer_point = nil
local explorer_go_next = 1
local explorer_threshold = 1.5
local explorer_thresholdvar = 3.0
local last_explorer_threshold_check = 0
local explorer_circle_radius_prev = 0

-- Nova variável para controlar o movimento
local movement_paused = false

-- Função auxiliar para obter posições em um raio
local function get_positions_in_radius(center_point, radius)
    local positions = {}
    local radius_squared = radius * radius
    for x = -radius, radius do
        for y = -radius, radius do
            if x*x + y*y <= radius_squared then
                table.insert(positions, vec3:new(center_point:x() + x, center_point:y() + y, center_point:z()))
            end
        end
    end
    return positions
end

-- Função auxiliar para obter um elemento aleatório de uma tabela
local function random_element(tb)
    return tb[math.random(#tb)]
end

-- Função para pausar o movimento
function circular_movement.pause_movement()
    movement_paused = true
end

-- Função para retomar o movimento
function circular_movement.resume_movement()
    movement_paused = false
end

-- Função para verificar se o jogador está próximo da Maiden
function circular_movement.is_near_maiden(player_position, maiden_position, radius)
    return player_position:dist_to(maiden_position) <= radius * 1.2
end

-- Função principal de movimento circular
function circular_movement.update(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
    local current_time = os.clock()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    if not menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then
        return
    end

    -- Verifica se o movimento está pausado
    if movement_paused then
        return
    end

    local player_position = local_player:get_position()

    -- Verifica se o jogador está próximo o suficiente da Maiden para iniciar o movimento circular
    if not circular_movement.is_near_maiden(player_position, helltide_final_maidenpos, explorer_circle_radius) then
        return
    end

    if menu_elements.main_helltide_maiden_auto_plugin_run_explorer:get() and helltide_final_maidenpos then
        run_explorer = 1
        
        if not explorer_points or explorer_circle_radius_prev ~= explorer_circle_radius then
            explorer_circle_radius_prev = explorer_circle_radius
            explorer_points = get_positions_in_radius(helltide_final_maidenpos, explorer_circle_radius)
        end

        if explorer_points then
            if explorer_go_next == 1 then
                if current_time - last_explorer_threshold_check < explorer_threshold then
                    return
                end
                last_explorer_threshold_check = current_time

                local random_waypoint = random_element(explorer_points)
                random_waypoint = utility.set_height_of_valid_position(random_waypoint)
                if utility.is_point_walkeable_heavy(random_waypoint) then
                    explorer_point = random_waypoint
                    
                    explorer_threshold = menu_elements.main_helltide_maiden_auto_plugin_explorer_threshold:get()
                    explorer_thresholdvar = math.random(0, menu_elements.main_helltide_maiden_auto_plugin_explorer_thresholdvar:get())
                    explorer_threshold = explorer_threshold + explorer_thresholdvar

                    pathfinder.force_move_raw(explorer_point)
                    explorer_go_next = 0
                end
            else
                if explorer_point and not explorer_point:is_zero() then
                    if player_position:dist_to(explorer_point) < 2.5 then
                        explorer_go_next = 1
                    else
                        pathfinder.force_move_raw(explorer_point)
                    end
                end
            end
        end
    else
        run_explorer = 0
        pathfinder.clear_stored_path()
    end
end

-- Função para limpar o blacklist (se necessário)
function circular_movement.clearBlacklist()
    -- Implemente a lógica de limpeza do blacklist, se houver
end

return circular_movement