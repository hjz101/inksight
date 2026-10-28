#!/usr/bin/env bash
# 原型实测探针 · 墨见 InkSight
# 用途：把 PRD v2.9 §15 的六项验收口径变成机器产出数字，人审只负责排除项。
# 这是「工具」，不是「结论」——验收记录由产品出，本脚本只负责出数。
#
# 用法：
#   bash deliverables/scripts/probe-prototype.sh
#
# 依赖：Microsoft Edge（已装在 /Applications）。无头模式跑本地 file://，
#      注入探针脚本后 dump DOM，从 #RESULT 里读 JSON。
#
# 已知坑（务必别踩）：
#   1. Edge 无头下 CSS 过渡不随 --virtual-time-budget 推进，浮层会停在入场中途，
#      看起来像布局错位。截图前必须注入 *{transition:none!important;animation:none!important}。
#   2. requestAnimationFrame 在无头虚拟时钟下不触发，采样必须用 setTimeout。
#   3. 事件监听器里抛出的异常不会传播到 dispatchEvent 调用方，
#      探针必须自己挂 window.onerror 收集，否则会静默失败。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTO="$(cd "$HERE/.." && pwd)/prototype/index.html"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$PROTO" ] || { echo "找不到原型：$PROTO" >&2; exit 1; }
[ -x "$EDGE" ] || { echo "找不到 Edge：$EDGE" >&2; exit 1; }

echo "原型：$PROTO"
echo "字节：$(wc -c < "$PROTO" | tr -d ' ')  行数：$(wc -l < "$PROTO" | tr -d ' ')"
# D-21：验收结论以「写入方声明写入结束 + 本 MD5 快照」为准，快照变更则结论作废
echo "MD5：$(md5 -q "$PROTO" | tr -d ' ')"
echo

# ---------- 0. 静态检查 ----------
echo "=== 0. 静态检查 ==="
python3 - "$PROTO" <<'PY'
import re, subprocess, sys, collections
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
blocks = re.findall(r'<script[^>]*>([\s\S]*?)</script>', s)
ok = True
for i, b in enumerate(blocks):
    open('/tmp/_probe_%d.js' % i, 'w', encoding='utf-8').write(b)
    r = subprocess.run(['node', '--check', '/tmp/_probe_%d.js' % i], capture_output=True, text=True)
    print('script %d  node --check: %s' % (i, 'OK' if r.returncode == 0 else 'FAIL\n' + r.stderr[:400]))
    ok = ok and r.returncode == 0
ids = re.findall(r'\sid="([^"]+)"', s)
dup = [k for k, v in collections.Counter(ids).items() if v > 1]
print('重复 id: %s' % (dup or '无'))
for t in ['div', 'section', 'p', 'span', 'button', 'svg', 'dl', 'dt', 'dd']:
    o = len(re.findall(r'<%s[\s>]' % t, s)); c = len(re.findall(r'</%s>' % t, s))
    if o != c:
        print('标签不配平: <%s> 开 %d 闭 %d' % (t, o, c)); ok = False
print('禁词计数: 换源=%d  example.com=%d  继续使用=%d' % (
    s.count('换源'), s.count('example.com'), s.count('继续使用')))
print('占位符: TBD-CONTACT=%d（应为 1）' % s.count('TBD-CONTACT'))
# D-22：三值符号必须逐个单模式统计。交替模式整体返回 0 不代表符号不存在。
print('三值符号（单模式）: ∅=%d  ✗=%d  ✓=%d' % (s.count('∅'), s.count('✗'), s.count('✓')))
# D-20：拦截页文案的真实字面是「今日阅读时长已用尽」，不是「时长用尽」
print('拦截页文案（单模式）: 今日阅读时长已用尽=%d  时段阅读暂停=%d' % (
    s.count('今日阅读时长已用尽'), s.count('时段阅读暂停')))
print('静态检查结论: %s' % ('通过' if ok and not dup else '不通过'))
PY
echo

