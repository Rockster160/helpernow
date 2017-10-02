$(document).ready(function() {

  addEmojiToLoader = function(name, aliases) {
    var colon_name = ":" + name + ":"
    var list_names = [name].concat(aliases).join(" ")
    var emoji = $("<i>", { alt: colon_name, title: colon_name, class: "emoji " + name })
    var emoji_name = $("<div>", { class: "emoji-name" }).html(colon_name)
    var emoji_wrapper = $("<div>", { class: "emoji-wrapper" }).append(emoji, emoji_name)
    var alias_list = $("<span>", { class: "aliases" }).html(aliases.map(function(alias) { return ":" + alias + ":" }).join(", "))
    var emoji_container = $("<div>", { class: "emoji-container", "data-names": list_names }).append(emoji_wrapper, alias_list)
    $(".emoji-loader").append(emoji_container)
  }

  var emoji_data, emojiNames = [], emojiAliases = []
  setTimeout(function() {
    if ($(".emoji-field").length > 0) {
      $("#pre-load").append($("<div>", { class: "emoji-loader" }))
    }
    $.getJSON("/emoji.json", function(data) {
      emoji_data = data
      for (var emojiName in emoji_data) {
        emojiNames.push(emojiName)
        emojiAliases = emojiAliases.concat(emoji_data[emojiName])
        addEmojiToLoader(emojiName, emoji_data[emojiName])
        if ($(".emoji-loader").hasClass("large")) { $(".emoji").addClass("large") }
      }
    })
  }, 10)

  $(".emoji-quick-search, .emoji-field").on("keyup", function() {
    var search_text = $(this).val().toLowerCase().replace(/[ \_\-]/, "")

    if (search_text.length == 0) {
      $(".emoji-container").removeClass("hidden")
    }

    $(".emoji-container").each(function() {
      var names = $(this).attr("data-names").split(" ")

      var hasMatched = false
      for (var name_idx in names) {
        if (hasMatched) { break }

        var name = names[name_idx], emojiText = name, string_valid = true
        emojiText = emojiText.replace(/[ \_\-]/, "")

        // NOTE: Word-based matching
        if (emojiText.indexOf(search_text) < 0) { string_valid = false }

        // NOTE: Character-based, order-dependent fuzzy matching
        // for (var idx in search_text.split("")) {
        //   if (hasMatched) { break }
        //
        //   var char = search_text[idx], char_index = emojiText.indexOf(char)
        //   if (char_index < 0) {
        //     string_valid = false
        //   } else {
        //     emojiText = emojiText.substr(char_index + 1)
        //   }
        // }

        if (string_valid) { hasMatched = true }
      }
      if (hasMatched) {
        $(this).removeClass("hidden")
      } else {
        $(this).addClass("hidden")
      }
    })
  })

  $(".emoji-field").on("keyup", function() {
    // Find the word the cursor is currently typing.
    // If the word starts with a colon and matches the regex, perform a filter
  })

})
