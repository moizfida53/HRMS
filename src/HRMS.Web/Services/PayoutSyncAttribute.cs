using HRMS.Web.Models.Organization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace HRMS.Web.Services;

/// <summary>
/// db/123: after a pay-out action succeeds (a POST answering ActionResponse.Success - payslips
/// generated, a bank file made, payments paid, a journal created / posted / reversed, a
/// collection received), the pay-out status of the payrolls in scope is saved again:
/// Approved -> Execution -> Completed (and back to Execution when a journal is reversed).
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public sealed class PayoutSyncAttribute : Attribute, IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var executed = await next();
        if (!HttpMethods.IsPost(context.HttpContext.Request.Method)) return;
        if (executed.Result is not JsonResult { Value: ActionResponse { Success: true } }) return;
        if (context.HttpContext.RequestServices.GetService<IPayrollWorkspace>() is not { } workspace) return;
        await workspace.SyncAsync(null, context.HttpContext.RequestAborted);
        context.HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
    }
}
