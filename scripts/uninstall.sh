#!/bin/bash
# 彻底卸载 FreeSwitch —— 命令行入口。
#
# 真正的卸载逻辑在 FreeSwitch/Support/uninstall.sh。设置窗口里的「彻底卸载」按钮
# 跑的也是那一份（随 App 打包）。两个入口共用一套实现，不再各写各的：
# 此前两套并存、慢慢改得不一致，正是卸载后留下残留的原因之一。
#
# 用法：./scripts/uninstall.sh [-y] [--list]
#   -y      不再询问确认
#   --list  只列出会删除的路径，不做任何改动
here="$(cd "$(dirname "$0")/.." && pwd)"
exec /bin/bash "$here/FreeSwitch/Support/uninstall.sh" --repo "$here" "$@"
