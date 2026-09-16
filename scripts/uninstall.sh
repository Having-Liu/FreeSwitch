#!/bin/bash
# 彻底卸载 FreeSwitch —— 把 App、控制中心扩展、特权助手、登录项、
# 偏好、沙盒容器、以及控制中心的控件快照缓存全部清干净。
#
# 想从零干净地重装（尤其是调控制中心控件）时，先跑这个再跑 install.sh。
# 单独删 /Applications/FreeSwitch.app 是不够的：pluginkit 的扩展登记、
# chronod 缓存的控件快照、sfltool 里的后台项都会留下来继续捣乱。

set -u

APP=/Applications/FreeSwitch.app
BUNDLE=com.freeswitch.FreeSwitch
EXT_ID=com.freeswitch.FreeSwitch.Controls
# macOS 的 App Group 要带 Team ID 前缀；早期版本用过不带前缀的写法，一并清掉。
GROUPS=(MXHBUQH27V.group.com.freeswitch.FreeSwitch group.com.freeswitch.FreeSwitch)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "${1:-}" != "-y" ]; then
    echo "将要彻底删除 FreeSwitch 及其所有数据（设置、快捷键、控制中心控件登记）。"
    printf "确定继续？[y/N] "
    read -r reply
    [ "$reply" = "y" ] || [ "$reply" = "Y" ] || { echo "已取消。"; exit 0; }
fi

echo "▸ 退出进程…"
osascript -e 'quit app "FreeSwitch"' 2>/dev/null || true
pkill -f FreeSwitchControls 2>/dev/null || true
pkill -f FreeSwitchHelper 2>/dev/null || true
sleep 1

echo "▸ 注销控制中心扩展（所有副本，含构建目录里的残留）…"
# pluginkit 按 bundle id 只认一份，残留副本会顶掉正主，所以要全部找出来注销。
while read -r path; do
    [ -n "$path" ] && pluginkit -r "$path" 2>/dev/null || true
done < <(pluginkit -m -v -i "$EXT_ID" 2>/dev/null | awk '{print $NF}' | grep '\.appex$')
# 本项目构建目录里的副本也一并清掉。
find "$(dirname "$0")/../build" -name 'FreeSwitchControls.appex' -maxdepth 6 2>/dev/null | while read -r p; do
    pluginkit -r "$p" 2>/dev/null || true
done

echo "▸ 注销特权助手与登录项…"
launchctl bootout system/com.freeswitch.FreeSwitch.helper 2>/dev/null || true
if [ -e /Library/LaunchDaemons/com.freeswitch.FreeSwitch.helper.plist ]; then
    sudo rm -f /Library/LaunchDaemons/com.freeswitch.FreeSwitch.helper.plist
fi

echo "▸ 删除 App…"
"$LSREGISTER" -u "$APP" 2>/dev/null || true
rm -rf "$APP"

echo "▸ 删除用户数据…"
defaults delete "$BUNDLE" 2>/dev/null || true
rm -f  ~/Library/Preferences/"$BUNDLE".plist
rm -f  ~/Library/Preferences/"$EXT_ID".plist
rm -rf ~/Library/Caches/"$BUNDLE" ~/Library/Caches/"$EXT_ID"
rm -rf ~/Library/HTTPStorages/"$BUNDLE"
rm -rf ~/Library/"Saved Application State"/"$BUNDLE".savedState
for g in "${GROUPS[@]}"; do rm -rf ~/Library/"Group Containers"/"$g"; done
rm -rf ~/Library/Containers/"$EXT_ID"

echo "▸ 恢复被改过的系统设置…"
# 「合盖也不休眠」用的是 pmset disablesleep，卸载前必须还原，否则合盖永不休眠。
if pmset -g | grep -q "SleepDisabled[[:space:]]*1"; then
    echo "  （检测到 SleepDisabled=1，需要管理员密码来还原）"
    sudo pmset -a disablesleep 0
fi

echo "▸ 重置隐私授权（辅助功能 / 自动化 / 蓝牙）…"
tccutil reset All "$BUNDLE" 2>/dev/null || true
tccutil reset All "$EXT_ID" 2>/dev/null || true

echo "▸ 清控制中心的控件快照缓存…"
# 只 killall ControlCenter 不够 —— 控件快照归 chronod 管，旧图标会一直画在那儿。
killall chronod 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

echo
echo "✓ 清理完成。剩下的手工一步："
echo "  «系统设置 › 通用 › 登录项与扩展»，若「后台 App 活动」里还留着 FreeSwitch，把它删掉。"
echo "  控制中心里若还留着旧控件占位，进入编辑控件把它们移除。"
