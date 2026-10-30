import io, os, re, shutil, subprocess
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# 1. pos.orders.js - button strips replaced by two selects
# ---------------------------------------------------------------------------
j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak2')
t = io.open(j, encoding='utf-8-sig').read()

def replace_fn(src, name, new):
    lines = src.split('\n')
    s = next(i for i, l in enumerate(lines) if re.match(r'\s*function %s\(' % re.escape(name), l))
    d, e = 0, None
    for i in range(s, len(lines)):
        d += lines[i].count('{') - lines[i].count('}')
        if d == 0 and i > s:
            e = i; break
    assert e is not None, name
    print('   %-20s lines %d-%d' % (name, s + 1, e + 1))
    return '\n'.join(lines[:s] + new.split('\n') + lines[e + 1:])

# buildStatusTabs -> fill the Status select. "Open" (all non-terminal) stays the
# default, because opening on every order ever placed is the surest way to make
# this screen feel slow.
t = replace_fn(t, 'buildStatusTabs', '''    function buildStatusTabs(statuses) {
        var $s = $('#fStatus').empty();
        var open = statuses.filter(function (x) { return !x.IsTerminal; })
                           .map(function (x) { return x.OrderStatusID; }).join(',');

        $s.append($('<option>').val(open).text('Open orders'));
        $s.append($('<option>').val('').text('All statuses'));
        $.each(statuses, function (_, x) {
            if (x.OrderStatusID === 0) return;      // "New" never persists
            $s.append($('<option>').val(x.OrderStatusID).text(x.OrderStatusName));
        });
        $s.val(open);
    }''')

t = replace_fn(t, 'currentFilters', '''    function currentFilters() {
        var mode = $('#fDateMode').val() || 'Today';
        return {
            BranchIDs:      multiVal('#fBranch'),
            StatusIDs:      $('#fStatus').val() || '',
            DateMode:       mode,
            FromDate:       mode === 'Range' ? ($('#fFrom').val() || null) : null,
            ToDate:         mode === 'Range' ? ($('#fTo').val()   || null) : null,
            Search:         $('#fSearch').val() || '',
            OrderType:      $('#fOrderType').val()     || null,
            PaymentTypeID:  $('#fPaymentType').val()   || null,
            PaymentStatus:  $('#fPaymentStatus').val() || '',
            IncludeDeleted: false
        };
    }''')

t = replace_fn(t, 'restoreFromUrl', '''    function restoreFromUrl() {
        var p = new URLSearchParams(location.search);
        if (p.get('d')) {
            $('#fDateMode').val(p.get('d'));
            $('#fRangeWrap').toggle(p.get('d') === 'Range');
        }
        if (p.get('q')) $('#fSearch').val(p.get('q'));
        if (p.get('t')) $('#fOrderType').val(p.get('t'));
        if (p.get('p')) $('#fPaymentStatus').val(p.get('p'));
        if (p.get('b')) $('#fBranch').val(p.get('b').split(','));
        if (p.get('s') !== null && $('#fStatus option[value="' + p.get('s') + '"]').length) {
            $('#fStatus').val(p.get('s'));
        }
    }''')

