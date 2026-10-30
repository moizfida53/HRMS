#nullable disable
//==============================================================================
//  Areas/POS/Hubs/DineInHub.cs  (ASP.NET Core SignalR - was SignalR 2 / OWIN)
//------------------------------------------------------------------------------
//  Real-time table status for every open Dine-In screen (tablets, cashiers).
//  Mapped at /signalr/dineInHub in Program.cs.
//
//  Browsers only LISTEN on this hub. Every change goes through DineInController
//  (signed in, permission-checked), which calls TableChanged / LayoutChanged /
//  TakeAwayChanged after the database accepted it. The hub itself requires a
//  signed-in HRMS user, so the floor status is not visible to anonymous visitors.
//
//  Client events (payload property names kept PascalCase, as before):
//      tableChanged({ TableID, Reason, By, At })
//      layoutChanged({ By, At })
//      takeAwayChanged({ By, At })
//==============================================================================

using System;
using HRMS.Web.Areas.Items.Legacy;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace HRMS.Web.Areas.POS.Hubs
{
    [Authorize]
    public class DineInHub : Hub
    {
        public const string Path = "/signalr/dineInHub";

        private static IHubContext<DineInHub> _ctx;

        /// <summary>Called once from Program.cs after the app is built.</summary>
        public static void Configure(IHubContext<DineInHub> ctx) => _ctx = ctx;

        private static void Send(string method, object payload, string what)
        {
            try
            {
                // Fire and forget: a failed broadcast must never fail or undo the
                // change itself - the screens also re-read the floor every 15-30 s.
                _ctx?.Clients.All.SendAsync(method, payload).ContinueWith(t =>
                {
                    if (t.Exception != null) DB.AuditTrail(t.Exception.GetBaseException(), "POS.DineInHub", what, null);
                }, System.Threading.Tasks.TaskContinuationOptions.OnlyOnFaulted);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInHub", what, null);
            }
        }

        public static void TableChanged(int tableId, string reason, string by) =>
            Send("tableChanged", new { TableID = tableId, Reason = reason, By = by, At = DateTime.Now.ToString("HH:mm:ss") }, "TableChanged");

        /// <summary>A Take Away bill was created, changed, paid or deleted.</summary>
        public static void TakeAwayChanged(string by) =>
            Send("takeAwayChanged", new { By = by, At = DateTime.Now.ToString("HH:mm:ss") }, "TakeAwayChanged");

        public static void LayoutChanged(string by) =>
            Send("layoutChanged", new { By = by, At = DateTime.Now.ToString("HH:mm:ss") }, "LayoutChanged");
    }
}
