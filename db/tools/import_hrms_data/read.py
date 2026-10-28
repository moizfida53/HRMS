"""Reads HRMS_Data.xlsx into plain Python data (json) - the generator works from that."""
import sys, json, datetime, openpyxl, re

wb = openpyxl.load_workbook(sys.argv[1], data_only=True)

def d(v):
    if v is None or v == '-' or (isinstance(v, str) and v.strip() in ('', '-', '#VALUE!')): return None
    if isinstance(v, datetime.datetime): return v.date().isoformat()
    if isinstance(v, str):
        v = v.strip()
        for fmt in ('%Y-%m-%d', '%d/%b/%Y', '%d/%m/%Y'):
            try: return datetime.datetime.strptime(v, fmt).date().isoformat()
            except ValueError: pass
    raise ValueError('date? %r' % v)

def s(v):
    if v is None: return None
    v = str(v).strip()
    return None if v in ('', '-', '#VALUE!') else v

out = {'licences': {}, 'vehicles': {}, 'employees': [], 'permit': {}}
company_tabs = ['أي جي أم كمبيوتر', 'بورج وكيل بالعمولة', 'زفير للمجوهرات', 'فور أم ديجيتال', 'شركة راند للتجارة العامة وا (2)', 'فلافل حماده']
for tab in company_tabs:
    ws = wb[tab]
    title = s(ws.cell(1, 1).value)
    lic, veh, part = [], [], 'lic'
    for r in ws.iter_rows(min_row=5, values_only=True):
        if r[0] == 'رخص المركبات': part = 'veh'; continue
        if r[0] == 'م' or not isinstance(r[0], int): continue
        row = {'no': r[0], 'name': s(r[1]), 'authority': s(r[2]), 'number': s(r[3]), 'issue': d(r[4]), 'expiry': d(r[5]), 'note': s(r[8])}
        (lic if part == 'lic' else veh).append(row)
    out['licences'][tab] = {'title': title, 'rows': lic}
    out['vehicles'][tab] = veh

ws = wb['Employee Data (3)']
for r in ws.iter_rows(min_row=3, values_only=True):
    if not isinstance(r[0], int): continue
    out['employees'].append({
        'sl': r[0], 'code': s(r[1]), 'name_ar': s(r[2]), 'name_en': s(r[3]), 'dob': d(r[4]), 'gender': s(r[5]),
        'nationality': s(r[6]), 'marital': s(r[7]), 'mobile': s(r[8]), 'joining': d(r[9]), 'designation': s(r[10]),
        'workplace': s(r[11]), 'licence': s(r[12]), 'salary': r[13], 'civil_id': s(r[14]), 'civil_exp': d(r[15]),
        'passport': s(r[17]), 'passport_exp': d(r[18]), 'passport_status': s(r[20]), 'note': s(r[21])})

ws = wb['بيانات العمالة']
for r in ws.iter_rows(min_row=3, values_only=True):
    if not isinstance(r[0], int): continue
    out['permit'][s(r[5])] = {'name_ar': s(r[1]), 'job_ar': s(r[2]), 'licence': s(r[3]),
                              'salary': None if s(r[4]) is None else r[4], 'residency_exp': d(r[6]),
                              'passport': s(r[8]), 'passport_exp': d(r[9]), 'note': s(r[12])}
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False, indent=1)
print(len(out['employees']), 'employees', len(out['permit']), 'permit rows',
      sum(len(v['rows']) for v in out['licences'].values()), 'licences', sum(len(v) for v in out['vehicles'].values()), 'vehicles')