t = replace_fn(t, 'wire', '''    function wire() {
        var debouncedReload = debounce(function () { reload(); }, DEBOUNCE);

        $('#fSearch').on('input', debouncedReload);
        $('#fBranch, #fOrderType, #fPaymentType, #fPaymentStatus, #fStatus, #fFrom, #fTo')
            .on('change', function () { reload(); });

        $('#fDateMode').on('change', function () {
            $('#fRangeWrap').toggle(this.value === 'Range');
            // A range with no dates yet would query all time; wait for both.
            if (this.value === 'Range' && !$('#fFrom').val() && !$('#fTo').val()) return;
            reload();
        });

        $('#btnReset').on('click', function () {
            $('#fSearch').val('');
            $('#fBranch').val([]);
            $('#fOrderType, #fPaymentType, #fPaymentStatus').val('');
            $('#fDateMode').val('Today').trigger('change');
            $('#fStatus').prop('selectedIndex', 0);
            reload();
        });

        $('#posOrders tbody').on('click', 'tr', function (e) {
            if ($(e.target).is('input, a')) return;
            var inv = $(this).attr('data-inv');
            if (inv) openDrawer(inv);
        });

        $('#posOrders tbody').on('change', '.pos-chk', function () {
            var v = $(this).val();
            if (this.checked) selected[v] = true; else delete selected[v];
            $(this).closest('tr').toggleClass('pos-sel', this.checked);
            updateSelInfo();
        });

        $('#chkAll').on('change', function () {
            var on = this.checked;
            $('#posOrders tbody .pos-chk').each(function () {
                this.checked = on;
                if (on) selected[this.value] = true; else delete selected[this.value];
                $(this).closest('tr').toggleClass('pos-sel', on);
            });
            updateSelInfo();
        });

        $('#drwClose, #posBackdrop').on('click', closeDrawer);

        $(document).on('keydown', function (e) {
            if ($(e.target).is('input, select, textarea')) {
                if (e.key === 'Escape') $(e.target).blur();
                return;
            }
            if (e.key === '/')      { e.preventDefault(); $('#fSearch').focus(); return; }
            if (e.key === 'Escape') { closeDrawer(); return; }

            if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                e.preventDefault();
                var $rows = $('#posOrders tbody tr');
                var $cur  = $rows.filter('.pos-focus');
                var idx   = $rows.index($cur);
                var next  = e.key === 'ArrowDown' ? Math.min(idx + 1, $rows.length - 1) : Math.max(idx - 1, 0);
                if (idx === -1) next = 0;
                $rows.removeClass('pos-focus').css('outline', '');
                $rows.eq(next).addClass('pos-focus').css('outline', '2px solid var(--tmm-teal)')[0]
                     .scrollIntoView({ block: 'nearest' });
                return;
            }
            if (e.key === 'Enter') {
                var inv = $('#posOrders tbody tr.pos-focus').attr('data-inv');
                if (inv) openDrawer(inv);
            }
            if (e.key === 'F5') {
                e.preventDefault();      // refresh the grid, not the whole page
                reload(true);
            }
        });

        document.addEventListener('visibilitychange', function () {
            if (!document.hidden) poll();
        });
    }''')

# the old strips are gone from the markup, so drop the dateMode global
t = t.replace("    var dateMode  = 'Today';\n", "")
t = t.replace("dateMode = $(this).data('mode');", "")

io.open(j, 'w', encoding='utf-8-sig', newline='').write(t)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js  :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])

r = subprocess.run(['node', '--check', 'Areas/POS/Scripts/pos.context.js'], capture_output=True, text=True)
print('pos.context.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])

# ---------------------------------------------------------------------------
# 2. Area registration - land on Dashboard
# ---------------------------------------------------------------------------
a = 'Areas/POS/POSAreaRegistration.cs'
shutil.copyfile(a, a + '.bak')
s = io.open(a, encoding='utf-8-sig').read()
s = s.replace('defaults: new { controller = "Orders", action = "Index"',
              'defaults: new { controller = "Dashboard", action = "Index"')
io.open(a, 'w', encoding='utf-8-sig', newline='').write(s)
print('area default   : Dashboard')

# ---------------------------------------------------------------------------
# 3. Login redirect -> Dashboard
# ---------------------------------------------------------------------------
p = 'Areas/POS/POSAuth.cs'
shutil.copyfile(p, p + '.bak')
s = io.open(p, encoding='utf-8-sig').read()
s = s.replace('return RedirectToAction("Index", "Orders", new { area = "POS" });',
              'return RedirectToAction("Index", "Dashboard", new { area = "POS" });')
io.open(p, 'w', encoding='utf-8-sig', newline='').write(s)
print('login redirect :', 'Dashboard' if 'Dashboard' in s else '!! not changed')

# ---------------------------------------------------------------------------
# 4. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak4')
c = io.open(cp, encoding='utf-8-sig').read()

if 'pos.ribbon.js' in c:
    c = re.sub(r'[ \t]*<Content Include="Areas\\POS\\Scripts\\pos\.ribbon\.js" />\r?\n', '', c)
    print('csproj         : pos.ribbon.js removed')

comp = r'    <Compile Include="Areas\POS\Controllers\DashboardController.cs" />'
if 'DashboardController.cs' not in c:
    c = c.replace(r'    <Compile Include="Areas\POS\Controllers\OrdersController.cs" />',
                  comp + '\r\n' + r'    <Compile Include="Areas\POS\Controllers\OrdersController.cs" />', 1)

anchor = r'    <Content Include="Areas\POS\Scripts\pos.orders.js" />'
add = ''
for f in [r'Areas\POS\Scripts\pos.context.js', r'Areas\POS\Views\Dashboard\Index.cshtml']:
    if f not in c:
        add += '    <Content Include="%s" />\r\n' % f
if add:
    c = c.replace(anchor, add + anchor, 1)

io.open(cp, 'w', encoding='utf-8-sig', newline='').write(c)
ET.parse(cp)
print('csproj         : updated, XML VALID')
