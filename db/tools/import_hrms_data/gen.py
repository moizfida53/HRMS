"""Builds db/92_Import_HRMS_Data.sql from data.json (read.py). Stops on anything it cannot map."""
import json, sys, re

x = json.load(open(sys.argv[1], encoding='utf-8'))

def q(v):
    if v is None: return 'NULL'
    if isinstance(v, (int, float)): return ('%.3f' % v) if isinstance(v, float) else str(v)
    return "N'" + str(v).replace("'", "''") + "'"

# ------------------------------------------------------------------ companies
# code, English name (short), Arabic legal name, licence text (employee sheet), workplace text, company tab
COMPANIES = [
    ('RAND',  'RAND General Trading & Contracting Co.', 'شركة راند للتجارة العامة والمقاولات',
     'راند للتجارة العامة والمقاولات', 'RAND Co.', 'شركة راند للتجارة العامة وا (2)'),
    ('FH',    'Falafel Hamada', 'فلافل حماده للمأكولات الخفيفة',
     'فلافل حماده للمأكولات الخفيفة', 'FALAFEL HAMADH', 'فلافل حماده'),
    ('4MG',   '4 MG Digital Printing', 'فور أم ديجيتال لأعمال الطباعة',
     'فور أم ديجيتال لأعمال الطباعة', '4 MG', 'فور أم ديجيتال'),
    ('IGM',   'IGM Computer - Security Devices & Systems', 'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها',
     'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها', 'IGM', 'أي جي أم كمبيوتر'),
    ('BURUJ', 'Buruj Commission Agent', 'بروج وكيل بالعمولة والتجار بالعمولة',
     'بروج وكيل بالعمولة والتجار بالعمولة', 'Buruj', 'بورج وكيل بالعمولة'),
    ('ZAFIR', 'Zafir Watches & Jewellery', 'زفير للبيع بالتجزئة للساعات بأنواعها والمجوهرات والمصوغات',
     'زفير للبيع بالتجزئة للساعات بأنواعها والمجوهرات والمصوغات', 'Zafir', 'زفير للمجوهرات'),
]
BY_LICENCE = {c[3]: c for c in COMPANIES}
BY_WORKPLACE = {c[4]: c for c in COMPANIES}
CODE_START = {'RAND': 2101, 'FH': 1101, '4MG': 4001, 'IGM': 3001, 'BURUJ': 5001, 'ZAFIR': 6001}

# ------------------------------------------------------------------ authorities
NEW_AUTHORITIES = [   # ShortName, English, Arabic
    ('NFSMED', 'National Fund for SME Development', 'الصندوق الوطني لرعاية وتنمية المشروعات الصغيرة والمتوسطة'),
    ('GTD', 'General Traffic Department (Ministry of Interior)', 'الإدارة العامة للمرور - وزارة الداخلية'),
    ('CAPT', 'Central Agency for Public Tenders', 'الجهاز المركزي للمناقصات العامة'),
]
AUTH = {'وزارة التجارة': 'MOCI', 'الهيئة العامة للقوى العاملة': 'PAM', 'بلدية الكويت': 'KM', 'الهيئة العامة للصناعة': 'PAI',
        'قوة الإطفاء العامة': 'KFF', 'قوة الإطفاء': 'KFF', 'وزارة الإعلام': 'MOInf', 'الصندوق الوطني': 'NFSMED',
        'إدارة المرور': 'GTD', 'الإدارة العامة للمرور': 'GTD', 'الجهاز المركزي للمناقصات العامة': 'CAPT',
        'الهيئة العامة للبيئة': 'EPA', 'وزارة الصحة': 'MOH', 'الهيئة العامة للغذاء والتغذية': 'PAFN',
        'شركة زمزم للتأمين التكافلي': None, 'الشركة العربية الإسلامية للتأمين التكافلي': None}   # None = private (insurer)

