using System.Net;
using Microsoft.AspNetCore.HttpOverrides;

namespace HRMS.Web.Services;

/// <summary>
/// The reverse proxies whose X-Forwarded-Proto / X-Forwarded-For headers are believed
/// (Program.cs), for any deployment - appsettings.json "ReverseProxy":
///   TrustCloudflare   true (default): Cloudflare's published ranges (https://www.cloudflare.com/ips/)
///   TrustedNetworks   any other proxy / load balancer in front of IIS - its addresses as CIDR
///                     ranges or single IPs, e.g. ["10.0.0.0/8", "203.0.113.7"] (Azure Front
///                     Door, AWS ALB, nginx, a company load balancer ...)
/// The server itself (loopback) is always trusted. Headers from any other address are
/// ignored - so a site served by IIS directly (http or https) behaves exactly as without this.
/// </summary>
public static class ForwardedProxies
{
    public const string SectionName = "ReverseProxy";

    public static readonly string[] Cloudflare =
    [
        // IPv4
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18",
        "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17",
        "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
        // IPv6
        "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32", "2405:8100::/32",
        "2a06:98c0::/29", "2c0f:f248::/32"
    ];

    public static ForwardedHeadersOptions Options(IConfiguration configuration)
    {
        var options = new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
            // proxy -> IIS is one hop
            ForwardLimit = 1
        };

        var section = configuration.GetSection(SectionName);
        var networks = new List<string>();
        if (section.GetValue("TrustCloudflare", true)) networks.AddRange(Cloudflare);
        networks.AddRange(section.GetSection("TrustedNetworks").Get<string[]>() ?? []);

        foreach (var entry in networks.Select(n => n.Trim()).Where(n => n.Length > 0))
        {
            // a single address counts as a one-address network
            var cidr = entry.Contains('/') ? entry : entry + (entry.Contains(':') ? "/128" : "/32");
            if (System.Net.IPNetwork.TryParse(cidr, out var network))
            {
                options.KnownIPNetworks.Add(network);
            }
        }
        // the defaults (loopback) stay: a proxy on the same machine is trusted too
        return options;
    }
}
