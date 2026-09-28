local is_chinese = locale == "zh" or locale == "zhr" or locale == "zht"

local function T(en, zh)
    return is_chinese and zh or en
end

name = T("Manual Cleanup", "手动清理")
author = "鲸"
version = "1.0.9"
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

Admins can open a selection UI and remove one target, nearby targets of the same prefab, or all matching targets in the world. The last cleanup operation can be restored.

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
- Hold Alt + Shift, then right-click the ground or a target to open the cleanup panel.
- Click a target to select it, then click an action button.
- Use the mouse wheel or page buttons to change pages.
- Delete buttons require a second click to confirm.
- Click Cancel to close the panel.

Protected targets such as players, structures, containers, backpacks, resurrection stones, the Florid Postern, Abigail, and other protected objects are filtered out.

Restore tries to rebuild the previous cleanup batch by prefab and position, including basic state such as stack size and durability where possible. Complex state such as container contents is not guaranteed.
]], [[
管理员专用的饥荒联机版服务器清理工具。

管理员可以打开选择界面，删除单个目标、附近同类目标，或全世界同类目标。支持恢复上一次清理操作。

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
- 管理员按住 Alt + Shift，再右键地面或目标打开清理面板。
- 鼠标点选目标后点击按钮操作。
- 鼠标滚轮或翻页按钮翻页。
- 删除按钮需要二次确认。
- 点击取消按钮关闭面板。

清理对象会过滤玩家、建筑、容器、背包、复活台、绚丽之门、阿比盖尔等保护目标。

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
            "Allow admins to open the cleanup panel with Alt + Shift + right-click.",
            "允许管理员按 Alt + Shift + 右键打开清理面板。"
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
            "How far the cleanup UI searches for selectable targets. Nearby same-prefab deletion uses the same range.",
            "清理界面搜索可选目标的范围，附近同类删除也使用同一范围。"
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
