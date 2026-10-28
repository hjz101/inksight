#!/usr/bin/env bash
# 跨文档一致性检查器 · 墨见 InkSight
# 用途：一次跑完，核验「同一件事在各文档里说的是同一句话」。
# 判据来源：交付决策台账 D-21/D-26/D-32/D-38/D-39/D-40/D-42/D-43
# 输出：PASS/FAIL 逐条列出；任何 FAIL 都意味着口径漂移。
set -uo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO="$D/prototype/index.html"
PRD="$D/PRD-墨见InkSight.md"
DES="$D/DESIGN-液态玻璃设计系统与页面规范-v1.9.md"
LEDGER="$D/交付决策台账-墨见InkSight.md"
ACC="$D/原型验收记录-墨见InkSight.md"
BOOK="$D/墨见InkSight-产品设计与规划总册.html"

PASS=0; FAIL=0
chk(){ # chk <名称> <期望> <实际> [期望为- 表示"必须 0 命中"]
  local name="$1" want="$2" got="$3"
  if [ "$want" = "-" ]; then
    if [ "$got" = "0" ]; then printf '  PASS  %-52s 0 命中\n' "$name"; PASS=$((PASS+1));
    else printf '  FAIL  %-52s 期望 0 命中，实际 %s\n' "$name" "$got"; FAIL=$((FAIL+1)); fi
  else
    if [ "$got" = "$want" ]; then printf '  PASS  %-52s %s\n' "$name" "$got"; PASS=$((PASS+1));
    else printf '  FAIL  %-52s 期望 %s，实际 %s\n' "$name" "$want" "$got"; FAIL=$((FAIL+1)); fi
  fi
}
cnt(){ grep -o "$2" "$1" 2>/dev/null | wc -l | tr -d ' '; }
has(){ grep -qF "$2" "$1" && echo yes || echo no; }

# unmarked <文件> <词> —— 统计「出现该词、但同一行没有任何留痕标记」的命中数。
# 判据来源 D-32 口径补充：出现在被取代的旧结论里是留痕（合规），
# 出现在现行判定里是口径污染（违规）；但留痕必须「自我标注为留痕」，否则读者无从分辨。
unmarked(){ # unmarked <file> <word> <marker-regex>
  local f="$1" w="$2" m="$3" n=0 line
  while IFS= read -r line; do
    case "$line" in *"$w"*) ;; *) continue;; esac
    if ! printf '%s' "$line" | grep -qE "$m"; then
      n=$((n+1)); printf '        └ 未标注留痕的行：%.110s\n' "$line"
    fi
  done < "$f"
  echo "$n"
}
# outside <file> <word> <start-regex> <end-regex> —— 统计指定区块之外的出现次数
outside(){ # outside <file> <word> <start-regex> <end-regex>
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re,sys
f,w,s,e = sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
lines=open(f,encoding='utf-8').read().split('\n')
inside=False; n=0
for L in lines:
    if re.search(s,L): inside=True
    if inside and re.search(e,L): inside=False; continue
    if not inside and w in L: n+=1
print(n)
PY
}

echo "════ 墨见 InkSight · 跨文档一致性检查 ════"
echo "原型 MD5：$(md5 -q "$PROTO" | tr -d ' ')  字节：$(wc -c < "$PROTO" | tr -d ' ')  行：$(wc -l < "$PROTO" | tr -d ' ')"
echo

echo "【A】最终快照一致（MD5 前 8 位必须在 4 份文档中一致出现；文档可用缩写形式）"
MD5="$(md5 -q "$PROTO" | tr -d ' ')"
P8="${MD5:0:8}"
chk "验收记录含最终 MD5"        yes "$(has "$ACC" "$MD5")"
chk "台账含最终 MD5"            yes "$(has "$LEDGER" "$MD5")"
chk "总册含最终 MD5 前缀"        yes "$(has "$BOOK" "$P8")"
chk "DESIGN 含最终 MD5 前缀"     yes "$(has "$DES" "$P8")"
echo "  ── 旧中间态只许出现在「沿革／快照链」等留痕语境"
chk "验收记录 旧 MD5 均带沿革标记" 0 "$(unmarked "$ACC" '1233b65b' '沿革|增量|快照链|绑定|前一档|上一版')"
chk "总册 旧 MD5 均带留痕标记"     0 "$(unmarked "$BOOK" '1233b65b' '沿革|增量|快照链|绑定|前一档|上一版|变更记录')"
echo