# ------------------------------------------------------------------ licence -> document type
# sheet name -> (TypeName, ArabicName, Category, note added to the document)
T = {
    'COMM':   ('Commercial License', 'الرخصة التجارية', 'LICENSE'),
    'IMPORT': ('Import License', 'رخصة استيراد', 'LICENSE'),
    'PAMSIG': ('PAM Signature Authorization', 'اعتماد توقيع الشؤون', 'AUTHORIZATION'),
    'ADV':    ('Advertising License', 'ترخيص الإعلان', 'LICENSE'),
    'IND':    ('Industrial License', 'الترخيص الصناعي', 'LICENSE'),
    'FIRE':   ('Fire Force License', 'ترخيص الإطفاء', 'LICENSE'),
    'PRESS':  ('Printing Press License', 'ترخيص مطبعة', 'LICENSE'),
    'INS':    ('Workers Insurance Policy', 'وثيقة التأمين', 'INSURANCE'),
    'INJ':    ('Work Injury Statistics', 'إحصائية إصابات العمل', 'REGISTRATION'),
    'NFUND':  ('National Fund Registration Certificate', 'شهادة قيد بالسجل الوطني', 'REGISTRATION'),
    'TRSIG':  ('Traffic Signature Authorization', 'اعتماد توقيع المرور', 'AUTHORIZATION'),
    'TENDC':  ('Public Tenders Registration Certificate', 'شهادة المناقصات', 'REGISTRATION'),
    'TENDS':  ('Public Tenders Signature Authorization', 'اعتماد توقيع لجنة المناقصات العامة', 'AUTHORIZATION'),
    'ENVC':   ('Environment Certificate', 'شهادة البيئة', 'LICENSE'),
    'ENVU':   ('Environment Data Update', 'تحديث بيانات البيئة', 'REGISTRATION'),
    'MEDW':   ('Medical Waste Transport License', 'ترخيص بمزاولة نقل النفايات الطبية', 'LICENSE'),
    'MEDV1':  ('Medical Waste Vehicle License 21-11532', 'ترخيص مركبة لنقل النفايات الطبية 21-11532', 'LICENSE'),
    'MEDV2':  ('Medical Waste Vehicle License 5-82116', 'ترخيص مركبة لنقل النفايات الطبية 5-82116', 'LICENSE'),
    'MEDD1':  ('Medical Waste Driver License - Ashraf', 'ترخيص قيادة مركبة نفايات طبية - أشرف', 'LICENSE'),
    'MEDD2':  ('Medical Waste Driver License - Abu Ali', 'ترخيص قيادة مركبة نفايات طبية - أبو علي', 'LICENSE'),
    'HLTH_H': ('Health License - Hawally', 'الترخيص الصحي - حولي', 'LICENSE'),
    'HLTH_Q': ('Health License - Qasr Al-Diyafa', 'الترخيص الصحي - قصر الضيافة', 'LICENSE'),
    'TM':     ('Trademark Certificate', 'شهادة العلامة التجارية', 'REGISTRATION'),
    'COMM_S': ('Commercial License - Salmiya', 'الرخصة التجارية - السالمية', 'LICENSE'),
    'COMM_Q': ('Commercial License - Qasr Al-Diyafa', 'الرخصة التجارية - قصر الضيافة', 'LICENSE'),
}
LIC = {   # sheet licence name -> (type key, extra note)
    'الرخصة التجارية': ('COMM', None), 'الترخيص التجاري': ('COMM', None), 'رخصة استيراد': ('IMPORT', None),
    'اعتماد توقيع الشئون': ('PAMSIG', None), 'اعتماد توقيع الشؤون': ('PAMSIG', None), 'اعتماد التوقيع الشئون': ('PAMSIG', None),
    'ترخيص الإعلان': ('ADV', None), 'ترخيص إعلان': ('ADV', None), 'الترخيص الصناعي': ('IND', None),
    'رخصة إطفاء (شركة النفيسي)': ('FIRE', 'شركة النفيسي'), 'ترخيص مطبعة': ('PRESS', None),
    'وثيقة التأمين': ('INS', None), 'وثيقة تأمين': ('INS', None), 'إحصائية إصابات العمل': ('INJ', None),
    'شهادة قيد بالسجل الوطني': ('NFUND', None), 'اعتماد توقيع المرور': ('TRSIG', None),
    'شهادة المناقصات': ('TENDC', None), 'اعتماد توقيع لجنة المناقصات العامة': ('TENDS', None),
    'شهادة البيئة': ('ENVC', None), 'تحديث بيانات البيئة': ('ENVU', None),
    'ترخيص بمزاولة نقل النفايات الطبية': ('MEDW', None),
    'ترخيص مركبة للاستخدام في نقل النفايات الطبية 21-11532': ('MEDV1', None),
    'ترخيص مركبة للاستخدام في نقل النفايات الطبية 5-82116': ('MEDV2', None),
    'ترخيص قيادة مركبة للاستخدام في نقل النفايات الطبية اشرف': ('MEDD1', None),
    'ترخيص قيادة مركبة للاستخدام في نقل النفايات الطبية ابو علي': ('MEDD2', None),
    'الرخصة التجارية حولي': ('COMM', 'حولي'), 'ترخيص الإطفاء حولي': ('FIRE', 'حولي'), 'ترخيص الصحي حولي': ('HLTH_H', None),
    'ترخيص إعلان حولي': ('ADV', 'حولي'), 'شهادة العلامة التجارية حولي': ('TM', 'حولي'),
    'الرخصة التجارية السالمية': ('COMM_S', None), 'الترخيص التجاري قصر الضيافة': ('COMM_Q', None),
    'الترخيص الصحي قصر الضيافة': ('HLTH_Q', None),
}

