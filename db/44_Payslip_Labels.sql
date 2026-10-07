/* =====================================================================
   44_Payslip_Labels.sql  -  HRMS: English + Arabic labels of Payslips
   ---------------------------------------------------------------------
   Run after 33 (Core.UiLabels) and 42 / 43. Idempotent: new keys are
   inserted; existing keys are only completed (an empty ArabicText /
   SourceText is filled in) - text already edited in the table is never
   overwritten by a re-run. Edit any of these in Core.UiLabels and the
   screens show the change within 30 seconds, no code change.

     ps.*      Payslips screens, the payslip document (printed in English,
               Arabic or both) and the payslip email
     js.ps_*   texts used by wwwroot/js/payslips.js
     msg.ps_*  messages of Payroll.usp_Payslip_Manage (db/43) and
               PayslipsController - matched by their SourceText, so {0}
               values are carried into Arabic
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
    /* page titles (ViewData["Title"] is translated by its English text; Generate / Employee /
       Email Payslips already come from db/36) */
    ('ps.title_payslip', 'ps', N'Payslip', N'كشف الراتب', N'Payslip'),
    ('ps.title_my_payslips', 'ps', N'My Payslips', N'كشوف رواتبي', N'My Payslips'),
    ('ps.my_payslips', 'ps', N'My Payslips', N'كشوف رواتبي', NULL),
    ('ps.generate_subtitle', 'ps', N'Generate the payslips of a closed payroll in English, Arabic or both', N'إصدار كشوف رواتب مسير مغلق بالإنجليزية أو العربية أو كلتيهما', NULL),
    ('ps.employees_subtitle', 'ps', N'Find, view and print any employee''s payslip', N'البحث عن كشف راتب أي موظف وعرضه وطباعته', NULL),
    ('ps.email_subtitle', 'ps', N'Tell employees their payslip is ready and track delivery', N'إبلاغ الموظفين بجاهزية كشوف رواتبهم ومتابعة الإرسال', NULL),
    ('ps.my_subtitle', 'ps', N'Your payslips - view, print or save them as PDF', N'كشوف رواتبك - اعرضها أو اطبعها أو احفظها بصيغة PDF', NULL),

    /* payroll picker and banners */
    ('ps.payroll', 'ps', N'Payroll', N'مسير الرواتب', NULL),
    ('ps.all_payrolls', 'ps', N'All payrolls', N'جميع المسيرات', NULL),
    ('ps.stage_closed', 'ps', N'Closed', N'مغلق', NULL),
    ('ps.stage_awaiting_approval', 'ps', N'Awaiting approval', N'بانتظار الاعتماد', NULL),
    ('ps.stage_validation', 'ps', N'In validation', N'قيد التدقيق', NULL),
    ('ps.no_payrolls_title', 'ps', N'No payroll has payslips yet', N'لا يوجد مسير رواتب له كشوف بعد', NULL),
    ('ps.no_payrolls_text', 'ps', N'Payslips come from a payroll that has been validated. They are generated once it is approved and closed.', N'تُستخرج كشوف الرواتب من مسير تم تدقيقه، وتُصدر بعد اعتماده وإغلاقه.', NULL),
    ('ps.not_closed_title', 'ps', N'This payroll is not closed yet.', N'هذا المسير لم يُغلق بعد.', NULL),
    ('ps.not_closed_text', 'ps', N'Its payslips can be previewed, but they are generated and emailed only once the payroll is approved and closed.', N'يمكن معاينة كشوف رواتبه، لكنها لا تُصدر ولا تُرسل إلا بعد اعتماد المسير وإغلاقه.', NULL),
    ('ps.outdated_title', 'ps', N'{0} payslips are outdated.', N'{0} من كشوف الرواتب غير محدّثة.', NULL),
    ('ps.outdated_text', 'ps', N'The payroll was recalculated after they were generated. Generate the payslips again before emailing them.', N'أُعيد احتساب المسير بعد إصدارها. أعد إصدار الكشوف قبل إرسالها.', NULL),
    ('ps.email_privacy_title', 'ps', N'No salary figures are emailed.', N'لا تُرسل أي أرقام للرواتب بالبريد.', NULL),
    ('ps.email_privacy_text', 'ps', N'The email tells the employee their payslip is ready and links to My Payslips, where they sign in to view, print or save it.', N'تُبلغ الرسالة الموظف بجاهزية كشف راتبه وتتضمن رابطاً إلى كشوف رواتبي حيث يسجّل الدخول لعرضه أو طباعته أو حفظه.', NULL),
    ('ps.email_off_title', 'ps', N'Email sending is switched off.', N'إرسال البريد متوقف.', NULL),
    ('ps.email_off_text', 'ps', N'Queued emails wait until the mail server is set up in the settings (Payslips:Email). Ask your system administrator.', N'تبقى الرسائل في قائمة الانتظار حتى يُضبط خادم البريد في الإعدادات (Payslips:Email). راجع مسؤول النظام.', NULL),

    /* key figures */
    ('ps.kpi_net_note', 'ps', N'Net KWD {0}', N'الصافي {0} د.ك', NULL),
    ('ps.kpi_generated', 'ps', N'Generated', N'تم إصدارها', NULL),
    ('ps.kpi_generated_note', 'ps', N'Last on {0}', N'آخرها في {0}', NULL),
    ('ps.kpi_not_yet', 'ps', N'Not yet', N'ليس بعد', NULL),
    ('ps.kpi_to_generate', 'ps', N'To generate', N'بانتظار الإصدار', NULL),
    ('ps.kpi_to_generate_note', 'ps', N'{0} new · {1} outdated', N'{0} جديدة · {1} غير محدّثة', NULL),
    ('ps.kpi_emailed', 'ps', N'Emailed', N'أُرسلت بالبريد', NULL),
    ('ps.kpi_viewed_note', 'ps', N'{0} opened by the employee', N'{0} فتحها الموظف', NULL),
    ('ps.kpi_not_sent_note', 'ps', N'{0} not sent yet', N'{0} لم تُرسل بعد', NULL),
    ('ps.kpi_delivered', 'ps', N'Sent', N'أُرسلت', NULL),
    ('ps.kpi_queued_note', 'ps', N'{0} waiting in the queue', N'{0} في قائمة الانتظار', NULL),
    ('ps.kpi_failed', 'ps', N'Failed', N'تعذّر إرسالها', NULL),
    ('ps.kpi_failed_note', 'ps', N'Check the address, then resend', N'تحقق من العنوان ثم أعد الإرسال', NULL),
    ('ps.kpi_no_email', 'ps', N'No email address', N'بلا بريد إلكتروني', NULL),
    ('ps.kpi_no_email_note', 'ps', N'Add it on the employee profile', N'أضفه في ملف الموظف', NULL),

    /* generate */
    ('ps.generate_title', 'ps', N'Generate payslips', N'إصدار كشوف الرواتب', NULL),
    ('ps.who', 'ps', N'Employees', N'الموظفون', NULL),
    ('ps.scope_all', 'ps', N'Everyone in the payroll ({0})', N'جميع موظفي المسير ({0})', NULL),
    ('ps.scope_all_hint', 'ps', N'Generates or refreshes every payslip', N'يُصدر أو يحدّث جميع الكشوف', NULL),
    ('ps.scope_department', 'ps', N'One department', N'قسم واحد', NULL),
    ('ps.scope_department_hint', 'ps', N'Only the employees of a department', N'موظفو قسم واحد فقط', NULL),
    ('ps.language', 'ps', N'Language', N'اللغة', NULL),
    ('ps.template_bilingual', 'ps', N'Bilingual', N'ثنائي اللغة', NULL),
    ('ps.template_english', 'ps', N'English', N'الإنجليزية', NULL),
    ('ps.template_arabic', 'ps', N'Arabic', N'العربية', NULL),
    ('ps.template_bilingual_hint', 'ps', N'English and Arabic on one page (default)', N'الإنجليزية والعربية في صفحة واحدة (افتراضي)', NULL),
    ('ps.template_english_hint', 'ps', N'English only', N'الإنجليزية فقط', NULL),
    ('ps.template_arabic_hint', 'ps', N'Arabic only, right to left', N'العربية فقط، من اليمين إلى اليسار', NULL),
    ('ps.check_closed', 'ps', N'Payroll approved and closed', N'المسير معتمد ومغلق', NULL),
    ('ps.check_generated', 'ps', N'Payslips generated and up to date', N'الكشوف صادرة ومحدّثة', NULL),
    ('ps.check_emails', 'ps', N'Employees with an email address', N'الموظفون الذين لديهم بريد إلكتروني', NULL),
    ('ps.n_without_email', 'ps', N'{0} without email', N'{0} بلا بريد', NULL),
    ('ps.all_have_email', 'ps', N'Everyone', N'الجميع', NULL),
    ('ps.no_generate_right', 'ps', N'You can view payslips but not generate them.', N'يمكنك عرض الكشوف دون إصدارها.', NULL),
    ('ps.view_payslips', 'ps', N'View payslips', N'عرض الكشوف', NULL),
    ('ps.generate_payslips', 'ps', N'Generate payslips', N'إصدار الكشوف', NULL),
    ('ps.generate_again', 'ps', N'Generate again', N'إعادة الإصدار', NULL),
    ('ps.next_email', 'ps', N'Email payslips', N'إرسال الكشوف بالبريد', NULL),

    /* lists */
    ('ps.search_placeholder', 'ps', N'Search name, number or email', N'ابحث بالاسم أو الرقم أو البريد', NULL),
    ('ps.filter_all', 'ps', N'All', N'الكل', NULL),
    ('ps.filter_generated', 'ps', N'Generated', N'صادرة', NULL),
    ('ps.filter_not_generated', 'ps', N'Not generated', N'غير صادرة', NULL),
    ('ps.filter_outdated', 'ps', N'Outdated', N'غير محدّثة', NULL),
    ('ps.filter_not_sent', 'ps', N'Not sent yet', N'لم تُرسل بعد', NULL),
    ('ps.filter_queued', 'ps', N'Queued', N'في الانتظار', NULL),
    ('ps.filter_sent', 'ps', N'Sent', N'أُرسلت', NULL),
    ('ps.filter_failed', 'ps', N'Failed', N'تعذّر الإرسال', NULL),
    ('ps.filter_no_email', 'ps', N'No email address', N'بلا بريد إلكتروني', NULL),
    ('ps.1_employee', 'ps', N'1 employee', N'موظف واحد', NULL),
    ('ps.0_employees', 'ps', N'{0} employees', N'{0} موظفين', NULL),
    ('ps.no_match', 'ps', N'No payslip matches your search', N'لا يوجد كشف يطابق البحث', NULL),
    ('ps.no_payslips_yet', 'ps', N'No payslips here yet', N'لا توجد كشوف هنا بعد', NULL),
    ('ps.no_payslips_text', 'ps', N'Payslips are listed for every employee paid by a validated payroll.', N'تظهر الكشوف لكل موظف شمله مسير رواتب مدقق.', NULL),
    ('ps.payslips', 'ps', N'Payslips', N'كشوف الرواتب', NULL),
    ('ps.payslip', 'ps', N'Payslip', N'كشف الراتب', NULL),
    ('ps.email_address', 'ps', N'Email', N'البريد الإلكتروني', NULL),
    ('ps.sent_on', 'ps', N'Sent', N'تاريخ الإرسال', NULL),
    ('ps.emailed', 'ps', N'Emailed', N'البريد', NULL),
    ('ps.no_email_address', 'ps', N'No email address', N'لا يوجد بريد إلكتروني', NULL),
    ('ps.sent_to_0', 'ps', N'Sent to {0}', N'أُرسل إلى {0}', NULL),
    ('ps.queued_on_0', 'ps', N'Queued {0}', N'في الانتظار منذ {0}', NULL),
    ('ps.not_generated', 'ps', N'Not generated', N'غير صادر', NULL),
    ('ps.generated', 'ps', N'Generated', N'صادر', NULL),
    ('ps.outdated', 'ps', N'Outdated', N'غير محدّث', NULL),
    ('ps.preview_only', 'ps', N'Preview only', N'معاينة فقط', NULL),
    ('ps.viewed_by_employee', 'ps', N'Opened by the employee', N'فتحه الموظف', NULL),
    ('ps.email_not_sent', 'ps', N'Not sent', N'لم يُرسل', NULL),
    ('ps.email_queued', 'ps', N'Queued', N'في الانتظار', NULL),
    ('ps.email_sent', 'ps', N'Sent', N'أُرسل', NULL),
    ('ps.email_failed', 'ps', N'Failed', N'تعذّر الإرسال', NULL),
    ('ps.email_missing', 'ps', N'Missing', N'غير متوفر', NULL),
    ('ps.view', 'ps', N'View', N'عرض', NULL),
    ('ps.view_0', 'ps', N'View the payslip of {0}', N'عرض كشف راتب {0}', NULL),
    ('ps.print', 'ps', N'Print', N'طباعة', NULL),
    ('ps.print_0', 'ps', N'Print the payslip of {0}', N'طباعة كشف راتب {0}', NULL),
    ('ps.add_email', 'ps', N'Add email', N'إضافة بريد', NULL),
    ('ps.send', 'ps', N'Send', N'إرسال', NULL),
    ('ps.resend', 'ps', N'Resend', N'إعادة الإرسال', NULL),
    ('ps.send_all_not_sent', 'ps', N'Send to all not yet sent ({0})', N'إرسال لكل من لم يُرسل له ({0})', NULL),

    /* the payslip document */
    ('ps.back_to_payslips', 'ps', N'Back to payslips', N'العودة إلى الكشوف', NULL),
    ('ps.back_to_my_payslips', 'ps', N'Back to my payslips', N'العودة إلى كشوف رواتبي', NULL),
    ('ps.lang_both', 'ps', N'EN + ع', N'EN + ع', NULL),
    ('ps.print_save_pdf', 'ps', N'Print / Save PDF', N'طباعة / حفظ PDF', NULL),
    ('ps.watermark', 'ps', N'Not final', N'غير نهائي', NULL),
    ('ps.watermark_not_final', 'ps', N'Preview - the payroll is not closed yet.', N'معاينة - المسير لم يُغلق بعد.', NULL),
    ('ps.watermark_not_generated', 'ps', N'This payslip has not been generated yet.', N'لم يُصدر هذا الكشف بعد.', NULL),
    ('ps.watermark_outdated', 'ps', N'This payslip is outdated - the payroll was recalculated after it was generated.', N'هذا الكشف غير محدّث - أُعيد احتساب المسير بعد إصداره.', NULL),
    ('ps.banner_generate_text', 'ps', N'The employee sees it only once it is generated.', N'لا يراه الموظف إلا بعد إصداره.', NULL),
    ('ps.generate_this', 'ps', N'Generate this payslip', N'إصدار هذا الكشف', NULL),
    ('ps.doc_title', 'ps', N'Payslip', N'كشف الراتب', NULL),
    ('ps.doc_payslip_no', 'ps', N'Payslip No.', N'رقم الكشف', NULL),
    ('ps.doc_employee', 'ps', N'Employee', N'الموظف', NULL),
    ('ps.doc_employee_no', 'ps', N'Employee No.', N'الرقم الوظيفي', NULL),
    ('ps.doc_civil_id', 'ps', N'Civil ID', N'الرقم المدني', NULL),
    ('ps.doc_department', 'ps', N'Department', N'القسم', NULL),
    ('ps.doc_designation', 'ps', N'Designation', N'المسمى الوظيفي', NULL),
    ('ps.doc_bank', 'ps', N'Bank account', N'الحساب البنكي', NULL),
    ('ps.doc_period', 'ps', N'Pay period', N'فترة الراتب', NULL),
    ('ps.doc_paid_days', 'ps', N'Paid days', N'الأيام المدفوعة', NULL),
    ('ps.doc_pay_date', 'ps', N'Pay date', N'تاريخ الصرف', NULL),
    ('ps.doc_joined', 'ps', N'Joining date', N'تاريخ الالتحاق', NULL),
    ('ps.doc_earnings', 'ps', N'Earnings', N'الاستحقاقات', NULL),
    ('ps.doc_deductions', 'ps', N'Deductions', N'الاستقطاعات', NULL),
    ('ps.doc_total_earnings', 'ps', N'Total earnings', N'إجمالي الاستحقاقات', NULL),
    ('ps.doc_total_deductions', 'ps', N'Total deductions', N'إجمالي الاستقطاعات', NULL),
    ('ps.doc_net_salary', 'ps', N'Net salary', N'صافي الراتب', NULL),
    ('ps.doc_generated', 'ps', N'Generated {0} · {1}', N'صدر في {0} · {1}', NULL),
    ('ps.doc_computer_generated', 'ps', N'Computer-generated payslip - no signature required.', N'كشف صادر آلياً - لا يتطلب توقيعاً.', NULL),

    /* My Payslips */
    ('ps.my_latest', 'ps', N'Latest payslip', N'أحدث كشف راتب', NULL),
    ('ps.my_all', 'ps', N'All payslips', N'جميع الكشوف', NULL),
    ('ps.net_pay', 'ps', N'Net pay', N'صافي الراتب', NULL),
    ('ps.paid_on_0', 'ps', N'Paid {0}', N'صُرف في {0}', NULL),
    ('ps.new', 'ps', N'New', N'جديد', NULL),
    ('ps.1_payslip', 'ps', N'1 payslip', N'كشف واحد', NULL),
    ('ps.0_payslips', 'ps', N'{0} payslips', N'{0} كشوف', NULL),
    ('ps.my_empty_title', 'ps', N'No payslips yet', N'لا توجد كشوف بعد', NULL),
    ('ps.my_empty_text', 'ps', N'Your payslip appears here once the payroll is closed and HR has generated the payslips.', N'يظهر كشف راتبك هنا بعد إغلاق المسير وإصدار الكشوف من الموارد البشرية.', NULL),
    ('ps.my_no_employee_title', 'ps', N'Your user is not linked to an employee', N'حسابك غير مرتبط بموظف', NULL),
    ('ps.my_no_employee_text', 'ps', N'Ask HR to link your user account to your employee record to see your payslips here.', N'اطلب من الموارد البشرية ربط حسابك بسجلك الوظيفي لعرض كشوف رواتبك هنا.', NULL),

    /* the payslip email */
    ('ps.email_subject', 'ps', N'Your payslip for {0} is ready', N'كشف راتبك لشهر {0} جاهز', NULL),
    ('ps.email_greeting', 'ps', N'Dear {0},', N'عزيزي/عزيزتي {0}،', NULL),
    ('ps.email_body', 'ps', N'Your payslip for {0} ({1}) is ready. Sign in to the HR system and open My Payslips to view, print or save it.', N'كشف راتبك لفترة {0} ({1}) جاهز. سجّل الدخول إلى نظام الموارد البشرية وافتح كشوف رواتبي لعرضه أو طباعته أو حفظه.', NULL),
    ('ps.email_action', 'ps', N'Open My Payslips', N'فتح كشوف رواتبي', NULL),
    ('ps.email_privacy', 'ps', N'For your privacy this email does not contain any salary figures. If you did not expect it, contact HR.', N'حفاظاً على خصوصيتك لا تتضمن هذه الرسالة أي أرقام للراتب. إن لم تكن تتوقعها فتواصل مع الموارد البشرية.', NULL),

    /* payslips.js */
    ('js.ps_failed', 'js', N'The request could not be completed.', N'تعذّر إتمام الطلب.', NULL),
    ('js.ps_choose_department', 'js', N'Choose the department.', N'اختر القسم.', NULL),

    /* procedure and controller messages */
    ('msg.ps_unsupported_action', 'msg', N'Unsupported action.', N'إجراء غير مدعوم.', N'Unsupported action.'),
    ('msg.ps_email_not_sending', 'msg', N'This payslip email is no longer being sent.', N'لم تعد رسالة هذا الكشف قيد الإرسال.', N'This payslip email is no longer being sent.'),
    ('msg.ps_no_payroll', 'msg', N'This payroll no longer exists or has no payslips.', N'هذا المسير لم يعد موجوداً أو ليس له كشوف.', N'This payroll no longer exists or has no payslips.'),
    ('msg.ps_not_closed', 'msg', N'Payslips can only be generated and emailed once the payroll is approved and closed.', N'لا تُصدر الكشوف ولا تُرسل إلا بعد اعتماد المسير وإغلاقه.', N'Payslips can only be generated and emailed once the payroll is approved and closed.'),
    ('msg.ps_select_language', 'msg', N'Select the payslip language.', N'اختر لغة الكشف.', N'Select the payslip language.'),
    ('msg.ps_nothing_to_generate', 'msg', N'No employee of this payroll matches your choice.', N'لا يوجد موظف في هذا المسير يطابق اختيارك.', N'No employee of this payroll matches your choice.'),
    ('msg.ps_1_generated', 'msg', N'1 payslip generated.', N'تم إصدار كشف واحد.', N'1 payslip generated.'),
    ('msg.ps_n_generated', 'msg', N'{0} payslips generated.', N'تم إصدار {0} كشوف.', N'{0} payslips generated.'),
    ('msg.ps_no_email_any', 'msg', N'None of these employees has an email address. Add it on the employee profile.', N'لا يملك أي من هؤلاء الموظفين بريداً إلكترونياً. أضفه في ملف الموظف.', N'None of these employees has an email address. Add it on the employee profile.'),
    ('msg.ps_nothing_to_send', 'msg', N'There is no generated, up-to-date payslip left to email. Generate the payslips first.', N'لا يوجد كشف صادر ومحدّث بانتظار الإرسال. أصدر الكشوف أولاً.', N'There is no generated, up-to-date payslip left to email. Generate the payslips first.'),
    ('msg.ps_n_queued', 'msg', N'{0} payslip emails queued.', N'أُضيفت {0} رسائل إلى قائمة الإرسال.', N'{0} payslip emails queued.'),
    ('msg.ps_1_queued', 'msg', N'1 payslip email queued.', N'أُضيفت رسالة واحدة إلى قائمة الإرسال.', N'1 payslip email queued.'),
    ('msg.ps_1_queued_no_email', 'msg', N'1 payslip email queued. No email address: {0}.', N'أُضيفت رسالة واحدة إلى قائمة الإرسال. بلا بريد إلكتروني: {0}.', N'1 payslip email queued. No email address: {0}.'),
    ('msg.ps_n_queued_no_email', 'msg', N'{0} payslip emails queued. No email address: {1}.', N'أُضيفت {0} رسائل إلى قائمة الإرسال. بلا بريد إلكتروني: {1}.', N'{0} payslip emails queued. No email address: {1}.'),
    ('msg.ps_select_payroll', 'msg', N'Select a payroll.', N'اختر مسير الرواتب.', N'Select a payroll.');
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

/* procedure messages of db/43 harvested by an earlier run of db/33 (msg.auto_*) get their Arabic too */
UPDATE l
   SET l.ArabicText = s.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN   #Seed AS s ON s.Module = 'msg' AND l.EnglishText = s.EnglishText COLLATE Latin1_General_BIN
WHERE  l.Deleted = 0 AND l.LabelKey LIKE 'msg.auto[_]%' AND NULLIF(l.ArabicText, N'') IS NULL AND s.ArabicText IS NOT NULL;

PRINT CONCAT(N'Payslip labels inserted: ', @Inserted, N', completed: ', @Completed);
DROP TABLE #Seed;
GO
