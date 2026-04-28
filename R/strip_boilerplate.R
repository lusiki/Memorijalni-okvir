#' Strip web boilerplate from text fields
#'
#' Removes scraped UI strings (cookie banners, share buttons, navigation text)
#' that appear in the corpus as content noise.
#'
#' @param dt data.table. Must contain FULL_TEXT and/or MENTION_SNIPPET columns.
#' @return dt with boilerplate removed in-place from both text fields.
#' @examples
#' dt <- strip_boilerplate(dt)
strip_boilerplate <- function(dt) {
  stopifnot(data.table::is.data.table(dt))

  pat_boilerplate <- paste0(
    "(?i)(",
    paste(c(
      "prihvati kola\u010di\u0107\\w*",
      "kola\u010di\u0107\\w* postavk\\w*",
      "koristimo kola\u010di\u0107\\w*",
      "politika privatnosti",
      "uvjeti korist\\w*",
      "podijeli na facebooku",
      "podijeli na twitteru",
      "podijeli na dru\u0161tvenim",
      "share on facebook",
      "tweet this",
      "\\btweet\\b",
      "\\bshare\\b",
      "\\bispis\\b",
      "\\bprint\\b",
      "kliknite ovdje",
      "pro\u010ditajte vi\u0161e",
      "nastavi \u010ditati",
      "cijeli \u010dlanak",
      "preuzeto s",
      "izvor fotografij\\w*",
      "foto arhiv\\w*",
      "\\bfoto\\b:\\s*\\w+",
      "messenger",
      "whatsapp",
      "viber"
    ), collapse = "|"),
    ")"
  )

  for (col in intersect(c("FULL_TEXT", "MENTION_SNIPPET"), names(dt))) {
    data.table::set(dt, j = col,
      value = stringi::stri_replace_all_regex(
        dt[[col]], pat_boilerplate, " ",
        opts_regex = stringi::stri_opts_regex(case_insensitive = TRUE)
      )
    )
    data.table::set(dt, j = col,
      value = stringi::stri_replace_all_regex(dt[[col]], "\\s{2,}", " ")
    )
  }
  dt
}
