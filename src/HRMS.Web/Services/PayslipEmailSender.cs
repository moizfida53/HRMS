using System.Globalization;
using System.Net;
using System.Net.Mail;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Services;

/// <summary>
/// Settings for emailing payslips - the "Payslips:Email" section of
/// appsettings.json. The SMTP password is a secret: set it with user secrets
/// or the environment (Payslips__Email__Password), never in appsettings.json.
/// </summary>
public sealed class PayslipEmailOptions
{
    public const string SectionName = "Payslips:Email";

    /// <summary>Off by default: queued emails wait (status "Queued") until this is switched on.</summary>
    public bool Enabled { get; set; }

    public string? Host { get; set; }
    public int Port { get; set; } = 587;
    public bool EnableSsl { get; set; } = true;
    public string? UserName { get; set; }
    public string? Password { get; set; }
    public string? FromAddress { get; set; }
    public string FromName { get; set; } = "HR & Payroll";

    /// <summary>The address employees use to reach the HRMS, e.g. https://hrms.example.com - the email links to My Payslips there.</summary>
    public string? AppBaseUrl { get; set; }

    /// <summary>Emails taken from the queue per round.</summary>
    public int BatchSize { get; set; } = 25;

    /// <summary>Seconds between two rounds when the queue is empty.</summary>
    public int PollSeconds { get; set; } = 30;

    public bool IsConfigured => Enabled && !string.IsNullOrWhiteSpace(Host) && !string.IsNullOrWhiteSpace(FromAddress);
}

