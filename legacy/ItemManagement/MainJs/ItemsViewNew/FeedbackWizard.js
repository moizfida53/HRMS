/* ============================================================================
 * FeedbackWizard.js
 * ----------------------------------------------------------------------------
 * One-question-at-a-time feedback flow driven by Feedback_Layout / Feedback_Type.
 *   - Each question is shown on its own step with a "Question X of N" counter
 *     and a progress bar; Next / Previous move between steps.
 *   - Question types: Star Rating (5 stars), Smiley (5 faces), Question (Yes/No),
 *     Text (comment box).
 *   - After the last question a final step collects Customer Name (required),
 *     Mobile (required) and Email (optional) and Submits.
 *   - A persistent device id (UDID) is generated/stored and sent on submit.
 *
 * This file is loaded AFTER BindCartDetails.js, so the functions defined here
 * intentionally OVERRIDE the older all-at-once versions of the same names.
 * ========================================================================== */
(function () {
    "use strict";

    var feedbackQuestions = [];     // raw question list from the server
    var feedbackTotalQuestions = 0; // number of question steps
    var feedbackCurrentStep = 0;    // 0..N-1 = questions, N = customer-info step

    function isArabic() {
        return $("body").hasClass("rtl") ||
               (($("html").attr("dir") || "").toLowerCase() === "rtl") ||
               (($("#selectedLang").val() || "").toUpperCase() === "AR");
    }

    function escapeHtml(s) {
        return $("<div>").text(s == null ? "" : String(s)).html();
    }

    /* ---- Persistent device id (UDID) ----------------------------------
       The UDID column is FLOAT, so the device id must be numeric. We build a
       15-digit number (below 2^53, so it is stored as an exact float).        */
    function getOrCreateUDID() {
        var key = "emenu_udid";
        var id = "";
        try { id = window.localStorage.getItem(key) || ""; } catch (e) { id = ""; }
        if (!id || !/^[0-9]{1,15}$/.test(id)) {   // (re)generate if missing or not numeric (e.g. an old GUID)
            var ts = Date.now() % 10000000000;             // 10 digits  - time component
            var rnd = Math.floor(Math.random() * 100000);  // 0..99999   - random component
            id = "" + ts + ("00000" + rnd).slice(-5);      // 15-digit numeric string
            try { window.localStorage.setItem(key, id); } catch (e) { /* private mode */ }
        }
        return id;
    }
    window.getOrCreateUDID = getOrCreateUDID;

    /* ---- Open the wizard --------------------------------------------- */
    function giveFeedback(btn) {
        $("#divMainQuestions").html("");
        $("#txtFdbCustomerName").val("");
        $("#txtFdbCustomerPhonenumber").val("");
        $("#txtFdbCustomerEmail").val("");
        $("#feedbackError").hide().text("");

        var objdata = { BrandId: $("#hdnbrandId").val() };
        $.ajax({
            type: "Post",
            data: JSON.stringify(objdata),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/ItemsViewNew/GetFeedbackFormQuestion",
            success: function (result) {
                if (result.Message === "Success") {
                    var list = JSON.parse(result.dtQuestions);
                    bindFeedBackQuestions(list);
                    $("#order-feedback").modal("show");
                } else {
                    bindFeedBackQuestions([]);   // no questions -> straight to details step
                    $("#order-feedback").modal("show");
                }
            }
        });
    }
    window.giveFeedback = giveFeedback;

    /* ---- Build one step per question --------------------------------- */
    function bindFeedBackQuestions(QuestionsList) {
        var arabic = isArabic();
        var yesTxt = arabic ? "نعم" : "Yes";
        var noTxt  = arabic ? "لا"  : "No";

        feedbackQuestions = QuestionsList || [];
        feedbackTotalQuestions = feedbackQuestions.length;
        feedbackCurrentStep = 0;

        var $container = $("#divMainQuestions").empty();

        $.each(feedbackQuestions, function (i, obj) {
            var lid = obj.LayoutID;
            var type = obj.Type;
            var dataVal = "Text";
            if (type === "Star Rating") { dataVal = "Rating"; }
            else if (type === "Smiley") { dataVal = "Smile"; }
            else if (type === "Question") { dataVal = "RadioQuestion"; }
            else { dataVal = "Text"; }

            var inner = "";
            if (type === "Star Rating") {
                inner = '<div class="fb-star-rating">';
                for (var s = 1; s <= 5; s++) {
                    inner += '<span id="strRating_' + lid + '_' + s + '" class="fa fa-star strRat" onclick="startRatingClick(this,' + lid + ',' + s + ')"></span>';
                }
                inner += '</div>';
            } else if (type === "Smiley") {
                var faces = ["😡", "🙁", "😐", "🙂", "😍"]; // 😡 🙁 😐 🙂 😍
                inner = '<div class="fb-smiley-row">';
                for (var f = 0; f < 5; f++) {
                    inner += '<span class="fb-smiley" onclick="smileyRatingClick(this,' + lid + ',' + (f + 1) + ')">' + faces[f] + '</span>';
                }
                inner += '</div>';
            } else if (type === "Question") {
                inner =
                    '<div class="fb-choice-row">' +
                        '<label class="fb-choice"><input type="radio" name="fbRadio_' + lid + '" id="chkRadio_' + lid + '_Yes" value="Yes"> <span>' + yesTxt + '</span></label>' +
                        '<label class="fb-choice"><input type="radio" name="fbRadio_' + lid + '" id="chkRadio_' + lid + '_No" value="No"> <span>' + noTxt + '</span></label>' +
                    '</div>';
            } else {
                inner = '<textarea id="txtarea_' + lid + '" class="form-control fb-textarea" rows="4"></textarea>';
            }

            var step =
                '<div id="question_' + lid + '" class="feedback-step clQuestions" ' +
                     'data-Question="' + lid + '" data-val="' + dataVal + '" data-FeedbackTypeId="' + obj.FeedbackTypeid + '" data-smile="0" style="display:none;">' +
                    '<div class="card mb-0"><div class="card-body p-4">' +
                        '<h5 id="questionTxt_' + lid + '" class="card-title font-weight-bold pb-3 text-center fb-question-text">' + escapeHtml(obj.Questions) + '</h5>' +
                        inner +
                    '</div></div>' +
                '</div>';
            $container.append(step);
        });

        // localise the static labels each time the wizard opens
        $("#fbNextLbl").text(arabic ? "التالي" : "Next");
        $("#fbPrevLbl").text(arabic ? "السابق" : "Previous");
        $("#fbSubmitLbl").text(arabic ? "إرسال" : "Submit");
        $("#fbCustomerInfoTitle").text(arabic ? "بياناتك" : "Your details");
        $("#my-modal-title").text(arabic ? "ملاحظاتك" : "Feedback");

        showFeedbackStep(0);
    }
    window.bindFeedBackQuestions = bindFeedBackQuestions;

    /* ---- Step navigation --------------------------------------------- */
    function showFeedbackStep(index) {
        if (index < 0) { index = 0; }
        if (index > feedbackTotalQuestions) { index = feedbackTotalQuestions; }
        feedbackCurrentStep = index;

        $("#feedbackError").hide().text("");
        $(".feedback-step").hide();

        if (index < feedbackTotalQuestions) {
            $("#divMainQuestions .feedback-step").eq(index).show();
        } else {
            $("#divFeedbackCustomerInfo").show();
        }
        updateFeedbackNav();
    }
    window.showFeedbackStep = showFeedbackStep;

    function updateFeedbackNav() {
        var arabic = isArabic();
        var onCustomer = (feedbackCurrentStep >= feedbackTotalQuestions);

        if (onCustomer) {
            $("#feedbackCounter").text(arabic ? "بياناتك" : "Your details");
        } else {
            var cur = feedbackCurrentStep + 1;
            $("#feedbackCounter").text(arabic
                ? ("سؤال " + cur + " من " + feedbackTotalQuestions)
                : ("Question " + cur + " of " + feedbackTotalQuestions));
        }

        $("#btnFeedbackPrev").toggle(feedbackCurrentStep > 0);
        $("#btnFeedbackNext").toggle(!onCustomer);
        $("#btnFeedbackSubmit").toggle(onCustomer);

        var totalSteps = feedbackTotalQuestions + 1;
        var pct = Math.round(((feedbackCurrentStep + 1) / totalSteps) * 100);
        $("#feedbackProgressBar").css("width", pct + "%");
    }

    function feedbackNext() {
        if (feedbackCurrentStep < feedbackTotalQuestions) {
            showFeedbackStep(feedbackCurrentStep + 1);
        }
    }
    window.feedbackNext = feedbackNext;

    function feedbackPrev() {
        if (feedbackCurrentStep > 0) {
            showFeedbackStep(feedbackCurrentStep - 1);
        }
    }
    window.feedbackPrev = feedbackPrev;

    /* ---- Input handlers (scoped to their own question) --------------- */
    function startRatingClick(btn, LayoutID, id) {
        $("#question_" + LayoutID + " .strRat").removeClass("checked");
        for (var i = 1; i <= id; i++) {
            $("#strRating_" + LayoutID + "_" + i).addClass("checked");
        }
    }
    window.startRatingClick = startRatingClick;

    function smileyRatingClick(el, LayoutID, val) {
        $("#question_" + LayoutID + " .fb-smiley").removeClass("fb-smiley-selected");
        $(el).addClass("fb-smiley-selected");
        $("#question_" + LayoutID).attr("data-smile", val);
    }
    window.smileyRatingClick = smileyRatingClick;

    /* ---- Collect + submit -------------------------------------------- */
    function btnFeedback_submitClick() {
        var arabic = isArabic();
        var name   = $.trim($("#txtFdbCustomerName").val() || "");
        var mobile = $.trim($("#txtFdbCustomerPhonenumber").val() || "");
        var email  = $.trim($("#txtFdbCustomerEmail").val() || "");

        if (!name) {
            return showFeedbackError(arabic ? "الرجاء إدخال الاسم" : "Please enter your name", "#txtFdbCustomerName");
        }
        if (!mobile || !/^[0-9()+\-\s]{6,20}$/.test(mobile)) {
            return showFeedbackError(arabic ? "الرجاء إدخال رقم هاتف صحيح" : "Please enter a valid mobile number", "#txtFdbCustomerPhonenumber");
        }
        if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            return showFeedbackError(arabic ? "البريد الإلكتروني غير صحيح" : "Please enter a valid email address", "#txtFdbCustomerEmail");
        }

        var questionList = [];
        $(".clQuestions").each(function () {
            var $q = $(this);
            var qId = $q.attr("data-Question");
            var qType = $q.attr("data-val");
            var qTypeId = $q.attr("data-FeedbackTypeId");
            var response = "";

            if (qType === "Rating") {
                var r = 0;
                for (var s = 5; s >= 1; s--) {
                    if ($("#strRating_" + qId + "_" + s).hasClass("checked")) { r = s; break; }
                }
                response = "" + r;
            } else if (qType === "Smile") {
                response = "" + ($q.attr("data-smile") || "0");
            } else if (qType === "RadioQuestion") {
                response = $("#chkRadio_" + qId + "_Yes").is(":checked") ? "Yes"
                         : ($("#chkRadio_" + qId + "_No").is(":checked") ? "No" : "");
            } else {
                response = $("#txtarea_" + qId).val() || "";
            }

            questionList.push({
                QuestionId: parseInt(qId, 10),
                Response_Type: parseInt(qTypeId, 10),
                Response: response
            });
        });

        var objdata = {
            customerName: name,
            customerEmail: email,
            customerMobile: mobile,
            BranchId: $("#hdnBranchId").val(),
            UDID: getOrCreateUDID(),
            questionList: questionList
        };

        $("#btnFeedbackSubmit").prop("disabled", true);
        $.ajax({
            type: "Post",
            data: JSON.stringify(objdata),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false,
            url: "/ItemsViewNew/PostFeedback",
            success: function (result) {
                $("#btnFeedbackSubmit").prop("disabled", false);
                $("#order-feedback").modal("hide");
                $("#alertTitle").html("");
                if (result.Message === "Success") {
                    $("#alertMessage").html(arabic ? "تم إرسال ملاحظاتك بنجاح" : "Feedback submitted successfully");
                } else {
                    $("#alertMessage").html(arabic ? "تعذّر إرسال الملاحظات، حاول مرة أخرى." : "Feedback was not submitted, please try again.");
                }
                $("#alertModal").modal();
            },
            error: function () {
                $("#btnFeedbackSubmit").prop("disabled", false);
                showFeedbackError(arabic ? "حدث خطأ، حاول مرة أخرى." : "Something went wrong, please try again.");
            }
        });
    }
    window.btnFeedback_submitClick = btnFeedback_submitClick;

    function showFeedbackError(msg, focusSelector) {
        $("#feedbackError").text(msg).show();
        if (focusSelector) { $(focusSelector).focus(); }
        return false;
    }
})();
