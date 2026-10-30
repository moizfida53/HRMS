import io, re, shutil, subprocess, os

# ---------------------------------------------------------------------------
# 1. Login.cshtml - replace the whole brand panel block
# ---------------------------------------------------------------------------
p = 'Areas/POS/Views/Auth/Login.cshtml'
shutil.copyfile(p, p + '.bak')
t = io.open(p, encoding='utf-8-sig').read()

new_aside = '''    <aside class="brand-pane">
        <div class="mark">
            <img src="~/Areas/POS/Content/tmm-logo-light.svg" alt="TMM" class="mark-img" />
            <div class="mark-text">
                <div class="wordmark">TMM</div>
                <div class="tag">Point of Sale</div>
            </div>
        </div>
    </aside>'''

t = re.sub(r'    <aside class="brand-pane">.*?</aside>', new_aside, t, flags=re.S)

# Razor does not expand ~/ inside a plain attribute, so resolve it server side.
t = t.replace('src="~/Areas/POS/Content/tmm-logo-light.svg"',
              'src="@Url.Content("~/Areas/POS/Content/tmm-logo-light.svg")"')

# --- CSS: stack mark above wordmark, size it, keep text readable on dark ---
old_css_start = t.index('.brand-pane .mark {')
old_css_end   = t.index('/* ---- right: form ---- */')
new_css = '''.brand-pane .mark {
            position: relative; z-index: 1;
            display: flex; flex-direction: column; align-items: center; text-align: center;
        }
        /* Sized explicitly. An <img> with no dimensions collapses to 0 or
           balloons to its intrinsic size depending on the browser. */
        .brand-pane .mark-img { width: 104px; height: 104px; display: block; }
        .brand-pane .wordmark {
            font-size: 46px; font-weight: 700; letter-spacing: 11px;
            margin: 22px 0 0 0; line-height: 1; color: #FFFFFF;
        }
        .brand-pane .tag {
            margin-top: 12px; color: #9DAAA8; font-size: 13.5px; letter-spacing: .4px;
        }

        '''
t = t[:old_css_start] + new_css + t[old_css_end:]

# mobile: side by side, smaller
t = t.replace('.brand-pane .mark { display: flex; align-items: center; gap: 14px; }',
              '.brand-pane .mark { flex-direction: row; align-items: center; gap: 14px; text-align: left; }\n'
              '            .brand-pane .mark-img { width: 44px; height: 44px; }\n'
              '            .brand-pane .mark-text { text-align: left; }')

io.open(p, 'w', encoding='utf-8-sig', newline='').write(t)
print('Login.cshtml   : brand panel replaced')

# ---------------------------------------------------------------------------
# 2. _LayoutPOS.cshtml - swap the inline svg for the light logo file
# ---------------------------------------------------------------------------
p2 = 'Areas/POS/Views/Shared/_LayoutPOS.cshtml'
shutil.copyfile(p2, p2 + '.bak')
t2 = io.open(p2, encoding='utf-8-sig').read()

t2 = re.sub(
    r'        @\* TMM mark.*?</svg>',
    '        <img src="@Url.Content("~/Areas/POS/Content/tmm-logo-light.svg")" alt="TMM" class="bar-logo" />',
    t2, flags=re.S)

t2 = t2.replace('.tmm-bar .logo { display: flex; align-items: center; gap: 10px; }',
                '.tmm-bar .logo { display: flex; align-items: center; gap: 10px; }\n'
                '        .tmm-bar .bar-logo { width: 28px; height: 28px; display: block; }')

io.open(p2, 'w', encoding='utf-8-sig', newline='').write(t2)
print('_LayoutPOS     : bar logo replaced')

# ---------------------------------------------------------------------------
# 3. csproj - register the two svg files
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak3')
c = io.open(cp, encoding='utf-8-sig').read()
anchor = r'    <Content Include="Areas\POS\Scripts\pos.ribbon.js" />'
add = ''
for f in ['tmm-logo-light.svg', 'tmm-logo-dark.svg']:
    e = r'    <Content Include="Areas\POS\Content\%s" />' % f
    if f not in c:
        add += e + '\r\n'
if add:
    c = c.replace(anchor, add + anchor, 1)
    io.open(cp, 'w', encoding='utf-8-sig', newline='').write(c)
print('csproj         : svg files registered' if add else 'csproj         : already present')

import xml.etree.ElementTree as ET
ET.parse(cp); print('csproj XML     : VALID')
for f in ['Areas/POS/Content/tmm-logo-light.svg', 'Areas/POS/Content/tmm-logo-dark.svg']:
    ET.parse(f); print('%-46s VALID' % f)
