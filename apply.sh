#!/usr/bin/env bash
# 一键给 Parallels Tools 12.x 的 prl_mod.tar.gz 打上现代内核移植补丁
# 用法: ./apply.sh <原始 prl_mod.tar.gz> [输出目录]
# 示例: ./apply.sh /media/cdrom0/kmods/prl_mod.tar.gz
set -euo pipefail

PATCH_DIR=$(cd "$(dirname "$0")" && pwd)
PATCH="$PATCH_DIR/prl_mod-kernel-7.x.patch"

SRC=${1:?用法: $0 <原始 prl_mod.tar.gz> [输出目录]}
OUT=${2:-.}

[ -f "$SRC" ] || { echo "错误: 找不到 $SRC" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "错误: 找不到补丁文件 $PATCH" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/kmods"
tar xzf "$SRC" -C "$WORK/kmods"
# 光驱来源的文件是只读的，先放开权限再打补丁
chmod -R u+w "$WORK/kmods"

echo "== 应用补丁 =="
(cd "$WORK/kmods" && patch --dry-run -p1 < "$PATCH" >/dev/null \
	&& patch -s -p1 < "$PATCH")

echo "== 重新打包 =="
mkdir -p "$OUT"
(cd "$WORK/kmods" && tar czf "$OUT/prl_mod.tar.gz" .)

echo "完成: $OUT/prl_mod.tar.gz"
echo "下一步: 替换安装文件树中的 kmods/prl_mod.tar.gz 后执行  sudo ./install --install"
