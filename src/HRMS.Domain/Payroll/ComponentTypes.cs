namespace HRMS.Domain.Payroll;

/// <summary>An item type of a Payroll Components page, by code (the same code in every company) - db/111.</summary>
public sealed class ComponentTypeOption
{
    public string ItemClass { get; init; } = Payroll.ItemClass.Earning;
    public string ComponentCode { get; init; } = string.Empty;
    public string? ComponentName { get; init; }
    public string? ArabicName { get; init; }
}

/// <summary>An item type a role / user is limited to (Unrestricted = every type of the page).</summary>
public sealed class ComponentTypeGrant
{
    public string ItemClass { get; init; } = Payroll.ItemClass.Earning;
    public string? ComponentCode { get; init; }
    public bool Unrestricted { get; init; }
}
