#!/usr/bin/env bash
#
# 手动打 tag 的应急/备用脚本：从 pubspec.yaml 读取当前版本，按规则升版写回，
# 然后提交并创建 v<version> 标签。
#
# 正常发布流程不需要它：.github/workflows/release-please.yml 会在合并
# release PR 时自动升版并打 tag（由 Conventional Commits 驱动）。此脚本仅
# 用于本地手动打 tag，或 CI 异常时的人工兜底。
#
# 用法:
#   scripts/tag_release.sh [--push] [patch|minor|major|<x.y.z>]
#
#   默认行为是递增补丁号（patch），例如 1.3.2 -> 1.3.3。
#   --push 会在提交后推送当前分支与 tags。
#
# 版本号只以 pubspec.yaml 顶层的 `version:` 字段为准；设置页和 TV 关于页
# 通过 lib/app/app_version.dart 运行时读取同一个字段。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$ROOT_DIR/pubspec.yaml"

usage() {
  cat <<'EOF'
用法: scripts/tag_release.sh [--push] [patch|minor|major|<x.y.z>]

参数:
  patch    递增补丁号（默认），例如 1.3.2 -> 1.3.3
  minor    递增次版本号，例如 1.3.2 -> 1.4.0
  major    递增主版本号，例如 1.3.2 -> 2.0.0
  <x.y.z>  直接指定新版本号，例如 1.4.0

选项:
  --push   提交后推送当前分支与 tags
  -h|--help  显示帮助
EOF
}

BUMP="patch"
PUSH=false
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    patch | minor | major) BUMP="$arg" ;;
    [0-9]*.[0-9]*.[0-9]*) BUMP="$arg" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

current="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$PUBSPEC" | head -n 1)"
if [[ -z "$current" || ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "无法从 $PUBSPEC 解析当前版本（当前值: '${current:-空}'）" >&2
  exit 1
fi

major="${current%%.*}"
rest="${current#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
patch="${patch%%+*}" # 丢弃 +build 后缀，tag 只使用语义化版本

new_version=""
case "$BUMP" in
  patch) new_version="$major.$minor.$((patch + 1))" ;;
  minor) new_version="$major.$((minor + 1)).0" ;;
  major) new_version="$((major + 1)).0.0" ;;
  *) new_version="$BUMP" ;;
esac

if [[ "$new_version" == "$current" ]]; then
  echo "新版本与当前版本相同（$current），无需升版。" >&2
  exit 1
fi

echo "当前版本: $current"
echo "新版本:   $new_version"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain -- pubspec.yaml)" ]]; then
  echo "警告: pubspec.yaml 存在未提交的改动，将随本次提交一并记录。" >&2
fi

# 只更新顶层 version: 行（BSD/GNU sed 兼容）。
sed -i.bak "s/^version:[[:space:]]*[^[:space:]]*/version: $new_version/" "$PUBSPEC"
rm -f "$PUBSPEC.bak"

git -C "$ROOT_DIR" add pubspec.yaml
git -C "$ROOT_DIR" commit -m "chore: bump version to $new_version"
git -C "$ROOT_DIR" tag -a "v$new_version" -m "Release v$new_version"

echo "已提交并创建标签 v$new_version"

if $PUSH; then
  branch="$(git -C "$ROOT_DIR" branch --show-current)"
  git -C "$ROOT_DIR" push origin "$branch" --tags
  echo "已推送分支 $branch 与标签 v$new_version"
fi
