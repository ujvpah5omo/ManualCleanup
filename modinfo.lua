local L = locale ~= "zh" and locale ~= "zhr" and locale ~= "zht"
name = L and "Manual Cleanup" or "手动清理"
author = "鲸"
version = "1.0.7"
description = [[
管理员专用的手动清理工具。

手柄操作：
长按 B 进入清理模式，方向键/摇杆选择目标，左右旋转键翻页。
Y 删除一个，X 删除附近同类，A 删除全世界同类。
清理模式内短按 B 退出，长按 B 恢复上次删除。

键鼠操作：
管理员按住 Alt + Shift，再右键地面或目标打开清理面板。
鼠标点选目标后点击按钮操作，鼠标滚轮或按钮翻页，删除按钮需要二次确认。
点击取消按钮关闭面板。

清理对象会过滤玩家、建筑、容器、背包、复活台、绚丽之门、阿比盖尔等保护目标。
恢复上次会按 prefab 和坐标重建上一批清理对象，堆叠、耐久等基础状态会尽量恢复，容器内容等复杂状态无法保证。

]]
forumthread = ""
api_version = 10
priority = 1

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
all_clients_require_mod = false
client_only_mod = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = { "手动", "清除", "清理", "clear", "clean" } --服务器标签
