//==============================================================================
//  Areas/POS/Hubs/DineInHub.cs
//------------------------------------------------------------------------------
//  Real-time table status for every open Dine-In screen (tablets, cashiers).
//
//  Browsers only LISTEN on this hub. Nothing is changed through it: every
//  change goes through DineInController (session-authenticated, permission-
//  checked), which calls TableChanged / LayoutChanged after the database has
//  accepted it. So a client can never mark a table occupied by talking to the
//  hub directly, and the hub needs no authentication of its own.
//
//  Client events:
//      tableChanged({ TableID, Reason, By, At })   reason: occupied | vacant |
//                                                   guest | order | refresh
//      layoutChanged({ By, At })                   an admin moved tables
//      takeAwayChanged({ By, At })                 the Take Away list changed
//
//  Requires the NuGet package Microsoft.AspNet.SignalR (2.4.x) and Startup.cs.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Hubs\DineInHub.cs" />
//==============================================================================

using System;
using Jar.Helper;
using Microsoft.AspNet.SignalR;
using Microsoft.AspNet.SignalR.Hubs;

namespace Jar.Areas.POS.Hubs
{
    [HubName("dineInHub")]
    public class DineInHub : Hub
    {
        private static IHubContext Ctx
        {
            get { return GlobalHost.ConnectionManager.GetHubContext<DineInHub>(); }
        }

        /// <summary>
        /// Broadcast after a table's state changed in the database. A failure
        /// here must never undo or fail the change itself - the screens also
        /// re-read the floor on reconnect and every 30 seconds.
        /// </summary>
        public static void TableChanged(int tableId, string reason, string by)
        {
            try
            {
                Ctx.Clients.All.tableChanged(new
                {
                    TableID = tableId,
                    Reason  = reason,
                    By      = by,
                    At      = DateTime.Now.ToString("HH:mm:ss")
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInHub", "TableChanged", null);
            }
        }

        /// <summary>A Take Away bill was created, changed, paid or deleted.</summary>
        public static void TakeAwayChanged(string by)
        {
            try
            {
                Ctx.Clients.All.takeAwayChanged(new { By = by, At = DateTime.Now.ToString("HH:mm:ss") });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInHub", "TakeAwayChanged", null);
            }
        }

        public static void LayoutChanged(string by)
        {
            try
            {
                Ctx.Clients.All.layoutChanged(new { By = by, At = DateTime.Now.ToString("HH:mm:ss") });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.DineInHub", "LayoutChanged", null);
            }
        }
    }
}
