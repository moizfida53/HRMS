/* =====================================================================
   61_Employee_PayrollCalendar_Audit_Labels.sql  -  HRMS: English + Arabic
   labels of the employee payroll calendar, Create Payroll by calendar and
   the Audit Report (db/60)
   ---------------------------------------------------------------------
   Run after 33 (Core.UiLabels) and 60. Idempotent: new keys are inserted;
   existing keys are only completed (an empty ArabicText / SourceText is
   filled in) - text already edited in the table is never overwritten.

     emp.paycal_*   the Payroll Calendar field of the employee profile
     pr.cr_*        Create Payroll: one payroll per payroll calendar
     aud.*          the Audit Report; aud.t_* / aud.f_* are the transaction
                    types and audited field names (matched by English text)
     msg.*          messages of EmployeesController and the db/35 / db/60
                    procedures - matched by their SourceText
   ===================================================================== */
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'tempdb..#Seed') IS NOT NULL DROP TABLE #Seed;
CREATE TABLE #Seed (
    LabelKey    VARCHAR(150)   COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    Module      VARCHAR(30)    COLLATE DATABASE_DEFAULT NOT NULL,
    EnglishText NVARCHAR(1000) COLLATE DATABASE_DEFAULT NOT NULL,
    ArabicText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
    SourceText  NVARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
);
INSERT INTO #Seed (LabelKey, Module, EnglishText, ArabicText, SourceText) VALUES
    ('emp.payroll_calendar', 'emp', N'Payroll Calendar', N'تقويم الرواتب', NULL),
    ('emp.paycal_hint', 'emp', N'The employee is paid by this calendar''s payrolls.', N'يُصرف راتب الموظف ضمن مسيرات هذا التقويم.', NULL),
    ('emp.paycal_change_hint', 'emp', N'Changing it needs a reason and is recorded in the Audit Report.', N'يتطلب تغييره ذكر السبب، ويُسجَّل في تقرير التدقيق.', NULL),
    ('emp.paycal_locked_hint', 'emp', N'Assigned. Only an administrator can change the payroll calendar.', N'مُعيَّن. لا يمكن تغيير تقويم الرواتب إلا من قِبل المسؤول.', NULL),
    ('emp.paycal_no_calendar_for_company', 'emp', N'This company has no active payroll calendar yet - add one in Payroll Calendar first.', N'لا يوجد تقويم رواتب نشط لهذه الشركة - أضف تقويماً من شاشة تقويم الرواتب أولاً.', NULL),
    ('emp.paycal_default', 'emp', N'Default', N'افتراضي', NULL),
    ('emp.paycal_reason', 'emp', N'Reason for changing the payroll calendar', N'سبب تغيير تقويم الرواتب', NULL),
    ('emp.paycal_reason_placeholder', 'emp', N'e.g. Moved to the weekly-paid site team', N'مثال: انتقل إلى فريق الموقع ذي الرواتب الأسبوعية', NULL),
    ('emp.paycal_reason_hint', 'emp', N'Saved with the change in the Audit Report.', N'يُحفظ مع التغيير في تقرير التدقيق.', NULL),
    ('emp.audit_history', 'emp', N'Audit history', N'سجل التدقيق', NULL),
    ('layout.audit_report', 'layout', N'Audit Report', N'تقرير التدقيق', NULL),
    ('sec.fn_payroll_calendar', 'sec', N'Change payroll calendar', N'تغيير تقويم الرواتب', NULL),
    ('sec.fn_payroll_calendar_hint', 'sec', N'Change an employee''s payroll calendar once it is assigned (the first assignment comes with Create / Edit).', N'تغيير تقويم رواتب الموظف بعد تعيينه (التعيين الأول متاح مع صلاحية الإنشاء / التعديل).', NULL),
    ('sec.pg_audit_report', 'sec', N'Audit Report', N'تقرير التدقيق', NULL),
    ('sec.pg_audit_report_hint', 'sec', N'Every audited change of each employee: payroll calendar, employee record, salary and bank, payroll inclusion.', N'كل التغييرات المدققة لكل موظف: تقويم الرواتب، وسجل الموظف، والراتب والبنك، والإدراج في المسير.', NULL),
    ('aud.subtitle', 'aud', N'Who changed what for each employee, and when', N'من غيّر ماذا لكل موظف، ومتى', NULL),
    ('aud.all_companies', 'aud', N'All companies', N'كل الشركات', NULL),
    ('aud.all_employees', 'aud', N'All employees', N'كل الموظفين', NULL),
    ('aud.all_transactions', 'aud', N'All transactions', N'كل الحركات', NULL),
    ('aud.all_in_group', 'aud', N'All: {0}', N'الكل: {0}', NULL),
    ('aud.group_calendar', 'aud', N'Payroll calendar', N'تقويم الرواتب', NULL),
    ('aud.group_employee', 'aud', N'Employee record', N'سجل الموظف', NULL),
    ('aud.group_salary', 'aud', N'Salary & bank', N'الراتب والبنك', NULL),
    ('aud.group_payroll', 'aud', N'Payroll inclusion', N'الإدراج في المسير', NULL),
    ('aud.transaction_type', 'aud', N'Transaction type', N'نوع الحركة', NULL),
    ('aud.date_range', 'aud', N'Date range', N'الفترة', NULL),
    ('aud.from', 'aud', N'From', N'من', NULL),
    ('aud.to', 'aud', N'To', N'إلى', NULL),
    ('aud.quick_ranges', 'aud', N'Quick date ranges', N'فترات سريعة', NULL),
    ('aud.today', 'aud', N'Today', N'اليوم', NULL),
    ('aud.last_7_days', 'aud', N'Last 7 days', N'آخر 7 أيام', NULL),
    ('aud.last_30_days', 'aud', N'Last 30 days', N'آخر 30 يوماً', NULL),
    ('aud.last_12_months', 'aud', N'Last 12 months', N'آخر 12 شهراً', NULL),
    ('aud.search_placeholder', 'aud', N'Search employee, value or reference', N'ابحث عن موظف أو قيمة أو مرجع', NULL),
    ('aud.reset_filters', 'aud', N'Reset filters', N'إعادة ضبط التصفية', NULL),
    ('aud.date_time', 'aud', N'Date & time', N'التاريخ والوقت', NULL),
    ('aud.change', 'aud', N'Change', N'التغيير', NULL),
    ('aud.changed_by', 'aud', N'Changed by', N'بواسطة', NULL),
    ('aud.changed_to', 'aud', N'changed to', N'تغيّر إلى', NULL),
    ('aud.field', 'aud', N'Field', N'الحقل', NULL),
    ('aud.old_value', 'aud', N'Old value', N'القيمة السابقة', NULL),
    ('aud.new_value', 'aud', N'New value', N'القيمة الجديدة', NULL),
    ('aud.reference', 'aud', N'Reference', N'المرجع', NULL),
    ('aud.remarks', 'aud', N'Remarks', N'ملاحظات', NULL),
    ('aud.only_this_employee', 'aud', N'Show this employee only', N'عرض هذا الموظف فقط', NULL),
    ('aud.1_transaction', 'aud', N'1 transaction', N'حركة واحدة', NULL),
    ('aud.n_transactions', 'aud', N'{0} transactions', N'{0} حركة', NULL),
    ('aud.no_match', 'aud', N'No transaction matches the filters', N'لا توجد حركة تطابق التصفية', NULL),
    ('aud.no_transactions', 'aud', N'No transactions yet', N'لا توجد حركات بعد', NULL),
    ('aud.empty_hint', 'aud', N'Widen the date range or choose another employee or transaction type.', N'وسّع الفترة أو اختر موظفاً أو نوع حركة آخر.', NULL),
    ('pr.cr_payroll_month', 'pr', N'Payroll month', N'شهر الرواتب', NULL),
    ('pr.cr_month_hint', 'pr', N'Every payroll calendar your employees are on gets its own payroll for this month.', N'لكل تقويم رواتب يتبعه موظفوك مسيرٌ خاص به لهذا الشهر.', NULL),
    ('pr.cr_no_month', 'pr', N'No open payroll period - generate periods on the payroll calendars first.', N'لا توجد فترة رواتب مفتوحة - أنشئ الفترات في تقاويم الرواتب أولاً.', NULL),
    ('pr.cr_payrolls_to_create', 'pr', N'Payrolls to create', N'المسيرات التي ستُنشأ', NULL),
    ('pr.cr_plan_hint', 'pr', N'One payroll per payroll calendar, paying only the employees on that calendar. Untick a calendar to leave it out.', N'مسير واحد لكل تقويم رواتب، يصرف فقط لموظفي ذلك التقويم. ألغِ تحديد التقويم لاستبعاده.', NULL),
    ('pr.cr_no_calendar_in_month', 'pr', N'No employee of this company is on a payroll calendar with an open period in this month.', N'لا يوجد موظف في هذه الشركة على تقويم رواتب له فترة مفتوحة في هذا الشهر.', NULL),
    ('pr.cr_choose_one', 'pr', N'Choose at least one payroll to create.', N'اختر مسيراً واحداً على الأقل لإنشائه.', NULL),
    ('pr.cr_n_employees', 'pr', N'{0} employees', N'{0} موظف', NULL),
    ('pr.cr_1_employee', 'pr', N'1 employee', N'موظف واحد', NULL),
    ('pr.cr_incl_unassigned', 'pr', N'incl. {0} without a calendar', N'منهم {0} بلا تقويم', NULL),
    ('pr.cr_ready', 'pr', N'Ready', N'جاهز', NULL),
    ('pr.cr_regular_exists', 'pr', N'Already created: {0}', N'أُنشئ مسبقاً: {0}', NULL),
    ('pr.cr_no_open_period', 'pr', N'No open period in this month', N'لا توجد فترة مفتوحة في هذا الشهر', NULL),
    ('pr.cr_no_employees', 'pr', N'No employees', N'لا يوجد موظفون', NULL),
    ('pr.cr_summary', 'pr', N'{0} payrolls · {1} employees', N'{0} مسيرات · {1} موظف', NULL),
    ('pr.cr_unassigned_default', 'pr', N'Employees without a payroll calendar: {0}. They are paid by the default calendar until one is assigned.', N'موظفون بلا تقويم رواتب: {0}. يُصرف لهم ضمن التقويم الافتراضي إلى أن يُعيَّن لهم تقويم.', NULL),
    ('pr.cr_unassigned_none', 'pr', N'Employees without a payroll calendar: {0}. The company has no default calendar, so they are not paid until one is assigned.', N'موظفون بلا تقويم رواتب: {0}. لا يوجد تقويم افتراضي للشركة، فلن يُصرف لهم حتى يُعيَّن لهم تقويم.', NULL),
    ('pr.cr_on_inactive', 'pr', N'Employees on an inactive payroll calendar: {0}. They are not in any payroll.', N'موظفون على تقويم رواتب غير نشط: {0}. لن يُدرجوا في أي مسير.', NULL),
    ('pr.cr_calendars_not_ready', 'pr', N'Employee payroll calendars are not set up yet (run db/60): the default calendar pays every employee.', N'تقاويم رواتب الموظفين غير مُعدّة بعد (شغّل db/60): يصرف التقويم الافتراضي لجميع الموظفين.', NULL),
    ('pr.cr_desc_required_offcycle', 'pr', N'Required: an off-cycle payroll needs a reason.', N'مطلوب: المسير خارج الدورة يحتاج إلى سبب.', NULL),
    ('pr.cr_scope_applies_to_all', 'pr', N'The filters below apply to every payroll being created.', N'تنطبق عوامل التصفية أدناه على كل المسيرات التي ستُنشأ.', NULL),
    ('pr.cr_payrolls', 'pr', N'Payrolls', N'المسيرات', NULL),
    ('pr.cr_switch_hint', 'pr', N'Review each payroll - click to switch.', N'راجع كل مسير - انقر للتبديل.', NULL),
    ('pr.cr_ready_n', 'pr', N'Ready to create {0} payrolls', N'جاهز لإنشاء {0} مسيرات', NULL),
    ('pr.cr_create_n_payrolls', 'pr', N'Create {0} payrolls', N'إنشاء {0} مسيرات', NULL),
    ('pr.cr_creating_0_of_1', 'pr', N'Creating payroll {0} of {1}…', N'جارٍ إنشاء المسير {0} من {1}…', NULL),
    ('pr.cr_created_n', 'pr', N'{0} created - fix the next one and press Create again.', N'تم إنشاء {0} - صحّح المسير التالي واضغط إنشاء مجدداً.', NULL),
    ('pr.cr_enter_reason', 'pr', N'Enter the reason for this payroll.', N'أدخل سبب هذا المسير.', NULL),
    ('msg.emp_paycal_not_saved', 'msg', N'The payroll calendar could not be saved.', N'تعذّر حفظ تقويم الرواتب.', N'The payroll calendar could not be saved.'),
    ('pr.cr_desc_optional', 'pr', N'Optional for a regular payroll.', N'اختياري للمسير العادي.', NULL),
    ('pr.cr_discard_drafts', 'pr', N'Discard drafts', N'حذف المسودات', NULL),
    ('pr.cr_unfinished_n', 'pr', N'You have {0} unfinished payrolls', N'لديك {0} مسيرات غير مكتملة', NULL),
    ('js.pr_discard_drafts', 'js', N'Discard these drafts? The lines added in them are removed.', N'حذف هذه المسودات؟ ستُحذف البنود المضافة فيها.', NULL),
    ('aud.t_calendar_assigned', 'aud', N'Payroll calendar assigned', N'تعيين تقويم الرواتب', NULL),
    ('aud.t_calendar_changed', 'aud', N'Payroll calendar changed', N'تغيير تقويم الرواتب', NULL),
    ('aud.t_employee_created', 'aud', N'Employee created', N'إنشاء موظف', NULL),
    ('aud.t_employee_updated', 'aud', N'Employee updated', N'تعديل بيانات موظف', NULL),
    ('aud.t_employee_activated', 'aud', N'Employee activated', N'تفعيل موظف', NULL),
    ('aud.t_employee_deactivated', 'aud', N'Employee deactivated', N'إيقاف موظف', NULL),
    ('aud.t_employee_deleted', 'aud', N'Employee deleted', N'حذف موظف', NULL),
    ('aud.t_salary_changed', 'aud', N'Salary changed', N'تغيير الراتب', NULL),
    ('aud.t_bank_changed', 'aud', N'Bank details changed', N'تغيير البيانات البنكية', NULL),
    ('aud.t_payroll_excluded', 'aud', N'Excluded from payroll', N'استبعاد من المسير', NULL),
    ('aud.t_payroll_included', 'aud', N'Included in payroll', N'إدراج في المسير', NULL),
    ('aud.f_first_name', 'aud', N'First name', N'الاسم الأول', NULL),
    ('aud.f_middle_name', 'aud', N'Middle name', N'الاسم الأوسط', NULL),
    ('aud.f_last_name', 'aud', N'Last name', N'اسم العائلة', NULL),
    ('aud.f_arabic_name', 'aud', N'Arabic name', N'الاسم بالعربية', NULL),
    ('aud.f_company', 'aud', N'Company', N'الشركة', NULL),
    ('aud.f_branch', 'aud', N'Branch', N'الفرع', NULL),
    ('aud.f_department', 'aud', N'Department', N'الإدارة', NULL),
    ('aud.f_section', 'aud', N'Section', N'القسم', NULL),
    ('aud.f_job_position', 'aud', N'Job position', N'الوظيفة', NULL),
    ('aud.f_designation', 'aud', N'Designation', N'المسمى الوظيفي', NULL),
    ('aud.f_grade', 'aud', N'Grade', N'الدرجة', NULL),
    ('aud.f_cost_center', 'aud', N'Cost center', N'مركز التكلفة', NULL),
    ('aud.f_work_location', 'aud', N'Work location', N'موقع العمل', NULL),
    ('aud.f_reporting_manager', 'aud', N'Reporting manager', N'المدير المباشر', NULL),
    ('aud.f_hire_date', 'aud', N'Hire date', N'تاريخ التعيين', NULL),
    ('aud.f_probation_end', 'aud', N'Probation end date', N'تاريخ انتهاء فترة التجربة', NULL),
    ('aud.f_termination_date', 'aud', N'Termination date', N'تاريخ انتهاء الخدمة', NULL),
    ('aud.f_employment_type', 'aud', N'Employment type', N'نوع التوظيف', NULL),
    ('aud.f_employment_status', 'aud', N'Employment status', N'حالة التوظيف', NULL),
    ('aud.f_notice_period', 'aud', N'Notice period (days)', N'فترة الإشعار (أيام)', NULL),
    ('aud.f_nationality', 'aud', N'Nationality', N'الجنسية', NULL),
    ('aud.f_date_of_birth', 'aud', N'Date of birth', N'تاريخ الميلاد', NULL),
    ('aud.f_mobile', 'aud', N'Mobile number', N'رقم الهاتف المحمول', NULL),
    ('aud.f_work_email', 'aud', N'Work email', N'البريد الإلكتروني للعمل', NULL),
    ('aud.f_basic_salary', 'aud', N'Basic salary (KWD)', N'الراتب الأساسي (د.ك)', NULL),
    ('aud.f_allowances', 'aud', N'Allowances (KWD)', N'البدلات (د.ك)', NULL),
    ('aud.f_bank_name', 'aud', N'Bank name', N'اسم البنك', NULL),
    ('aud.f_iban', 'aud', N'IBAN / account no.', N'رقم الآيبان / الحساب', NULL),
    ('aud.f_active', 'aud', N'Active', N'نشط', NULL),
    ('aud.f_payroll', 'aud', N'Payroll', N'المسير', NULL),
    ('aud.f_payroll_calendar', 'aud', N'Payroll calendar', N'تقويم الرواتب', NULL),
    ('aud.system', 'aud', N'System', N'النظام', NULL),
    ('aud.initial_assignment', 'aud', N'Initial assignment: the company''s default payroll calendar (db/60).', N'تعيين أولي: تقويم الرواتب الافتراضي للشركة (db/60).', NULL),
    ('msg.emp_paycal_required', 'msg', N'Choose the payroll calendar the employee is paid by.', N'اختر تقويم الرواتب الذي يُصرف للموظف بموجبه.', N'Choose the payroll calendar the employee is paid by.'),
    ('msg.emp_paycal_other_company', 'msg', N'The employee''s payroll calendar belongs to another company. Only an administrator can change it.', N'تقويم رواتب الموظف يتبع شركة أخرى. لا يمكن تغييره إلا من قِبل المسؤول.', N'The employee''s payroll calendar belongs to another company. Only an administrator can change it.'),
    ('msg.emp_paycal_same_company', 'msg', N'Choose a payroll calendar of the employee''s company.', N'اختر تقويم رواتب يتبع شركة الموظف.', N'Choose a payroll calendar of the employee''s company.'),
    ('msg.emp_paycal_admin_only', 'msg', N'Only an administrator can change the payroll calendar once it is assigned.', N'لا يمكن تغيير تقويم الرواتب بعد تعيينه إلا من قِبل المسؤول.', N'Only an administrator can change the payroll calendar once it is assigned.'),
    ('msg.emp_paycal_reason_required', 'msg', N'Enter the reason for changing the payroll calendar.', N'أدخل سبب تغيير تقويم الرواتب.', N'Enter the reason for changing the payroll calendar.'),
    ('msg.emp_paycal_choose', 'msg', N'Choose the payroll calendar of the employee.', N'اختر تقويم الرواتب للموظف.', N'Choose the payroll calendar of the employee.'),
    ('msg.emp_paycal_must_belong', 'msg', N'The payroll calendar must belong to the employee''s company.', N'يجب أن يتبع تقويم الرواتب شركة الموظف.', N'The payroll calendar must belong to the employee''s company.'),
    ('msg.emp_paycal_assigned', 'msg', N'Payroll calendar assigned.', N'تم تعيين تقويم الرواتب.', N'Payroll calendar assigned.'),
    ('msg.emp_paycal_changed', 'msg', N'Payroll calendar changed.', N'تم تغيير تقويم الرواتب.', N'Payroll calendar changed.'),
    ('msg.pr_calendar_inactive', 'msg', N'This payroll calendar is inactive.', N'تقويم الرواتب هذا غير نشط.', N'This payroll calendar is inactive.'),
    ('msg.pr_reason_first_of_period', 'msg', N'Enter the reason for this payroll - it is not the first payroll for this period.', N'أدخل سبب هذا المسير - فهو ليس أول مسير لهذه الفترة.', N'Enter the reason for this payroll - it is not the first payroll for this period.'),
    ('msg.aud_created_salary', 'msg', N'Basic salary {0} KWD, allowances {1} KWD', N'الراتب الأساسي {0} د.ك، البدلات {1} د.ك', N'Basic salary {0} KWD, allowances {1} KWD');
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM   #Seed AS s
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey AND l.Deleted = 0);

DECLARE @Inserted INT = @@ROWCOUNT;

UPDATE l
   SET l.ArabicText = ISNULL(NULLIF(l.ArabicText, N''), s.ArabicText),
       l.SourceText = ISNULL(l.SourceText, s.SourceText)
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.LabelKey = l.LabelKey
WHERE  l.Deleted = 0
  AND (   (NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL)
       OR (l.SourceText IS NULL AND s.SourceText IS NOT NULL));

DECLARE @Completed INT = @@ROWCOUNT;

/* controller messages harvested earlier as msg.auto_* get their Arabic too */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.Module = 'msg' AND l.EnglishText = s.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND l.LabelKey LIKE 'msg.auto[_]%' AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT CONCAT(N'Payroll calendar / audit labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
