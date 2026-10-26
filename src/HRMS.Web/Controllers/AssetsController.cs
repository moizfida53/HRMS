using HRMS.Data.Repositories;
using HRMS.Domain.Assets;
using HRMS.Domain.Common;
using HRMS.Web.Models.Assets;
using HRMS.Web.Models.Organization;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Workforce > Assets (db/84): company cars, motor bikes, phones ... - type, brand, model, colour,
/// purchase and expiry dates (alerts before the expiry are set per type on Setup > Organization >
/// Asset Types) and the employee who uses each one, with the history of who held it.
/// View / Edit / Delete are given per role on Security > Create Roles.
/// </summary>
[Route("assets")]
public sealed class AssetsController : Controller
{
    public const string PermView = "ASSET_VIEW";
    public const string PermEdit = "ASSET_EDIT";
    public const string PermDelete = "ASSET_DELETE";
    private const string Views = "~/Views/Assets/";

    private readonly IAssetRepository _assets;
    private readonly IAssetTypeRepository _types;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly ILogger<AssetsController> _logger;

    public AssetsController(IAssetRepository assets, IAssetTypeRepository types, ILookupRepository lookups,
        ICurrentUser currentUser, ICompanyFilter companyFilter, ILogger<AssetsController> logger)
    {
        _assets = assets;
        _types = types;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private AssetRights Rights => new(Can(PermView) || Can(PermEdit), Can(PermEdit), Can(PermDelete));
    private AssetScope Scope => new(_currentUser.ActiveCompanyId, _companyFilter.Csv, _currentUser.UserId);
    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
    private static readonly string[] Statuses = ["ASSIGNED", "AVAILABLE", "EXPIRING", "EXPIRED", "RETIRED"];
    private static string? Status(string? status) => Statuses.Contains(status?.ToUpperInvariant()) ? status!.ToUpperInvariant() : null;

    [HttpGet("")]
    public async Task<IActionResult> Index(int? type, string? status)
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        return View(Views + "Index.cshtml", new AssetsPageModel
        {
            Rights = r,
            Summary = await _assets.SummaryAsync(Scope, Ct),
            TypeId = type,
            Status = Status(status)
        });
    }

    /// <summary>The figures and type chips again (they change with every save).</summary>
    [HttpGet("summary")]
    public async Task<IActionResult> Summary(int? type, string? status)
    {
        if (!Rights.CanView) return Forbid();
        return PartialView(Views + "_Summary.cshtml", new AssetsPageModel
        {
            Rights = Rights, Summary = await _assets.SummaryAsync(Scope, Ct), TypeId = type, Status = Status(status)
        });
    }

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(int? type, string? status, string? q, int page = 1)
    {
        var r = Rights;
        if (!r.CanView) return Forbid();
        var filter = new AssetFilter(type, Status(status), q, Math.Max(1, page));
        var (rows, total) = await _assets.ListAsync(filter, Scope, Ct);
        return PartialView(Views + "_Grid.cshtml", new AssetGridModel
        {
            Rights = r, Rows = rows, Total = total, PageNumber = filter.PageNumber, PageSize = filter.PageSize,
            Filtered = type is > 0 || filter.Status is not null || !string.IsNullOrWhiteSpace(q)
        });
    }

    /// <summary>Add or change an asset (and who uses it); assign=true opens it on "assigned to".</summary>
    [HttpGet("form")]
    public async Task<IActionResult> Form(long id = 0, int? type = null)
    {
        if (!Rights.CanEdit) return Forbid();
        AssetRow? asset = null;
        if (id > 0)
        {
            asset = await _assets.GetAsync(id, Scope, Ct);
            if (asset is null) return NotFound();
        }

        var types = (await _types.ListAsync(new GridRequest { PageSize = 200, SortColumn = "SortOrder" }, Ct)).Items
            .Where(t => t.IsActive || t.AssetTypeId == asset?.AssetTypeId).ToList();
        var companies = await CompaniesAsync();
        var companyIds = companies.Select(c => c.Id).ToHashSet();
        var employees = (await _lookups.GetAsync(LookupType.Employee, companyId: _currentUser.ActiveCompanyId, cancellationToken: Ct))
            .Where(e => e.ParentId is not { } co || companyIds.Contains(co))
            .OrderBy(e => e.Text, StringComparer.OrdinalIgnoreCase)
            .ToList();

        return PartialView(Views + "_Form.cshtml", new AssetFormModel
        {
            Asset = asset,
            Types = types,
            Companies = companies,
            Employees = employees,
            CompanyId = asset?.CompanyId ?? _currentUser.ActiveCompanyId ?? _companyFilter.SingleCompanyId ?? companies.FirstOrDefault()?.Id,
            TypeId = asset?.AssetTypeId ?? (type is > 0 ? type : null)
        });
    }

    [HttpPost("save")]
    public async Task<IActionResult> Save(AssetInput input)
    {
        if (!Can(PermEdit)) return Denied();
        if (!ModelState.IsValid)
        {
            var errors = ModelState.Where(e => e.Value?.Errors.Count > 0)
                .ToDictionary(e => e.Key, e => e.Value!.Errors.Select(x => x.ErrorMessage).ToArray());
            return Json(ActionResponse.Invalid(errors));
        }
        // the company must be one the user may see (also checked by the procedure)
        if (input.AssetId <= 0 && !(await CompaniesAsync()).Any(c => c.Id == input.CompanyId))
        {
            return Json(ActionResponse.Failed("Choose the company the asset belongs to.", "VALIDATION"));
        }
        var result = await _assets.SaveAsync(input, Scope, Ct);
        if (!result.Success) _logger.LogInformation("Asset save rejected with {Code}.", result.ErrorCode);
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>Take the asset back from its holder - it is available again.</summary>
    [HttpPost("return")]
    public async Task<IActionResult> Return(long id, string? remarks)
    {
        if (!Can(PermEdit)) return Denied();
        var result = await _assets.ReturnAsync(id, remarks, Scope, Ct);
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("delete")]
    public async Task<IActionResult> Delete(long id)
    {
        if (!Can(PermDelete)) return Denied();
        var result = await _assets.DeleteAsync(id, Scope, Ct);
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>Who held the asset, from / to.</summary>
    [HttpGet("history")]
    public async Task<IActionResult> History(long id)
    {
        if (!Rights.CanView) return Forbid();
        var asset = await _assets.GetAsync(id, Scope, Ct);
        if (asset is null) return NotFound();
        return PartialView(Views + "_History.cshtml", new AssetHistoryModel
        {
            Asset = asset,
            Entries = await _assets.HistoryAsync(id, Scope, Ct)
        });
    }

    /// <summary>The companies the user may add assets to (pinned company, top-bar filter).</summary>
    private async Task<IReadOnlyList<LookupItem>> CompaniesAsync()
    {
        var all = _currentUser.OwnCompanies(LookupType.Company,
            await _lookups.GetAsync(LookupType.Company, companyId: _currentUser.LookupCompany(null), cancellationToken: Ct));
        var selected = _companyFilter.SelectedIds;
        return selected.Count == 0 ? all : all.Where(c => selected.Contains(c.Id)).ToList();
    }
}
