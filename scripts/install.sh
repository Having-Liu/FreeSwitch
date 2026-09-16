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
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

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

# pluginkit 按 bundle id 只认一份扩展。构建目录里的副本（Debug 和 Release 都算）
# 会把 /Applications 这份顶掉，于是控制中心用的根本不是你刚装的那个 —— 重装多少次都没用。
# 所以这里要把构建目录下的所有副本统统注销，一个不留。
# 注意有三个来源会抢：项目内 build/（Debug 和 Release 都算），以及在 Xcode 里
# 按 Run 时产生的 ~/Library/Developer/Xcode/DerivedData/FreeSwitch-*/。漏掉任何一个，
# 控制中心用的就不是你刚装的那份。
echo "▸ 注销所有构建目录里的扩展副本…"
while IFS= read -r p; do
    [ -n "$p" ] && pluginkit -r "$p" 2>/dev/null || true
done < <(find "$PWD/build" "$HOME/Library/Developer/Xcode/DerivedData" \
              -maxdepth 8 -name 'FreeSwitchControls.appex' 2>/dev/null)
rm -rf build/Build/Products/Debug

echo "▸ 重新登记控制中心扩展…"
pluginkit -r "$APP/$APPEX_REL" 2>/dev/null || true
sleep 1
pluginkit -a "$APP/$APPEX_REL"
# 只 -a 不够：新增的控件不会出现在控制中心的控件库里。还要显式标记启用，
# 并刷新 LaunchServices 对这个包的记录，chronod 才会重新扫描出新控件。
pluginkit -e use -i com.freeswitch.FreeSwitch.Controls 2>/dev/null || true
touch "$APP"
"$LSREGISTER" -f "$APP" 2>/dev/null || true

# 核对最终生效的到底是不是 /Applications 那份，不对就明说，别让它静悄悄地错下去。
WINNER=$(pluginkit -m -v -i com.freeswitch.FreeSwitch.Controls 2>/dev/null | awk '{print $NF}' | grep '\.appex$' | head -1)
echo "  生效的扩展：${WINNER:-（无）}"
case "$WINNER" in
    "$APP/$APPEX_REL") ;;
    *) echo "  ✗ 生效的不是 /Applications 那份！控制中心用的会是上面这个副本。" >&2 ;;
esac
# 控件的快照缓存归 chronod 管，只重启 ControlCenter 清不掉旧图标。
killall chronod 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

echo "▸ 启动…"
open -a "$APP"
echo "✓ 完成。控制中心里的控件若仍是旧样子，把它移除后重新添加一次。"