# ------------------------------------------------------------------ vehicles (company tab, row no) -> asset
# type, brand, model, colour   (plate = licence number, expiry = registration expiry)
VEH = {
    ('شركة راند للتجارة العامة وا (2)', 1): ('Cars', 'Toyota', 'Jeep - 2012', None),
    ('شركة راند للتجارة العامة وا (2)', 2): ('Trucks & Pickups', 'Mitsubishi', 'Pickup - 2013', 'White'),
    ('شركة راند للتجارة العامة وا (2)', 3): ('Cars', 'Hyundai', 'Jeep - 2015', None),
    ('شركة راند للتجارة العامة وا (2)', 4): ('Trucks & Pickups', 'Mitsubishi', 'Pickup - 2010', 'White'),
    ('شركة راند للتجارة العامة وا (2)', 5): ('Trucks & Pickups', 'Ashok Leyland', 'Pickup - 2021', None),
    ('فلافل حماده', 1): ('Motor Bikes', None, 'Motorcycle - 2020', None),
    ('فلافل حماده', 2): ('Motor Bikes', None, 'Motorcycle - 2022', None),
    ('فلافل حماده', 3): ('Motor Bikes', None, 'Motorcycle - 2021', None),
    ('فلافل حماده', 4): ('Cars', 'Kia', 'Saloon - 2017', 'White'),
    ('فلافل حماده', 5): ('Trucks & Pickups', None, 'Saloon truck - 2024', 'White'),
}

