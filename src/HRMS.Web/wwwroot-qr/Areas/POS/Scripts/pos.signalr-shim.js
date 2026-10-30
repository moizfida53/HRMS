/*
 * pos.signalr-shim.js
 *
 * The Dine-In screen was written for SignalR 2 (jquery.signalR + /signalr/hubs):
 *     $.connection.dineInHub.client.tableChanged = fn;
 *     $.connection.hub.stateChanged(fn) / reconnected(fn) / disconnected(fn) / start()
 * HRMS runs ASP.NET Core SignalR, whose browser client (@microsoft/signalr,
 * loaded before this file) has a different API. This file provides the old
 * $.connection surface on top of it, so pos.dinein.js needs no changes.
 *
 * Needs: jQuery, window.signalR, window.POS_HUB_URL (set by DineIn/Index.cshtml).
 */
(function ($, signalR) {
    'use strict';
    if (!$ || !signalR) return;

    var conn = new signalR.HubConnectionBuilder()
        .withUrl(window.POS_HUB_URL || '/signalr/dineInHub')
        .configureLogging(signalR.LogLevel.Warning)
        .build();

    var client = {}, onState = [], onReconnected = [], onDisconnected = [], state = 4;

    ['tableChanged', 'layoutChanged', 'takeAwayChanged'].forEach(function (name) {
        conn.on(name, function (m) { if (typeof client[name] === 'function') client[name](m); });
    });

    // SignalR 2 states: 0 connecting, 1 connected, 2 reconnecting, 4 disconnected
    function setState(s) {
        var old = state; state = s;
        if (old !== s) onState.forEach(function (f) { f({ oldState: old, newState: s }); });
    }
    function fire(list) { list.forEach(function (f) { try { f(); } catch (e) { /* ignore */ } }); }

    conn.onclose(function () { setState(4); fire(onDisconnected); });

    $.connection = {
        dineInHub: { client: client },
        hub: {
            stateChanged: function (f) { onState.push(f); },
            reconnected:  function (f) { onReconnected.push(f); },
            disconnected: function (f) { onDisconnected.push(f); },
            start: function () {
                var d = $.Deferred();
                if (conn.state !== signalR.HubConnectionState.Disconnected) { d.resolve(); return d.promise(); }
                var wasConnected = conn._posEverConnected;
                setState(wasConnected ? 2 : 0);
                conn.start().then(function () {
                    conn._posEverConnected = true;
                    setState(1);
                    if (wasConnected) fire(onReconnected);
                    d.resolve();
                }, function (err) {
                    setState(4);
                    d.reject(err);
                    // SignalR 2 raised "disconnected" after a failed start too; the
                    // page retries from there.
                    fire(onDisconnected);
                });
                return d.promise();
            }
        }
    };
})(window.jQuery, window.signalR);
