local L = locale ~= "zh" and locale ~= "zhr" and locale ~= "zht"
name = L and "Manual Cleanup" or "手动清理"
author = "鲸"
version = "1.0.3"
description = [[
在mod目录下创建黑名单文件 blacklist.txt 和白名单文件 whitelist.txt
在黑名单中添加批量清理的物品，也可以控制台指定清理的物品，在白名单中添加不清理的物品
指定清理的物品在白名单内时，执行两次命令将会进行清理操作
控制台执行 DoRemoveList()清理黑名单中且不在白名单的物品
控制台执行 DoRemove("name")清理指定物品
控制台执行 DoRemoveMatch("name")清理指定的匹配名称的物品
批量清理的物品一定是可以库存(可以被收纳)且没有被收纳的，比如没有放在包包里和箱子里也没有打包的
指定清理的物品一定是可见的物品，在包包内和包裹内的不被清理
指定清理的物品没有限制，可以是生物、地面物品、可拾取物品
白名单可以使用关键字匹配，黑名单和指定删除的物品必须精确匹配名称
黑白名单文件每行只有一个物品名称，按逗号分割字符串，取第一个值，所以逗号之后可以写注释

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