echo "【B】D-32 判定二元化：被禁判定词在现行判定中 0 命中，留痕处须自我标注"
chk "验收记录 无该措辞"         - "$(cnt "$ACC" '有条件通过')"
chk "总册 无该措辞"             - "$(cnt "$BOOK" '有条件通过')"
chk "PRD 无该措辞"              - "$(cnt "$PRD" '有条件通过')"
chk "DESIGN 无该措辞"           - "$(cnt "$DES" '有条件通过')"
chk "台账：该措辞全部落在 D-32 条目内" 0 "$(outside "$LEDGER" '有条件通过' '^### D-32' '^### D-(?!32)')"
echo

echo "【C】D-38/D-40 面积口径：30% 数字必须是 100,451pt²，103,000 只许作为「已作废的旧数」出现"
chk "总册含 100,451pt²"         yes "$(has "$BOOK" '100,451')"
chk "总册不再把 103,000 当现值"  0 "$(grep -o '103,000pt²' "$BOOK" 2>/dev/null | wc -l | tr -d ' ')"
chk "DESIGN 含 100,451pt²"      yes "$(has "$DES" '100,451')"
chk "台账含 100,451pt²"         yes "$(has "$LEDGER" '100,451')"
chk "验收记录含 100,451pt²"     yes "$(has "$ACC" '100,451')"
chk "总册含高度口径 639pt"       yes "$(has "$BOOK" '639')"
echo

echo "【D】D-39/D-42 术语：禁用「奇数字号」；引述须自我标注"
chk "DESIGN 奇数字号 0 命中"    - "$(cnt "$DES" '奇数字号')"
chk "PRD 奇数字号 0 命中"       - "$(cnt "$PRD" '奇数字号')"
chk "总册 奇数字号 0 命中"        - "$(cnt "$BOOK" '奇数字号')"
chk "验收记录 奇数字号均带引述标记" 0 "$(unmarked "$ACC" '奇数字号' '原写|旧结论|原结论|与规则原文对不上|已按|留痕|作废')"
echo "  ── chrome 剩余命中（英文 ID chromeToggle 允许保留）"
for f in "$PRD" "$DES" "$ACC" "$BOOK"; do
  n=$(grep -o 'chrome' "$f" 2>/dev/null | wc -l | tr -d ' ')
  m=$(grep -o 'chromeToggle' "$f" 2>/dev/null | wc -l | tr -d ' ')
  o=$(grep -o 'chrome' "$f" 2>/dev/null | wc -l | tr -d ' ')
  printf "      %-34s chrome=%-3s 其中 chromeToggle=%s\n" "$(basename "$f")" "$n" "$m"
done
echo

echo "【E】D-42 EGG5 语义：PRD 与原型一致；D-08/D-44 行动作名统一「换一个版本」"
chk "PRD 含 随机书摘卡"          yes "$(has "$PRD" '随机书摘卡')"
chk "PRD 旧名仅存于改名说明句"      0 "$(unmarked "$PRD" '换一份文件' '全量改|旧名|曾写|原写|改名|统一为')"
chk "DESIGN 含 随机书摘卡"        yes "$(has "$DES" '随机书摘卡')"
chk "原型含 摇一摇 · 随机书摘"    yes "$(has "$PROTO" '摇一摇 · 随机书摘')"
chk "原型 厚玻璃 0 命中"         - "$(cnt "$PROTO" '厚玻璃')"
chk "台账含 换一份文件（D-08 旧名留痕）" yes "$(has "$LEDGER" '换一份文件')"
echo "  ── D-44/D-46 旧名清零（归档稿除外，保留旧名是正确的；「改名说明句」内的旧名引述属留痕，合规）"
for f in "$PRD" "$DES" "$ACC" "$BOOK" "$D/降级申报清单-墨见InkSight.md" \
         "$D/埋点需求表-墨见InkSight.md" "$D/行业合规与风险意见书-墨见InkSight.md"; do
  chk "$(basename "$f") 旧名仅存于改名说明句" 0 "$(unmarked "$f" '换一份文件' '全量改|旧名|曾写|原写|改名|统一为')"
