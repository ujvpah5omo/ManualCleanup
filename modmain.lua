local TheNet = GLOBAL.TheNet
local TheInput = GLOBAL.TheInput
local TheSim = GLOBAL.TheSim
local math = GLOBAL.math
local string = GLOBAL.string
local table = GLOBAL.table
local ipairs = GLOBAL.ipairs
local pairs = GLOBAL.pairs
local type = GLOBAL.type
local tostring = GLOBAL.tostring
local tonumber = GLOBAL.tonumber
local next = GLOBAL.next
local require = GLOBAL.require
local rawget = GLOBAL.rawget
local rawset = GLOBAL.rawset
local pcall = GLOBAL.pcall

local RPC_NAMESPACE = "ManualCleanup"
local CONFIG_MOD_NAMES = { "workshop-3008351689", "ManualCleanup" }

local function GetConfigValue(name, default)
    local get_config = GLOBAL.GetModConfigData
    if get_config == nil then
        return default
    end

    for _, mod_name in ipairs(CONFIG_MOD_NAMES) do
        local ok, value = pcall(get_config, name, mod_name)
        if ok and value ~= nil then
            return value
        end
    end

    return default
end

local function GetConfigBool(name, default)
    return GetConfigValue(name, default) == true
end

local function GetConfigNumber(name, default, min_value, max_value)
    local value = tonumber(GetConfigValue(name, default)) or default
    if min_value ~= nil and value < min_value then
        value = min_value
    end
    if max_value ~= nil and value > max_value then
        value = max_value
    end
    return value
end

local ENABLE_MOUSE_UI = GetConfigBool("enable_mouse_ui", true)
local ENABLE_CONTROLLER_UI = GetConfigBool("enable_controller_ui", true)
local WHEEL_RANGE = GetConfigNumber("cleanup_range", 80, 20, 200)
local WHEEL_SLOTS = 8
local WHEEL_RADIUS = 210
local WHEEL_LABEL_WIDTH = 132
local WHEEL_LABEL_HEIGHT = 70
local WHEEL_TEXT_SIZE = 36
local WHEEL_TEXT_MIN_WIDTH = 132
local WHEEL_TEXT_MAX_WIDTH = 340
local WHEEL_CENTER_Y_OFFSET = 70
local MOUSE_BUTTON_ROW_WIDTH = 160
local MOUSE_BUTTON_ROW_HEIGHT = 42
local MOUSE_BUTTON_ROW_GAP = 168
local MOUSE_CONFIRM_SECONDS = 6

local function GetGlobal(name)
    return rawget(GLOBAL, name)
end

local function InGame()
    local in_game = GetGlobal("InGame")
    return in_game == nil or in_game()
end

local function SetManualCleanupHUDFocus(enabled)
    local set_focus = GetGlobal("SetModHUDFocus")
    if set_focus ~= nil then
        set_focus("ManualCleanup", enabled)
    end
end

local cleanup_undo = {}
local RemoveItem

local blocked_prefabs = {
    multiplayer_portal = true,
    multiplayer_portal_moonrock = true,
    resurrectionstone = true,
    wendy_abigail = true,
    abigail = true,
    abigail_flower = true,
}

local function SayToPlayer(player, message)
    if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
        player.components.talker:Say(message)
    else
        print(message)
    end
end

local function IsPlayerServerAdmin(player)
    if player == nil then
        return true
    end

    local userid = player.userid
    if userid == nil then
        return false
    end

    local server_userid = TheNet.GetUserID ~= nil and TheNet:GetUserID() or nil
    if server_userid ~= nil and userid == server_userid and TheNet:GetIsServerAdmin() then
        return true
    end

    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        if client.userid == userid then
            return client.admin == true or client.performance ~= nil
        end
    end

    return false
end

local function IsLocalAdmin()
    return TheNet:GetIsServerAdmin()
end

local function GetEntityDisplayName(inst)
    if inst == nil then
        return "unknown"
    end

    local name
    local get_description = GetGlobal("GetDescriptionString")
    if get_description ~= nil then
        local ok, description = pcall(get_description, inst)
        if ok and type(description) == "string" and description ~= "" and description ~= "MISSING NAME" and description ~= "missing name" then
            name = description
        end
    end

    if type(inst.name) == "string" and inst.name ~= "" and inst.name ~= "MISSING NAME" and inst.name ~= "missing name" then
        name = name or inst.name
    end

    name = name or inst.prefab or "unknown"
    return name:gsub("[\r\n]+", " ")
end

local function GetListKey(inst)
    return GetEntityDisplayName(inst) .. "  " .. tostring(inst ~= nil and inst.prefab or "unknown")
end

local function AddRemovedCount(list, inst)
    local key = GetListKey(inst)
    list[key] = (list[key] or 0) + 1
end

local function GetUndoKey(player)
    return tostring(player ~= nil and player.userid or "console")
end

local function BeginUndoBatch(player, label)
    return {
        userid = GetUndoKey(player),
        label = label or "清理",
        entries = {},
    }
end

local function GetStackSize(inst)
    local stackable = inst ~= nil and inst.components ~= nil and inst.components.stackable or nil
    if stackable ~= nil and stackable.StackSize ~= nil then
        return stackable:StackSize()
    end

    stackable = inst ~= nil and inst.replica ~= nil and inst.replica.stackable or nil
    if stackable ~= nil and stackable.StackSize ~= nil then
        return stackable:StackSize()
    end

    return 1
end

local function AddUndoEntry(batch, inst)
    if batch == nil or inst == nil or not inst:IsValid() or type(inst.prefab) ~= "string" or inst.Transform == nil then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local rotation = inst.Transform.GetRotation ~= nil and inst.Transform:GetRotation() or nil
    local health = inst.components ~= nil and inst.components.health or nil
    local finiteuses = inst.components ~= nil and inst.components.finiteuses or nil
    local fueled = inst.components ~= nil and inst.components.fueled or nil
    table.insert(batch.entries, {
        prefab = inst.prefab,
        x = x,
        y = y,
        z = z,
        rotation = rotation,
        stack_size = GetStackSize(inst),
        health_percent = health ~= nil and health.GetPercent ~= nil and health:GetPercent() or nil,
        finite_uses_percent = finiteuses ~= nil and finiteuses.GetPercent ~= nil and finiteuses:GetPercent() or nil,
        fuel_percent = fueled ~= nil and fueled.GetPercent ~= nil and fueled:GetPercent() or nil,
        skinname = inst.skinname,
    })
end

local function RemoveWithUndo(list, batch, inst)
    AddRemovedCount(list, inst)
    AddUndoEntry(batch, inst)
    RemoveItem(inst)
end

local function SaveUndoBatch(player, batch)
    if batch ~= nil and #batch.entries > 0 then
        cleanup_undo[batch.userid] = batch
    end
end

local function ApplyUndoEntry(entry)
    if entry == nil or type(entry.prefab) ~= "string" then
        return false
    end

    local spawn_prefab = GetGlobal("SpawnPrefab")
    if spawn_prefab == nil then
        return false
    end

    local inst = spawn_prefab(entry.prefab, entry.skinname)
    if inst == nil then
        return false
    end

    if inst.Transform ~= nil then
        inst.Transform:SetPosition(entry.x or 0, entry.y or 0, entry.z or 0)
        if entry.rotation ~= nil and inst.Transform.SetRotation ~= nil then
            inst.Transform:SetRotation(entry.rotation)
        end
    end

    if entry.stack_size ~= nil and entry.stack_size > 1
        and inst.components ~= nil
        and inst.components.stackable ~= nil
        and inst.components.stackable.SetStackSize ~= nil then
        inst.components.stackable:SetStackSize(entry.stack_size)
    end

    if entry.health_percent ~= nil
        and inst.components ~= nil
        and inst.components.health ~= nil
        and inst.components.health.SetPercent ~= nil then
        inst.components.health:SetPercent(entry.health_percent)
    end

    if entry.finite_uses_percent ~= nil
        and inst.components ~= nil
        and inst.components.finiteuses ~= nil
        and inst.components.finiteuses.SetPercent ~= nil then
        inst.components.finiteuses:SetPercent(entry.finite_uses_percent)
    end

    if entry.fuel_percent ~= nil
        and inst.components ~= nil
        and inst.components.fueled ~= nil
        and inst.components.fueled.SetPercent ~= nil then
        inst.components.fueled:SetPercent(entry.fuel_percent)
    end

    return true
