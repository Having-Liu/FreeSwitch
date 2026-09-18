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
# 换包之前必须先停 chronod：它是负责拉起控件扩展的那个进程。
# 原来只 pkill 扩展、而 killall chronod 放在最后，中间留了个窗口——
# 扩展刚被杀，chronod 立刻把它拉起来，紧接着 rm -rf 把它的可执行文件抽走。
# ~/Library/Logs/DiagnosticReports 里那一批 FreeSwitchControls 崩溃报告（存活 3～43 秒不等、
# 父进程都是 launchd、栈顶是 ExtensionFoundation 启动握手里的断言）多半就是这么来的。
# 说“多半”是因为没复现成功：单独跑 pluginkit 登记、单独 killall 宿主，都没能再触发。
killall chronod 2>/dev/null || true
pkill -f FreeSwitchControls 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -f FreeSwitchControls >/dev/null || break; sleep 0.2; done
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

# 顺序要紧：lsregister -f 会重置这个包的插件登记，所以必须放在 pluginkit 登记之前。
# 放后面的话，刚登记好的扩展会被它清掉。
echo "▸ 刷新 LaunchServices 对这个包的记录…"
touch "$APP"
"$LSREGISTER" -f "$APP" 2>/dev/null || true
sleep 1

echo "▸ 重新登记控制中心扩展…"
pluginkit -r "$APP/$APPEX_REL" 2>/dev/null || true
sleep 1
pluginkit -a "$APP/$APPEX_REL"
# 只 -a 不够：新增的控件不会出现在控制中心的控件库里，还要显式标记启用，
# chronod 才会重新扫描出新控件。
pluginkit -e use -i com.freeswitch.FreeSwitch.Controls 2>/dev/null || true
sleep 1

# 核对最终生效的到底是不是 /Applications 那份，不对就明说，别让它静悄悄地错下去。
# 末尾的 || true 不能省：查不到时 grep 返回 1，在 set -euo pipefail 下会让整个脚本中断。
WINNER=$(pluginkit -m -v -i com.freeswitch.FreeSwitch.Controls 2>/dev/null | awk '{print $NF}' | grep '\.appex$' | head -1 || true)
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
