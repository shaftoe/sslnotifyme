/*global $ showWheel hideWheel setResponseMessage*/

$(function () {
    initializeEvents();
});

function initializeEvents() {
    $("#remind_me_btn").click(function () {
        remindMe();
    });

    $("#host").focus();

    onDaysKeyPress();
    onSubmit();    
    onModalShow();
    onModalShown();
}

function onSubmit() {
    $("#modal_form").submit(function (event) {
        event.preventDefault();
        saveUser();
    });

    $("#check_form").submit(function (event) {
        event.preventDefault();
        checkSSL();
    });
}

function onDaysKeyPress() {
    $("#days").keypress(function (e) {
        if (e.which == 13) {
            checkSSL();
        }
    });
}

function checkSSL() {
    if (validateHost() && validateDays()) {
        $.ajax({
            url: 'https://sslexpired.info/' + $("#host").val() + '?days=' + $("#days").val(),
            type: "GET",
            dataType: "json",
            beforeSend: function(){
                showWheel();
            },
            success: function (data) {
                handleCheckSSLResult(data);
            },
            complete: function(){
               hideWheel();
            }
        });
    }
}

/**
 * Handles SSL check result data (shows success/error message)
 * @param data
 */
function handleCheckSSLResult(data) {
    if (data.err != undefined) {
        setResponseMessage("response_message", true, data.err);
    } else if (data.alert != undefined) {
        setResponseMessage("response_message", true, data.response);
    } else {
        setResponseMessage("response_message", false, data.response);
    }
}

/*
Check if host and days are valid, if so opens a pop-up modal window.
 */
function remindMe() {
    if (validateHost() && validateDays()) {
        showModal();
    }
}

function saveUser() {
    if (validateEmail() && validateDays()) {
        var url = 'https://api.sslnotify.me/user/' + $("#notify_email").val() + "?domain=" + $("#host").val() + "&days=" + $("#days").val();

        $.ajax(url, {
            type: "PUT",
            dataType: "json",
            beforeSend: function(){
                showWheel();
            },
            success: function (data) {
                setResponseMessage("response_message", false, data.Message);
            },
            error:function (data) {
                setResponseMessage("response_message", true, data.responseJSON.Message);
            },
            complete: function(){
                hideWheel();
            }
        });

        hideModal();
    }
}

function onModalShow() {
    $("#remindMeModal").on('show.bs.modal', function () {
        //setting Modal Title
        $(".modal-title").html("Register to receive alerts via email starting from <b>" + $("#days").val() +  " days</b> before the SSL certificate for <b>" + $("#host").val() + "</b> will expire.");

        //cleaning email and response message fields
        $("#notify_email").val("");
        cleanResponseMessage($("#modal_response_message"));
    });
}

function onModalShown() {
    $("#remindMeModal").on('shown.bs.modal', function () {
        $("#notify_email").focus();
    });
}

/**
 * Validates that host is not empty
 * @param host
 * @returns {boolean}
 */
function validateHost() {
    var host = $("#host").val();

    if (!host) {
        setResponseMessage("response_message", true, "Please provide a <b>Host</b> to check");
        return false;
    }

    if (!isHost(host)) {
        setResponseMessage("response_message", true, "Please specify a valid <b>Host</b> value");
        return false;
    }

    cleanResponseMessage($("#response_message"));
    return true;
}

/**
 * Validates that days is a positive integer
 * @returns {boolean}
 */
function validateDays() {
    var days = $("#days").val();

    if (!days) {
        setResponseMessage("response_message", true, "Please provide the number of days");
        return false;
    }

    if (days < 1) {
        setResponseMessage("response_message", true, "<b>Days Tolerance</b> value must be a positive number");
        return false;
    }

    cleanResponseMessage($("#response_message"));
    return true;
}

/**
 * Validates that email is not empty and is valid email format
 * @param email
 * @returns {boolean}
 */
function validateEmail() {
    var email = $("#notify_email").val();

    if (!email) {
        setResponseMessage("modal_response_message", true, "Please specify the Email address.");
        return false;
    }

    if(!isEmail(email)) {
        setResponseMessage("modal_response_message", true, "Please specify a valid Email address.");
        return false;
    }

    return true;
}

function isEmail(email) {
    var regex = /^.+\@.+\..+$/;
    return regex.test(email);
}

function isHost(host) {
    var regex = /^.+\..+$/;
    return regex.test(host);
}

function cleanResponseMessage(element) {
    element.hide();
}

function hideModal() {
    $("#remindMeModal").modal('hide');
}

function showModal() {
    $("#remindMeModal").modal('show');
}


