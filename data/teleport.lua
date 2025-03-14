local waypoint_loader = require("functions.waypoint_loader")
local countdown_display = require("graphics.countdown_display")
local teleport = {}

-- Variáveis locais
local current_index = 1
local valid_zones = {}
local last_position = nil
local stable_position_count = 0
local stable_position_threshold = 2 -- Reduzido para acelerar a detecção de posição estável
local teleport_start_time = 0
local teleport_timeout = 5 -- Reduzido para 5 segundos

-- Variáveis para controle de tentativas e cooldown
local teleport_attempts = 0
local max_teleport_attempts = 3 -- Reduzido para 3 tentativas
local teleport_cooldown = 0
local teleport_cooldown_duration = 15 -- Reduzido para 15 segundos

-- FSM States
local FSM = {
    IDLE = "idle",
    INITIATING = "initiating",
    TELEPORTING = "teleporting",
    STABILIZING = "stabilizing",
    COOLDOWN = "cooldown"
}

local current_state = FSM.IDLE

local function update_valid_zones()
    valid_zones = {}
    for zone, info in pairs(waypoint_loader.zone_mappings) do
        table.insert(valid_zones, {name = zone, id = info.id})
    end
end

local function cleanup_before_teleport(ChestsInteractor, Movement)
    if not ChestsInteractor or not Movement then
        console.print("ChestsInteractor ou Movement não disponíveis. Não é possível limpar antes do teleporte.")
        return
    end
    collectgarbage("collect")
    waypoint_loader.clear_cached_waypoints()
    ChestsInteractor.clearInteractedObjects()
    Movement.reset()
end

local function is_loading_or_limbo()
    local current_world = world.get_current_world()
    if not current_world then
        return true
    end
    local world_name = current_world:get_name()
    return world_name:find("Limbo") ~= nil or world_name:find("Loading") ~= nil
end

-- Função para obter o próximo local de teleporte
function teleport.get_next_teleport_location()
    update_valid_zones()
    return valid_zones[current_index].name
end

-- Função principal de teleporte
function teleport.tp_to_next(ChestsInteractor, Movement, target_zone)
    local current_time = get_time_since_inject()
    local current_world = world.get_current_world()
    local local_player = get_local_player()
    
    if not current_world or not local_player then
        return false
    end

    local world_name = current_world:get_name()
    local current_position = local_player:get_position()

    -- FSM Logic
    if current_state == FSM.IDLE then
        if is_loading_or_limbo() then
            return false
        end
        
        if current_time < teleport_cooldown then
            current_state = FSM.COOLDOWN
            return false
        end

        current_state = FSM.INITIATING
        teleport_start_time = current_time
        cleanup_before_teleport(ChestsInteractor, Movement)
        
        update_valid_zones()
        local teleport_destination
        if target_zone then
            local target_info = waypoint_loader.zone_mappings[target_zone]
            if not target_info then
                console.print("Erro: Zona de destino inválida: " .. target_zone)
                current_state = FSM.IDLE
                return false
            end
            teleport_destination = {name = target_zone, id = target_info.id}
        else
            if #valid_zones == 0 then
                console.print("Erro: Não há zonas válidas para teleporte")
                current_state = FSM.IDLE
                return false
            end
            teleport_destination = valid_zones[current_index]
            current_index = (current_index % #valid_zones) + 1
        end

        teleport_to_waypoint(teleport_destination.id)
        last_position = current_position
        console.print("Teleporte iniciado para " .. teleport_destination.name)
        countdown_display.start_countdown(teleport_timeout)
        
    elseif current_state == FSM.INITIATING then
        if is_loading_or_limbo() then
            current_state = FSM.TELEPORTING
        elseif current_time - teleport_start_time > teleport_timeout then
            console.print("Teleporte falhou: timeout. Tentando novamente...")
            current_state = FSM.IDLE
            teleport_attempts = teleport_attempts + 1
            if teleport_attempts >= max_teleport_attempts then
                console.print("Número máximo de tentativas de teleporte atingido. Entrando em cooldown.")
                teleport_cooldown = current_time + teleport_cooldown_duration
                current_state = FSM.COOLDOWN
                teleport_attempts = 0
            end
        end
        
    elseif current_state == FSM.TELEPORTING then
        if not is_loading_or_limbo() then
            current_state = FSM.STABILIZING
            last_position = current_position
            stable_position_count = 0
        end
        
    elseif current_state == FSM.STABILIZING then
        if is_loading_or_limbo() then
            current_state = FSM.TELEPORTING
        elseif last_position and current_position:dist_to(last_position) < 0.5 then
            stable_position_count = stable_position_count + 1
            if stable_position_count >= stable_position_threshold then
                local current_zone = current_world:get_current_zone_name()
                current_state = FSM.IDLE
                console.print("Teleporte concluído com sucesso para " .. current_zone)
                teleport_attempts = 0
                return true
            end
        else
            stable_position_count = 0
        end
        last_position = current_position
        
    elseif current_state == FSM.COOLDOWN then
        if current_time >= teleport_cooldown then
            current_state = FSM.IDLE
            console.print("Cooldown de teleporte finalizado.")
        end
    end

    return false
end

-- Função para teleportar para uma zona específica
function teleport.tp_to_zone(target_zone, ChestsInteractor, Movement)
    update_valid_zones()
    if #valid_zones == 0 then
        console.print("Erro: Não há zonas válidas para teleporte")
        return false
    end
    
    local target_info = waypoint_loader.zone_mappings[target_zone]
    if not target_info then
        console.print("Erro: Zona de destino inválida: " .. target_zone)
        return false
    end
    
    return teleport.tp_to_next(ChestsInteractor, Movement, target_zone)
end

-- Função para resetar o estado do teleporte
function teleport.reset()
    current_state = FSM.IDLE
    last_position = nil
    stable_position_count = 0
    current_index = 1
    teleport_attempts = 0
    teleport_cooldown = 0
    console.print("Estado do teleporte resetado")
end

-- Função para obter o estado atual do teleporte
function teleport.get_teleport_state()
    return current_state
end

-- Função para obter informações detalhadas sobre o teleporte
function teleport.get_teleport_info()
    return {
        state = current_state or "Desconhecido",
        attempts = teleport_attempts or 0,
        max_attempts = max_teleport_attempts or 0,
        cooldown = math.max(0, math.floor((teleport_cooldown or 0) - get_time_since_inject()))
    }
end

return teleport