# ---------- 1. 行为探针 ----------
cat > "$TMP/probe.html" <<'HTML'
<script>
(function(){
  var out={}; function q(s){return document.querySelector(s);}
  function ms(v){ return v.split(',').map(function(x){ return parseFloat(x)*1000; }); }
  try{
    // §15-1 动效挂载
    var dump = window.MotionRegistry.dump();
    out.motionTotal = dump.length;
    out.motionMounted = dump.filter(function(r){return r['状态']==='已挂载';}).length;
    out.motionMissing = dump.filter(function(r){return r['状态']!=='已挂载';}).map(function(r){return r.ID;});

    // §15-2 减弱动效：实测时长 + 无中间帧
    q('#rmSwitch').click();
    out.reduceOn = document.body.classList.contains('reduce');
    var all = document.querySelectorAll('*'), viol = [];
    for (var i=0;i<all.length;i++){
      var cs = getComputedStyle(all[i]);
      var td = ms(cs.transitionDuration||'0s'), ad = ms(cs.animationDuration||'0s');
      if (td.some(function(x){return x>1;})) viol.push({sel:all[i].tagName+'.'+(all[i].className||'').toString().split(' ')[0], type:'transition', v:cs.transitionDuration});
      if (ad.some(function(x){return x>1;})) viol.push({sel:all[i].tagName+'.'+(all[i].className||'').toString().split(' ')[0], type:'animation', v:cs.animationDuration});
    }
    out.elements = all.length;
    out.motionViolations = viol.length;   // 0 => 任何动效不可能产生中间帧
    out.violationList = viol.slice(0,10);

    // §15-2b 遮罩维度（补 D-26 盲区）：backdrop-filter 不产生可采样时长，
    // 过渡维度全为 0 的元素仍可能带全屏模糊。须单独穷举。
    var bf = [], bfAll = [];
    for (var j=0;j<all.length;j++){
      var cj = getComputedStyle(all[j]);
      var v = cj.backdropFilter || cj.webkitBackdropFilter || 'none';
      if (v && v !== 'none'){
        var item = {sel:all[j].tagName+'#'+all[j].id+'.'+(all[j].className||'').toString().split(' ').join('.'), v:v};
        bfAll.push(item);
        // 宵禁拦截页与正文区禁止任何遮罩
        if (all[j].id === 'curtain' || all[j].id === 'quoteModal' ||
            all[j].closest('#curtain') || all[j].closest('#quoteModal')){
          bf.push(item);
        }
      }
    }
    out.backdropTotal = bfAll.length;
    out.backdropList = bfAll.slice(0,20);
    out.backdropForbidden = bf.length;   // 宵禁页/书摘卡应为 0
    out.backdropForbiddenList = bf.slice(0,10);

    // §15-2c 宵禁拦截页专项：不得有遮罩、不得有过渡、遮罩色须为 .94
    var cur = q('#curtain');
    var curCs = getComputedStyle(cur);
    out.curtainBackdrop = curCs.backdropFilter || curCs.webkitBackdropFilter || 'none';
    out.curtainTransition = curCs.transitionDuration;
    out.curtainBg = curCs.backgroundColor;

    // §15-3 ∅ 结构不生成（DOM 中不存在该节点，而非不可见）
    q('[data-ageopen]').click();
    var res = {};
    ['minorConfirmed','ageUnresolved','unverified'].forEach(function(st){
      q('#stateSw button[data-astate="'+st+'"]').click();
      res[st] = {
        banner: q('#sbT').textContent,
        pathHidden: q('#pathRow').hidden,
        curtainButtonCount: q('#curtainBtns').querySelectorAll('button').length
      };
    });
    out.states = res;

    // §15-4 变体切换后取值变化
    q('#variantSw button[data-variant="release"]').click();
    out.releaseOnline = Array.prototype.map.call(
      q('#ageMatrix').querySelectorAll('.mx-row[data-r="在线书源"] .mx-cell'),
      function(c){return c.textContent;});
    q('#stateSw button[data-astate="unverified"]').click();
    out.releaseUnverifiedBanner = q('#sbT').textContent;
    q('#variantSw button[data-variant="research"]').click();
    out.researchOnline = Array.prototype.map.call(
      q('#ageMatrix').querySelectorAll('.mx-row[data-r="在线书源"] .mx-cell'),
      function(c){return c.textContent;});
    q('#stateSw button[data-astate="unverified"]').click();
    out.researchUnverifiedBanner = q('#sbT').textContent;

    // §15-5 拦截页文案由状态条派生（两处必须同形）
    q('#stateSw button[data-astate="ageUnresolved"]').click();
    var banner = q('#sbT').textContent;
    q('#curtainBtns button').click();
    out.curtainTitle = q('#ctTitle').textContent;
    out.curtainDerivesFromBanner = (out.curtainTitle.indexOf(banner) === 0);
    out.curtainPathHidden = q('#ctPath').hidden;

    // §15-6 故事板与 UI 页码同步
    out.storyButtons = q('#storyBtns').children.length;
    q('[data-story="contact"]').click();
    out.uiPageAfterContact = q('#uiPage').textContent.trim();
  }catch(e){ out.err = e.message + ' @ ' + ((e.stack||'').split('\n')[1]||''); }
  var d=document.createElement('div'); d.id='RESULT'; d.textContent=JSON.stringify(out,null,1); document.body.appendChild(d);
})();
</script>
HTML

