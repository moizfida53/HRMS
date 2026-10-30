//==============================================================================
//  Helper/AssetVersion.cs
//------------------------------------------------------------------------------
//  Cache-busting for the site's own css/js.
//
//  THE PROBLEM
//  -----------
//  Browsers (and any CDN or proxy in front of the site) cache /cssNew/style.css
//  and /MainJs/... by URL. Deploying a new copy of a file does not change its
//  URL, so a returning customer keeps running the old one until they hard-
//  refresh - which is not something you can ask a customer to do. Index.cshtml
//  had a partial answer, "?v=@ViewBag.CssVersion", but that value is the *theme*
//  version from tblMenuTheme: it moves when someone saves colours in the admin,
//  not when a css or js file is edited and published. So a code deploy still
//  served stale assets.
//
//  THE FIX
//  -------
//  Stamp every local asset with its own file modification time. The URL changes
//  exactly when the file changes - no manual version to remember to bump, and
//  files that did NOT change keep their URL and stay cached, so a deploy does
//  not needlessly re-download everything.
//
//  USAGE (Jar.Helper is registered in Views\Web.config, so no @using is needed)
//      <link href="@Asset.V("~/cssNew/style.css")" rel="stylesheet" />
//      <script src="@Asset.V("~/MainJs/ItemsViewNew/Index.js")"></script>
//      @Asset.V("~/cssNew/" + name, ViewBag.CssVersion)   // extra token appended
//
//  Add to the .csproj:
//      <Compile Include="Helper\AssetVersion.cs" />
//==============================================================================

using System;
using System.Collections.Concurrent;
using System.IO;
using System.Web;
using System.Web.Hosting;

namespace Jar.Helper
{
    public static class Asset
    {
        private sealed class Entry
        {
            public DateTime CheckedUtc;
            public string Stamp;
        }

        // Re-stat a file at most this often. Stat calls are cheap, but a busy
        // menu page asks for ~20 assets per render; this keeps a burst of
        // traffic from turning into a burst of disk hits while still picking a
        // new file up within a few seconds of it landing on the server.
        private static readonly TimeSpan ReStatAfter = TimeSpan.FromSeconds(5);

        private static readonly ConcurrentDictionary<string, Entry> _cache =
            new ConcurrentDictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// Application-relative ("~/...") path in, browser URL with a version
        /// query string out. Anything that is not an app-relative local path
        /// (a CDN url, a protocol-relative url) is returned untouched, so it is
        /// safe to wrap a reference without checking first.
        /// </summary>
        public static string V(string virtualPath)
        {
            return V(virtualPath, null);
        }

        /// <summary>
        /// As V(path), plus an extra token folded into the query string. Used
        /// for the brand css, which must also change when the admin saves a new
        /// theme even though the .css file on disk did not move.
        /// </summary>
        public static string V(string virtualPath, object extra)
        {
            if (string.IsNullOrEmpty(virtualPath)) return virtualPath;
            if (!virtualPath.StartsWith("~/", StringComparison.Ordinal)) return virtualPath;

            string url;
            try { url = VirtualPathUtility.ToAbsolute(virtualPath); }
            catch { url = virtualPath.Substring(1); }   // "~/x" -> "/x"

            string stamp = Stamp(virtualPath);

            // The path may already carry a query string of its own.
            string sep = url.IndexOf('?') >= 0 ? "&" : "?";

            if (!string.IsNullOrEmpty(stamp))
            {
                url += sep + "v=" + stamp;
                sep = "&";
            }

            string ex = extra == null ? null : Convert.ToString(extra).Trim();
            if (!string.IsNullOrEmpty(ex) && ex != "0")
                url += sep + "t=" + HttpUtility.UrlEncode(ex);

            return url;
        }

        /// <summary>
        /// The file's last-write time as a compact token, or "" when the file
        /// cannot be found or read. Returning "" rather than throwing matters:
        /// a mistyped path should render a link that 404s visibly, not take the
        /// whole page down with a YSOD.
        /// </summary>
        public static string Stamp(string virtualPath)
        {
            Entry e;
            DateTime now = DateTime.UtcNow;

            if (_cache.TryGetValue(virtualPath, out e) && (now - e.CheckedUtc) < ReStatAfter)
                return e.Stamp;

            string stamp = "";
            try
            {
                string physical = HostingEnvironment.MapPath(virtualPath);
                if (!string.IsNullOrEmpty(physical) && File.Exists(physical))
                {
                    // Base-36 keeps the token short (~9 chars) and it is
                    // monotonic, so a newer file always sorts after an older one
                    // if anyone ever needs to eyeball which build is being served.
                    stamp = ToBase36(File.GetLastWriteTimeUtc(physical).Ticks);
                }
            }
            catch
            {
                stamp = "";
            }

            _cache[virtualPath] = new Entry { CheckedUtc = now, Stamp = stamp };
            return stamp;
        }

        private static string ToBase36(long value)
        {
            const string digits = "0123456789abcdefghijklmnopqrstuvwxyz";
            if (value <= 0) return "0";

            char[] buf = new char[13];
            int i = buf.Length;
            while (value > 0)
            {
                buf[--i] = digits[(int)(value % 36)];
                value /= 36;
            }
            return new string(buf, i, buf.Length - i);
        }
    }
}
