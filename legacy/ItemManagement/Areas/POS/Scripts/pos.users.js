/*==============================================================================
  Areas/POS/Scripts/pos.users.js

  Admin-only User Management: list every tblUser row, Add User, Update User,
  Assign / Re-Assign Role (inline on the row, and from the edit form), and
  Assign Branches (Order List / Dashboard access - edit form only, a
  checklist rather than a single value since a user can see more than one
  branch).

  Branches come from the same sp_POS_GetLookups round trip the Order List
  already uses (POS.urls.lookups). Only an admin (CanManageMasters) can even
  reach this page, and that permission bypasses the branch restriction, so
  this always returns every branch - exactly the full list needed to build
  the "assign branches to someone else" checklist.
==============================================================================*/
(function () {
    'use strict';

    var users = [], roles = [], branches = [];
    var userBranchMap = {};   // UserID -> [BranchID, ...]
    var table = null;
    var editingId = 0;

    // ------------------------------------------------------------------ utils
    function esc(s) {
        if (s === null || s === undefined) return '';
        return String(s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    function roleName(id) {
        var r = roles.filter(function (x) { return String(x.RoleID) === String(id); })[0];
        return r ? r.RoleName : '(no role)';
    }

    function roleOptions(selectedId) {
        return roles.map(function (r) {
            var sel = String(r.RoleID) === String(selectedId) ? ' selected' : '';
            return '<option value="' + r.RoleID + '"' + sel + '>' + esc(r.RoleName) + '</option>';
        }).join('');
    }

    function branchNamesFor(userId) {
        var ids = userBranchMap[String(userId)] || [];
        return ids.map(function (id) {
            var b = branches.filter(function (x) { return String(x.BranchID) === String(id); })[0];
            return b ? b.BranchName : null;
        }).filter(Boolean);
    }

    // ------------------------------------------------------------------ grid
    function initTable() {
        table = $('#umTable').DataTable({
            data: users,
            paging: true,
            pageLength: 25,
            order: [[0, 'asc']],
            language: { emptyTable: 'No users found.' },
            dom: '<"top"t><"bottom"lip>',
            columns: [
                {
                    data: 'NAME',
                    render: function (v, t, row) {
                        return '<div class="um-name">' + esc(v) + '</div>' +
                               '<div class="um-username">@' + esc(row.USERNAME) + '</div>';
                    }
                },
                {
                    data: null,
                    render: function (v, t, row) {
                        var names = branchNamesFor(row.ID);
                        if (!names.length) return '<span class="um-branch-none">none - sees nothing</span>';
                        return names.map(function (n) { return '<span class="um-branch-badge">' + esc(n) + '</span>'; }).join('');
                    }
                },
                {
                    // Read-only here on purpose: role is only ever changed
                    // through Edit, not from the grid - see openEdit().
                    data: 'RoleID',
                    render: function (v) {
                        return '<span class="um-role-badge">' + esc(roleName(v)) + '</span>';
                    }
                },
                {
                    data: 'HasHashedPassword',
                    render: function (v) {
                        return v
                            ? '<span class="um-pw-flag ok">Secure</span>'
                            : '<span class="um-pw-flag weak" title="Still using the legacy plain-text password - set a new one to upgrade it.">Needs upgrade</span>';
                    }
                },
                {
                    data: null,
                    orderable: false,
                    render: function (v, t, row) {
                        return '<button type="button" class="um-edit" data-id="' + row.ID + '">Edit</button>';
                    }
                }
            ]
        });

        $('#umTable tbody').on('click', '.um-edit', function () {
            openEdit(parseInt($(this).data('id'), 10));
        });
    }

    function reloadTable() {
        if (!table) { initTable(); return; }
        table.clear();
        table.rows.add(users);
        table.draw(false);
    }

    // ------------------------------------------------------ branch checklist
    function renderBranchChecklist(checkedIds) {
        var checked = {};
        (checkedIds || []).forEach(function (id) { checked[String(id)] = true; });

        if (!branches.length) {
            $('#umBranchList').html('<div class="um-branch-empty">No branches found.</div>');
            return;
        }

        $('#umBranchList').html(branches.map(function (b) {
            var isChecked = checked[String(b.BranchID)] ? ' checked' : '';
            return '<label><input type="checkbox" class="um-branch-cb" value="' + b.BranchID + '"' + isChecked + ' />' +
                   esc(b.BranchName) + '</label>';
        }).join(''));
    }

    function checkedBranchIds() {
        var ids = [];
        $('#umBranchList .um-branch-cb:checked').each(function () { ids.push($(this).val()); });
        return ids.join(',');
    }

    // ------------------------------------------------------------- add/edit
    function openAdd() {
        editingId = 0;
        $('#umTitle').text('Add User');
        $('#umUserId').val(0);
        $('#umName').val('');
        $('#umUsername').val('');
        $('#umPassword').val('').attr('placeholder', '');
        $('#umPwHint').text('Stored as a salted hash - never shown again once set.');
        $('#umRole').html(roleOptions(null));
        renderBranchChecklist([]);
        showModal();
    }

    function openEdit(userId) {
        var u = users.filter(function (x) { return String(x.ID) === String(userId); })[0];
        if (!u) return;

        editingId = u.ID;
        $('#umTitle').text('Update User');
        $('#umUserId').val(u.ID);
        $('#umName').val(u.NAME);
        $('#umUsername').val(u.USERNAME);
        $('#umPassword').val('').attr('placeholder', 'Leave blank to keep the current password');
        $('#umPwHint').text('Leave blank to keep the current password. Typing a new one replaces it with a salted hash.');
        $('#umRole').html(roleOptions(u.RoleID));
        renderBranchChecklist(userBranchMap[String(u.ID)] || []);
        showModal();
    }

    function showModal() {
        $('#umError').hide().text('');
        $('#umSave').prop('disabled', false).text('Save');
        $('#umScrim').addClass('open');
        $('#umModal').addClass('open').attr('aria-hidden', 'false');
        $('#umName').focus();
    }
    function closeModal() {
        $('#umScrim').removeClass('open');
        $('#umModal').removeClass('open').attr('aria-hidden', 'true');
    }

    // Validates, then asks for confirmation before anything is sent. The
    // actual save only happens if umConfirmYes is clicked - see doSave().
    function onSaveClick() {
        var name = $.trim($('#umName').val());
        var username = $.trim($('#umUsername').val());
        var password = $('#umPassword').val();

        if (!name)     { return showError('Name is required.'); }
        if (!username) { return showError('Username is required.'); }
        if (editingId === 0 && !password) { return showError('A password is required for a new user.'); }

        var branchCount = $('#umBranchList .um-branch-cb:checked').length;
        var branchNote = branchCount === 0
            ? 'They will see <strong>no</strong> orders or reports (no branches checked), unless they have the Settings/User Management permission.'
            : 'They will see <strong>' + branchCount + '</strong> branch' + (branchCount === 1 ? '' : 'es') + ' worth of orders and reports.';

        var verb = editingId === 0 ? 'Add' : 'Save changes for';
        openConfirm(
            editingId === 0 ? 'Confirm Add User' : 'Confirm Save',
            verb + ' <strong>' + esc(name) + '</strong> (@' + esc(username) + ')? ' + branchNote
        );
    }

    function openConfirm(title, message) {
        $('#umConfirmTitle').text(title);
        $('#umConfirmMessage').html(message);
        $('#umConfirmError').hide().text('');
        $('#umConfirmYes').prop('disabled', false).text('Confirm');
        $('#umConfirmScrim').addClass('open');
        $('#umConfirmModal').addClass('open').attr('aria-hidden', 'false');
    }
    function closeConfirm() {
        $('#umConfirmScrim').removeClass('open');
        $('#umConfirmModal').removeClass('open').attr('aria-hidden', 'true');
    }

    function doSave() {
        var name = $.trim($('#umName').val());
        var username = $.trim($('#umUsername').val());
        var password = $('#umPassword').val();
        var roleId = $('#umRole').val();
        var branchIds = checkedBranchIds();

        $('#umConfirmYes').prop('disabled', true).text('Saving…');

        $.ajax({
            type: 'POST', url: POS.urls.usersSave,
            data: {
                userId: editingId, name: name, username: username,
                newPassword: password, roleId: roleId, branchIds: branchIds
            }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                closeConfirm();
                closeModal();
                loadAll();
            } else {
                $('#umConfirmError').text((res && res.Detail) || 'The user could not be saved.').show();
            }
        }).fail(function () {
            $('#umConfirmError').text('The user could not be saved.').show();
        }).always(function () {
            $('#umConfirmYes').prop('disabled', false).text('Confirm');
        });
    }

    function showError(msg) {
        $('#umError').text(msg).show();
    }

    // --------------------------------------------------------------- search
    function wireSearch() {
        $('#umSearch').on('input', function () {
            if (table) table.search($(this).val()).draw();
        });
    }

    // ----------------------------------------------------------------- load
    function loadAll() {
        $.getJSON(POS.urls.usersList).done(function (res) {
            if (res && res.Message === 'Success') {
                users = res.Users || [];
                roles = res.Roles || [];
                users.forEach(function (u) { u.RoleName = roleName(u.RoleID); });

                userBranchMap = {};
                (res.UserBranches || []).forEach(function (r) {
                    var key = String(r.UserID);
                    if (!userBranchMap[key]) userBranchMap[key] = [];
                    userBranchMap[key].push(r.BranchID);
                });

                reloadTable();
            }
        });
    }

    function loadBranches(done) {
        $.getJSON(POS.urls.lookups).done(function (res) {
            if (res && res.Message === 'Success') branches = res.Branches || [];
        }).always(done);
    }

    // ----------------------------------------------------------------- wire
    function wire() {
        $('#umAddBtn').on('click', openAdd);
        $('#umClose, #umCancel, #umScrim').on('click', closeModal);
        $('#umSave').on('click', onSaveClick);
        $('#umModal').on('keydown', function (e) {
            if (e.key === 'Escape') closeModal();
            if (e.key === 'Enter' && $(e.target).is('input')) onSaveClick();
        });

        $('#umConfirmClose, #umConfirmBack, #umConfirmScrim').on('click', closeConfirm);
        $('#umConfirmYes').on('click', doSave);
        $('#umConfirmModal').on('keydown', function (e) {
            if (e.key === 'Escape') closeConfirm();
            if (e.key === 'Enter') doSave();
        });

        wireSearch();
    }

    // ---------------------------------------------------------------- start
    $(function () {
        wire();
        // Branches load first: the grid's "Assigned Branches" column and the
        // edit checklist both need names resolved from IDs.
        loadBranches(loadAll);
    });
})();