python3 - "$PROTO" "$TMP/probe.html" <<'PY'
import sys
src = open(sys.argv[1], encoding='utf-8').read()
probe = open(sys.argv[2], encoding='utf-8').read()
open(sys.argv[2], 'w', encoding='utf-8').write(src.replace('</body>', probe + '</body>'))
PY

"$EDGE" --headless=new --disable-gpu --no-sandbox --virtual-time-budget=6000 \
        --dump-dom "file://$TMP/probe.html" 2>/dev/null > "$TMP/dom.html"

echo "=== 1. 行为探针实测 ==="
python3 - "$TMP/dom.html" <<'PY'
import re, json, sys
d = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<div id="RESULT">(.*?)</div>', d, re.S)
if not m:
    print('未取得结果（探针可能静默失败）'); raise SystemExit(1)
t = m.group(1).replace('&quot;','"').replace('&amp;','&').replace('&lt;','<').replace('&gt;','>')
o = json.loads(t)
if o.get('err'): print('探针异常:', o['err'])
print('动效挂载       : %s/%s  缺失=%s' % (o.get('motionMounted'), o.get('motionTotal'), o.get('motionMissing')))
print('减弱动效       : reduceOn=%s  扫描元素=%s  时长>1ms 违规=%s' % (o.get('reduceOn'), o.get('elements'), o.get('motionViolations')))
for v in o.get('violationList', [])[:5]: print('    违规:', v)
print('遮罩维度(补盲区): 全文档带 backdrop-filter 元素=%s  其中宵禁页/书摘卡=%s' % (o.get('backdropTotal'), o.get('backdropForbidden')))
for v in o.get('backdropForbiddenList', [])[:5]: print('    禁遮罩违规:', v)
print('宵禁页专项     : backdrop=%r  transition=%r  bg=%r' % (o.get('curtainBackdrop'), o.get('curtainTransition'), o.get('curtainBg')))
for st, v in (o.get('states') or {}).items():
    print('  态 %-16s banner=%r  路径隐藏=%s  拦截页按钮数=%d' % (st, v['banner'], v['pathHidden'], v['curtainButtonCount']))
print('变体 release   : 在线书源列=%s  未完善横幅=%r' % (o.get('releaseOnline'), o.get('releaseUnverifiedBanner')))
print('变体 research  : 在线书源列=%s  未完善横幅=%r' % (o.get('researchOnline'), o.get('researchUnverifiedBanner')))
print('拦截页派生     : 标题=%r' % o.get('curtainTitle'))
print('               由状态条派生=%s  系统路径隐藏=%s' % (o.get('curtainDerivesFromBanner'), o.get('curtainPathHidden')))
print('故事板         : 按钮数=%s  切到投诉页后 UI 页码=%r' % (o.get('storyButtons'), o.get('uiPageAfterContact')))
PY

echo
echo "完成。数字为机器产出；验收记录的判断与排除项由产品负责。"
