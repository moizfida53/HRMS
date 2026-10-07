/* =====================================================================
   46_Payroll_Settings_Labels.sql  -  HRMS: English + Arabic labels of the
   Payroll Settings screens (Payroll > Payroll Settings)
   ---------------------------------------------------------------------
   Run after 33 (Core.UiLabels). Only labels - the screens use the
   procedures of db/30 (and later db/47+). Idempotent: new keys are
   inserted, existing keys only completed (text already edited in
   Core.UiLabels is never overwritten).

     st.*       Payroll Settings screens
     js.st_*    wwwroot/js/payroll-settings.js
     msg.st_*   messages of the settings procedures - matched by SourceText
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
    ('js.st_failed', 'js', N'The request could not be completed.', N'تعذّر إتمام الطلب.', NULL),
    ('st.title_pay_item_types', 'st', N'Pay Item Types', N'أنواع بنود الرواتب', N'Pay Item Types'),
    ('st.item_types_subtitle', 'st', N'The earnings and deductions offered when adding a pay item, and how the payroll treats them', N'الاستحقاقات والاستقطاعات المتاحة عند إضافة بند راتب، وكيف يعاملها مسير الرواتب', NULL),
    ('st.item_types_banner_title', 'st', N'Data-driven.', N'تُدار من البيانات.', NULL),
    ('st.item_types_banner_text', 'st', N'Add, rename or deactivate item types without any code change. Standard types (Basic Salary, PIFSS, Loan ...) are known to the payroll engine: they can be renamed and re-flagged but not deleted.', N'أضف أنواع البنود أو أعد تسميتها أو أوقفها دون أي تعديل برمجي. الأنواع القياسية (الراتب الأساسي، التأمينات، القرض ...) يعرفها محرك الرواتب: يمكن إعادة تسميتها وتعديل خصائصها دون حذفها.', NULL),
    ('st.add_item_type', 'st', N'Add item type', N'إضافة نوع بند', NULL),
    ('st.edit_item_type', 'st', N'Edit item type', N'تعديل نوع البند', NULL),
    ('st.delete_item_type_text', 'st', N'Delete this item type? It can only be deleted while no salary structure uses it.', N'حذف نوع البند هذا؟ لا يمكن حذفه إلا إذا لم يُستخدم في أي هيكل رواتب.', NULL),
    ('st.add_standard_types', 'st', N'Add standard types', N'إضافة الأنواع القياسية', NULL),
    ('st.add_standard_types_hint', 'st', N'Adds the standard item types this company is missing (Basic Salary, PIFSS, Loan ...)', N'يضيف الأنواع القياسية الناقصة لهذه الشركة (الراتب الأساسي، التأمينات، القرض ...)', NULL),
    ('st.search_item_types', 'st', N'Search code, name or GL account', N'ابحث بالرمز أو الاسم أو حساب الأستاذ', NULL),
    ('st.type', 'st', N'Type', N'النوع', NULL),
    ('st.all_types', 'st', N'All types', N'جميع الأنواع', NULL),
    ('st.earnings', 'st', N'Earnings', N'الاستحقاقات', NULL),
    ('st.deductions', 'st', N'Deductions', N'الاستقطاعات', NULL),
    ('st.1_item_type', 'st', N'1 item type', N'نوع بند واحد', NULL),
    ('st.0_item_types', 'st', N'{0} item types', N'{0} أنواع بنود', NULL),
    ('st.no_item_types_match', 'st', N'No item type matches your search', N'لا يوجد نوع بند يطابق البحث', NULL),
    ('st.no_item_types_yet', 'st', N'No item types yet', N'لا توجد أنواع بنود بعد', NULL),
    ('st.no_item_types_text', 'st', N'Use Add standard types to load Basic Salary, PIFSS, Loan and the other standard types, then add your own.', N'استخدم إضافة الأنواع القياسية لتحميل الراتب الأساسي والتأمينات والقرض وغيرها، ثم أضف أنواعك.', NULL),
    ('st.pay_item_types', 'st', N'Pay item types', N'أنواع بنود الرواتب', NULL),
    ('st.item_type', 'st', N'Item type', N'نوع البند', NULL),
    ('st.class', 'st', N'Class', N'الفئة', NULL),
    ('st.class_salary', 'st', N'Salary', N'راتب', NULL),
    ('st.class_earning', 'st', N'Earning', N'استحقاق', NULL),
    ('st.class_deduction', 'st', N'Deduction', N'استقطاع', NULL),
    ('st.class_loan', 'st', N'Loan / advance', N'قرض / سلفة', NULL),
    ('st.class_statutory', 'st', N'Statutory', N'نظامي', NULL),
    ('st.calculation', 'st', N'Calculation', N'طريقة الحساب', NULL),
    ('st.included_in', 'st', N'Included in', N'يدخل في', NULL),
    ('st.gl_account', 'st', N'GL account', N'حساب الأستاذ العام', NULL),
    ('st.gl_account_name', 'st', N'GL account name', N'اسم حساب الأستاذ العام', NULL),
    ('st.standard', 'st', N'Standard', N'قياسي', NULL),
    ('st.standard_hint', 'st', N'A standard type the payroll engine relies on', N'نوع قياسي يعتمد عليه محرك الرواتب', NULL),
    ('st.standard_type', 'st', N'Standard type.', N'نوع قياسي.', NULL),
    ('st.standard_type_text', 'st', N'The payroll engine knows it by its code and type, so those cannot change; name, flags and accounting can.', N'يعرفه محرك الرواتب برمزه ونوعه، لذا لا يمكن تغييرهما؛ أما الاسم والخصائص والحسابات فيمكن تعديلها.', NULL),
    ('st.of', 'st', N'of', N'من', NULL),
    ('st.recurring', 'st', N'Recurring', N'متكرر', NULL),
    ('st.one_time', 'st', N'One-time', N'لمرة واحدة', NULL),
    ('st.fixed', 'st', N'Fixed', N'ثابت', NULL),
    ('st.variable', 'st', N'Variable', N'متغير', NULL),
    ('st.method', 'st', N'Method', N'الطريقة', NULL),
    ('st.method_amount', 'st', N'Amount', N'مبلغ', NULL),
    ('st.method_percentage', 'st', N'Percentage', N'نسبة مئوية', NULL),
    ('st.method_days', 'st', N'Days', N'أيام', NULL),
    ('st.method_hours', 'st', N'Hours', N'ساعات', NULL),
    ('st.method_formula', 'st', N'Formula', N'معادلة', NULL),
    ('st.method_system', 'st', N'Calculated by the payroll', N'يحتسبه مسير الرواتب', NULL),
    ('st.base', 'st', N'Base', N'الأساس', NULL),
    ('st.base_basic', 'st', N'Basic salary', N'الراتب الأساسي', NULL),
    ('st.base_fixed_gross', 'st', N'Fixed gross', N'الإجمالي الثابت', NULL),
    ('st.base_overtime', 'st', N'Overtime base', N'أساس العمل الإضافي', NULL),
    ('st.base_indemnity', 'st', N'Indemnity base', N'أساس مكافأة نهاية الخدمة', NULL),
    ('st.flag_pifss', 'st', N'PIFSS', N'التأمينات', NULL),
    ('st.flag_eos', 'st', N'End of service', N'نهاية الخدمة', NULL),
    ('st.flag_overtime', 'st', N'Overtime', N'العمل الإضافي', NULL),
    ('st.flag_leave', 'st', N'Leave salary', N'راتب الإجازة', NULL),
    ('st.flag_prorated', 'st', N'Prorated', N'يُحتسب بالتناسب', NULL),
    ('st.flag_taxable', 'st', N'Taxable', N'خاضع للضريبة', NULL),
    ('st.name_english', 'st', N'Name (English)', N'الاسم (إنجليزي)', NULL),
    ('st.name_arabic', 'st', N'Name (Arabic)', N'الاسم (عربي)', NULL),
    ('st.payslip_label', 'st', N'Payslip label', N'التسمية في كشف الراتب', NULL),
    ('st.payslip_label_hint', 'st', N'Leave empty to use the name', N'اتركه فارغاً لاستخدام الاسم', NULL),
    ('st.display_order', 'st', N'Display order', N'ترتيب العرض', NULL),
    ('st.earning', 'st', N'Earning', N'استحقاق', NULL),
    ('st.earning_hint', 'st', N'Adds to the pay', N'يُضاف إلى الراتب', NULL),
    ('st.deduction', 'st', N'Deduction', N'استقطاع', NULL),
    ('st.deduction_hint', 'st', N'Taken from the pay', N'يُخصم من الراتب', NULL),
    ('st.value_type', 'st', N'Value', N'القيمة', NULL),
    ('st.default_amount', 'st', N'Default amount (KWD)', N'المبلغ الافتراضي (د.ك)', NULL),
    ('st.default_percentage', 'st', N'Default percentage', N'النسبة الافتراضية', NULL),
    ('st.formula', 'st', N'Formula', N'المعادلة', NULL),
    ('st.min_amount', 'st', N'Minimum amount', N'الحد الأدنى', NULL),
    ('st.max_amount', 'st', N'Maximum amount', N'الحد الأقصى', NULL),
    ('st.behaviour', 'st', N'Behaviour', N'السلوك', NULL),
    ('st.recurring_hint', 'st', N'Paid or taken every month until ended', N'يُصرف أو يُخصم كل شهر حتى إيقافه', NULL),
    ('st.prorated_hint', 'st', N'Paid for the days worked in a partial month', N'يُصرف عن أيام العمل في الشهر الجزئي', NULL),
    ('st.show_on_payslip', 'st', N'Show on payslip', N'يظهر في كشف الراتب', NULL),
    ('st.show_on_payslip_hint', 'st', N'Listed as its own line on the payslip', N'يظهر كسطر مستقل في كشف الراتب', NULL),
    ('st.taxable_hint', 'st', N'Counted as taxable income', N'يُحتسب دخلاً خاضعاً للضريبة', NULL),
    ('st.included_in_bases', 'st', N'Included in the bases of (earnings only)', N'يدخل في أساس احتساب (للاستحقاقات فقط)', NULL),
    ('st.pifss_hint', 'st', N'Part of the PIFSS contribution salary', N'جزء من راتب الاشتراك في التأمينات', NULL),
    ('st.eos_hint', 'st', N'Part of the end-of-service indemnity salary', N'جزء من راتب مكافأة نهاية الخدمة', NULL),
    ('st.overtime_hint', 'st', N'Part of the overtime hourly rate base', N'جزء من أساس أجر ساعة العمل الإضافي', NULL),
    ('st.leave_hint', 'st', N'Part of the leave salary', N'جزء من راتب الإجازة', NULL),
    ('st.accounting', 'st', N'Accounting', N'المحاسبة', NULL),
    ('st.cost_center', 'st', N'Cost center', N'مركز التكلفة', NULL),
    ('st.employee_cost_center', 'st', N'The employee''s cost center', N'مركز تكلفة الموظف', NULL),
    ('st.description', 'st', N'Description', N'الوصف', NULL),
    ('msg.st_pc_created_earning', 'msg', N'Earning component created successfully.', N'تم إنشاء نوع الاستحقاق بنجاح.', N'Earning component created successfully.'),
    ('msg.st_pc_created_deduction', 'msg', N'Deduction component created successfully.', N'تم إنشاء نوع الاستقطاع بنجاح.', N'Deduction component created successfully.'),
    ('msg.st_pc_updated', 'msg', N'Component updated successfully.', N'تم تحديث نوع البند بنجاح.', N'Component updated successfully.'),
    ('msg.st_pc_deleted', 'msg', N'Component deleted successfully.', N'تم حذف نوع البند بنجاح.', N'Component deleted successfully.'),
    ('msg.st_pc_activated', 'msg', N'Component activated.', N'تم تفعيل نوع البند.', N'Component activated.'),
    ('msg.st_pc_deactivated', 'msg', N'Component deactivated.', N'تم إيقاف نوع البند.', N'Component deactivated.'),
    ('msg.st_pc_seed_none', 'msg', N'This company already has all the standard components.', N'لدى هذه الشركة جميع الأنواع القياسية.', N'This company already has all the standard components.'),
    ('msg.st_pc_seed_n', 'msg', N'{0} standard component(s) added.', N'أُضيف {0} من الأنواع القياسية.', N'{0} standard component(s) added.'),
    ('msg.st_pc_basic', 'msg', N'Basic Salary is required by the payroll engine and cannot be deactivated.', N'الراتب الأساسي مطلوب لمحرك الرواتب ولا يمكن إيقافه.', N'Basic Salary is required by the payroll engine and cannot be deactivated.'),
    ('msg.st_pc_basic_delete', 'msg', N'Basic Salary is required by the payroll engine and cannot be deleted.', N'الراتب الأساسي مطلوب لمحرك الرواتب ولا يمكن حذفه.', N'Basic Salary is required by the payroll engine and cannot be deleted.'),
    ('msg.st_pc_std_delete', 'msg', N'This is a standard component the payroll engine relies on. Deactivate it instead of deleting it.', N'هذا نوع قياسي يعتمد عليه محرك الرواتب. أوقفه بدلاً من حذفه.', N'This is a standard component the payroll engine relies on. Deactivate it instead of deleting it.'),
    ('msg.st_pc_in_use', 'msg', N'This component is used in a salary structure and cannot be deleted. Remove it from the structure or deactivate it instead.', N'هذا النوع مستخدم في هيكل رواتب ولا يمكن حذفه. أزله من الهيكل أو أوقفه.', N'This component is used in a salary structure and cannot be deleted. Remove it from the structure or deactivate it instead.'),
    ('msg.st_pc_dup', 'msg', N'That code is already in use. Enter a different code.', N'هذا الرمز مستخدم. أدخل رمزاً آخر.', N'That code is already in use. Enter a different code.'),
    ('msg.st_pc_earn_flags', 'msg', N'Social security, end-of-service, overtime and leave-salary flags apply to earnings only.', N'خصائص التأمينات ونهاية الخدمة والعمل الإضافي وراتب الإجازة تخص الاستحقاقات فقط.', N'Social security, end-of-service, overtime and leave-salary flags apply to earnings only.'),
    ('msg.st_pc_need_base', 'msg', N'Percentage, Days and Hours methods need a calculation base (Basic, Fixed gross, Overtime base or Indemnity base).', N'طرق النسبة والأيام والساعات تحتاج إلى أساس احتساب (الأساسي، الإجمالي الثابت، أساس العمل الإضافي أو أساس نهاية الخدمة).', N'Percentage, Days and Hours methods need a calculation base (Basic, Fixed gross, Overtime base or Indemnity base).'),
    ('msg.st_pc_need_pct', 'msg', N'Enter the default percentage.', N'أدخل النسبة الافتراضية.', N'Enter the default percentage.'),
    ('msg.st_pc_need_formula', 'msg', N'Enter the formula.', N'أدخل المعادلة.', N'Enter the formula.'),
    ('msg.st_pc_minmax', 'msg', N'Maximum amount cannot be less than the minimum amount.', N'لا يمكن أن يقل الحد الأقصى عن الحد الأدنى.', N'Maximum amount cannot be less than the minimum amount.'),
    ('msg.st_pc_cc', 'msg', N'The selected cost center does not belong to this company.', N'مركز التكلفة المختار لا يتبع هذه الشركة.', N'The selected cost center does not belong to this company.');
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

/* messages harvested by an earlier run of db/33 (msg.auto_*) get their Arabic too */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.Module = 'msg' AND l.EnglishText = s.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND l.LabelKey LIKE 'msg.auto[_]%' AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT CONCAT(N'Payroll Settings labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
