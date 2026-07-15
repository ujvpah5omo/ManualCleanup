local TheNet = GLOBAL.TheNet
local lang = TheNet:GetDefaultServerLanguage()
local io = GLOBAL.io

local lightbulb = "󰀏"

local whitelist = {
    "book",                     --奶奶的书(关键词)
    "mooneye",                  --月眼(关键词)
    "saddle",                   --鞍(关键词)
    "powcake",                  --芝士蛋糕(关键词)
    "waxwelljournal",           --老麦的书
    "fireflies",                --萤火虫
    "slurper",                  --啜食者
    "pumpkin_lantern",          --南瓜灯
    "bullkelp_beachedroot",     --海带
    "driftwood_log",            --浮木桩
    "panflute",                 --排箫
    "skeletonhat",              --骨盔
    "armorskeleton",            --骨甲
    "thurible",                 --香炉
    "fossil_piece",             --化石碎片
    "shadowheart",              --心脏
    "amulet",                   --生命护符
    "reviver",                  --救赎之心
    "heatrock",                 --暖石
    "dug_trap_starfish",        --挖起的海星
    "yellowstaff",              --唤星法杖
    "opalstaff",                --喚月法杖
    "cane",                     --步行手杖
    "orangestaff",              --瞬移手杖
    "glommerfuel",              --格罗姆燃料
    "lureplantbulb",            --食人花种子
    "tentaclespots",            --触手皮
    "hivehat",                  --蜂王帽
    "tentaclespike",            --狼牙棒
    "nightsword",               --影刀
    "armor_sanity",             --影甲
    "tacklecontainer",          --钓具箱
    "supertacklecontainer",     --超级钓具箱
    "singingshell_octave",      --贝壳钟(关键词 有3 4 5)
}

local blacklist = {
    "spoiled_food",             --腐烂食物
}

local whitetag = {
    "smallcreature",           --鸟、兔子、鼹鼠
    "irreplaceable",           --可疑的大理石、远古钥匙、眼骨、星空、天体灵球、格罗姆花
    "heavy",                   --雕像
    "backpack",                --背包、小猪包、小偷包
    "bundle",                  --包裹、礼物
    "deerantler",              --鹿角
    "trap",                    --陷阱、狗牙陷阱、海星
}

