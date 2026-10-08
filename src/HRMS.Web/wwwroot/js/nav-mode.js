/* Loaded in <head>, before the first paint: the sidebar starts minimized (auto-minimize)
   unless the user pinned it open - so it never flashes open and then shrinks.
   site.js does the rest (hover / scroll / focus to expand, pin button). */
(function () {
    var mini = true;
    try { mini = window.localStorage.getItem("hrms:nav-mode") !== "pinned"; } catch (e) { /* storage off */ }
    if (mini) { document.documentElement.classList.add("nav-mini"); }
})();
