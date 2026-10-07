/* ==========================================================================
 * HRMS Kuwait - Dashboard
 * Month picker + the two line charts (headcount trend, payroll trend).
 * Plain SVG, no chart library (CSP allows only same-origin scripts).
 * Data comes from <script type="application/json" id="dashboard-data">.
 * ========================================================================== */
(function () {
    "use strict";

    // Month picker in the top bar reloads the page for that month.
    var picker = document.querySelector("[data-dash-month]");
    if (picker) {
        picker.addEventListener("change", function () { picker.form.submit(); });
    }

    var dataEl = document.getElementById("dashboard-data");
    if (!dataEl) { return; }

    var data;
    try { data = JSON.parse(dataEl.textContent); } catch (e) { return; }

    var SVG = "http://www.w3.org/2000/svg";
    var ACCENT = "#1d5fbf";      // $blue-600 - one series, one hue
    var GRID = "#eef1f5";        // $line-100
    var AXIS = "#98a2b3";        // $ink-400
    var INK = "#101828";

    function el(name, attrs, parent) {
        var node = document.createElementNS(SVG, name);
        Object.keys(attrs || {}).forEach(function (k) { node.setAttribute(k, attrs[k]); });
        if (parent) { parent.appendChild(node); }
        return node;
    }

    function niceMax(v) {
        if (v <= 0) { return 1; }
        var p = Math.pow(10, Math.floor(Math.log10(v)));
        var n = v / p;
        var step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
        return step * p;
    }

    /**
     * One-series line chart with a light area, 4 grid lines, an end label,
     * and a crosshair tooltip that snaps to the nearest month.
     * rows(i) returns [{ label, value }] lines for the tooltip at index i.
     */
    function lineChart(host, values, opts) {
        var tip = document.createElement("div");
        tip.className = "hrms-chart__tip";
        tip.hidden = true;

        function draw() {
            host.innerHTML = "";
            host.appendChild(tip);

            var width = Math.max(280, host.clientWidth);
            var height = host.clientHeight || 220;
            var pad = { top: 16, right: opts.padRight || 44, bottom: 28, left: opts.padLeft || 44 };
            var w = width - pad.left - pad.right;
            var h = height - pad.top - pad.bottom;

            var max = niceMax(Math.max.apply(null, values.map(function (v) { return v || 0; })) * 1.1);
            var n = values.length;
            var x = function (i) { return pad.left + (n === 1 ? w / 2 : (i * w) / (n - 1)); };
            var y = function (v) { return pad.top + h - ((v || 0) / max) * h; };

            var svg = el("svg", { width: width, height: height, viewBox: "0 0 " + width + " " + height, "aria-hidden": "true" }, host);

            // grid + y labels (4 steps, values the axis actually reaches)
            for (var g = 0; g <= 4; g++) {
                var gv = (max / 4) * g;
                var gy = y(gv);
                el("line", { x1: pad.left, x2: pad.left + w, y1: gy, y2: gy, stroke: GRID, "stroke-width": 1 }, svg);
                var t = el("text", { x: pad.left - 8, y: gy + 4, "text-anchor": "end", "font-size": 11, fill: AXIS }, svg);
                t.textContent = opts.format(gv, true);
            }

            // x labels - every other month when narrow
            var every = width < 520 ? 2 : 1;
            data.months.forEach(function (m, i) {
                if ((n - 1 - i) % every !== 0) { return; }
                var lbl = el("text", { x: x(i), y: height - 8, "text-anchor": "middle", "font-size": 11, fill: AXIS }, svg);
                lbl.textContent = m;
            });

            // area + line
            var pts = values.map(function (v, i) { return x(i) + "," + y(v); }).join(" ");
            el("polygon", {
                points: x(0) + "," + y(0) + " " + pts + " " + x(n - 1) + "," + y(0),
                fill: ACCENT, "fill-opacity": 0.08
            }, svg);
            el("polyline", { points: pts, fill: "none", stroke: ACCENT, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }, svg);

            // emphasised end point + direct label
            var last = values[n - 1] || 0;
            el("circle", { cx: x(n - 1), cy: y(last), r: 4, fill: ACCENT, stroke: "#fff", "stroke-width": 2 }, svg);
            var end = el("text", { x: x(n - 1) + 8, y: y(last) + 4, "font-size": 12, "font-weight": 600, fill: INK }, svg);
            end.textContent = opts.format(last, true);

            // crosshair + hover target
            var cross = el("line", { y1: pad.top, y2: pad.top + h, stroke: AXIS, "stroke-width": 1, "stroke-dasharray": "3 3", visibility: "hidden" }, svg);
            var dot = el("circle", { r: 4.5, fill: "#fff", stroke: ACCENT, "stroke-width": 2, visibility: "hidden" }, svg);
            var hit = el("rect", { x: pad.left - 10, y: pad.top, width: w + 20, height: h, fill: "transparent", tabindex: 0 }, svg);

            function show(i) {
                var cx = x(i), cy = y(values[i]);
                cross.setAttribute("x1", cx); cross.setAttribute("x2", cx);
                cross.setAttribute("visibility", "visible");
                dot.setAttribute("cx", cx); dot.setAttribute("cy", cy);
                dot.setAttribute("visibility", "visible");

                tip.textContent = "";
                var head = document.createElement("div");
                head.className = "hrms-chart__tip-head";
                head.textContent = data.monthsLong[i];
                tip.appendChild(head);
                opts.rows(i).forEach(function (r) {
                    var row = document.createElement("div");
                    row.className = "hrms-chart__tip-row";
                    var v = document.createElement("strong");
                    v.textContent = r.value;
                    var l = document.createElement("span");
                    l.textContent = r.label;
                    row.appendChild(v); row.appendChild(l);
                    tip.appendChild(row);
                });
                tip.hidden = false;
                var left = cx + 12;
                if (left + tip.offsetWidth > width) { left = cx - tip.offsetWidth - 12; }
                tip.style.left = left + "px";
                tip.style.top = Math.max(0, cy - tip.offsetHeight / 2) + "px";
            }

            function hide() {
                cross.setAttribute("visibility", "hidden");
                dot.setAttribute("visibility", "hidden");
                tip.hidden = true;
            }

            var focusIndex = n - 1;
            hit.addEventListener("pointermove", function (e) {
                var r = svg.getBoundingClientRect();
                var px = e.clientX - r.left;
                var i = Math.round(((px - pad.left) / w) * (n - 1));
                show(Math.max(0, Math.min(n - 1, i)));
            });
            hit.addEventListener("pointerleave", hide);
            hit.addEventListener("focus", function () { show(focusIndex); });
            hit.addEventListener("blur", hide);
            hit.addEventListener("keydown", function (e) {
                if (e.key === "ArrowLeft") { focusIndex = Math.max(0, focusIndex - 1); show(focusIndex); e.preventDefault(); }
                if (e.key === "ArrowRight") { focusIndex = Math.min(n - 1, focusIndex + 1); show(focusIndex); e.preventDefault(); }
            });
        }

        draw();
        var timer = null;
        window.addEventListener("resize", function () {
            window.clearTimeout(timer);
            timer = window.setTimeout(draw, 120);
        });
    }

    function kwd(v, short) {
        v = v || 0;
        if (short && v >= 1e6) { return "KD " + (v / 1e6).toFixed(2).replace(/\.?0+$/, "") + "M"; }
        if (short && v >= 1e4) { return "KD " + (v / 1e3).toFixed(1).replace(/\.0$/, "") + "K"; }
        return "KD " + v.toLocaleString("en-US", { minimumFractionDigits: short ? 0 : 3, maximumFractionDigits: 3 });
    }

    var headHost = document.querySelector('[data-chart="headcount"]');
    if (headHost) {
        lineChart(headHost, data.headcount, {
            format: function (v) { return Math.round(v).toLocaleString("en-US"); },
            rows: function (i) {
                return [
                    { value: data.headcount[i].toLocaleString("en-US"), label: HRMS.t("js.chart_employees", "employees") },
                    { value: "+" + data.joiners[i], label: HRMS.t("js.chart_joined", "joined") },
                    { value: "−" + data.leavers[i], label: HRMS.t("js.chart_left", "left") }
                ];
            }
        });
    }

    var payHost = document.querySelector('[data-chart="payroll"]');
    if (payHost) {
        lineChart(payHost, data.gross.map(function (v) { return v || 0; }), {
            padLeft: 68,
            padRight: 80,
            format: kwd,
            rows: function (i) {
                return [{ value: kwd(data.gross[i] || 0, false), label: HRMS.t("js.chart_gross_payroll", "gross payroll") }];
            }
        });
    }
})();
