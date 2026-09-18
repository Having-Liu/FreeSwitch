#!/bin/bash
# FreeSwitch 彻底卸载 —— 唯一的一份实现。
#
# 两个入口共用它，免得两套逻辑各改各的、慢慢不一致（残留问题正是这么来的）：
#   - 设置窗口的「彻底卸载」按钮：App 把本脚本拷到临时目录，带 --from-app 运行，然后自己退出。
#   - 命令行：scripts/uninstall.sh 转调这里。
#
# 顺序和做法都是踩坑换来的，改之前先读这段：
#  1. 偏好设置必须等 App 进程退出后再删，并且用 `defaults delete`（经过 cfprefsd，连缓存一起清）。
#     App 还活着时删文件没用：退出时 AppKit 会写回设置窗口的位置，
#     cfprefsd 顺手把整个域都写了回去——曾实测在残留的偏好里看到了窗口位置那个键。
#  2. 删扩展的沙盒容器之前，先注销扩展、结束扩展进程、重启 chronod 和控制中心，
#     否则控制中心渲染已放置的控件时会把扩展重新拉起来，容器随之又被建出来。
#  3. 同一个容器，开发用的 shell 能删，由 App 发起的删除却静默失败（按容器的创建时间核对过：
#     不是删了又被重建，而是压根没删掉）。本脚本从 App 启动时继承 App 的身份，同样删不掉。
#     曾试过交给访达移废纸篓——实测访达同样没权限，还留下一个一直转的进度窗，比失败更糟。
#     现在的做法：删不掉根目录就清空里面的数据，只留一个不含任何内容的空壳，并如实报出来。
#  4. 后台项登记（sfltool dumpbtm 里的记录）不在这里处理：注销后它们只是停用的旧记录，
#     唯一的清除手段 `sfltool resetbtm` 会重置所有 App 的后台项授权，代价太大。
#
# 注意 macOS 自带的是 bash 3.2：`set -u` 下展开空数组会报 unbound variable，
# 所以遍历 LEFT 之前一定先判断它是否为空。

set -u

BUNDLE=com.freeswitch.FreeSwitch
EXT_ID=com.freeswitch.FreeSwitch.Controls
HELPER=com.freeswitch.FreeSwitch.helper
APP=/Applications/FreeSwitch.app
REPO=""
FROM_APP=0
ASSUME_YES=0
LIST_ONLY=0
REPORT=/tmp/FreeSwitch-uninstall.log
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

while [ $# -gt 0 ]; do
    case "$1" in
        -y)         ASSUME_YES=1 ;;
        --from-app) FROM_APP=1; ASSUME_YES=1 ;;
        --app-path) APP="$2"; shift ;;
        --repo)     REPO="$2"; shift ;;
        --list)     LIST_ONLY=1 ;;
    esac
    shift
done

# 要清除的数据。App 包单独处理（要先从 LaunchServices 注销）。
TARGETS=(
    "$HOME/Library/Preferences/$BUNDLE.plist"
    "$HOME/Library/Caches/$BUNDLE"
    "$HOME/Library/HTTPStorages/$BUNDLE"
    "$HOME/Library/Saved Application State/$BUNDLE.savedState"
    "$HOME/Library/Containers/$EXT_ID"
    "$HOME/Library/Group Containers/MXHBUQH27V.group.com.freeswitch.FreeSwitch"
    "$HOME/Library/Group Containers/group.com.freeswitch.FreeSwitch"
)

if [ "$LIST_ONLY" = 1 ]; then
    printf '%s\n' "$APP" "${TARGETS[@]}"
    exit 0
fi

: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }

if [ "$ASSUME_YES" != 1 ]; then
    echo "将要彻底删除 FreeSwitch 及其所有数据（设置、快捷键、控制中心控件登记）。"
    printf "确定继续？[y/N] "
    read -r reply
    [ "$reply" = "y" ] || [ "$reply" = "Y" ] || { echo "已取消。"; exit 0; }
fi

say "▸ 等待 FreeSwitch 退出…"
for _ in $(seq 1 50); do pgrep -x FreeSwitch >/dev/null || break; sleep 0.2; done
if pgrep -x FreeSwitch >/dev/null; then
    osascript -e 'quit app "FreeSwitch"' >/dev/null 2>&1
    sleep 1
    pkill -x FreeSwitch 2>/dev/null
fi

say "▸ 注销控制中心扩展，并防止它被重新拉起…"
pluginkit -r "$APP/Contents/PlugIns/FreeSwitchControls.appex" 2>/dev/null
pluginkit -m -v -i "$EXT_ID" 2>/dev/null | awk '{print $NF}' | grep '\.appex$' | while read -r p; do
    pluginkit -r "$p" 2>/dev/null
