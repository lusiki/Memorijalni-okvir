library(data.table)
library(stringi)

in_path  <- "analysis/02-descriptive/data/destinations_analytical_final.rds"
out_rds  <- "analysis/02-descriptive/data/destinations_analytical_final_audited.rds"
out_csv  <- "analysis/02-descriptive/output/tables/destinations_matches_audit.csv"

dt <- readRDS(in_path)
setDT(dt)
cat("Loaded", nrow(dt), "rows.\n")

destination_patterns <- list(
  marija_bistrica = c("marija bistric","mariju bistricu","marije bistrice",
                      "marijom bistricom","bistričk","majka božja bistrička",
                      "majke božje bistričke","majku božju bistričku"),
  trsat = c("trsat","trsatsk","gospa trsatsk","gospu trsatsk","gospe trsatsk",
            "gospom trsatsk","majka božja trsatsk"),
  sinj = c("sinj","sinjsk","alka","alkar"),
  aljmas = c("aljmaš","aljmaša","aljmašu","aljmašem","aljmašk",
             "gospa aljmašk","gospe aljmašk","gospu aljmašk",
             "utočišt","majka božja aljmašk"),
  ludbreg = c("ludbreg","ludbrešk","ludbrešku"),
  krasno = c("krasn","krasnarsk"),
  vocin = c("voćin","voćinsk","gospa voćinsk","gospe voćinsk",
            "gospu voćinsk","gospom voćinsk","majka božja voćinsk"),
  vepric = c("vepric","veprič","gospa od lurda","gospe od lurda",
             "gospu od lurda","hrvatski lurd"),
  nin = c("nin","ninsk","ninskim"),
  solin = c("solin","solinsk")
)

# dt$destination is already the snake_case key matching names(destination_patterns)

registers <- list(
  religious = c("svetiš","hodočast","hodočasn","biskup","nadbiskup","kardinal",
                "svećenik","fratar","franjev","papa ","papinsk","vatikan",
                "misa ","misu ","mise ","misom","liturgij","euharistij","pričes",
                "gospa","majka božj","isus","krist","molitv","blagoslov","sakram",
                "katolič","kršćan","vjernic","vjera ","crkv","katedral","kapel",
                "bazilik","blagdan","korizm","advent","uskrs","procesij","zavjet",
                "čudo","čuda","čudotvor","marijansk","duhovn"),
  tourism = c("turizam","turist","turistič","destinacij","posjetitelj","posjet",
              "dolasci","dolazak","noćenj","smještaj","hotel","apartm","ljeto",
              "ljetn","sezon","hrvatska turistič","turistička zajednic","putnic",
              "putovanj","izletnic","izlet"),
  scandal = c("skandal","afer","optužn","optužnic","optužuj","korupcij","korumpir",
              "pronevjer","zloporab","kriminal","kriminaln","pljačk","pokrad",
              "prevar","prevarant","uhit","uhićen","istražni zatvor","privedeni",
              "priveden","osuđen","osuđuj","osudio","odšteta zbog","tužb","tuženi",
              "pedofil","zlostavlj","zlostavljan")
)

# split text into sentences on . ! ? and newlines; keep ordering
split_sentences <- function(txt) {
  if (is.na(txt) || !nzchar(txt)) return(character(0))
  s <- stri_split_regex(txt, "(?<=[.!?])\\s+|\\n+")[[1]]
  s <- stri_trim_both(s)
  s[nzchar(s)]
}

# for one row: given text + keyword vector, return list(words, sentences)
collect_matches <- function(txt, keywords) {
  if (is.na(txt) || !nzchar(txt)) return(list(words = character(0), sents = character(0)))
  lower_txt <- stri_trans_tolower(txt, locale = "hr")
  sents <- split_sentences(txt)
  if (length(sents) == 0) return(list(words = character(0), sents = character(0)))
  lower_sents <- stri_trans_tolower(sents, locale = "hr")

  words_out <- character(0)
  sents_out <- character(0)
  for (kw in keywords) {
    kw_l <- stri_trans_tolower(kw, locale = "hr")
    hits <- which(stri_detect_fixed(lower_sents, kw_l))
    if (length(hits) > 0) {
      words_out <- c(words_out, rep(kw, length(hits)))
      sents_out <- c(sents_out, sents[hits])
    }
  }
  list(words = words_out, sents = sents_out)
}

n <- nrow(dt)
dest_words   <- character(n); dest_sents   <- character(n)
relig_words  <- character(n); relig_sents  <- character(n)
tour_words   <- character(n); tour_sents   <- character(n)
scan_words   <- character(n); scan_sents   <- character(n)

SEP <- " ||| "

pb_step <- max(1L, n %/% 20L)
for (i in seq_len(n)) {
  txt <- dt$FULL_TEXT[i]
  dkey <- dt$destination[i]
  dpat <- destination_patterns[[dkey]]
  if (is.null(dpat)) dpat <- character(0)

  d <- collect_matches(txt, dpat)
  r <- collect_matches(txt, registers$religious)
  t <- collect_matches(txt, registers$tourism)
  s <- collect_matches(txt, registers$scandal)

  dest_words[i]  <- paste(d$words, collapse = SEP)
  dest_sents[i]  <- paste(d$sents, collapse = SEP)
  relig_words[i] <- paste(r$words, collapse = SEP)
  relig_sents[i] <- paste(r$sents, collapse = SEP)
  tour_words[i]  <- paste(t$words, collapse = SEP)
  tour_sents[i]  <- paste(t$sents, collapse = SEP)
  scan_words[i]  <- paste(s$words, collapse = SEP)
  scan_sents[i]  <- paste(s$sents, collapse = SEP)

  if (i %% pb_step == 0L) cat(sprintf("  %d / %d (%.0f%%)\n", i, n, 100*i/n))
}

dt[, match_destination_words     := dest_words]
dt[, match_destination_sentences := dest_sents]
dt[, match_religious_words       := relig_words]
dt[, match_religious_sentences   := relig_sents]
dt[, match_tourism_words         := tour_words]
dt[, match_tourism_sentences     := tour_sents]
dt[, match_scandal_words         := scan_words]
dt[, match_scandal_sentences     := scan_sents]

saveRDS(dt, out_rds)
cat("Saved enriched RDS:", out_rds, "\n")

audit_csv <- dt[, .(pair_id, DATE, destination, dominant_frame, TITLE, URL,
                     match_destination_words, match_destination_sentences,
                     match_religious_words,   match_religious_sentences,
                     match_tourism_words,     match_tourism_sentences,
                     match_scandal_words,     match_scandal_sentences)]
fwrite(audit_csv, out_csv, bom = TRUE)
cat("Saved audit CSV:", out_csv, "\n")

cat("\nQuick coverage check (non-empty match columns):\n")
print(audit_csv[, .(
  has_dest     = sum(nzchar(match_destination_words)),
  has_relig    = sum(nzchar(match_religious_words)),
  has_tour     = sum(nzchar(match_tourism_words)),
  has_scandal  = sum(nzchar(match_scandal_words))
)])
