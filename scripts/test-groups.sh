#!/bin/bash
# 编译并运行分组核心逻辑的测试（直接用 App 里的 SwitchGroups.swift）。
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/group-tests"
swiftc -O FreeSwitch/Model/SwitchGroups.swift scripts/tests/main.swift -o "$out"
"$out"