done
# 构建目录里的副本也会顶掉正式安装的那份：Xcode 的 DerivedData，以及从仓库运行时的 build/。
SEARCH=("$HOME/Library/Developer/Xcode/DerivedData")
[ -n "$REPO" ] && SEARCH+=("$REPO/build")
find "${SEARCH[@]}" -maxdepth 8 -name 'FreeSwitchControls.appex' 2>/dev/null | while read -r p; do
    pluginkit -r "$p" 2>/dev/null
done
pkill -f FreeSwitchControls 2>/dev/null
killall chronod ControlCenter 2>/dev/null
sleep 1

if [ "$FROM_APP" != 1 ]; then
    # 从 App 发起时，这两步已经在 App 进程里用 App 自己的身份做过了。
    say "▸ 移除特权助手、还原电源设置…"
    if launchctl print "system/$HELPER" >/dev/null 2>&1; then
        sudo launchctl bootout "system/$HELPER"
    fi
    if pmset -g | grep -q "SleepDisabled[[:space:]]*1"; then
        say "  「合盖也不休眠」仍开着，需要管理员密码来还原"
        sudo pmset -a disablesleep 0
    fi
fi

say "▸ 删除 App…"
"$LSREGISTER" -u "$APP" 2>/dev/null
rm -rf "$APP" 2>/dev/null

# 删一个路径。沙盒容器的根目录归 containermanagerd 管，由 App 发起的删除会被系统拒绝
# （同一个目录，开发用的 shell 却删得掉——差别在发起者的身份，不在文件权限）。
# 删不掉时退而求其次：把里面的数据清空，只留一个不含任何内容的空壳。
#
# 这里曾经改用访达移到废纸篓，实测同样没权限，而且会留下一个一直转的
# 「正在移到废纸篓」进度窗，比失败本身更糟。所以不再走访达。
remove_path() {
    rm -rf "$1" 2>/dev/null
    [ -e "$1" ] || return 0
    find "$1" -mindepth 1 -maxdepth 1 \
        ! -name '.com.apple.containermanagerd.metadata.plist' -exec rm -rf {} + 2>/dev/null
    return 1
}

# 里面除了系统自己的元数据什么都不剩 = 空壳，不含任何用户数据。
is_empty_shell() {
    [ -z "$(find "$1" -mindepth 1 -maxdepth 1 ! -name '.com.apple.containermanagerd.metadata.plist' 2>/dev/null)" ]
}

say "▸ 删除设置与数据…"
defaults delete "$BUNDLE" >/dev/null 2>&1
for t in "${TARGETS[@]}"; do
    remove_path "$t" || say "  根目录删不掉（系统托管），已清空其中数据：$t"
done

say "▸ 重置隐私授权…"
tccutil reset All "$BUNDLE" >/dev/null 2>&1
tccutil reset All "$EXT_ID" >/dev/null 2>&1

# 核对：分成「还留着数据」和「只剩系统托管的空壳」两类，如实报出来。
LEFT=()
SHELLS=()
for t in "$APP" "${TARGETS[@]}"; do
    [ -e "$t" ] || continue
    if is_empty_shell "$t"; then SHELLS+=("$t"); else LEFT+=("$t"); fi
done
if defaults read "$BUNDLE" >/dev/null 2>&1; then
    LEFT+=("偏好设置域 $BUNDLE（仍可被读到）")
fi

if [ ${#LEFT[@]} -eq 0 ]; then
    if [ ${#SHELLS[@]} -eq 0 ]; then
        say "✓ 已彻底卸载，没有任何残留。"
        NOTE="所有数据都已清除，没有残留。"
    else
        say "✓ 数据已全部清除。另有 ${#SHELLS[@]} 个由系统托管的空容器（里面什么都没有，App 的身份删不掉它）："
        for s in "${SHELLS[@]}"; do say "  $s"; done
        say "  想彻底删掉的话：在访达里手动移到废纸篓，或在终端运行 scripts/uninstall.sh（终端的权限够）。"
        NOTE="数据已全部清除；另有 ${#SHELLS[@]} 个空容器需要在访达里手动删除。"
    fi
    [ "$FROM_APP" = 1 ] && osascript -e "display notification \"$NOTE\" with title \"FreeSwitch 已彻底卸载\"" >/dev/null 2>&1
    exit 0
fi

say "✗ 以下 ${#LEFT[@]} 项没能清除："
for l in "${LEFT[@]}"; do say "  $l"; done
if [ "$FROM_APP" = 1 ]; then
    osascript -e "display notification \"有 ${#LEFT[@]} 项没能自动清除，已在访达中标出，按 ⌘⌫ 即可删除。\" with title \"FreeSwitch 卸载未完全\"" >/dev/null 2>&1
    for l in "${LEFT[@]}"; do
        [ -e "$l" ] && open -R "$l"
    done
fi
exit 1
