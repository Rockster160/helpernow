$(".ctr-posts.act-show").ready(function() {

  $(document).on("click", ".quote-reply", function(evt) {
    evt.preventDefault()
    var reply_text = $(this).parents(".reply-container").find(".reply-content").last().attr("data-original-content")
    var author_name = $(this).parents(".reply-container").find(".reply-username").html()
    $("#reply_body").focus()
    $("#reply_body").val($("#reply_body").val() + "[quote " + author_name + "]" + reply_text + "[/quote]")
    return false
  })

  $(document).on("click", ".edit-reply", function(evt) {
    evt.preventDefault()
    // $("#new-reply-form")
    // var reply_text = $(this).parents(".reply-container").find(".reply-content").last().attr("data-original-content")
    // var author_name = $(this).parents(".reply-container").find(".reply-username").html()
    // $("#reply_body").focus()
    // $("#reply_body").val($("#reply_body").val() + "[quote " + author_name + "]" + reply_text + "[/quote]")
    return false
  })

})
