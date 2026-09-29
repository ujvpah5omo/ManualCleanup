local is_chinese = locale == "zh" or locale == "zhr" or locale == "zht"

local function T(en, zh)
    return is_chinese and zh or en
end

name = T("Manual Cleanup", "手动清理")
author = "鲸"
version = "1.0.11"
forumthread = "https://steamcommunity.com/sharedfiles/filedetails/?id=3008351689"

api_version = 10
api_version_dst = 10
priority = 1

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false
forge_compatible = false
gorge_compatible = false

all_clients_require_mod = true
client_only_mod = false
server_only_mod = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = {
    "manual",
    "cleanup",
    "clean",
    "admin",
    "手动",
    "清理",
    "清除",
    "管理员",
}

description = T([[
Admin-only cleanup tool for Don't Starve Together servers.

Admins can open a selection UI and remove dropped inventory items, nearby dropped items of the same prefab, or all matching dropped items in the world. The last cleanup operation can be restored.

Controller:
- Hold B to enter cleanup mode.
- Use the D-pad or stick to select a target.
- Rotate left/right to change pages.
- Y removes one target.
- X removes nearby targets of the same prefab.
- A removes all matching targets in the world.
- Tap B to exit cleanup mode.
- Hold B while in cleanup mode to restore the last cleanup.

Keyboard and mouse:
- Hold Alt + Shift, then right-click empty space to open the cleanup panel.
- Click a target to select it, then click an action button.
- Use the mouse wheel or page buttons to change pages.
- Delete buttons require a second click to confirm.
- Click Cancel to close the panel.

Only visible dropped items that can be stored in an inventory are selectable. Held items, items inside containers, containers/backpacks themselves, players, structures, resurrection stones, the Florid Postern, Abigail, and other protected objects are filtered out.

Restore tries to rebuild the previous cleanup batch by prefab and position, including basic state such as stack size and durability where possible. Complex state such as container contents is not guaranteed.
]], [[
管理员专用的饥荒联机版服务器清理工具。

管理员可以打开选择界面，删除掉在地上的可库存物品、附近同类掉落物，或全世界同类掉落物。支持恢复上一次清理操作。

手柄操作：
- 长按 B 进入清理模式。
- 方向键 / 摇杆选择目标。
- 左右旋转键翻页。
- Y 删除一个目标。
- X 删除附近同类目标。
- A 删除全世界同类目标。
- 短按 B 退出清理模式。
- 清理模式内长按 B 恢复上次删除。

键鼠操作：
- 管理员按住 Alt + Shift，再右键点击空白处打开清理面板。
- 鼠标点选目标后点击按钮操作。
- 鼠标滚轮或翻页按钮翻页。
- 删除按钮需要二次确认。
- 点击取消按钮关闭面板。

只有可视范围内、掉在地上、可放入库存的物品会作为清理目标。身上、包里、箱子里的物品，以及容器/背包本体、玩家、建筑、复活台、绚丽之门、阿比盖尔等保护目标都会被过滤。

恢复上次会按 prefab 和坐标重建上一批清理对象，并尽量恢复堆叠、耐久等基础状态。容器内容等复杂状态无法保证。
]])

local boolean_options = {
    { description = T("Enabled", "开启"), data = true },
    { description = T("Disabled", "关闭"), data = false },
}

configuration_options = {
    {
        name = "enable_mouse_ui",
        label = T("Keyboard / Mouse Panel", "键鼠清理面板"),
        hover = T(
            "Allow admins to open the cleanup panel with Alt + Shift + right-click on empty space.",
            "允许管理员按 Alt + Shift + 右键点击空白处打开清理面板。"
        ),
        options = boolean_options,
        default = true,
    },
    {
        name = "enable_controller_ui",
        label = T("Controller Cleanup Mode", "手柄清理模式"),
        hover = T(
            "Allow admins to hold B on a controller to enter cleanup mode.",
            "允许管理员使用手柄长按 B 进入清理模式。"
        ),
        options = boolean_options,
        default = true,
    },
    {
        name = "cleanup_range",
        label = T("Scan Range", "扫描范围"),
        hover = T(
            "Maximum search radius for selectable targets. The panel only shows targets that are also visible on screen. Nearby same-prefab deletion uses this range.",
            "可选目标的最大搜索半径。面板只显示当前屏幕可见的目标；附近同类删除也使用同一范围。"
        ),
        options = {
            { description = T("40 - Small", "40 - 小"), data = 40 },
            { description = T("60 - Medium", "60 - 中"), data = 60 },
            { description = T("80 - Default", "80 - 默认"), data = 80 },
            { description = T("120 - Large", "120 - 大"), data = 120 },
            { description = T("160 - Very Large", "160 - 很大"), data = 160 },
        },
        default = 80,
    },
}
