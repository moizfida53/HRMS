/* =====================================================================
   58_Security_Labels.sql  -  HRMS: English + Arabic labels of Security >
   Create Roles / Assign Roles, and of their messages
   ---------------------------------------------------------------------
   Run after db/57. Idempotent: new keys are inserted, existing keys only
   completed (text already edited in Core.UiLabels is never overwritten).

     sec.*      the Views/Security pages, Security/AccessCatalog.cs
     layout.*   the sidebar's Security group
     js.sec_*   wwwroot/js/security.js
     msg.sec_*  messages of db/57 and SecurityController (matched by SourceText)
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
    ('layout.security', 'layout', N'Security', N'الأمان', NULL),
    ('layout.create_roles', 'layout', N'Create Roles', N'إنشاء الأدوار', NULL),
    ('layout.assign_roles', 'layout', N'Assign Roles', N'تعيين الأدوار', NULL),
    ('js.sec_failed', 'js', N'The request could not be completed.', N'تعذّر إتمام الطلب.', NULL),
    ('js.sec_discard_changes', 'js', N'Discard the changes to this role?', N'هل تريد تجاهل التغييرات على هذا الدور؟', NULL),
    ('js.sec_summary', 'js', N'{0} pages · {1} functions · {2} approval rights', N'{0} صفحات · {1} وظائف · {2} صلاحيات اعتماد', NULL),
    ('js.sec_expand_all', 'js', N'Expand all', N'توسيع الكل', NULL),
    ('js.sec_collapse_all', 'js', N'Collapse all', N'طي الكل', NULL),
    ('js.sec_name_code', 'js', N'Enter the role name and a code (letters, digits and _).', N'أدخل اسم الدور ورمزاً له (حروف وأرقام و _).', NULL),
    ('sec.roles_subtitle', 'sec', N'Create a role and choose what it may read, change and approve on every page', N'أنشئ دوراً واختر ما يمكنه عرضه وتعديله واعتماده في كل صفحة', NULL),
    ('sec.assign_subtitle', 'sec', N'Give users their roles - their access is the rights of all their roles', N'امنح المستخدمين أدوارهم - صلاحياتهم هي مجموع صلاحيات أدوارهم', NULL),
    ('sec.roles', 'sec', N'Roles', N'الأدوار', NULL),
    ('sec.role', 'sec', N'Role', N'الدور', NULL),
    ('sec.new_role', 'sec', N'New role', N'دور جديد', NULL),
    ('sec.new_role_text', 'sec', N'Name the role, then tick what it may do on each page.', N'سمِّ الدور ثم حدّد ما يمكنه فعله في كل صفحة.', NULL),
    ('sec.search_roles', 'sec', N'Search roles', N'ابحث في الأدوار', NULL),
    ('sec.no_roles', 'sec', N'No roles yet.', N'لا توجد أدوار بعد.', NULL),
    ('sec.pick_role', 'sec', N'Choose a role', N'اختر دوراً', NULL),
    ('sec.pick_role_text', 'sec', N'Pick a role on the left to see and change its access, or create a new one.', N'اختر دوراً من القائمة لعرض صلاحياته وتعديلها، أو أنشئ دوراً جديداً.', NULL),
    ('sec.n_users', 'sec', N'{0} users', N'{0} مستخدمين', NULL),
    ('sec.n_rights', 'sec', N'{0} rights', N'{0} صلاحيات', NULL),
    ('sec.role_meta', 'sec', N'{0} users · {1} rights', N'{0} مستخدمين · {1} صلاحيات', NULL),
    ('sec.system', 'sec', N'System', N'نظام', NULL),
    ('sec.system_role', 'sec', N'System role', N'دور النظام', NULL),
    ('sec.system_role_text', 'sec', N'System Administrator always has every right. It cannot be changed or deleted.', N'مسؤول النظام يملك جميع الصلاحيات دائماً، ولا يمكن تعديله أو حذفه.', NULL),
    ('sec.read_only', 'sec', N'Read-only', N'للعرض فقط', NULL),
    ('sec.read_only_text', 'sec', N'You can see this role but not change it (it is shared by every company, or you have no right to edit roles).', N'يمكنك عرض هذا الدور دون تعديله (مشترك بين جميع الشركات أو ليست لديك صلاحية تعديل الأدوار).', NULL),
    ('sec.role_name', 'sec', N'Role name', N'اسم الدور', NULL),
    ('sec.role_code', 'sec', N'Role code', N'رمز الدور', NULL),
    ('sec.all_companies', 'sec', N'All companies', N'جميع الشركات', NULL),
    ('sec.active', 'sec', N'Active', N'نشط', NULL),
    ('sec.inactive', 'sec', N'Inactive', N'غير نشط', NULL),
    ('sec.description', 'sec', N'Description', N'الوصف', NULL),
    ('sec.description_hint', 'sec', N'What this role is for, e.g. "Prepares the monthly payroll"', N'الغرض من هذا الدور، مثل "يُعِدّ الرواتب الشهرية"', NULL),
    ('sec.page_access', 'sec', N'Page access', N'صلاحيات الصفحات', NULL),
    ('sec.page_access_text', 'sec', N'Tick Read, Write or Full for each page and its functions. A page tick applies to its functions; open a page to fine-tune them.', N'حدّد عرض أو كتابة أو كامل لكل صفحة ووظائفها. تحديد الصفحة ينطبق على وظائفها، وافتح الصفحة لضبط كل وظيفة.', NULL),
    ('sec.search_pages', 'sec', N'Search pages and functions', N'ابحث في الصفحات والوظائف', NULL),
    ('sec.quick_set', 'sec', N'Quick set', N'تحديد سريع', NULL),
    ('sec.all_read', 'sec', N'Read everything', N'عرض الكل', NULL),
    ('sec.all_full', 'sec', N'Full everywhere', N'كامل للكل', NULL),
    ('sec.clear_all', 'sec', N'Clear all', N'مسح الكل', NULL),
    ('sec.expand_all', 'sec', N'Expand all', N'توسيع الكل', NULL),
    ('sec.legend', 'sec', N'Legend', N'دليل الألوان', NULL),
    ('sec.read', 'sec', N'Read', N'عرض', NULL),
    ('sec.write', 'sec', N'Write', N'كتابة', NULL),
    ('sec.full', 'sec', N'Full', N'كامل', NULL),
    ('sec.read_hint', 'sec', N'see it, read-only', N'الاطلاع فقط', NULL),
    ('sec.write_hint', 'sec', N'add, edit, process', N'إضافة وتعديل ومعالجة', NULL),
    ('sec.full_hint', 'sec', N'write + delete, cancel, reopen', N'الكتابة + الحذف والإلغاء وإعادة الفتح', NULL),
    ('sec.page_function', 'sec', N'Page / function', N'الصفحة / الوظيفة', NULL),
    ('sec.all_0_in_1', 'sec', N'{0} for every page of {1}', N'{0} لكل صفحات {1}', NULL),
    ('sec.0_on_1', 'sec', N'{0}: {1}', N'{0}: {1}', NULL),
    ('sec.functions_of_0', 'sec', N'Functions of {0}', N'وظائف {0}', NULL),
    ('sec.n_functions', 'sec', N'{0} functions', N'{0} وظائف', NULL),
    ('sec.not_applicable', 'sec', N'Not applicable', N'لا ينطبق', NULL),
    ('sec.with_page', 'sec', N'Read with its page', N'العرض مع الصفحة', NULL),
    ('sec.no_pages_match', 'sec', N'No pages or functions match.', N'لا توجد صفحات أو وظائف مطابقة.', NULL),
    ('sec.approval_rights', 'sec', N'Approval rights', N'صلاحيات الاعتماد', NULL),
    ('sec.approval_rights_text', 'sec', N'Who reviews (level 1), who approves (level 2) and who may approve their own submissions, per process.', N'من يراجع (المستوى 1) ومن يعتمد (المستوى 2) ومن يمكنه اعتماد ما قدّمه بنفسه، لكل عملية.', NULL),
    ('sec.process', 'sec', N'Process', N'العملية', NULL),
    ('sec.level_1', 'sec', N'Level 1', N'المستوى 1', NULL),
    ('sec.level_1_hint', 'sec', N'HR review', N'مراجعة الموارد البشرية', NULL),
    ('sec.level_2', 'sec', N'Level 2', N'المستوى 2', NULL),
    ('sec.level_2_hint', 'sec', N'Finance approval', N'اعتماد المالية', NULL),
    ('sec.self_approve', 'sec', N'Approve own', N'اعتماد الذاتي', NULL),
    ('sec.self_approve_hint', 'sec', N'their own submissions', N'ما قدّموه بأنفسهم', NULL),
    ('sec.approval_note', 'sec', N'The amount limits and the roles of each level are set on Payroll Settings > Approval Workflow.', N'حدود المبالغ وأدوار كل مستوى تُضبط في إعدادات الرواتب > مسار الاعتماد.', NULL),
    ('sec.unsaved', 'sec', N'Unsaved changes', N'تغييرات غير محفوظة', NULL),
    ('sec.discard', 'sec', N'Discard', N'تجاهل', NULL),
    ('sec.create_role', 'sec', N'Create role', N'إنشاء الدور', NULL),
    ('sec.save_role', 'sec', N'Save role', N'حفظ الدور', NULL),
    ('sec.delete_role', 'sec', N'Delete role', N'حذف الدور', NULL),
    ('sec.delete_confirm', 'sec', N'Delete the role {0}? Users must not have it any more.', N'هل تريد حذف الدور {0}؟ يجب ألا يكون مُسنداً لأي مستخدم.', NULL),
    ('sec.mod_workforce', 'sec', N'Workforce', N'القوى العاملة', NULL),
    ('sec.mod_organization', 'sec', N'Organization setup', N'إعداد المنشأة', NULL),
    ('sec.mod_payroll', 'sec', N'Payroll processing', N'معالجة الرواتب', NULL),
    ('sec.mod_payslips', 'sec', N'Payslips', N'قسائم الرواتب', NULL),
    ('sec.mod_finance', 'sec', N'Bank, accounting & reports', N'البنك والمحاسبة والتقارير', NULL),
    ('sec.mod_settings', 'sec', N'Payroll settings', N'إعدادات الرواتب', NULL),
    ('sec.mod_security', 'sec', N'Security', N'الأمان', NULL),
    ('sec.pg_employees', 'sec', N'Employees', N'الموظفون', NULL),
    ('sec.pg_employees_hint', 'sec', N'list, add an employee (Write), delete / deactivate (Full)', N'القائمة، إضافة موظف (كتابة)، حذف / تعطيل (كامل)', NULL),
    ('sec.fn_personal', 'sec', N'Personal info & employment', N'البيانات الشخصية والوظيفية', NULL),
    ('sec.fn_personal_hint', 'sec', N'read with the profile; Write = edit', N'تُعرض مع الملف؛ الكتابة = التعديل', NULL),
    ('sec.fn_compliance', 'sec', N'Kuwait compliance', N'الامتثال الكويتي', NULL),
    ('sec.fn_dependents', 'sec', N'Dependents', N'المُعالون', NULL),
    ('sec.fn_documents', 'sec', N'Documents', N'المستندات', NULL),
    ('sec.fn_documents_hint', 'sec', N'Write = upload, Full = remove', N'الكتابة = الرفع، الكامل = الإزالة', NULL),
    ('sec.pg_organization', 'sec', N'Organization setup', N'إعداد المنشأة', NULL),
    ('sec.pg_organization_hint', 'sec', N'branches, departments, sections, designations, positions, locations, cost centers', N'الفروع والأقسام والوحدات والمسميات والوظائف والمواقع ومراكز التكلفة', NULL),
    ('sec.fn_companies', 'sec', N'Companies', N'الشركات', NULL),
    ('sec.fn_companies_hint', 'sec', N'add / edit companies (Write), delete (Full)', N'إضافة / تعديل الشركات (كتابة)، حذف (كامل)', NULL),
    ('sec.pg_payroll_dashboard', 'sec', N'Payroll dashboard', N'لوحة الرواتب', NULL),
    ('sec.pg_payrolls', 'sec', N'Payrolls', N'الرواتب', NULL),
    ('sec.pg_payrolls_hint', 'sec', N'create, register, validate and submit; history', N'الإنشاء والتسجيل والتحقق والإرسال؛ السجل', NULL),
    ('sec.fn_run_exclude', 'sec', N'Exclude / include employees', N'استبعاد / إعادة إدراج الموظفين', NULL),
    ('sec.fn_run_cancel', 'sec', N'Cancel a payroll', N'إلغاء الرواتب', NULL),
    ('sec.fn_run_reopen', 'sec', N'Reopen a closed payroll', N'إعادة فتح رواتب مغلقة', NULL),
    ('sec.pg_calendar', 'sec', N'Payroll calendar & pay periods', N'تقويم الرواتب وفترات الدفع', NULL),
    ('sec.pg_calendar_hint', 'sec', N'pay groups and their periods', N'مجموعات الدفع وفتراتها', NULL),
    ('sec.pg_pay_items', 'sec', N'Pay items & loans', N'بنود الرواتب والقروض', NULL),
    ('sec.pg_pay_items_hint', 'sec', N'earnings, deductions, salary changes, loans', N'الاستحقاقات والاستقطاعات وتغييرات الراتب والقروض', NULL),
    ('sec.pg_settlement', 'sec', N'Final settlement', N'التسوية النهائية', NULL),
    ('sec.fn_fs_pay', 'sec', N'Mark as paid', N'تعليم كمدفوعة', NULL),
    ('sec.pg_payslips', 'sec', N'Payslips', N'قسائم الرواتب', NULL),
    ('sec.pg_payslips_hint', 'sec', N'employee payslips; Write = generate', N'قسائم الموظفين؛ الكتابة = الإنشاء', NULL),
    ('sec.fn_payslip_email', 'sec', N'Email payslips', N'إرسال القسائم بالبريد', NULL),
    ('sec.pg_bank', 'sec', N'Bank processing', N'المعالجة البنكية', NULL),
    ('sec.pg_bank_hint', 'sec', N'bank files and the payment register', N'ملفات البنك وسجل المدفوعات', NULL),
    ('sec.pg_accounting', 'sec', N'Accounting', N'المحاسبة', NULL),
    ('sec.pg_accounting_hint', 'sec', N'payroll journal, GL posting, cost allocation', N'قيد الرواتب والترحيل ومراكز التكلفة', NULL),
    ('sec.pg_reports', 'sec', N'Payroll reports', N'تقارير الرواتب', NULL),
    ('sec.pg_payroll_settings', 'sec', N'Payroll settings', N'إعدادات الرواتب', NULL),
    ('sec.pg_payroll_settings_hint', 'sec', N'rules, pay item types, deductions, proration, approvals, banks, GL mapping', N'القواعد وأنواع البنود والاستقطاعات والتناسب والاعتماد والبنوك وربط الحسابات', NULL),
    ('sec.pg_roles', 'sec', N'Create roles', N'إنشاء الأدوار', NULL),
    ('sec.pg_roles_hint', 'sec', N'Write = create / change roles, Full = delete', N'الكتابة = إنشاء / تعديل الأدوار، الكامل = الحذف', NULL),
    ('sec.pg_assign', 'sec', N'Assign roles', N'تعيين الأدوار', NULL),
    ('sec.pg_assign_hint', 'sec', N'Write = give and remove roles', N'الكتابة = منح الأدوار وإزالتها', NULL),
    ('sec.apr_payroll', 'sec', N'Payroll run', N'دورة الرواتب', NULL),
    ('sec.apr_payroll_hint', 'sec', N'submitted payrolls', N'الرواتب المُرسلة للاعتماد', NULL),
    ('sec.apr_pay_items', 'sec', N'Pay items, salary changes & loans', N'بنود الرواتب وتغييرات الراتب والقروض', NULL),
    ('sec.apr_pay_items_hint', 'sec', N'items waiting for approval', N'البنود بانتظار الاعتماد', NULL),
    ('sec.apr_settlement', 'sec', N'Final settlement', N'التسوية النهائية', NULL),
    ('sec.apr_settlement_hint', 'sec', N'end of service, resignation, encashment', N'نهاية الخدمة والاستقالة وصرف الإجازات', NULL),
    ('sec.search_users', 'sec', N'Search name, username or email', N'ابحث بالاسم أو اسم المستخدم أو البريد', NULL),
    ('sec.all_roles', 'sec', N'All roles', N'جميع الأدوار', NULL),
    ('sec.no_role', 'sec', N'No role', N'بدون دور', NULL),
    ('sec.users', 'sec', N'Users', N'المستخدمون', NULL),
    ('sec.user', 'sec', N'User', N'المستخدم', NULL),
    ('sec.1_user', 'sec', N'1 user', N'مستخدم واحد', NULL),
    ('sec.n_users_count', 'sec', N'{0} users', N'{0} مستخدمين', NULL),
    ('sec.no_users', 'sec', N'No users yet.', N'لا يوجد مستخدمون بعد.', NULL),
    ('sec.no_users_match', 'sec', N'No users match.', N'لا يوجد مستخدمون مطابقون.', NULL),
    ('sec.last_sign_in', 'sec', N'Last sign-in', N'آخر دخول', NULL),
    ('sec.assign_roles', 'sec', N'Assign roles', N'تعيين الأدوار', NULL),
    ('sec.view_roles', 'sec', N'View roles', N'عرض الأدوار', NULL),
    ('sec.roles_of_0', 'sec', N'Roles of {0}', N'أدوار {0}', NULL),
    ('sec.save_roles', 'sec', N'Save roles', N'حفظ الأدوار', NULL),
    ('sec.assign_hint', 'sec', N'Tick the roles this user has. Their access is everything their roles allow; changes apply within a minute.', N'حدّد أدوار هذا المستخدم. صلاحياته هي كل ما تسمح به أدواره، وتسري التغييرات خلال دقيقة.', NULL),
    ('sec.cannot_assign', 'sec', N'You can only give roles whose rights you hold yourself', N'يمكنك منح الأدوار التي تملك صلاحياتها فقط', NULL),
    ('msg.sec_role_gone', 'msg', N'That role no longer exists. Refresh and try again.', N'هذا الدور لم يعد موجوداً. حدّث الصفحة وحاول مجدداً.', N'That role no longer exists. Refresh and try again.'),
    ('msg.sec_system_rights', 'msg', N'System Administrator is a system role - it always has every right.', N'مسؤول النظام دور نظام - يملك جميع الصلاحيات دائماً.', N'System Administrator is a system role - it always has every right.'),
    ('msg.sec_shared_change', 'msg', N'Only a System Administrator can change a role shared by every company.', N'فقط مسؤول النظام يمكنه تعديل دور مشترك بين جميع الشركات.', N'Only a System Administrator can change a role shared by every company.'),
    ('msg.sec_code_name', 'msg', N'Enter the role code and name.', N'أدخل رمز الدور واسمه.', N'Enter the role code and name.'),
    ('msg.sec_code_rule', 'msg', N'The role code may use letters, digits and _ only, and cannot be SYSADMIN.', N'رمز الدور يقبل الحروف والأرقام و _ فقط، ولا يمكن أن يكون SYSADMIN.', N'The role code may use letters, digits and _ only, and cannot be SYSADMIN.'),
    ('msg.sec_code_taken', 'msg', N'Another role already uses this code.', N'هناك دور آخر يستخدم هذا الرمز.', N'Another role already uses this code.'),
    ('msg.sec_role_created', 'msg', N'Role created.', N'تم إنشاء الدور.', N'Role created.'),
    ('msg.sec_role_saved', 'msg', N'Role saved.', N'تم حفظ الدور.', N'Role saved.'),
    ('msg.sec_role_created_kept', 'msg', N'Role created. Rights you do not hold yourself were left out.', N'تم إنشاء الدور. الصلاحيات التي لا تملكها لم تُضَف.', N'Role created. Rights you do not hold yourself were left out.'),
    ('msg.sec_role_saved_kept', 'msg', N'Role saved. Rights you do not hold yourself were left as they were.', N'تم حفظ الدور. الصلاحيات التي لا تملكها بقيت كما هي.', N'Role saved. Rights you do not hold yourself were left as they were.'),
    ('msg.sec_system_delete', 'msg', N'System Administrator is a system role and cannot be deleted.', N'مسؤول النظام دور نظام ولا يمكن حذفه.', N'System Administrator is a system role and cannot be deleted.'),
    ('msg.sec_shared_delete', 'msg', N'Only a System Administrator can delete a role shared by every company.', N'فقط مسؤول النظام يمكنه حذف دور مشترك بين جميع الشركات.', N'Only a System Administrator can delete a role shared by every company.'),
    ('msg.sec_role_in_use', 'msg', N'Users still have this role. Remove it from them on Assign Roles first.', N'ما زال هذا الدور مُسنداً لمستخدمين. أزله منهم في تعيين الأدوار أولاً.', N'Users still have this role. Remove it from them on Assign Roles first.'),
    ('msg.sec_role_deleted', 'msg', N'Role deleted.', N'تم حذف الدور.', N'Role deleted.'),
    ('msg.sec_user_gone', 'msg', N'That user was not found.', N'لم يُعثر على هذا المستخدم.', N'That user was not found.'),
    ('msg.sec_sysadmin_only', 'msg', N'Only a System Administrator can give or remove the System Administrator role.', N'فقط مسؤول النظام يمكنه منح دور مسؤول النظام أو إزالته.', N'Only a System Administrator can give or remove the System Administrator role.'),
    ('msg.sec_last_admin', 'msg', N'This is the last active System Administrator - give the role to another user first.', N'هذا آخر مسؤول نظام نشط - امنح الدور لمستخدم آخر أولاً.', N'This is the last active System Administrator - give the role to another user first.'),
    ('msg.sec_roles_saved', 'msg', N'Roles saved. They apply to the user within a minute.', N'تم حفظ الأدوار، وتسري على المستخدم خلال دقيقة.', N'Roles saved. They apply to the user within a minute.'),
    ('msg.sec_no_escalation', 'msg', N'You can only give or remove roles whose rights you hold yourself.', N'يمكنك منح أو إزالة الأدوار التي تملك صلاحياتها فقط.', N'You can only give or remove roles whose rights you hold yourself.'),
    ('msg.sec_record_gone', 'msg', N'That record was not found. Refresh and try again.', N'لم يُعثر على السجل. حدّث الصفحة وحاول مجدداً.', N'That record was not found. Refresh and try again.'),
    ('msg.sec_record_missing', 'msg', N'That record was not found.', N'لم يُعثر على السجل.', N'That record was not found.'),
    ('msg.sec_no_right', 'msg', N'You do not have permission to do this.', N'ليست لديك صلاحية للقيام بذلك.', N'You do not have permission to do this.');
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

PRINT CONCAT(N'Security labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
