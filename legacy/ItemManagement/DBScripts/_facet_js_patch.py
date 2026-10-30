import io, re, shutil, subprocess

j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak3')
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
    print('  %-16s lines %d-%d' % (name, s + 1, e + 1))
    return '\n'.join(lines[:s] + new.split('\n') + lines[e + 1:])

# A facet panel that fails silently looks identical to one with no data, which
# is what made the CTE bug so hard to spot. Say which it is.
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
            renderFacet('#facetBrands',   res.Brands,       'brand',  'BrandID',       'BrandName');
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

# Distinguish "no rows configured" from "request failed", and keep the group
# usable when a name is missing.
t = replace_fn(t, 'renderFacet', '''    function renderFacet(target, rows, group, idKey, nameKey) {
        var $t = $(target).empty();

        if (!rows || !rows.length) {
            $t.append('<div class="pos-muted" style="padding:8px 12px;font-size:12.5px;">'
                    + 'None configured</div>');
            return;
        }

        $.each(rows, function (_, r) {
            var id = String(r[idKey]);
            var n  = parseInt(r.Cnt, 10) || 0;
            var $l = $('<label>')
                .append($('<input type="checkbox">')
                    .attr('data-group', group).attr('data-id', id)
                    .prop('checked', !!sel[group][id]))
                .append($('<span class="nm">').text(r[nameKey] || ('#' + id)))
                .append($('<span class="cnt">').addClass(n === 0 ? 'zero' : '').text(n));
            $t.append($l);
        });
    }''')

io.open(j, 'w', encoding='utf-8-sig', newline='').write(t)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])