end

RemoveItem = function(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    if inst.components ~= nil and inst.components.lootdropper ~= nil then
        inst.components.lootdropper.DropLoot = function() end
    end

    if inst.components ~= nil and inst.components.inventory ~= nil and inst.components.inventory.DropEverything ~= nil then
        inst.components.inventory.DropEverything = function() end
    end

    inst:Remove()
end

local function AnnounceRemovedList(list)
    if next(list) ~= nil then
        for key, count in pairs(list) do
            print("wiped", count, key)
            TheNet:Announce(string.format("清理了   %d    %s", count, key))
        end
    end
end

local function RequireAdmin(player)
    if IsPlayerServerAdmin(player) then
        return true
    end

    SayToPlayer(player, "只有管理员可以执行清理。")
    return false
end

local function IsContainerCleanupTarget(inst)
    return inst ~= nil
        and (inst:HasTag("_container")
            or inst:HasTag("chest")
            or inst:HasTag("backpack")
            or (inst.replica ~= nil and inst.replica.container ~= nil)
            or (inst.components ~= nil and inst.components.container ~= nil))
end

local function IsCleanupTarget(inst, player)
    if inst == nil
        or inst == player
        or not inst:IsValid()
        or type(inst.prefab) ~= "string"
        or inst.Transform == nil
        or inst.inlimbo
        or blocked_prefabs[inst.prefab]
        or inst:HasTag("FX")
        or inst:HasTag("DECOR")
        or inst:HasTag("INLIMBO")
        or inst:HasTag("NOCLICK")
        or inst:HasTag("player")
        or inst:HasTag("wall")
        or inst:HasTag("heavy")
        or inst:HasTag("irreplaceable")
        or inst:HasTag("companion")
        or inst:HasTag("abigail")
        or inst:HasTag("portal")
        or inst:HasTag("resurrector")
        or inst:HasTag("antlion_sinkhole_blocker")
        or IsContainerCleanupTarget(inst) then
        return false
    end

    if inst:HasTag("structure") then
        return false
    end

    if inst.components ~= nil and inst.components.inventoryitem ~= nil then
        return inst.components.inventoryitem.owner == nil
    end

    local inventoryitem = inst.replica ~= nil and inst.replica.inventoryitem or nil
    return inventoryitem ~= nil
        and (inventoryitem.IsHeld == nil or not inventoryitem:IsHeld())
end

local function IsTargetNearPlayer(inst, player)
    return player ~= nil
        and inst ~= nil
        and player.Transform ~= nil
        and inst.Transform ~= nil
        and player:GetDistanceSqToInst(inst) <= WHEEL_RANGE * WHEEL_RANGE
end

local function IsTargetOnScreen(inst, viewer)
    if inst == nil or inst.Transform == nil then
        return false
    end

    local can_see = GetGlobal("CanEntitySeeTarget")
    if can_see ~= nil and viewer ~= nil and not can_see(viewer, inst) then
        return false
    end

    local world_x, world_y, world_z
    if inst.AnimState ~= nil then
        world_x, world_y, world_z = inst.AnimState:GetSymbolPosition("", 0, 0, 0)
    end
    if world_x == nil then
        world_x, world_y, world_z = inst.Transform:GetWorldPosition()
    end

    local screen_x, screen_y = TheSim:GetScreenPos(world_x, world_y, world_z)
    local screen_width, screen_height = TheSim:GetScreenSize()
    return screen_x ~= nil
        and screen_y ~= nil
        and screen_x >= 0
        and screen_x <= screen_width
        and screen_y >= 0
        and screen_y <= screen_height
end

local function GetEntityFromSingleRequest(player, guid, prefab, x, y, z)
    guid = tonumber(guid) or guid
    local inst = guid ~= nil and GLOBAL.Ents[guid] or nil
    if IsCleanupTarget(inst, player) and IsTargetNearPlayer(inst, player) then
        return inst
    end

    if type(prefab) ~= "string" or prefab == "" or x == nil or z == nil then
        return nil
    end

    x = tonumber(x)
    y = tonumber(y) or 0
    z = tonumber(z)
    if x == nil or z == nil then
        return nil
    end

    local best
    local best_dist_sq
    for _, candidate in ipairs(TheSim:FindEntities(x, y, z, 6, nil, {"FX", "DECOR", "INLIMBO", "NOCLICK"})) do
        if IsCleanupTarget(candidate, player)
            and candidate.prefab == prefab
            and IsTargetNearPlayer(candidate, player) then
            local dx, _, dz = candidate.Transform:GetWorldPosition()
            local dist_sq = (dx - x) * (dx - x) + (dz - z) * (dz - z)
            if best == nil or dist_sq < best_dist_sq then
                best = candidate
                best_dist_sq = dist_sq
            end
        end
    end
    return best
end

local function RemoveSingleServer(player, guid, prefab, x, y, z)
    if not RequireAdmin(player) then
        return
    end

    local inst = GetEntityFromSingleRequest(player, guid, prefab, x, y, z)
    if not IsCleanupTarget(inst, player) or not IsTargetNearPlayer(inst, player) then
        SayToPlayer(player, "目标已经不存在或距离太远。")
        return
    end

    local list = {}
    local undo = BeginUndoBatch(player, "删除一个")
    RemoveWithUndo(list, undo, inst)
    SaveUndoBatch(player, undo)
    AnnounceRemovedList(list)
end

local function RemoveNearbyPrefabServer(player, prefab)
    if not RequireAdmin(player) then
        return
    end
    if player == nil or player.Transform == nil or type(prefab) ~= "string" or prefab == "" then
        return
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, WHEEL_RANGE, nil, {"FX", "DECOR", "INLIMBO", "NOCLICK"})
    local list = {}
    local undo = BeginUndoBatch(player, "附近同类清理 " .. prefab)
    for _, inst in ipairs(ents) do
        if IsCleanupTarget(inst, player) and inst.prefab == prefab then
            RemoveWithUndo(list, undo, inst)
        end
    end
    SaveUndoBatch(player, undo)
    AnnounceRemovedList(list)
end

local function RemoveGlobalPrefabServer(player, prefab)
    if not RequireAdmin(player) then
        return
    end
    if type(prefab) ~= "string" or prefab == "" then
        return
    end

    local list = {}
    local undo = BeginUndoBatch(player, "全世界同类清理 " .. prefab)
    for _, inst in pairs(GLOBAL.Ents) do
        if IsCleanupTarget(inst, player) and inst.prefab == prefab then
            RemoveWithUndo(list, undo, inst)
        end
    end
    SaveUndoBatch(player, undo)
    AnnounceRemovedList(list)
end

