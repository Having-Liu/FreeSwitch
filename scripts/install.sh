#!/bin/bash
# 构建并安装 FreeSwitch 到 /Applications。
#
# 必须用 Release：Debug 构建会把扩展的真实代码拆进单独的 .debug.dylib，
# 主二进制只剩一个桩。系统拉不起这样的沙盒扩展，于是控制中心里
# 「带状态的开关」渲染不出图标，只显示 app.dashed 占位图
# （按钮类不跑代码所以看着正常，很容易误判成图标写错了）。

set -euo pipefail
cd "$(dirname "$0")/.."

APP=/Applications/FreeSwitch.app
APPEX_REL=Contents/PlugIns/FreeSwitchControls.appex

echo "▸ 构建 Release…"
xcodebuild -project FreeSwitch.xcodeproj -scheme FreeSwitch \
    -configuration Release -derivedDataPath build build >/dev/null

BUILT=build/Build/Products/Release/FreeSwitch.app

# 兜底检查：万一哪天设置被改回去，这里能第一时间发现。
if [ -e "$BUILT/$APPEX_REL/Contents/MacOS/FreeSwitchControls.debug.dylib" ]; then
    echo "✗ 扩展里出现了 debug dylib，控制中心的开关会渲染不出来。请确认是 Release 构建。" >&2
    exit 1
fi

echo "▸ 替换 $APP…"
osascript -e 'quit app "FreeSwitch"' 2>/dev/null || true
pkill -f FreeSwitchControls 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R "$BUILT" "$APP"

# pluginkit 按 bundle id 只认一份扩展。构建目录里残留的 Debug 包会把
# /Applications 这份顶掉，于是控制中心用的一直是那个跑不起来的桩 —— 重装多少次都没用。
echo "▸ 清掉构建目录里的 Debug 扩展…"
DEBUG_APPEX="$PWD/build/Build/Products/Debug/FreeSwitch.app/$APPEX_REL"
[ -e "$DEBUG_APPEX" ] && pluginkit -r "$DEBUG_APPEX" 2>/dev/null || true
rm -rf build/Build/Products/Debug

echo "▸ 重新登记控制中心扩展…"
pluginkit -r "$APP/$APPEX_REL" 2>/dev/null || true
pluginkit -a "$APP/$APPEX_REL"
pluginkit -m -v -i com.freeswitch.FreeSwitch.Controls
killall ControlCenter 2>/dev/null || true

echo "▸ 启动…"
open -a "$APP"
echo "✓ 完成。控制中心里的控件若仍是旧样子，把它移除后重新添加一次。"
