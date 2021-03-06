$(document).ready(function() {
  if (current_userid.length == 0) { return }

  App.notifications = App.cable.subscriptions.create({
    channel: "NotificationsChannel",
    channel_id: "notifications_" + current_userid
  }, {
    connected: function() {
      setTimeout(function() {
        $("#loading-notifications").addClass("hidden")
      }, 1000)
      updateNotifications()
    },
    disconnected: function() {
      $("#loading-notifications").removeClass("hidden")
    },
    received: function(data) {
      if (data["message"] != undefined && data["message"].length > 0) {
        addFlashNotice(data["message"])
      }
      updateNotifications()
    }
  })

  updateNotifications = function() {
    $.rails.refreshCSRFTokens()
    $.get(notifications_url).success(function(data) {
      $("#notifications-notices").text(data.notices)
      $("#notifications-shouts").text(data.shouts)
      $("#notifications-invites").text(data.invites)
      $("#notifications-mod-queue").text(data.modq)
    })
  }

})