local function RestoreLastCleanupServer(player)
    if not RequireAdmin(player) then
        return
    end

    local undo_key = GetUndoKey(player)
    local batch = cleanup_undo[undo_key]
    if batch == nil or batch.entries == nil or #batch.entries == 0 then
        SayToPlayer(player, "没有可恢复的上一次清理记录。")
        return
    end

    cleanup_undo[undo_key] = nil
    local restored = 0
    for _, entry in ipairs(batch.entries) do
        if ApplyUndoEntry(entry) then
            restored = restored + 1
        end
    end

    TheNet:Announce(string.format("已恢复上一次清理：%s，恢复 %d/%d 个实体。", batch.label or "清理", restored, #batch.entries))
end

AddModRPCHandler(RPC_NAMESPACE, "RemoveSingle", function(player, guid, prefab, x, y, z)
    RemoveSingleServer(player, guid, prefab, x, y, z)
end)

AddModRPCHandler(RPC_NAMESPACE, "RemoveNearbyPrefab", function(player, prefab)
    RemoveNearbyPrefabServer(player, prefab)
end)

AddModRPCHandler(RPC_NAMESPACE, "RemoveGlobalPrefab", function(player, prefab)
    RemoveGlobalPrefabServer(player, prefab)
end)

AddModRPCHandler(RPC_NAMESPACE, "RestoreLast", function(player)
    RestoreLastCleanupServer(player)
end)

local function GetUtf8Codepoint(text, index)
    local byte1 = text:byte(index)
    if byte1 == nil then
        return nil, index + 1
    elseif byte1 < 0x80 then
        return byte1, index + 1
    elseif byte1 < 0xE0 then
        local byte2 = text:byte(index + 1) or 0
        return (byte1 - 0xC0) * 0x40 + (byte2 - 0x80), index + 2
    elseif byte1 < 0xF0 then
        local byte2 = text:byte(index + 1) or 0
        local byte3 = text:byte(index + 2) or 0
        return (byte1 - 0xE0) * 0x1000 + (byte2 - 0x80) * 0x40 + (byte3 - 0x80), index + 3
    else
        local byte2 = text:byte(index + 1) or 0
        local byte3 = text:byte(index + 2) or 0
        local byte4 = text:byte(index + 3) or 0
        return (byte1 - 0xF0) * 0x40000 + (byte2 - 0x80) * 0x1000 + (byte3 - 0x80) * 0x40 + (byte4 - 0x80), index + 4
    end
end

local function IsChineseCodepoint(codepoint)
    return codepoint ~= nil
        and ((codepoint >= 0x3400 and codepoint <= 0x4DBF)
            or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
            or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
            or (codepoint >= 0x20000 and codepoint <= 0x2A6DF)
            or (codepoint >= 0x2A700 and codepoint <= 0x2B73F)
            or (codepoint >= 0x2B740 and codepoint <= 0x2B81F)
            or (codepoint >= 0x2B820 and codepoint <= 0x2CEAF))
end

local function GetTextUnits(text)
    text = type(text) == "string" and text or ""
    local units = 0
    local index = 1
    while index <= #text do
        local codepoint
        codepoint, index = GetUtf8Codepoint(text, index)
        if IsChineseCodepoint(codepoint) then
            units = units + 1
        elseif codepoint ~= nil and codepoint < 0x80 then
            units = units + .55
        else
            units = units + 1
        end
    end
    return units
end

local function GetTextSize(text, max_size, min_size)
    local units = GetTextUnits(text)
    if units <= 8 then
        return max_size
    elseif units <= 14 then
        return math.max(min_size, max_size - 4)
    elseif units <= 20 then
        return math.max(min_size, max_size - 8)
    end
    return min_size
end

local function GetTextWidth(text)
    local width = 64 + GetTextUnits(text) * 17
    return math.max(WHEEL_TEXT_MIN_WIDTH, math.min(WHEEL_TEXT_MAX_WIDTH, width))
end

local function GetCleanupIcon(inst)
    local inventoryitem = inst ~= nil and inst.replica ~= nil and inst.replica.inventoryitem or nil
    local image = inventoryitem ~= nil and inventoryitem.GetImage ~= nil and inventoryitem:GetImage() or nil
    local atlas = inventoryitem ~= nil and inventoryitem.GetAtlas ~= nil and inventoryitem:GetAtlas() or nil
    local get_inventory_item_atlas = GetGlobal("GetInventoryItemAtlas")
    if atlas == nil and image ~= nil and get_inventory_item_atlas ~= nil then
        atlas = get_inventory_item_atlas(image)
    end
    return atlas, image
end

local function GetCleanupTargets(player)
    local x, y, z = player.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, WHEEL_RANGE, nil, {"FX", "DECOR", "INLIMBO", "NOCLICK"})
    local grouped = {}
    local keys = {}

    for _, inst in ipairs(ents) do
        if IsCleanupTarget(inst, player) and IsTargetOnScreen(inst, player) then
            local name = GetEntityDisplayName(inst)
            local key = inst.prefab .. "\0" .. name
            local stackable = inst.replica ~= nil and inst.replica.stackable or nil
            local stack_size = stackable ~= nil and stackable.StackSize ~= nil and stackable:StackSize() or 1
            local distance_sq = player:GetDistanceSqToInst(inst)
            local entry = grouped[key]

            if entry ~= nil then
                entry.count = entry.count + stack_size
                if distance_sq < entry.distance_sq then
                    entry.target = inst
                    entry.guid = inst.GUID
                    entry.distance_sq = distance_sq
                end
            else
                local atlas, image = GetCleanupIcon(inst)
                entry = {
                    target = inst,
                    guid = inst.GUID,
                    prefab = inst.prefab,
                    name = name,
                    atlas = atlas,
                    image = image,
                    count = stack_size,
                    distance_sq = distance_sq,
                }
                grouped[key] = entry
                table.insert(keys, key)
            end
        end
    end

    local entries = {}
    for _, key in ipairs(keys) do
        table.insert(entries, grouped[key])
    end
    table.sort(entries, function(a, b)
        return a.distance_sq < b.distance_sq
    end)
    return entries
end

local function GetWheelCenter(player, screen_width, screen_height)
    local world_x, world_y, world_z
    if player.AnimState ~= nil then
        world_x, world_y, world_z = player.AnimState:GetSymbolPosition("head", 0, 0, 0)
    end
    if world_x == nil then
        world_x, world_y, world_z = player.Transform:GetWorldPosition()
    end

    local screen_x, screen_y = TheSim:GetScreenPos(world_x, world_y, world_z)
    local center_x = screen_x or screen_width * .5
    local center_y = (screen_y or screen_height * .5) + WHEEL_CENTER_Y_OFFSET
    local min_x = WHEEL_RADIUS + WHEEL_LABEL_WIDTH * .5
    local max_x = screen_width - WHEEL_RADIUS - WHEEL_LABEL_WIDTH * .5
    local min_y = WHEEL_RADIUS + WHEEL_LABEL_HEIGHT
    local max_y = screen_height - WHEEL_RADIUS - WHEEL_LABEL_HEIGHT

    if min_x <= max_x then
        center_x = math.max(min_x, math.min(max_x, center_x))
    else
        center_x = 0
    end
    if min_y <= max_y then
        center_y = math.max(min_y, math.min(max_y, center_y))
    else
        center_y = 0
    end

    return center_x, center_y
end

local function GetSlotAngle(index, count)
    return math.pi * .5 - (index - 1) * math.pi * 2 / count
end

local function GetPageCount(targets)
    return math.max(1, math.ceil(#targets / WHEEL_SLOTS))
end

local function GetPageStart(page)
    return (page - 1) * WHEEL_SLOTS + 1
end

AddComponentPostInit("playercontroller", function(self, inst)
    if inst ~= GetGlobal("ThePlayer") then
        return
    end

    local PlayerControllerOnControl = self.OnControl
    local SelectCleanupTarget
    local SelectCleanupTargetRelative
    local ChangeCleanupPage
    local DeleteSingleSelection
    local DeleteGroupSelection
    local DeleteGlobalGroupSelection
    local RestoreLastCleanup
    local SelectCleanupTargetFromMouse
    local UpdateWheel

    local function CancelHoldTask()
        if self._manualcleanup_hold_task ~= nil then
            self._manualcleanup_hold_task:Cancel()
            self._manualcleanup_hold_task = nil
        end
    end

    local function CancelModeCancelHoldTask()
        if self._manualcleanup_cancel_hold_task ~= nil then
            self._manualcleanup_cancel_hold_task:Cancel()
            self._manualcleanup_cancel_hold_task = nil
        end
    end

    local function StopCleanupWalking()
        self.directwalking = false
        self.predictwalking = false
        if self.RemoteStopWalking ~= nil then
            self:RemoteStopWalking()
        end
        local locomotor = inst.replica ~= nil and inst.replica.locomotor or nil
        if locomotor ~= nil and locomotor.Stop ~= nil then
            locomotor:Stop()
        end
    end

    local function IsCancelControl(control)
        return control == GLOBAL.CONTROL_CANCEL or control == GLOBAL.CONTROL_CONTROLLER_ALTACTION
    end

    local function IsSingleDeleteControl(control)
        return control == GLOBAL.CONTROL_INSPECT
            or control == GLOBAL.CONTROL_OPEN_CRAFTING
            or control == GetGlobal("CONTROL_MENU_MISC_1")
            or control == GetGlobal("CONTROL_MENU_MISC_2")
            or control == GetGlobal("CONTROL_MENU_MISC_3")
            or control == GetGlobal("CONTROL_MENU_MISC_4")
            or control == GetGlobal("CONTROL_OPEN_DEBUG_MENU")
    end

    local function SetCleanupCameraLocked(locked)
        local camera = GetGlobal("TheCamera")
        if camera == nil or camera.SetControllable == nil then
            return
        end

        if locked then
            if self._manualcleanup_camera_controllable == nil then
                self._manualcleanup_camera_controllable = camera.IsControllable ~= nil and camera:IsControllable() or true
            end
            camera:SetControllable(false)
        elseif self._manualcleanup_camera_controllable ~= nil then
            camera:SetControllable(self._manualcleanup_camera_controllable)
            self._manualcleanup_camera_controllable = nil
        end
    end

    local function InstallCleanupWalkingBlocker()
        local current = self.DoDirectWalking
        if current == nil or current == self._manualcleanup_directwalking_wrapper then
            return
        end

        self._manualcleanup_directwalking_base = current
        self._manualcleanup_directwalking_wrapper = function(controller, ...)
            if controller._manualcleanup_mode then
                StopCleanupWalking()
                return false
            end
            return controller._manualcleanup_directwalking_base(controller, ...)
        end
        self.DoDirectWalking = self._manualcleanup_directwalking_wrapper
    end

    local function ClearMouseConfirm(skip_update)
        if self._manualcleanup_mouse_confirm_task ~= nil then
            self._manualcleanup_mouse_confirm_task:Cancel()
            self._manualcleanup_mouse_confirm_task = nil
        end
        if self._manualcleanup_mouse_confirm ~= nil then
            self._manualcleanup_mouse_confirm = nil
            if not skip_update and self._manualcleanup_mode then
                UpdateWheel()
            end
        end
    end

    local function ClearTarget()
        local highlight = self._manualcleanup_highlight
        if highlight ~= nil and highlight:IsValid() and highlight.AnimState ~= nil then
            highlight.AnimState:SetHighlightColour()
        end
        self._manualcleanup_highlight = nil
        self._manualcleanup_target = nil
        if self._manualcleanup_wheel ~= nil then
            self._manualcleanup_wheel:Hide()
        end
    end

    local function ExitCleanupMode(preserve_swallow_controls)
        CancelHoldTask()
        CancelModeCancelHoldTask()
        ClearMouseConfirm(true)
        ClearTarget()
        SetManualCleanupHUDFocus(false)
        SetCleanupCameraLocked(false)
        self._manualcleanup_mode = false
        self._manualcleanup_hold_elapsed = nil
        self._manualcleanup_targets = nil
        self._manualcleanup_target_index = nil
        self._manualcleanup_target_page = nil
        self._manualcleanup_keyboard_mode = nil
        self._manualcleanup_waiting_for_cancel_release = nil
        self._manualcleanup_cancel_hold_elapsed = nil
        if not preserve_swallow_controls then
            self._manualcleanup_swallow_controls = nil
        end
    end

    local function GetSelectedCleanupEntry()
        local targets = self._manualcleanup_targets or {}
        return targets[self._manualcleanup_target_index or 1]
    end

    local function GetMouseConfirmKey(action, entry)
        if entry == nil then
            return nil
        elseif action == "single" then
            return entry.guid ~= nil and ("single:" .. tostring(entry.guid)) or nil
        elseif type(entry.prefab) == "string" then
            return action .. ":" .. entry.prefab
        end
        return nil
    end

    local function ConfirmMouseDelete(action, label, delete_fn)
        if self._manualcleanup_keyboard_mode ~= true or delete_fn == nil then
            return
        end

        local entry = GetSelectedCleanupEntry()
        local key = GetMouseConfirmKey(action, entry)
        if key == nil then
            return
        end

        local confirm = self._manualcleanup_mouse_confirm
        if confirm ~= nil and confirm.key == key then
            ClearMouseConfirm(true)
            delete_fn()
            return
        end

        ClearMouseConfirm(true)
        self._manualcleanup_mouse_confirm = {
            key = key,
            action = action,
            label = label,
            name = entry.name,
            prefab = entry.prefab,
        }
        self._manualcleanup_mouse_confirm_task = inst:DoTaskInTime(MOUSE_CONFIRM_SECONDS, function()
            self._manualcleanup_mouse_confirm_task = nil
            ClearMouseConfirm()
        end)
        UpdateWheel()
    end

    local function ConfirmMouseRestore()
        if self._manualcleanup_keyboard_mode ~= true or RestoreLastCleanup == nil then
            return
        end

        local confirm = self._manualcleanup_mouse_confirm
        if confirm ~= nil and confirm.key == "restore:last" then
            ClearMouseConfirm(true)
            RestoreLastCleanup()
            return
        end

        ClearMouseConfirm(true)
        self._manualcleanup_mouse_confirm = {
            key = "restore:last",
            action = "restore",
            label = "恢复上次",
            name = "上一次清理",
        }
        self._manualcleanup_mouse_confirm_task = inst:DoTaskInTime(MOUSE_CONFIRM_SECONDS, function()
            self._manualcleanup_mouse_confirm_task = nil
            ClearMouseConfirm()
        end)
        UpdateWheel()
    end

    local function EnsureWheel()
        if self._manualcleanup_wheel ~= nil or inst.HUD == nil or inst.HUD.controls == nil then
            return
        end

        local Widget = require("widgets/widget")
        local Image = require("widgets/image")
        local Text = require("widgets/text")
        local root = inst.HUD.controls:AddChild(Widget("manualcleanup_controller_wheel"))
        root:SetPosition(0, 0)
        if root.SetClickable ~= nil then
            root:SetClickable(true)
        end
        root.OnMouseWheel = function(_, up)
            if self._manualcleanup_keyboard_mode == true and ChangeCleanupPage ~= nil then
                ChangeCleanupPage(up and -1 or 1)
                return true
            end
            return false
        end
        root.title = root:AddChild(Text(GLOBAL.HEADERFONT, 34, ""))
        root.slots = {}

        for i = 1, WHEEL_SLOTS do
            local slot = root:AddChild(Widget("manualcleanup_controller_wheel_slot"))
            slot.bg = slot:AddChild(Image("images/global.xml", "square.tex"))
            slot.bg:SetSize(WHEEL_LABEL_WIDTH, WHEEL_LABEL_HEIGHT)
            slot.bg:SetTint(0, 0, 0, .58)
            slot.icon = slot:AddChild(Image("images/global.xml", "square.tex"))
            slot.icon:SetSize(46, 46)
            slot.icon:Hide()
            slot.text = slot:AddChild(Text(GLOBAL.BODYTEXTFONT, WHEEL_TEXT_SIZE, ""))
            slot.text:SetRegionSize(WHEEL_TEXT_MIN_WIDTH, WHEEL_LABEL_HEIGHT)
            if slot.text.EnableWordWrap then
                slot.text:EnableWordWrap(false)
            end
            if slot.text.EnableWhitespaceWrap then
                slot.text:EnableWhitespaceWrap(false)
            end
            slot._manualcleanup_slot_index = i
            if slot.SetClickable ~= nil then
                slot:SetClickable(true)
            end
            slot.OnMouseButton = function(_, button, down)
                if self._manualcleanup_keyboard_mode == true
                    and button == GLOBAL.MOUSEBUTTON_LEFT
                    and down
                    and SelectCleanupTargetFromMouse ~= nil then
                    SelectCleanupTargetFromMouse(slot._manualcleanup_slot_index)
                    return true
                end
                return false
            end
            slot.OnMouseWheel = function(_, up)
                if self._manualcleanup_keyboard_mode == true and ChangeCleanupPage ~= nil then
                    ChangeCleanupPage(up and -1 or 1)
                    return true
                end
                return false
            end
            slot:Hide()
            root.slots[i] = slot
        end

        root.footer = root:AddChild(Text(GLOBAL.BODYTEXTFONT, WHEEL_TEXT_SIZE, ""))
        root.footer:SetRegionSize(920, 122)
        if root.footer.EnableWordWrap then
            root.footer:EnableWordWrap(false)
        end
        if root.footer.EnableWhitespaceWrap then
            root.footer:EnableWhitespaceWrap(false)
        end

        local function AddMouseButton(label, onclick)
            local button = root:AddChild(Widget("manualcleanup_mouse_button"))
            button.bg = button:AddChild(Image("images/global.xml", "square.tex"))
            button.bg:SetSize(MOUSE_BUTTON_ROW_WIDTH, MOUSE_BUTTON_ROW_HEIGHT)
            button.bg:SetTint(.08, .08, .08, .88)
            button.text = button:AddChild(Text(GLOBAL.BODYTEXTFONT, 26, label))
            button.text:SetRegionSize(MOUSE_BUTTON_ROW_WIDTH - 12, MOUSE_BUTTON_ROW_HEIGHT)
            if button.text.EnableWordWrap then
                button.text:EnableWordWrap(false)
            end
            if button.text.EnableWhitespaceWrap then
                button.text:EnableWhitespaceWrap(false)
            end
            button.SetManualCleanupText = function(widget, text)
                widget.text:SetString(text)
            end
            if button.SetClickable ~= nil then
                button:SetClickable(true)
            end
            if button.bg.SetClickable ~= nil then
                button.bg:SetClickable(true)
            end
            if button.text.SetClickable ~= nil then
                button.text:SetClickable(true)
            end
            local function SetButtonFocusTint(focused)
                button.bg:SetTint(focused and .18 or .08, focused and .15 or .08, focused and .10 or .08, focused and .95 or .88)
            end
            local function HandleButtonClick(_, mouse_button, down)
                if self._manualcleanup_keyboard_mode == true
                    and mouse_button == GLOBAL.MOUSEBUTTON_LEFT
                    and down then
                    onclick()
                    return true
                end
                return false
            end
            local function HandleButtonWheel(_, up)
                if self._manualcleanup_keyboard_mode == true and ChangeCleanupPage ~= nil then
                    ChangeCleanupPage(up and -1 or 1)
                    return true
                end
                return false
            end
            button.OnGainFocus = function()
                SetButtonFocusTint(true)
            end
            button.bg.OnGainFocus = function()
                SetButtonFocusTint(true)
            end
            button.text.OnGainFocus = function()
                SetButtonFocusTint(true)
            end
            button.OnLoseFocus = function()
                SetButtonFocusTint(false)
            end
            button.bg.OnLoseFocus = function()
                SetButtonFocusTint(false)
            end
            button.text.OnLoseFocus = function()
                SetButtonFocusTint(false)
            end
            button.OnMouseButton = HandleButtonClick
            button.bg.OnMouseButton = HandleButtonClick
            button.text.OnMouseButton = HandleButtonClick
            button.OnMouseWheel = HandleButtonWheel
            button.bg.OnMouseWheel = HandleButtonWheel
            button.text.OnMouseWheel = HandleButtonWheel
            button:Hide()
            return button
        end

        root.mouse_buttons = {
            previous_target = AddMouseButton("上一个", function()
                if SelectCleanupTargetRelative ~= nil then
                    SelectCleanupTargetRelative(-1)
                end
            end),
            next_target = AddMouseButton("下一个", function()
                if SelectCleanupTargetRelative ~= nil then
                    SelectCleanupTargetRelative(1)
                end
            end),
            previous_page = AddMouseButton("上一页", function()
                if ChangeCleanupPage ~= nil then
                    ChangeCleanupPage(-1)
                end
            end),
            next_page = AddMouseButton("下一页", function()
                if ChangeCleanupPage ~= nil then
                    ChangeCleanupPage(1)
                end
            end),
            single = AddMouseButton("删除一个", function()
                ConfirmMouseDelete("single", "删除一个", DeleteSingleSelection)
            end),
            nearby = AddMouseButton("附近一类", function()
                ConfirmMouseDelete("nearby", "附近一类", DeleteGroupSelection)
            end),
            global = AddMouseButton("全世界一类", function()
                ConfirmMouseDelete("global", "全世界一类", DeleteGlobalGroupSelection)
            end),
            restore = AddMouseButton("恢复上次", function()
                ConfirmMouseRestore()
            end),
            cancel = AddMouseButton("取消", function()
                ExitCleanupMode()
            end),
        }

        self._manualcleanup_wheel = root
        root:Hide()
    end

    local function UpdateMouseButtons(root, center_x, footer_y)
        if root.mouse_buttons == nil then
            return
        end

        if self._manualcleanup_keyboard_mode ~= true then
            for _, button in pairs(root.mouse_buttons) do
                button:Hide()
            end
            return
        end

        local row1_y = math.max(92, footer_y - 70)
        local row2_y = math.max(42, row1_y - 50)
        local buttons = root.mouse_buttons
        local confirm = self._manualcleanup_mouse_confirm
        local function SetButtonText(button, action, label)
            if button.SetManualCleanupText ~= nil then
                button:SetManualCleanupText(confirm ~= nil and confirm.action == action and ("确认" .. label) or label)
            end
        end

        buttons.previous_target:SetPosition(center_x - MOUSE_BUTTON_ROW_GAP * 1.5, row1_y)
        buttons.next_target:SetPosition(center_x - MOUSE_BUTTON_ROW_GAP * .5, row1_y)
        buttons.previous_page:SetPosition(center_x + MOUSE_BUTTON_ROW_GAP * .5, row1_y)
        buttons.next_page:SetPosition(center_x + MOUSE_BUTTON_ROW_GAP * 1.5, row1_y)

        buttons.single:SetPosition(center_x - MOUSE_BUTTON_ROW_GAP * 2, row2_y)
        buttons.nearby:SetPosition(center_x - MOUSE_BUTTON_ROW_GAP, row2_y)
        buttons.global:SetPosition(center_x, row2_y)
        buttons.restore:SetPosition(center_x + MOUSE_BUTTON_ROW_GAP, row2_y)
        buttons.cancel:SetPosition(center_x + MOUSE_BUTTON_ROW_GAP * 2, row2_y)

        SetButtonText(buttons.single, "single", "删除一个")
        SetButtonText(buttons.nearby, "nearby", "附近一类")
        SetButtonText(buttons.global, "global", "全世界一类")
        SetButtonText(buttons.restore, "restore", "恢复上次")

        for _, button in pairs(buttons) do
            if button.bg ~= nil and button.bg.SetSize ~= nil then
                button.bg:SetSize(MOUSE_BUTTON_ROW_WIDTH, MOUSE_BUTTON_ROW_HEIGHT)
            end
            if button.text ~= nil and button.text.SetSize ~= nil then
                button.text:SetSize(26)
            end
            button:Show()
        end
    end

    UpdateWheel = function()
        EnsureWheel()
        local root = self._manualcleanup_wheel
        local entries = self._manualcleanup_targets or {}
        local selected = self._manualcleanup_target_index or 1
        if root == nil or #entries == 0 then
            return
        end

        local screen_width, screen_height = TheSim:GetScreenSize()
        local center_x, center_y = GetWheelCenter(inst, screen_width, screen_height)
        local page_count = GetPageCount(entries)
        local page = math.max(1, math.min(page_count, self._manualcleanup_target_page or math.ceil(selected / WHEEL_SLOTS)))
        self._manualcleanup_target_page = page
        local first = GetPageStart(page)
        local visible_count = math.min(WHEEL_SLOTS, #entries - first + 1)

        root.title:SetString(string.format("手动清理  %d/%d  %d/%d", selected, #entries, page, page_count))
        root.title:SetPosition(center_x, center_y + 4)

        for slot_index, slot in ipairs(root.slots) do
            local entry_index = first + slot_index - 1
            local entry = entries[entry_index]
            if entry ~= nil then
                local angle = GetSlotAngle(slot_index, visible_count)
                local dir_x = math.cos(angle)
                local dir_y = math.sin(angle)
                local align_x = dir_x > .35 and GLOBAL.ANCHOR_LEFT
                    or dir_x < -.35 and GLOBAL.ANCHOR_RIGHT
                    or GLOBAL.ANCHOR_MIDDLE
                local count = entry.count > 1 and ("  x" .. tostring(entry.count)) or ""
                local slot_text = entry.name .. count
                local slot_width = entry.atlas ~= nil and entry.image ~= nil
                    and WHEEL_LABEL_WIDTH
                    or GetTextWidth(slot_text)

                slot:SetPosition(center_x + dir_x * WHEEL_RADIUS + dir_x * slot_width * .35, center_y + dir_y * WHEEL_RADIUS)
                slot.text:SetHAlign(align_x)

                if entry.atlas ~= nil and entry.image ~= nil then
                    slot.bg:SetSize(WHEEL_LABEL_WIDTH, WHEEL_LABEL_HEIGHT)
                    slot.icon:SetTexture(entry.atlas, entry.image)
                    slot.icon:Show()
                    slot.text:SetRegionSize(WHEEL_TEXT_MIN_WIDTH, WHEEL_LABEL_HEIGHT)
                    slot.text:SetSize(WHEEL_TEXT_SIZE)
                    slot.text:SetString(count)
                    slot.text:SetPosition(0, -34)
                else
                    slot.icon:Hide()
                    slot.bg:SetSize(slot_width, WHEEL_LABEL_HEIGHT)
                    slot.text:SetRegionSize(slot_width - 14, WHEEL_LABEL_HEIGHT)
                    slot.text:SetPosition(dir_x > .35 and 8 or dir_x < -.35 and -8 or 0, 0)
                    slot.text:SetSize(GetTextSize(slot_text, WHEEL_TEXT_SIZE, 22))
                    slot.text:SetString(slot_text)
                end

                if entry_index == selected then
                    slot.bg:SetTint(.55, .10, .06, .90)
                    slot.text:SetColour(1, .82, .25, 1)
                    slot.icon:SetTint(1, .72, .45, 1)
                else
                    slot.bg:SetTint(0, 0, 0, .58)
                    slot.text:SetColour(.9, .9, .9, 1)
                    slot.icon:SetTint(1, 1, 1, 1)
                end
                slot:Show()
            else
                slot:Hide()
            end
        end

        local keyboard_mode = self._manualcleanup_keyboard_mode == true
        local controller_id = TheInput:GetControllerID()
        local control_hint
        local page_hint = ""
        if keyboard_mode then
            control_hint = "鼠标点选目标，点击按钮执行操作，点取消关闭"
            page_hint = page_count > 1 and "   滚轮/按钮翻页" or ""
        else
            local single_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_INSPECT)
            local group_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_CONTROLLER_ATTACK)
            local global_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_CONTROLLER_ACTION)
            local cancel_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_CANCEL)
            local previous_page_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_ROTATE_LEFT)
            local next_page_control = TheInput:GetLocalizedControl(controller_id, GLOBAL.CONTROL_ROTATE_RIGHT)
            control_hint = string.format(
                "方向选择   %s 删除一个   %s 附近一类   %s 全世界一类   %s 短按退出/长按恢复",
                single_control,
                group_control,
                global_control,
                cancel_control
            )
            page_hint = page_count > 1 and string.format("   %s/%s 翻页", previous_page_control, next_page_control) or ""
        end
        local selected_entry = entries[selected]
        local selected_name = selected_entry ~= nil and selected_entry.name or ""
        local selected_prefab = selected_entry ~= nil and selected_entry.prefab or ""
        local selected_distance = selected_entry ~= nil and math.floor(math.sqrt(selected_entry.distance_sq) / 4 * 10) / 10 or 0
        local mouse_confirm = self._manualcleanup_mouse_confirm
        local mouse_hint = ""
        if keyboard_mode then
            if mouse_confirm ~= nil then
                mouse_hint = string.format("\n确认提示：再点一次[%s]删除 %s", mouse_confirm.label, mouse_confirm.name or mouse_confirm.prefab or "")
            else
                mouse_hint = "\n鼠标点选目标，再点击删除按钮；删除按钮需要二次确认"
            end
        end

        root.footer:SetSize(GetTextSize(selected_name, WHEEL_TEXT_SIZE, 22))
        root.footer:SetString(string.format(
            "%s [%s] %.1f\n%s%s%s",
            selected_name,
            selected_prefab,
            selected_distance,
            control_hint,
            page_hint,
            mouse_hint
        ))
        local footer_y = math.max(154, center_y - WHEEL_RADIUS - 58)
        root.footer:SetPosition(center_x, footer_y)
        UpdateMouseButtons(root, center_x, footer_y)
        root:Show()
    end

    local function SetCleanupTarget(entry)
        ClearTarget()
        local target = entry ~= nil and entry.target or nil
        if not IsCleanupTarget(target, inst) then
            return false
        end

        self._manualcleanup_target = target
        local highlight = target.highlightforward or target
        if highlight.AnimState ~= nil then
            highlight.AnimState:SetHighlightColour(.45, .12, .04, 0)
            self._manualcleanup_highlight = highlight
        end

        UpdateWheel()
        return true
    end

    SelectCleanupTarget = function(index)
        local targets = self._manualcleanup_targets or {}
        while #targets > 0 do
            index = ((index - 1) % #targets) + 1
            if self._manualcleanup_target_index ~= index then
                ClearMouseConfirm(true)
            end
            self._manualcleanup_target_index = index
            self._manualcleanup_target_page = math.ceil(index / WHEEL_SLOTS)
            if SetCleanupTarget(targets[index]) then
                return true
            end
            table.remove(targets, index)
            if index > #targets then
                index = 1
            end
        end
        ExitCleanupMode()
        return false
    end

    SelectCleanupTargetFromMouse = function(slot_index)
        if self._manualcleanup_keyboard_mode ~= true then
            return false
        end
        local targets = self._manualcleanup_targets or {}
        if #targets == 0 then
            ExitCleanupMode()
            return false
        end

        local page = self._manualcleanup_target_page or 1
        local index = GetPageStart(page) + slot_index - 1
        if targets[index] == nil then
            return false
        end
        SelectCleanupTarget(index)
        return true
    end

    local function EnterCleanupMode(force_keyboard)
        self._manualcleanup_hold_task = nil
        self._manualcleanup_hold_elapsed = true
        if not InGame()
            or not IsLocalAdmin()
            or inst.HUD == nil
            or (inst.HUD.IsControllerInventoryOpen and inst.HUD:IsControllerInventoryOpen()) then
            return
        end
        if not force_keyboard and not TheInput:ControllerAttached() then
            return
        end

        local targets = GetCleanupTargets(inst)
        if #targets == 0 then
            SayToPlayer(inst, "附近没有可清理目标。")
            return
        end

        self._manualcleanup_mode = true
        self._manualcleanup_keyboard_mode = force_keyboard == true and not TheInput:ControllerAttached()
        self._manualcleanup_targets = targets
        self._manualcleanup_waiting_for_cancel_release = true
        StopCleanupWalking()
        SetCleanupCameraLocked(true)

        local preferred = self:GetControllerTarget() or self:GetControllerAttackTarget()
        local index = 1
        if preferred ~= nil then
            for i, entry in ipairs(targets) do
                if entry.target == preferred then
                    index = i
                    break
                end
            end
        end

        self._manualcleanup_target_index = index
        self._manualcleanup_target_page = math.ceil(index / WHEEL_SLOTS)
        SetManualCleanupHUDFocus(true)
        SelectCleanupTarget(index)
    end

    local function SelectCleanupTargetByAngle(angle)
        local targets = self._manualcleanup_targets or {}
        if #targets == 0 then
            ExitCleanupMode()
            return
        end

        local best_index = 1
        local best_dot = -math.huge
        local direction_x = math.cos(angle)
        local direction_y = math.sin(angle)
        local page = self._manualcleanup_target_page or 1
        local first = GetPageStart(page)
        local visible_count = math.min(WHEEL_SLOTS, #targets - first + 1)
        for slot_index = 1, visible_count do
            local slot_angle = GetSlotAngle(slot_index, visible_count)
            local dot = math.cos(slot_angle) * direction_x + math.sin(slot_angle) * direction_y
            if dot > best_dot then
                best_dot = dot
                best_index = first + slot_index - 1
            end
        end
        SelectCleanupTarget(best_index)
    end

    ChangeCleanupPage = function(step)
        local targets = self._manualcleanup_targets or {}
        if #targets == 0 then
            ExitCleanupMode()
            return
        end

        local page_count = GetPageCount(targets)
        local page = self._manualcleanup_target_page or 1
        page = ((page - 1 + step) % page_count) + 1
        self._manualcleanup_target_page = page
        SelectCleanupTarget(GetPageStart(page))
    end

    SelectCleanupTargetRelative = function(step)
        local targets = self._manualcleanup_targets or {}
        if #targets == 0 then
            ExitCleanupMode()
            return
        end
        SelectCleanupTarget((self._manualcleanup_target_index or 1) + step)
    end

    local function GetControllerMoveAngle(control)
        local up = control == GLOBAL.CONTROL_MOVE_UP or TheInput:IsControlPressed(GLOBAL.CONTROL_MOVE_UP)
        local down = control == GLOBAL.CONTROL_MOVE_DOWN or TheInput:IsControlPressed(GLOBAL.CONTROL_MOVE_DOWN)
        local right = control == GLOBAL.CONTROL_MOVE_RIGHT or TheInput:IsControlPressed(GLOBAL.CONTROL_MOVE_RIGHT)
        local left = control == GLOBAL.CONTROL_MOVE_LEFT or TheInput:IsControlPressed(GLOBAL.CONTROL_MOVE_LEFT)
        local x = (right and 1 or 0) - (left and 1 or 0)
        local y = (up and 1 or 0) - (down and 1 or 0)

        if x == 0 and y == 0 then
            return nil
        elseif x == 0 then
            return y > 0 and math.pi * .5 or -math.pi * .5
        elseif y == 0 then
            return x > 0 and 0 or math.pi
        elseif x > 0 and y > 0 then
            return math.pi * .25
        elseif x < 0 and y > 0 then
            return math.pi * .75
        elseif x < 0 and y < 0 then
            return -math.pi * .75
        else
            return -math.pi * .25
        end
    end

    local function IsAnyControl(control, ...)
        for i = 1, GLOBAL.select("#", ...) do
            local compare_control = GLOBAL.select(i, ...)
            if compare_control ~= nil and control == compare_control then
                return true
            end
        end
        return false
    end

    local function ShouldHandleControlPress(control)
        if not self._manualcleanup_mode or not control then
            return false
        end

        if not TheInput:IsControlPressed(control) then
            return true
        end

        self._manualcleanup_last_control_down = self._manualcleanup_last_control_down or {}
        if self._manualcleanup_last_control_down[control] then
            return false
        end
        self._manualcleanup_last_control_down[control] = true
        return true
    end

    local function SwallowControls(...)
        self._manualcleanup_swallow_controls = self._manualcleanup_swallow_controls or {}
        for i = 1, GLOBAL.select("#", ...) do
            local control = GLOBAL.select(i, ...)
            if control ~= nil then
                self._manualcleanup_swallow_controls[control] = true
            end
        end
    end

    local function IsSwallowingControl(control)
        return self._manualcleanup_swallow_controls ~= nil
            and control ~= nil
            and self._manualcleanup_swallow_controls[control] == true
    end

    local function ClearSwallowedControl(control)
        if self._manualcleanup_swallow_controls ~= nil and control ~= nil then
            self._manualcleanup_swallow_controls[control] = nil
            if self._manualcleanup_last_control_down ~= nil then
                self._manualcleanup_last_control_down[control] = nil
            end
            if next(self._manualcleanup_swallow_controls) == nil then
                self._manualcleanup_swallow_controls = nil
            end
        end
    end

    local function ClearSwallowedControls(...)
        for i = 1, GLOBAL.select("#", ...) do
            ClearSwallowedControl(GLOBAL.select(i, ...))
        end
    end

    local function SendCleanupRPC(rpc_name, ...)
        local send_rpc = GetGlobal("SendModRPCToServer")
        local get_rpc = GetGlobal("GetModRPC")
        if send_rpc ~= nil and get_rpc ~= nil then
            send_rpc(get_rpc(RPC_NAMESPACE, rpc_name), ...)
        end
    end

    DeleteSingleSelection = function()
        local targets = self._manualcleanup_targets or {}
        local entry = targets[self._manualcleanup_target_index or 1]
        if entry ~= nil and entry.guid ~= nil then
            SwallowControls(
                GLOBAL.CONTROL_INSPECT,
                GLOBAL.CONTROL_OPEN_CRAFTING,
                GetGlobal("CONTROL_MENU_MISC_1"),
                GetGlobal("CONTROL_MENU_MISC_2"),
                GetGlobal("CONTROL_MENU_MISC_3"),
                GetGlobal("CONTROL_MENU_MISC_4"),
                GetGlobal("CONTROL_OPEN_DEBUG_MENU")
            )
            local target = entry.target
            local x, y, z
            if IsCleanupTarget(target, inst) and target.Transform ~= nil then
                x, y, z = target.Transform:GetWorldPosition()
            end
            SendCleanupRPC("RemoveSingle", entry.guid, entry.prefab, x, y, z)
            ExitCleanupMode(true)
        end
    end

    DeleteGroupSelection = function()
        local targets = self._manualcleanup_targets or {}
        local entry = targets[self._manualcleanup_target_index or 1]
        if entry ~= nil and type(entry.prefab) == "string" then
            SwallowControls(GLOBAL.CONTROL_CONTROLLER_ATTACK, GLOBAL.CONTROL_ATTACK, GLOBAL.CONTROL_FORCE_ATTACK)
            SendCleanupRPC("RemoveNearbyPrefab", entry.prefab)
            ExitCleanupMode(true)
        end
    end

    DeleteGlobalGroupSelection = function()
        local targets = self._manualcleanup_targets or {}
        local entry = targets[self._manualcleanup_target_index or 1]
        if entry ~= nil and type(entry.prefab) == "string" then
            SwallowControls(GLOBAL.CONTROL_CONTROLLER_ACTION, GLOBAL.CONTROL_ACCEPT, GLOBAL.CONTROL_ACTION)
            SendCleanupRPC("RemoveGlobalPrefab", entry.prefab)
            ExitCleanupMode(true)
        end
    end

    RestoreLastCleanup = function()
        SwallowControls(GLOBAL.CONTROL_CANCEL, GLOBAL.CONTROL_CONTROLLER_ALTACTION)
        SendCleanupRPC("RestoreLast")
        ExitCleanupMode(true)
    end

    local function HandleModeCancelControl(control, down)
        if self._manualcleanup_waiting_for_cancel_release then
            if not down then
                self._manualcleanup_waiting_for_cancel_release = nil
            end
            return true
        end

        if down then
            CancelModeCancelHoldTask()
            self._manualcleanup_cancel_hold_elapsed = false
            self._manualcleanup_cancel_hold_task = inst:DoTaskInTime(.5, function()
                self._manualcleanup_cancel_hold_task = nil
                self._manualcleanup_cancel_hold_elapsed = true
                RestoreLastCleanup()
            end)
        else
            local should_exit = self._manualcleanup_cancel_hold_task ~= nil
            CancelModeCancelHoldTask()
            self._manualcleanup_cancel_hold_elapsed = nil
            if should_exit then
                SwallowControls(control)
                ExitCleanupMode(true)
            end
        end
        return true
    end

    local function HandleCleanupControl(control, down)
        if IsSwallowingControl(control) then
            if not down then
                if self._manualcleanup_last_control_down ~= nil then
                    self._manualcleanup_last_control_down[control] = nil
                end
                if IsSingleDeleteControl(control) then
                    ClearSwallowedControls(
                        GLOBAL.CONTROL_INSPECT,
                        GLOBAL.CONTROL_OPEN_CRAFTING,
                        GetGlobal("CONTROL_MENU_MISC_1"),
                        GetGlobal("CONTROL_MENU_MISC_2"),
                        GetGlobal("CONTROL_MENU_MISC_3"),
                        GetGlobal("CONTROL_MENU_MISC_4"),
                        GetGlobal("CONTROL_OPEN_DEBUG_MENU")
                    )
                elseif IsAnyControl(control, GLOBAL.CONTROL_CONTROLLER_ATTACK, GLOBAL.CONTROL_ATTACK, GLOBAL.CONTROL_FORCE_ATTACK) then
                    ClearSwallowedControls(GLOBAL.CONTROL_CONTROLLER_ATTACK, GLOBAL.CONTROL_ATTACK, GLOBAL.CONTROL_FORCE_ATTACK)
                elseif IsAnyControl(control, GLOBAL.CONTROL_CONTROLLER_ACTION, GLOBAL.CONTROL_ACCEPT, GLOBAL.CONTROL_ACTION) then
                    ClearSwallowedControls(GLOBAL.CONTROL_CONTROLLER_ACTION, GLOBAL.CONTROL_ACCEPT, GLOBAL.CONTROL_ACTION)
                elseif IsCancelControl(control) or control == GLOBAL.CONTROL_PAUSE then
                    ClearSwallowedControls(GLOBAL.CONTROL_CANCEL, GLOBAL.CONTROL_CONTROLLER_ALTACTION, GLOBAL.CONTROL_PAUSE)
                else
                    ClearSwallowedControl(control)
                end
            end
            return true
        end

        if not down and self._manualcleanup_last_control_down ~= nil then
            self._manualcleanup_last_control_down[control] = nil
        end

        if self._manualcleanup_mode and self._manualcleanup_keyboard_mode == true then
            if control == GLOBAL.CONTROL_CANCEL or control == GLOBAL.CONTROL_PAUSE then
                return false
            elseif control == GLOBAL.CONTROL_ZOOM_IN or control == GLOBAL.CONTROL_ZOOM_OUT then
                if down and ChangeCleanupPage ~= nil and ShouldHandleControlPress(control) then
                    ChangeCleanupPage(control == GLOBAL.CONTROL_ZOOM_IN and -1 or 1)
                end
                return true
            end
            return false
        end

        if not TheInput:ControllerAttached() then
            if self._manualcleanup_mode and self._manualcleanup_keyboard_mode ~= true then
                ExitCleanupMode()
            elseif not self._manualcleanup_mode then
                self._manualcleanup_swallow_controls = nil
            end
            return false
        end

        if not self._manualcleanup_mode then
            if not ENABLE_CONTROLLER_UI then
                return false
            end
            if not IsCancelControl(control) then
                return false
            end

            local is_holding = self._manualcleanup_hold_task ~= nil or self._manualcleanup_hold_elapsed ~= nil
            local can_start = InGame()
                and IsLocalAdmin()
                and inst.HUD ~= nil
                and (not inst.HUD.IsControllerInventoryOpen or not inst.HUD:IsControllerInventoryOpen())

            if down and can_start then
                CancelHoldTask()
                self._manualcleanup_hold_elapsed = false
                self._manualcleanup_hold_task = inst:DoTaskInTime(.5, EnterCleanupMode)
                return true
            elseif not down and is_holding then
                local should_cancel = self._manualcleanup_hold_task ~= nil
                CancelHoldTask()
                self._manualcleanup_hold_elapsed = nil
                if should_cancel then
                    PlayerControllerOnControl(self, control, true)
                    PlayerControllerOnControl(self, control, false)
                end
                return true
            end
            return false
        elseif IsAnyControl(control, GLOBAL.CONTROL_MOVE_UP, GLOBAL.CONTROL_MOVE_DOWN, GLOBAL.CONTROL_MOVE_LEFT, GLOBAL.CONTROL_MOVE_RIGHT) then
            StopCleanupWalking()
            if down then
                local angle = GetControllerMoveAngle(control)
                if angle ~= nil then
                    SelectCleanupTargetByAngle(angle)
                end
            end
            return true
        elseif IsSingleDeleteControl(control) then
            if down and ShouldHandleControlPress(control) then
                DeleteSingleSelection()
            end
            return true
        elseif IsAnyControl(control, GLOBAL.CONTROL_CONTROLLER_ATTACK, GLOBAL.CONTROL_ATTACK, GLOBAL.CONTROL_FORCE_ATTACK) then
            if down and ShouldHandleControlPress(control) then
                DeleteGroupSelection()
            end
            return true
        elseif IsAnyControl(control, GLOBAL.CONTROL_CONTROLLER_ACTION, GLOBAL.CONTROL_ACCEPT, GLOBAL.CONTROL_ACTION) then
            if down and ShouldHandleControlPress(control) then
                DeleteGlobalGroupSelection()
            end
            return true
        elseif control == GLOBAL.CONTROL_ROTATE_LEFT then
            if down and ShouldHandleControlPress(control) then
                SwallowControls(GLOBAL.CONTROL_ROTATE_LEFT)
                ChangeCleanupPage(-1)
            end
            return true
        elseif control == GLOBAL.CONTROL_ROTATE_RIGHT then
            if down and ShouldHandleControlPress(control) then
                SwallowControls(GLOBAL.CONTROL_ROTATE_RIGHT)
                ChangeCleanupPage(1)
            end
            return true
        elseif IsCancelControl(control) then
            return HandleModeCancelControl(control, down)
        elseif control == GLOBAL.CONTROL_OPEN_INVENTORY
            or control == GLOBAL.CONTROL_MAP
            or control == GLOBAL.CONTROL_PAUSE then
            ExitCleanupMode()
            return true
        end

        return self._manualcleanup_mode == true
    end

    local function ShouldOpenMouseCleanup(control, down)
        return down
            and ENABLE_MOUSE_UI
            and not self._manualcleanup_mode
            and not TheInput:ControllerAttached()
            and control == GLOBAL.CONTROL_SECONDARY
            and InGame()
            and IsLocalAdmin()
            and TheInput:IsControlPressed(GLOBAL.CONTROL_FORCE_INSPECT)
            and TheInput:IsKeyDown(GLOBAL.KEY_SHIFT)
            and not TheInput:GetHUDEntityUnderMouse()
            and (TheInput.GetWorldEntityUnderMouse == nil or not TheInput:GetWorldEntityUnderMouse())
    end

    if TheInput.AddMouseWheelHandler ~= nil then
        TheInput:AddMouseWheelHandler(function(up)
            if self._manualcleanup_mode and self._manualcleanup_keyboard_mode == true and ChangeCleanupPage ~= nil then
                ChangeCleanupPage(up and -1 or 1)
                return true
            end
            return false
        end)
    end

    self.OnControl = function(self, control, down, ...)
        if HandleCleanupControl(control, down) then
            return true
        end
        if ShouldOpenMouseCleanup(control, down) then
            EnterCleanupMode(true)
            return true
        end
        return PlayerControllerOnControl(self, control, down, ...)
    end

    InstallCleanupWalkingBlocker()
    inst:DoTaskInTime(0, InstallCleanupWalkingBlocker)

    inst:ListenForEvent("onremove", function()
        ExitCleanupMode()
    end)
end)
