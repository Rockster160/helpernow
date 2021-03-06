$(document).ready(function() {

  $("[data-masterCheckbox]").change(function() {
    $("[data-followsMaster='#" + this.id + "']").prop("checked", this.checked)
  })

  $(document)
    .on("click tap", "[data-toggle-display]", toggleDisplay)
    .on("click tap", ".whispercontrol", toggleWhisperDisplay)
    .on("click tap", ".removed-shout.clickable", displayShout)
    .on("click tap", ".edit-shout", editShout)

})

function toggleDisplay(evt) {
  $(this).next($(this).attr("data-toggle-display")).toggleClass("hidden")
}

function toggleWhisperDisplay() {
  $(this).next(".whispercontent").toggleClass("hidden")
}

function displayShout() {
  $(this).next(".shout-container.removed").toggleClass("hidden")
}

function editShout() {
  var $container = $(this).parents(".shout-container")
  $container.find(".shout-edit").toggleClass("hidden")
  $container.find(".shout-body").toggleClass("hidden")
}