# ------------------------------------------------------------------ work permit job -> designation
JOB = {
    'مخلص معاملات': ('DSG-CLEAR', 'Transactions Clearance Clerk'),
    'معد وجبات سريعة': ('DSG-FFPREP', 'Fast Food Preparer'),
    'سائق / دراجة نارية': ('DSG-DRVBIKE', 'Driver - Motorcycle'),
    'صراف نقود / كاشير في المنشآت التجارية': ('DSG-CASHIER', 'Cashier'),
    'أمين مخزن': ('DSG-STORE', 'Storekeeper'),
    'مساعد طاهي / طباخ': ('DSG-ASTCOOK', 'Assistant Cook'),
    'سائق / شاحنة': ('DSG-DRVTRUCK', 'Driver - Truck'),
    'مراقب إداري': ('DSG-ADMSUP', 'Administrative Supervisor'),
    'عامل تعبئة منتجات': ('DSG-PACK', 'Product Packing Worker'),
    'كاتب إداري / عام': ('DSG-CLERK', 'Administrative Clerk'),
    'كهربائي لوحات مراقبة وتحكم': ('DSG-ELECPNL', 'Control Panel Electrician'),
    'مسؤول قانوني': ('DSG-LEGAL', 'Legal Officer'),
    'سائق / سيارة خصوصي': ('DSG-DRVCAR', 'Driver - Private Car'),
    'عامل تحميل / شاحنات': ('DSG-LOAD', 'Loading Worker - Trucks'),
    'مندوب مبيعات (متجول)': ('DSG-SALESREP', 'Sales Representative (Field)'),
    'فني نظم معلوماتية': ('DSG-ITTECH', 'IT Systems Technician'),
    'محاسب': ('DSG-ACC', 'Accountant'),
    'مسؤول مالي وإداري': ('DSG-FINADM', 'Finance & Administration Officer'),
    'مشغل / آلة تجهيز رولات الورق': ('DSG-ROLLOP', 'Paper Roll Machine Operator'),
    'مراسل': ('DSG-MSGR', 'Messenger'),
    'بائع مجوهرات': ('DSG-JEWEL', 'Jewellery Salesperson'),
    'كهربائي تمديدات كهربائية / عام': ('DSG-ELECGEN', 'Electrician - General Wiring'),
    'عامل مخازن': ('DSG-WHWORK', 'Warehouse Worker'),
}

COUNTRY = {'Egyptian': ('EG', 'Egypt'), 'Jordanian': ('JO', 'Jordan'), 'Sudanese': ('SD', 'Sudan'), 'Indian': ('IN', 'India'),
           'Bangladeshi': ('BD', 'Bangladesh'), 'Syrian': ('SY', 'Syria'), 'Filipino': ('PH', 'Philippines'),
           'Pakistani': ('PK', 'Pakistan'), 'Lebanese': ('LB', 'Lebanon'), 'Yemeni': ('YE', 'Yemen'), 'Iraqi': ('IQ', 'Iraq')}

NOTE_EN = {'عمالة خارجية': 'external labour (عمالة خارجية)', 'خارجية': 'external (خارجية)', 'مع الموظف': 'passport with the employee',
           'في انتظار إصدار البطاقة المدنية': 'waiting for the civil ID card', 'كشف طبي': 'medical examination',
           'عمالة وطنية': 'national labour (عمالة وطنية)', 'تجديد جواز': 'passport renewal', 'مسافر': 'travelling',
           'تمديد شهرين': 'two-month extension', 'تغيب': 'absent (تغيب)', 'تحديد 3 أشهر': 'three-month limit (تحديد 3 أشهر)'}

# ------------------------------------------------------------------ names
JOIN_NEXT = {'Abu', 'Abd', 'Abdul', 'Abdel'}
def split_name(full):
    t = full.split()
    if t[0] in JOIN_NEXT and len(t) > 2: t = [t[0] + ' ' + t[1]] + t[2:]
    if len(t) > 2 and t[-2] in {'Al', 'El', 'Abu', 'Abul', 'Abdul', 'Abd', 'Bait', 'Bin', 'Abdel', 'Gad'} or (len(t) > 2 and t[-1] in {'M.D.', 'MD'}): t = t[:-2] + [t[-2] + ' ' + t[-1]]
    if len(t) == 1: return t[0], None, None
    if len(t) == 2: return t[0], None, t[1]
    return t[0], ' '.join(t[1:-1]), t[-1]

# ------------------------------------------------------------------ rows
emps, generated, flags = [], [], []
next_code = dict(CODE_START)
for e in x['employees']:
    co = BY_LICENCE[e['licence']]
    work = BY_WORKPLACE[e['workplace']]
    p = x['permit'][e['civil_id']]
    code = e['code']
    if code is None:
        code = str(next_code[co[0]]); next_code[co[0]] += 1
        generated.append((co[0], code, e['name_en']))
    first, middle, last = split_name(e['name_en'])
    job = JOB[p['job_ar']]
    notes = [n for n in {e['note'], p['note']} if n]
    emps.append(dict(sl=e['sl'], company=co[0], workplace=None if work is co else work[0], code=code, generated=e['code'] is None,
                     first=first, middle=middle, last=last, ar=e['name_ar'], gender=e['gender'], dob=e['dob'],
                     nat=e['nationality'], civil=e['civil_id'], civil_exp=e['civil_exp'] or p['residency_exp'],
                     passport=e['passport'] or p['passport'], passport_exp=e['passport_exp'] or p['passport_exp'],
                     salary=e['salary'], permit_salary=p['salary'], job_code=job[0], job_en=job[1], job_ar=p['job_ar'],
                     sponsor=co[2], notes=' / '.join(NOTE_EN.get(n, n) for n in notes) or None))

