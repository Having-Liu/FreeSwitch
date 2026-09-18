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
# App 在退出前用自己的身份清空并核对过的容器。本脚本没有 App 的 entitlement，
# 对这些路径只能报「看不了」，但 App 那边是真查过的，以它的结论为准。
VERIFIED=""
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

while [ $# -gt 0 ]; do
    case "$1" in
        -y)         ASSUME_YES=1 ;;
        --from-app) FROM_APP=1; ASSUME_YES=1 ;;
        --app-path) APP="$2"; shift ;;
        --repo)     REPO="$2"; shift ;;
        --verified-empty) VERIFIED="$VERIFIED$2"$'\n'; shift ;;
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

# 容器现在是什么状态：empty=只剩系统元数据、hasdata=还有东西、unreadable=看都看不了。
#
# 必须把「读不了」和「空的」分开。本脚本由 App 启动时继承的是 App 的身份，
# 却不带 App 的 entitlement——group 容器会连列目录都不允许。早先的写法把
# 「列不出东西」当成「里面是空的」，于是谎报成已清空，比不报还糟。
# 只数真正的文件，不数目录。容器根目录删不掉，而删空之后系统会把 Data/ 下那套标准骨架
# （Desktop、Documents、Library、Movies…几十个空目录）重新建出来——那是系统的脚手架，
# 不是我们的数据。按顶层条目判断会把这套骨架当成「还有数据」，白白吓用户一跳。
container_state() {
    if ! ls -A "$1" >/dev/null 2>&1; then echo unreadable; return; fi
    local n
    n=$(find "$1" -type f ! -name '.com.apple.containermanagerd.metadata.plist' 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" = 0 ] && echo empty || echo hasdata
}

# 里面的文件是不是控制中心写的控件占位快照。
# 实测过一次：卸载把扩展容器删干净了，13 分钟后它又出现，里面只有
# Data/SystemData/com.apple.chrono/… 下两个 lockKeyboard 的快照——
# 因为控制中心里还留着 FreeSwitch 的控件，用户一拉开控制中心，chronod 就照着占位重新渲染，
# 容器跟着被建回来。这种残留删多少次都会回来，得让用户去控制中心把控件撤掉。
has_chrono_leftover() {
    find "$1" -type f -path '*com.apple.chrono*' 2>/dev/null | grep -q . 
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
# 三类分开存，数组里只放路径——后面要用它 open -R，混进说明文字就不是路径了。
LEFT=()
SHELLS=()
UNSURE=()
for t in "$APP" "${TARGETS[@]}"; do
    [ -e "$t" ] || continue
    state=$(container_state "$t")
    # 看不了，但 App 退出前已经清空并核对过——采信它，别再报一条假的「卸载未完全」。
    if [ "$state" = unreadable ] && printf '%s' "$VERIFIED" | grep -qxF "$t"; then
        state=empty
    fi
    case "$state" in
        empty)      SHELLS+=("$t") ;;
        unreadable) UNSURE+=("$t") ;;
        *)          LEFT+=("$t") ;;
    esac
done
if defaults read "$BUNDLE" >/dev/null 2>&1; then
    LEFT+=("偏好设置域 $BUNDLE（仍可被读到）")
fi

# 三类一次报全。以前 UNSURE 一非空就提前 exit，把后面「空壳」那段整个吞掉，
# 用户只看到「无法确认」，不知道其余的到底清没清。
FAILED=0

if [ ${#LEFT[@]} -gt 0 ]; then
    FAILED=1
    say "✗ 以下 ${#LEFT[@]} 项没能清除："
    CHRONO=0
    for l in "${LEFT[@]}"; do
        say "  $l"
        [ -d "$l" ] && has_chrono_leftover "$l" && CHRONO=1
    done
    if [ "$CHRONO" = 1 ]; then
        say "  其中有控制中心写的控件占位快照——说明控制中心里还留着 FreeSwitch 的控件。"
        say "  请拉开控制中心，把 FreeSwitch 的控件长按移除，否则这个容器删掉还会再被建出来。"
    fi
fi

if [ ${#UNSURE[@]} -gt 0 ]; then
    FAILED=1
    say "⚠ 以下 ${#UNSURE[@]} 项没有权限查看，无法确认是否已清空："
    for u in "${UNSURE[@]}"; do say "  $u"; done
fi

if [ ${#SHELLS[@]} -gt 0 ]; then
    say "· 另有 ${#SHELLS[@]} 个空容器：数据已清干净，只剩一个由系统托管、App 删不掉的空壳。"
    for s in "${SHELLS[@]}"; do say "  $s"; done
fi

if [ "$FAILED" = 0 ]; then
    if [ ${#SHELLS[@]} -eq 0 ]; then
        say "✓ 已彻底卸载，没有任何残留。"
        NOTE="所有数据都已清除，没有残留。"
    else
        # 通知里不写「去访达手动删」：空壳是 0 个文件的系统托管目录，留着不影响任何东西，
        # 把它说成待办事项只会让用户以为卸载没做完。想连壳一起删的办法写在日志里就够了。
        NOTE="数据已全部清除。剩下 ${#SHELLS[@]} 个系统托管的空目录，里面什么都没有。"
        say "✓ 数据已全部清除。那 ${#SHELLS[@]} 个空壳留着无妨；一定要连壳删就在访达里移到废纸篓，或在终端运行 scripts/uninstall.sh。"
    fi
    [ "$FROM_APP" = 1 ] && osascript -e "display notification \"$NOTE\" with title \"FreeSwitch 已彻底卸载\"" >/dev/null 2>&1
    exit 0
fi

N=$(( ${#LEFT[@]} + ${#UNSURE[@]} ))
say "  在终端运行 scripts/uninstall.sh 可以彻底清掉它们（终端的权限够）。"
if [ "$FROM_APP" = 1 ]; then
    osascript -e "display notification \"有 $N 项没能自动清除，已在访达中标出。\" with title \"FreeSwitch 卸载未完全\"" >/dev/null 2>&1
    # bash 3.2 + set -u：展开空数组会报 unbound variable，所以两个数组各自判空再展开。
    [ ${#LEFT[@]} -gt 0 ]   && for l in "${LEFT[@]}";   do [ -e "$l" ] && open -R "$l"; done
    [ ${#UNSURE[@]} -gt 0 ] && for u in "${UNSURE[@]}"; do [ -e "$u" ] && open -R "$u"; done
fi
exit 1
