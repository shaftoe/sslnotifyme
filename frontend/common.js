/*global $*/

function showWheel() {
    $("#waiting_icon").show();
}

function hideWheel() {
    $("#waiting_icon").hide();
}

function setResponseMessage(alert_element_id, isError, message) {
    var alert_element = $("#"+ alert_element_id);
    if (isError) {
        alert_element.removeClass().addClass("alert alert-danger");
    } else {
        alert_element.removeClass().addClass("alert alert-success");
    }

    alert_element.html(message).show();
}

function setSeconds(sec) {
    $("#redirect_message").html("<p>redirecting to homepage in " + sec + " seconds...</p>");
}

function timedRedirectToIndex() {
    var sec = 5
    setSeconds(sec--);
    $("#redirect_message").show();
    var timer = setInterval(function () {
        setSeconds(sec--);
        if (sec < 0) {
            clearInterval(timer);
            window.location = 'index.html';
        }
    }, 1000);
}

function getURLParameter(sParam) {
    var sPageURL = window.location.search.substring(1);
    var sURLVariables = sPageURL.split('&');
    for (var i = 0; i < sURLVariables.length; i++) {

        var sParameterName = sURLVariables[i].split('=');
        if (sParameterName[0] == sParam) {
            return sParameterName[1];
        }
    }
}

function callApi(method, path, data) {
    $.ajax("https://api.sslnotify.me" + path, {
        type: method,
        contentType: "application/json",
        dataType: "json",
        data: data,
        beforeSend: function(){
            showWheel();
        },
        success: function (data) {
            setResponseMessage("response_message", false, data.Message);
        },
        error: function (data) {
            setResponseMessage("response_message", true, data.responseJSON.Message);
        },
        complete: function(){
            hideWheel();
            timedRedirectToIndex();
        }
    });
}

function usersApi(method) {
    var user = getURLParameter("user");
    var uuid = getURLParameter("uuid");
    var path = '/user/' + user + "?uuid=" + uuid;
    callApi(method, path);
}

function confirmUser() {
    usersApi('PUT');
}

function unsubscribeUser() {
    usersApi('DELETE');
}

function sendFeedback() {
    callApi('POST', "/feedback/", $("#feedback-form").serialize());
}