# ------------------------------------------------------------------ SQL
L = []
w = L.append
w(open(sys.argv[2], encoding='utf-8').read())   # header (hand-written)

w("/* ---- the companies ------------------------------------------------- */")
w("DECLARE @Company TABLE (Code NVARCHAR(30) PRIMARY KEY, NameEn NVARCHAR(200), LegalAr NVARCHAR(300), CompanyId INT NULL);")
w("INSERT INTO @Company (Code, NameEn, LegalAr) VALUES")
w(",\n".join("    (%s, %s, %s)" % (q(c[0]), q(c[1]), q(c[2])) for c in COMPANIES) + ";")
w("")

w("/* ---- company documents (licences): one row per licence ---------------- */")
w("DECLARE @TypeDef TABLE (TypeKey VARCHAR(10) PRIMARY KEY, TypeName NVARCHAR(150), ArabicName NVARCHAR(150), Category VARCHAR(20), AuthorityShort NVARCHAR(20) NULL);")
type_auth = {}
docs = []
for c in COMPANIES:
    for r in x['licences'][c[5]]['rows']:
        if r['name'] not in LIC: raise SystemExit('unmapped licence: %r (%s)' % (r['name'], c[0]))
        if r['authority'] not in AUTH: raise SystemExit('unmapped authority: %r' % r['authority'])
        key, extra = LIC[r['name']]
        a = AUTH[r['authority']]
        if key in type_auth and type_auth[key] != a and a is not None: flags.append('type %s: authorities %s / %s' % (key, type_auth[key], a))
        type_auth.setdefault(key, a)
        note = ' - '.join(n for n in (extra, r['note']) if n)
        docs.append((c[0], key, r['number'], r['authority'], r['issue'], r['expiry'], note or None))
w("INSERT INTO @TypeDef VALUES")
w(",\n".join("    (%s, %s, %s, %s, %s)" % (q(k), q(v[0]), q(v[1]), q(v[2]), q(type_auth.get(k))) for k, v in T.items() if k in type_auth) + ";")
w("DECLARE @Doc TABLE (Seq INT IDENTITY(1, 1), CompanyCode NVARCHAR(30), TypeKey VARCHAR(10), DocNumber NVARCHAR(100), Authority NVARCHAR(150), IssueDate DATE, ExpiryDate DATE, Notes NVARCHAR(500));")
w("INSERT INTO @Doc (CompanyCode, TypeKey, DocNumber, Authority, IssueDate, ExpiryDate, Notes) VALUES")
w(",\n".join("    (%s)" % ", ".join(q(v) for v in d) for d in docs) + ";")
# a company holds one current document per type
seen = {}
for d in docs:
    k = (d[0], d[1])
    if k in seen: raise SystemExit('two documents of one type for one company: %r' % (k,))
    seen[k] = 1
w("")

w("/* ---- vehicles -> Assets ----------------------------------------------- */")
w("DECLARE @Vehicle TABLE (Seq INT IDENTITY(1, 1), CompanyCode NVARCHAR(30), TypeName NVARCHAR(100), Brand NVARCHAR(100), Model NVARCHAR(100), Color NVARCHAR(50), Plate NVARCHAR(100), ExpiryDate DATE, Notes NVARCHAR(500));")
vrows = []
for c in COMPANIES:
    for r in x['vehicles'][c[5]]:
        v = VEH[(c[5], r['no'])]
        note = '%s%s%s' % (r['name'], (' - ' + r['note']) if r['note'] else '', (' - registered %s' % r['issue']) if r['issue'] else '')
        vrows.append((c[0], v[0], v[1], v[2], v[3], r['number'], r['expiry'], note))