function string_split(str, reps)
    local strlist = {}
    string.gsub(str,'[^'..reps..']+',function ( w ) strlist[#strlist + 1] = w end)
    return strlist
end

local readtxt,err = io.open(MODROOT.."/whitelist.txt", "r")
if not err then
	for line in readtxt:lines() do
		local tokens = string_split(line, ',')
		table.insert(whitelist,tokens[1])
		print('Whitelist Add:', tokens[1])
	end
end

local readtxt,err = io.open(MODROOT.."/blacklist.txt", "r")
if not err then
	for line in readtxt:lines() do
		local tokens = string_split(line, ',')
		table.insert(blacklist,tokens[1])
		print('Blacklist Add:', tokens[1])
	end
end

local function isWhitelist(name)
    for k,v in pairs(whitelist) do
        if(string.find(name, v)) then
            return true
        end
    end
    return false
end

local function isBlacklist(name)
    for k,v in pairs(blacklist) do
        if(name == v) then
            return true
        end
    end
    return false
end

local function isWhiteTag(fabs)
    for k,v in pairs(whitetag) do
        if fabs:HasTag(v) then
            return true
        end
    end
    return false
end

local function RemoveItem(inst)
	if inst.components.health ~= nil and not inst:HasTag("wall") then
		if inst.components.lootdropper ~= nil then
			inst.components.lootdropper.DropLoot = function(pt) end
		end
		inst.components.health:SetPercent(0)
	else
		inst:Remove()
	end
end


local function DoRemoveList()
    local list = {}
    for k,v in pairs(GLOBAL.Ents) do
        if v.components.inventoryitem and v.components.inventoryitem.owner == nil then
            if  not isWhitelist(v.prefab) and not isWhiteTag(v)  and isBlacklist(v.prefab) then
				local numm = list[v.name.."  "..v.prefab]
				if numm == nil then
					list[v.name.."  "..v.prefab] = 1
				else
					numm = numm + 1
					list[v.name.."  "..v.prefab] = numm
				end
				RemoveItem(v)
            end
        end
    end
    
    --如果list为空就不宣告
    if GLOBAL.next(list) ~= nil then
        for k,v in pairs(list) do
            print("wiped", v, k)
			TheNet:Announce(string.format("清理了   %d    %s", v, k))
        end
    end
	print("Wiping Done!")
	if not GLOBAL.TheShard:IsSecondary() then
		if lang == "zh" then
			TheNet:Announce(lightbulb.."服务器清理完毕"..lightbulb)
		else
			TheNet:Announce(lightbulb.."Server Cleaning Done"..lightbulb)
		end
	end
end


local function DoRemove(name)
    local list = {}
	if not name or name == "" then return end
    for k,v in pairs(GLOBAL.Ents) do
        if not v.inlimbo then
			if (v.prefab and v.prefab == name) then
				if isWhitelist(v.prefab) or isWhiteTag(v) then
					if v:HasTag("RemoveCountOne") then
						RemoveItem(v)
						local numm = list[v.name.."  "..v.prefab]
						if numm == nil then
							list[v.name.."  "..v.prefab] = 1
						else
							numm = numm + 1
							list[v.name.."  "..v.prefab] = numm
						end
					else
						v:AddTag("RemoveCountOne")
					end
				else
					RemoveItem(v)
					local numm = list[v.name.."  "..v.prefab]
					if numm == nil then
						list[v.name.."  "..v.prefab] = 1
					else
						numm = numm + 1
						list[v.name.."  "..v.prefab] = numm
					end
				end
			end
        end
    end
	if isWhitelist(name) then
		TheNet:Announce(string.format("白名单物品执行两次将确认删除 %s", name))
	end

    
    --如果list为空就不宣告
    if GLOBAL.next(list) ~= nil then
        for k,v in pairs(list) do
            print("wiped", v, k)
			TheNet:Announce(string.format("清理了   %d    %s", v, k))
        end
    end
	print("Wiping Done!")
	if not GLOBAL.TheShard:IsSecondary() then
		if lang == "zh" then
			TheNet:Announce(lightbulb.."服务器清理完毕"..lightbulb)
		else
			TheNet:Announce(lightbulb.."Server Cleaning Done"..lightbulb)
		end
	end
end


local function DoRemoveMatch(name)
    local list = {}
	if not name or name == "" then return end
    for k,v in pairs(GLOBAL.Ents) do
        if not v.inlimbo then
			if (v.prefab and string.find(v.prefab,name)) then
				if isWhitelist(v.prefab) or isWhiteTag(v) then
					if v:HasTag("RemoveCountOne") then
						RemoveItem(v)
						local numm = list[v.name.."  "..v.prefab]
						if numm == nil then
							list[v.name.."  "..v.prefab] = 1
						else
							numm = numm + 1
							list[v.name.."  "..v.prefab] = numm
						end
					else
						v:AddTag("RemoveCountOne")
					end
				else
					RemoveItem(v)
					local numm = list[v.name.."  "..v.prefab]
					if numm == nil then
						list[v.name.."  "..v.prefab] = 1
					else
						numm = numm + 1
						list[v.name.."  "..v.prefab] = numm
					end
				end
			end
        end
    end
	if isWhitelist(name) then
		TheNet:Announce(string.format("白名单物品执行两次将确认删除 %s", name))
	end

    
    --如果list为空就不宣告
    if GLOBAL.next(list) ~= nil then
        for k,v in pairs(list) do
            print("wiped", v, k)
			TheNet:Announce(string.format("清理了   %d    %s", v, k))
        end
    end
	print("Wiping Done!")
	if not GLOBAL.TheShard:IsSecondary() then
		if lang == "zh" then
			TheNet:Announce(lightbulb.."服务器清理完毕"..lightbulb)
		else
			TheNet:Announce(lightbulb.."Server Cleaning Done"..lightbulb)
		end
	end
end

--添加手动清理的功能
GLOBAL.DoRemoveList = DoRemoveList
GLOBAL.DoRemove = DoRemove
GLOBAL.DoRemoveMatch = DoRemoveMatch



