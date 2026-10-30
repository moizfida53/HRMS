//==============================================================================
//  Startup.cs   (OWIN)
//------------------------------------------------------------------------------
//  Only job: switch on SignalR at /signalr for the Dine-In floor plan
//  (Areas/POS/Hubs/DineInHub.cs). MVC routing in Global.asax is unchanged.
//
//  Requires:  Install-Package Microsoft.AspNet.SignalR -Version 2.4.3
//  (brings Microsoft.Owin, Microsoft.Owin.Host.SystemWeb and Owin with it)
//
//  Add to the .csproj:
//      <Compile Include="Startup.cs" />
//==============================================================================

using Microsoft.Owin;
using Owin;

[assembly: OwinStartup(typeof(Jar.Startup))]

namespace Jar
{
    public class Startup
    {
        public void Configuration(IAppBuilder app)
        {
            app.MapSignalR();
        }
    }
}