w("INSERT INTO @Vehicle (CompanyCode, TypeName, Brand, Model, Color, Plate, ExpiryDate, Notes) VALUES")
w(",\n".join("    (%s)" % ", ".join(q(v) for v in r) for r in vrows) + ";")
w("")

w("/* ---- nationalities ---------------------------------------------------- */")
w("DECLARE @CountryMap TABLE (Nationality NVARCHAR(50) PRIMARY KEY, CountryCode NVARCHAR(10), CountryName NVARCHAR(100), CountryId INT NULL);")
w("INSERT INTO @CountryMap (Nationality, CountryCode, CountryName) VALUES")
w(",\n".join("    (%s, %s, %s)" % (q(k), q(v[0]), q(v[1])) for k, v in COUNTRY.items()) + ";")
w("")

w("/* ---- designations (the job title of the work permit, in English and Arabic) */")
w("DECLARE @Job TABLE (JobCode NVARCHAR(20) PRIMARY KEY, NameEn NVARCHAR(150), NameAr NVARCHAR(150));")
used = {}
for e in emps: used[e['job_code']] = (e['job_en'], e['job_ar'])
w("INSERT INTO @Job VALUES")
w(",\n".join("    (%s, %s, %s)" % (q(k), q(v[0]), q(v[1])) for k, v in sorted(used.items())) + ";")
w("")

w("/* ---- the employees (sheet \"Employee Data (3)\" + \"بيانات العمالة\", matched on the civil ID) */")
w("""DECLARE @Import TABLE (
    Sl INT PRIMARY KEY, CompanyCode NVARCHAR(30) NOT NULL, WorkplaceCode NVARCHAR(30) NULL,
    EmployeeCode NVARCHAR(20) NOT NULL, CodeGenerated BIT NOT NULL,
    FirstName NVARCHAR(100) NOT NULL, MiddleName NVARCHAR(100) NULL, LastName NVARCHAR(100) NULL, ArabicName NVARCHAR(300) NULL,
    Gender CHAR(1) NULL, DateOfBirth DATE NULL, Nationality NVARCHAR(50) NULL,
    CivilIdNumber NVARCHAR(20) NOT NULL, CivilIdExpiry DATE NULL, PassportNumber NVARCHAR(30) NULL, PassportExpiry DATE NULL,
    BasicSalary DECIMAL(12, 3) NULL, PermitSalary DECIMAL(12, 3) NULL,
    JobCode NVARCHAR(20) NULL, SponsorName NVARCHAR(200) NULL, SheetNotes NVARCHAR(300) NULL);""")
cols = ['sl', 'company', 'workplace', 'code', 'generated', 'first', 'middle', 'last', 'ar', 'gender', 'dob', 'nat', 'civil', 'civil_exp',
        'passport', 'passport_exp', 'salary', 'permit_salary', 'job_code', 'sponsor', 'notes']
w("INSERT INTO @Import VALUES")
def qv(k, v):
    if k == 'generated': return '1' if v else '0'
    if k in ('salary', 'permit_salary') and v is not None: return '%.3f' % float(v)
    return q(v)
w(",\n".join("    (" + ", ".join(qv(k, e[k]) for k in cols) + ")" for e in emps) + ";")
w("")
w(open(sys.argv[3], encoding='utf-8').read())   # body (hand-written)
open(sys.argv[4], 'w', encoding='utf-8-sig').write("\n".join(L))

json.dump({'generated': generated, 'flags': flags, 'emps': emps, 'companies': COMPANIES, 'vehicles': vrows,
           'cross': [(e['sl'], e['code'], e['first'] + ' ' + (e['last'] or ''), e['company'], e['workplace']) for e in emps if e['workplace']],
           'names': [(e['sl'], e['first'], e['middle'], e['last']) for e in emps]},
          open(sys.argv[5], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('ok', len(emps), 'employees', len(docs), 'documents', len(vrows), 'vehicles', len(generated), 'codes generated', flags)