done
echo "  ── D-46 术语与命名一致性"
chk "原型 换文件 0 命中"          - "$(cnt "$PROTO" '换文件')"
chk "原型 换一份文件 0 命中"       - "$(cnt "$PROTO" '换一份文件')"
chk "原型 换源 0 命中"            - "$(cnt "$PROTO" '换源')"
chk "DESIGN 更多菜单 0 命中"       - "$(cnt "$DES" '更多菜单')"
chk "PRD 更多菜单 0 命中"          - "$(cnt "$PRD" '更多菜单')"
chk "台账含 D-46"                yes "$(has "$LEDGER" 'D-46')"
chk "台账含 D-49"                yes "$(has "$LEDGER" 'D-49')"
chk "归档稿标注保留（旧名留存合法）" 12 "$(ls "$D"/DESIGN-archive/*.md | wc -l | tr -d ' ')"
echo

echo "【E2】D-48 字阶口径：UI 声明内 px 字面奇数整数 ＝ 107；三口径必须写明"
chk "验收记录 第16项判据列含 19／20／21" yes "$(grep -qE '10／11／13／15／17／19／20／21／22／28／34' "$ACC" && echo yes || echo no)"
chk "DESIGN 含 107 口径"         yes "$(has "$DES" '107')"
chk "台账含 107 口径"            yes "$(has "$LEDGER" '107')"
chk "验收记录 含 107 口径"        yes "$(has "$ACC" '107')"
chk "原型「⋯」三点图标 0 残留"    - "$(grep -o '<circle cx="6" cy="12" r="1.3"/>' "$PROTO" | wc -l | tr -d ' ')"
echo

echo "【F】D-43 徽标：原型与台账口径一致"
chk "原型 ui-page 仍在左下角"    yes "$(has "$PROTO" 'bottom:86px')"
chk "台账含 D-43"                yes "$(has "$LEDGER" 'D-43')"
echo

echo "【G】HTML 标签配平（总册）"
python3 - "$BOOK" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read()
d=0; bad=0
for m in re.finditer(r'<li\b|</li>', s):
    if m.group(0)=='<li': d+=1
    else:
        d-=1
        if d<0: bad+=1; d=0
print('  %s  %-52s 开=%d 闭=%d 游离=%d' % ('PASS' if (d==0 and bad==0) else 'FAIL','总册 <li> 配平',s.count('<li'),s.count('</li>'),bad))
PY
echo

echo "【I】台账结构"
chk "台账含 D-40"                yes "$(has "$LEDGER" 'D-40')"
chk "台账含 D-41"                yes "$(has "$LEDGER" 'D-41')"
chk "台账含 D-42"                yes "$(has "$LEDGER" 'D-42')"
chk "台账含 D-43"                yes "$(has "$LEDGER" 'D-43')"
chk "台账含 D-45"                yes "$(has "$LEDGER" 'D-45')"
chk "台账含 D-46"                yes "$(has "$LEDGER" 'D-46')"
chk "台账含 D-47"                yes "$(has "$LEDGER" 'D-47')"
chk "台账含 D-48"                yes "$(has "$LEDGER" 'D-48')"
chk "台账含 D-49"                yes "$(has "$LEDGER" 'D-49')"
chk "台账含 D-50"                yes "$(has "$LEDGER" 'D-50')"
chk "台账编号单调递增"          yes "$(python3 -c "
import re
s=open('$LEDGER',encoding='utf-8').read()
ids=[int(m) for m in re.findall(r'^### D-(\d+)', s, re.M)]
print('yes' if ids==sorted(ids) else 'no')")"
chk "台账 chrome 表述带单位"      yes "$(grep -qE '23 行（词频 27 次）' "$LEDGER" && echo yes || echo no)"
chk "台账含「指针（非改判）」体例" yes "$(has "$LEDGER" '指针（非改判')"
echo

echo "【J】《原型验收记录》判定本身（总判二元化 ＋ 逐项全通过）"
chk "总判为「通过。」"            yes "$(grep -qE '^\*\*通过。\*\*$' "$ACC" && echo yes || echo no)"
chk "无「不通过」判定项"          0 "$(grep -o '| \*\*不通过\*\* |' "$ACC" | wc -l | tr -d ' ')"
chk "24 项判定行齐备"            24 "$(grep -cE '^\| [0-9]+ \| ' "$ACC")"
chk "无被禁判定词"               - "$(cnt "$ACC" '有条件通过')"
chk "含最终快照 MD5"             yes "$(has "$ACC" "$MD5")"
echo
echo "════ 结果：PASS $PASS / FAIL $FAIL ════"
[ "$FAIL" -eq 0 ] && echo "结论：跨文档口径一致。" || echo "结论：存在口径漂移，见上方 FAIL 行。"
