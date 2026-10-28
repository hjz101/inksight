#!/usr/bin/env bash
# 禁词扫描 · 墨见 InkSight · v2
# 设计原则（来自架构评审）：**脚本出数、人审排除项**。
#   - 脚本负责"数"，并**输出被排除的清单**（逐文件逐行号），使排除过程可复核；
#   - 人负责"判断"：审核排除清单是否合理，而不是自己数数。
#   - 反型错误：把脚本结论当成人工判断的替代。
#
# 用法：./scripts/scan-banned-terms.sh [目录，默认 deliverables]
# 退出码：0 = 未排除命中为 0；1 = 存在未排除命中

set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

WORDS=(
  "书源" "换源" "多源" "源站" "订阅源" "书源规则"
  "聚合" "全网" "海量" "百万书库"
  "免费" "省钱" "正版平替"
  "全本" "全集" "完本" "完结" "最新章节" "追更" "更新提醒" "补章" "精校"
  "去广告" "去水印" "净化" "纯净版" "破解" "解锁"
  "授权"
)

# 文件级 allowlist：整份文档即元提及（合规台账 / 禁词表本体 / 归档稿）
FILE_ALLOW='DESIGN-archive/|禁词与文案合规检查表|行业合规与风险意见书|元数据与提审合规清单'
# 行级 allowlist：该行本身是"元提及"（列举禁词、写禁止项、写自查结论）
LINE_ALLOW='禁词|禁止|不得出现|不得写|命中|自查|allowlist|替换|已作废|删除；|一律删除'

echo "== 禁词扫描 v2 =="
echo "范围: ${ROOT}/*.md   时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo

ALLOWED=0
HIT=0
HITLINES=""

for w in "${WORDS[@]}"; do
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f="${line%%:*}"
    rest="${line#*:}"
    ln="${rest%%:*}"
    content="${rest#*:}"
    if printf '%s' "$f" | grep -qE "$FILE_ALLOW" || printf '%s' "$content" | grep -qE "$LINE_ALLOW"; then
      ALLOWED=$((ALLOWED+1))
      echo "  [排除] ${f#$ROOT/}:$ln  ($w)"
    else
      HIT=$((HIT+1))
      HITLINES="${HITLINES}${f#$ROOT/}:$ln  ($w)  ${content:0:80}\n"
      echo "  [命中] ${f#$ROOT/}:$ln  ($w)"
    fi
  done < <(grep -rn --include='*.md' -F "$w" "$ROOT" 2>/dev/null)
done

echo
echo "---- 汇总 ----"
echo "排除（元提及，需人工复核是否合理）: ${ALLOWED}"
echo "命中（未排除）: ${HIT}"
if [ "$HIT" -gt 0 ]; then
  echo
  echo "未排除命中明细："
  printf "%b" "$HITLINES"
  exit 1
fi
exit 0