/// <summary>
/// Sends the queued payslip emails (Payroll.Payslips, EmailStatus QUEUED) in
/// the background and records SENT / FAILED for each. The email says the
/// payslip is ready and links to My Payslips; it carries no salary figures,
/// so nothing confidential travels by email.
/// </summary>
public sealed class PayslipEmailSender : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly IOptionsMonitor<PayslipEmailOptions> _options;
    private readonly LabelStore _labels;
    private readonly ILogger<PayslipEmailSender> _logger;

    public PayslipEmailSender(IServiceScopeFactory scopes, IOptionsMonitor<PayslipEmailOptions> options, LabelStore labels,
                              ILogger<PayslipEmailSender> logger)
    {
        _scopes = scopes;
        _options = options;
        _labels = labels;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var options = _options.CurrentValue;
            var sent = 0;
            if (options.IsConfigured)
            {
                try
                {
                    sent = await SendBatchAsync(options, stoppingToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception ex)
                {
                    // The database is unreachable or similar - try again next round.
                    _logger.LogError(ex, "Payslip email round failed.");
                }
            }

            // A full batch means more may be waiting: go again at once.
            if (sent < Math.Max(1, options.BatchSize))
            {
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(Math.Clamp(options.PollSeconds, 5, 3600)), stoppingToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    return;
                }
            }
        }
    }

    private async Task<int> SendBatchAsync(PayslipEmailOptions options, CancellationToken cancellationToken)
    {
        using var scope = _scopes.CreateScope();
        var repository = scope.ServiceProvider.GetRequiredService<IPayslipRepository>();

        var jobs = await repository.ClaimEmailsAsync(options.BatchSize, cancellationToken).ConfigureAwait(false);
        if (jobs.Count == 0)
        {
            return 0;
        }

        await _labels.RefreshIfStaleAsync(cancellationToken).ConfigureAwait(false);

        using var client = new SmtpClient(options.Host!, options.Port)
        {
            EnableSsl = options.EnableSsl,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 30000
        };
        if (!string.IsNullOrWhiteSpace(options.UserName))
        {
            client.Credentials = new NetworkCredential(options.UserName, options.Password);
        }

        foreach (var job in jobs)
        {
            bool success;
            string? error = null;
            try
            {
                using var message = Compose(job, options);
                await client.SendMailAsync(message, cancellationToken).ConfigureAwait(false);
                success = true;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                // Left in SENDING: claimed again after 15 minutes.
                throw;
            }
            catch (Exception ex) when (ex is SmtpException or FormatException or InvalidOperationException)
            {
                success = false;
                error = ex is FormatException ? "The email address is not valid." : ex.Message;
                _logger.LogWarning(ex, "Payslip email {PayslipNo} to {Email} failed.", job.PayslipNo, job.EmailTo);
            }

            await repository.EmailResultAsync(job.PayslipId, success, error, CancellationToken.None).ConfigureAwait(false);
        }

        return jobs.Count;
    }

    private MailMessage Compose(PayslipEmailJob job, PayslipEmailOptions options)
    {
        var english = job.Template != PayslipTemplate.Arabic;
        var arabic = job.Template != PayslipTemplate.English;
        var link = string.IsNullOrWhiteSpace(options.AppBaseUrl) ? null : options.AppBaseUrl.TrimEnd('/') + "/payroll/payslips/my";

        var periodEn = Period(job, false);
        var periodAr = Period(job, true);
        var nameEn = job.EmployeeName ?? string.Empty;
        var nameAr = string.IsNullOrWhiteSpace(job.ArabicName) ? nameEn : job.ArabicName!;

        string En(string key, string fallback, params object?[] args) => LabelStore.SafeFormat(_labels.Find(key, false) ?? fallback, args);
        string Ar(string key, string fallback, params object?[] args) =>
            LabelStore.SafeFormat(_labels.Find(key, true) ?? _labels.Find(key, false) ?? fallback, args);

        var subject = (english, arabic) switch
        {
            (true, true) => En("ps.email_subject", "Your payslip for {0} is ready", periodEn) + " | " + Ar("ps.email_subject", "Your payslip for {0} is ready", periodAr),
            (false, true) => Ar("ps.email_subject", "Your payslip for {0} is ready", periodAr),
            _ => En("ps.email_subject", "Your payslip for {0} is ready", periodEn)
        };

        var html = new StringBuilder();
        var text = new StringBuilder();
        html.Append("<!doctype html><html><body style=\"margin:0;padding:24px;background:#f4f6fa;font-family:Segoe UI,Arial,sans-serif;color:#1d2939\">");
        html.Append("<div style=\"max-width:560px;margin:0 auto;background:#fff;border:1px solid #e4e7ec;border-radius:10px;padding:24px\">");
        html.Append("<div style=\"font-weight:700;color:#0f2a4d;font-size:16px;margin-bottom:16px\">").Append(Enc(job.CompanyName)).Append("</div>");

        void Block(bool rtl, string greeting, string body, string action, string privacy)
        {
            var dir = rtl ? "rtl" : "ltr";
            var align = rtl ? "right" : "left";
            html.Append($"<div dir=\"{dir}\" style=\"text-align:{align};margin-bottom:20px\">");
            html.Append("<p style=\"margin:0 0 10px\">").Append(Enc(greeting)).Append("</p>");
            html.Append("<p style=\"margin:0 0 14px\">").Append(Enc(body)).Append("</p>");
            if (link is not null)
            {
                html.Append($"<p style=\"margin:0 0 14px\"><a href=\"{Enc(link)}\" style=\"display:inline-block;background:#1d5fbf;color:#fff;text-decoration:none;padding:9px 16px;border-radius:6px\">")
                    .Append(Enc(action)).Append("</a></p>");
            }
            html.Append("<p style=\"margin:0;color:#667085;font-size:12px\">").Append(Enc(privacy)).Append("</p></div>");

            text.AppendLine(greeting).AppendLine().AppendLine(body);
            if (link is not null)
            {
                text.AppendLine().AppendLine(action + ": " + link);
            }
            text.AppendLine().AppendLine(privacy).AppendLine().AppendLine("----");
        }

        if (english)
        {
            Block(false,
                En("ps.email_greeting", "Dear {0},", nameEn),
                En("ps.email_body", "Your payslip for {0} ({1}) is ready. Sign in to the HR system and open My Payslips to view, print or save it.", periodEn, job.PayslipNo),
                En("ps.email_action", "Open My Payslips"),
                En("ps.email_privacy", "For your privacy this email does not contain any salary figures. If you did not expect it, contact HR."));
        }

        if (arabic)
        {
            Block(true,
                Ar("ps.email_greeting", "Dear {0},", nameAr),
                Ar("ps.email_body", "Your payslip for {0} ({1}) is ready. Sign in to the HR system and open My Payslips to view, print or save it.", periodAr, job.PayslipNo),
                Ar("ps.email_action", "Open My Payslips"),
                Ar("ps.email_privacy", "For your privacy this email does not contain any salary figures. If you did not expect it, contact HR."));
        }

        html.Append("</div></body></html>");

        var message = new MailMessage
        {
            From = new MailAddress(options.FromAddress!, options.FromName),
            Subject = subject,
            SubjectEncoding = Encoding.UTF8,
            BodyEncoding = Encoding.UTF8,
            Body = text.ToString(),
            IsBodyHtml = false
        };
        message.To.Add(new MailAddress(job.EmailTo!, nameEn));
        message.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(html.ToString(), Encoding.UTF8, "text/html"));
        return message;
    }

    /// <summary>"September 2026", or "Week 41 (05/10 – 11/10)" - in the label language.</summary>
    private string Period(PayslipEmailJob job, bool arabic)
    {
        string Label(string key, string fallback) =>
            (arabic ? _labels.Find(key, true) : null) ?? _labels.Find(key, false) ?? fallback;

        if (job.PayFrequency == "MONTHLY")
        {
            var month = Label($"common.month_{job.RunMonth.Month}", CultureInfo.InvariantCulture.DateTimeFormat.GetMonthName(job.RunMonth.Month));
            return $"{month} {job.RunMonth.Year.ToString(CultureInfo.InvariantCulture)}";
        }

        var number = job.PeriodNumber ?? 0;
        var label = job.PayFrequency == "WEEKLY"
            ? LabelStore.SafeFormat(Label("pr.week_n", "Week {0}"), [number])
            : LabelStore.SafeFormat(Label("pr.fortnight_n", "Fortnight {0}"), [number]);
        return $"{label} ({job.StartDate.ToString("dd/MM", CultureInfo.InvariantCulture)} – {job.EndDate.ToString("dd/MM", CultureInfo.InvariantCulture)})";
    }

    private static string Enc(string? value) => WebUtility.HtmlEncode(value ?? string.Empty);
}
