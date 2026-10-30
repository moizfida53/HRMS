import io, re, shutil, subprocess
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# 1. OrdersController - Place action
# ---------------------------------------------------------------------------
p = 'Areas/POS/Controllers/OrdersController.cs'
shutil.copyfile(p, p + '.bak')
c = io.open(p, encoding='utf-8-sig', newline='').read()

if 'ActionResult Place' not in c:
    anchor = '''        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }'''
    add = anchor + '''

        /// <summary>Counter order entry. Placeholder screen for now.</summary>
        public ActionResult Place()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }'''
    assert anchor in c, 'Index action anchor not found'
    c = c.replace(anchor, add, 1)
    io.open(p, 'w', encoding='utf-8-sig', newline='').write(c)
    print('controller : Place action added')
else:
    print('controller : Place already present')

# ---------------------------------------------------------------------------
# 2. pos.orders.js - hide the Brands facet when there is only one brand,
#    and wire the new toolbar controls
# ---------------------------------------------------------------------------
j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak4')
t = io.open(j, encoding='utf-8-sig', newline='').read()

def replace_fn(src, name, new):
    lines = src.split('\n')
    s = next(i for i, l in enumerate(lines) if re.match(r'\s*function %s\(' % re.escape(name), l))
    d, e = 0, None
    for i in range(s, len(lines)):
        d += lines[i].count('{') - lines[i].count('}')
        if d == 0 and i > s:
            e = i; break
    assert e is not None, name
    print('   %-14s lines %d-%d' % (name, s + 1, e + 1))
    return '\n'.join(lines[:s] + new.split('\n') + lines[e + 1:])

t = replace_fn(t, 'loadFacets', '''    function loadFacets() {
        $.ajax({
            type: 'POST', url: POS.urls.facets,
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(currentFilters())
        }).done(function (res) {
            if (!res || res.Message !== 'Success') {
                facetError('Could not load filters.');
                return;
            }
            facetCache = res;

            // A filter with one option cannot narrow anything - it only costs a
            // click and a block of screen. Hide the group instead of showing a
            // single permanently-redundant checkbox.
            var multiBrand = (res.Brands || []).length > 1;
            $('#facetBrandBox').toggle(multiBrand);
            if (!multiBrand) sel.brand = {};      // never filter by a hidden group

            if (multiBrand) {
                renderFacet('#facetBrands', res.Brands, 'brand', 'BrandID', 'BrandName');
            }
            renderFacet('#facetBranches', res.Branches,     'branch', 'BranchID',      'BranchName');
            renderFacet('#facetTypes',    res.InvoiceTypes, 'itype',  'InvoiceTypeID', 'InvoiceTypeName');
            renderChips();
        }).fail(function (xhr) {
            facetError('Could not load filters (' + xhr.status + ').');
        });
    }

    function facetError(msg) {
        $('#facetBrands, #facetBranches, #facetTypes').html(
            '<div class="text-danger" style="padding:8px 12px;font-size:12.5px;">' + esc(msg) + '</div>');
    }''')

# toolbar wiring: clear button, filter-panel toggle, keep the rest
old_reset = """        $('#btnReset').on('click', function () {"""
new_bits = """        // show/hide the whole filter column
        $('#btnToggleFilters').on('click', function () {
            var show = !$('#olSide').is(':visible');
            $('#olSide').toggle(show);
            $(this).toggleClass('on', show);
        });

        // clear button inside the search field
        function syncClear() {
            $('#searchShell').toggleClass('has-value', !!$('#fSearch').val());
        }
        $('#fSearch').on('input', syncClear);
        syncClear();

        $('#btnClearSearch').on('click', function () {
            $('#fSearch').val('').focus();
            syncClear();
            refreshAll();
        });

        $('#btnReset').on('click', function () {"""
if '#btnToggleFilters' not in t:
    assert old_reset in t, 'reset handler anchor not found'
    t = t.replace(old_reset, new_bits, 1)

# reset should also clear the search-shell state
t = t.replace("""            $('.facet input[type=checkbox]').prop('checked', false);
            refreshAll();""",
              """            $('.facet input[type=checkbox]').prop('checked', false);
            $('#searchShell').removeClass('has-value');
            refreshAll();""")

io.open(j, 'w', encoding='utf-8-sig', newline='').write(t)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])

# ---------------------------------------------------------------------------
# 3. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak8')
c = io.open(cp, encoding='utf-8-sig', newline='').read()
rel = r'Areas\POS\Views\Orders\Place.cshtml'
if 'Include="%s"' % rel not in c:
    a = '    <Content Include="Areas\\POS\\Views\\Orders\\Index.cshtml" />'
    assert a in c
    c = c.replace(a, '    <Content Include="%s" />\r\n' % rel + a, 1)
    io.open(cp, 'w', encoding='utf-8-sig', newline='').write(c)
    print('csproj        : Place.cshtml added')
else:
    print('csproj        : already there')
ET.parse(cp); print('csproj XML    : VALID')
