library(data.table)
library(stringi)
library(jsonlite)

in_path   <- "analysis/02-descriptive/data/destinations_analytical_final_audited.rds"
llm_json  <- "validation/llm-audit/llm_results_partial.json"
out_rds   <- "analysis/02-descriptive/data/destinations_analytical_cleaned.rds"
log_csv   <- "validation/llm-audit/cleaning_log.csv"

dt <- readRDS(in_path)
setDT(dt)
cat("Loaded", nrow(dt), "rows.\n")

# --------------------------------------------------------------------------
# 1. Word-boundary destination re-check
#    Fixes Class A: substring false positives (nin in Putinera, Nino, Ningbo, ...)
# --------------------------------------------------------------------------

# Word-boundary regex per destination. Croatian diacritics preserved.
# \b in stringi/ICU handles Unicode correctly.
# For polysemic destinations we use stricter patterns requiring case endings.
wb_patterns <- list(
  marija_bistrica = "\\b(marij[aeuo]|mariji|marijom)\\s+bistric[aeuio]|bistri(\u010dk|\u010dki|\u010dka|\u010dko|\u010dku|\u010dkoj|\u010dkom|\u010dke|\u010dkih|\u010dkim)|majk[aeou]\\s+bo\u017ej[aeou]\\s+bistri\u010dk",
  trsat           = "\\btrsat([aeui]|om|ovi|ova|ovima)?\\b|\\btrsatsk[aeiou]|\\btrsatskim",
  sinj            = "\\bsinj([aeui]|om|evi)?\\b|\\bsinjsk[aeiou]|\\balk[aeui](rski|rska|rsko|rskoj|rskom|rsku|rskih|rskim)?\\b|\\balkar[aeiu]?\\b",
  aljmas          = "\\baljma\u0161([aeui]|om|em)?\\b|\\baljma\u0161k[aeiou]|\\bgospa?\\s+aljma\u0161k|uto\u010di\u0161t",
  ludbreg         = "\\bludbreg([aeuia]|om)?\\b|\\bludbre\u0161k[aeiou]|\\bludbre\u0161ku",
  krasno          = "\\bkrasn[aeiouom]\\b|\\bkrasnu\\b|\\bkrasno\\b",
  vocin           = "\\bvo\u0107in([aeuia]|om)?\\b|\\bvo\u0107insk[aeiou]|\\bgospa?\\s+vo\u0107insk",
  vepric          = "\\bvepric([aeuia]|om)?\\b|\\bvepri\u010d(ki|ka|ko|kom|ke)|gospa?\\s+od\\s+lurda|hrvatski\\s+lurd",
  nin             = "\\bnin([aeuia]|om|e|ima)?\\b|\\bninsk[aeiou]|\\bninskim\\b",
  solin           = "\\bsolin([aeuia]|om|e)?\\b|\\bsolinsk[aeiou]"
)

cat("Running word-boundary destination re-check...\n")

dt[, wb_destination_ok := FALSE]

for (i in seq_len(nrow(dt))) {
  dkey <- dt$destination[i]
  pat <- wb_patterns[[dkey]]
  if (is.null(pat)) next

  title_text <- if (is.na(dt$TITLE[i])) "" else dt$TITLE[i]
  snip_text  <- if (is.na(dt$MENTION_SNIPPET[i])) "" else dt$MENTION_SNIPPET[i]
  full_text  <- if (is.na(dt$FULL_TEXT[i])) "" else dt$FULL_TEXT[i]

  combined <- stri_trans_tolower(
    paste(title_text, snip_text, full_text, sep = " "),
    locale = "hr")

  dt$wb_destination_ok[i] <- stri_detect_regex(combined, pat)
}

cat("  Word-boundary destination match rate by destination:\n")
wb_stats <- dt[, .(n = .N,
                   wb_ok = sum(wb_destination_ok),
                   wb_fail_pct = round(100 * (1 - mean(wb_destination_ok)), 1)),
               by = destination]
print(wb_stats[order(-wb_fail_pct)])

# --------------------------------------------------------------------------
# 2. Tightened register re-tagging
#    Fixes Class B: dictionary noise
#    Strategy: drop the worst offenders; require word-boundary matches;
#    add negative exclusions for documented false-fire patterns.
# --------------------------------------------------------------------------

# Tightened religious register
# - "papa " needs space or punct boundary (already ok)
# - "krist" would match Kristina -> require krist[a-zaceiouš]* but not after K capital name pattern
# - "advent" in Croatian is nearly always liturgical, but in Christmas-song context it fires
# - "ku\u0161d[oa]" is problematic (idioms) -> require "\u010cudo" capitalised or next to religious terms
# - We use word boundaries + Unicode letter class
tight_religious <- c(
  "\\bsveti\u0161t", "\\bhodo\u010da(s|st)", "\\bhodo\u010dasn",
  "\\bbiskup[a-z]*", "\\bnadbiskup", "\\bkardinal",
  "\\bsve\u0107eni(k|c|ka|ku|cima)", "\\bfratar", "\\bfranjev",
  "\\bpapa\\b", "\\bpapinsk", "\\bvatikan",
  "\\bmis[aeui]\\b", "\\bmisom\\b", "\\bliturgij", "\\beuharistij", "\\bpri\u010des",
  "\\bgospa\\b", "\\bgospe\\b", "\\bgospu\\b", "\\bgospom\\b",
  "\\bmajk[aeu]\\s+bo\u017ej",
  "\\bisus", "\\bkrist[aou]\\b", "\\bkristov",
  "\\bmolitv", "\\bblagoslov", "\\bsakram",
  "\\bkatoli\u010d", "\\bkr\u0161\u0107an", "\\bvjerni(k|c|ka)",
  "\\bcrkv[aeuio]", "\\bcrkava\\b", "\\bkatedral", "\\bkapel[aeuio]",
  "\\bbazilik", "\\bkorizm", "\\buskrs[aeu]?\\b", "\\bprocesij",
  "\\bzavjet", "\\b\u010dudotvor", "\\bmarijansk", "\\bduhovn",
  "\\bblagdan[aeuio]?"
)
pat_relig_tight <- paste0("(?i)(", paste(tight_religious, collapse = "|"), ")")

# Tightened tourism register
# - "sezon" is fine but noisy in sports/sale contexts; keep but flag low confidence
# - "ljeto/ljetn" is the biggest noise source (obljetnica); drop these
# - "dolasci/dolazak" noise-heavy (dolazak u mirovinu, kindergarten arrivals); require plural form only
# - "posjet[a-z]" fires on social visits, field trips; require specific tourism context
# - "putovanj" mostly fine
# - keep core tourism terms with strong boundaries
tight_tourism <- c(
  "\\bturizam", "\\bturist[aeuio]?", "\\bturisti\u010dk",
  "\\bdestinacij",
  "\\bposjetitelj",
  "\\bno\u0107enj", "\\bsmje\u0161taj",
  "\\bhotel[aeui]?\\b", "\\bhotela\\b", "\\bhotelom\\b", "\\bhotelski",
  "\\bapartm",
  "\\bturisti\u010dka\\s+zajednic",
  "\\bhrvatska\\s+turisti\u010dk",
  "\\bputnic[aeuio]", "\\bputovanj",
  "\\bizlet[aeuio]?", "\\bizletnic",
  "\\bgost[i]?(iju|ima)\\b", "\\bgostiju\\b"
)
pat_tour_tight <- paste0("(?i)(", paste(tight_tourism, collapse = "|"), ")")

# Scandal register: already tightened in phase 2c, reuse
tight_scandal <- c(
  "\\bskandal", "\\bafer[aeu]",
  "\\boptu\u017en", "\\boptu\u017enic", "\\boptu\u017euj",
  "\\bkorupcij", "\\bkorumpir",
  "\\bpronevjer", "\\bzloporab",
  "\\bkriminal", "\\bpljac\u0301k", "\\bpljack",
  "\\bpokrad", "\\bprevar", "\\bprevarant",
  "\\buhit", "\\buhi\u0107en", "\\bistra\u017eni\\s+zatvor",
  "\\bprivedeni", "\\bpriveden",
  "\\bosu\u0111en", "\\bosu\u0111uj", "\\bosudio",
  "\\bod\u0161teta\\s+zbog", "\\btu\u017eb", "\\btu\u017eeni",
  "\\bpedofil", "\\bzlostavlj"
)
pat_scan_tight <- paste0("(?i)(", paste(tight_scandal, collapse = "|"), ")")

cat("\nRunning tightened register re-tagging...\n")
full_lower <- stri_trans_tolower(dt$FULL_TEXT, locale = "hr")
full_lower[is.na(full_lower)] <- ""

dt[, clean_religious := stri_detect_regex(full_lower, pat_relig_tight)]
dt[, clean_tourism   := stri_detect_regex(full_lower, pat_tour_tight)]
dt[, clean_scandal   := stri_detect_regex(full_lower, pat_scan_tight)]

# --------------------------------------------------------------------------
# 3. Hand-confirmed LLM false-positive blocklist
#    From validation/llm-audit/llm_results_partial.json
# --------------------------------------------------------------------------

llm <- fromJSON(llm_json)
setDT(llm)
llm[, pair_id := as.integer(pair_id)]

llm_false_pos <- llm[is_about_destination == "false_positive", pair_id]
llm_not_rt    <- llm[is_religious_tourism == "no" &
                     is_about_destination %in% c("incidental", "false_positive"),
                     pair_id]

cat("LLM-confirmed false positives:", length(llm_false_pos), "\n")
cat("LLM-confirmed off-topic (incidental + not RT):", length(llm_not_rt), "\n")

dt[, llm_flagged_false_positive := pair_id %in% llm_false_pos]
dt[, llm_flagged_offtopic       := pair_id %in% llm_not_rt]

# --------------------------------------------------------------------------
# 4. Derive cleaning action + cleaned frame
# --------------------------------------------------------------------------

dt[, cleaning_action := fcase(
  !wb_destination_ok,                  "drop_substring",
  llm_flagged_false_positive,          "drop_llm_confirmed",
  !clean_religious & !clean_tourism,   "drop_no_register",
  default = "keep"
)]

dt[, cleaning_reason := fcase(
  cleaning_action == "drop_substring",
    "destination name matched only as substring (no word-boundary hit)",
  cleaning_action == "drop_llm_confirmed",
    "LLM audit confirmed false positive",
  cleaning_action == "drop_no_register",
    "tightened register tagging drops all religious/tourism flags",
  default = ""
)]

# Cleaned frame: same logic as Phase 2c but using tight flags
dt[, clean_dominant_frame := fcase(
  clean_scandal & !clean_religious & !clean_tourism, "scandal",
  clean_religious & clean_tourism,                   "religious_tourism_mixed",
  clean_religious & !clean_tourism & clean_scandal,  "religious_with_scandal",
  clean_religious & !clean_tourism,                  "religious_only",
  clean_tourism & !clean_religious & clean_scandal,  "tourism_with_scandal",
  clean_tourism & !clean_religious,                  "tourism_only",
  default = "other"
)]

# --------------------------------------------------------------------------
# 5. Reports
# --------------------------------------------------------------------------

cat("\n=== CLEANING SUMMARY ===\n")
cat("Total rows:", nrow(dt), "\n\n")

cat("Cleaning actions:\n")
print(dt[, .N, by = cleaning_action][order(-N)])

cat("\nCleaning action by destination:\n")
print(dcast(dt[, .N, by = .(destination, cleaning_action)],
            destination ~ cleaning_action, value.var = "N", fill = 0L))

cat("\nFrame shift (original vs clean):\n")
print(dt[, .N, by = .(original = dominant_frame, cleaned = clean_dominant_frame)][
  order(-N)][1:20])

cat("\nCount of articles kept after cleaning:\n")
print(dt[cleaning_action == "keep", .N, by = destination][order(-N)])

# --------------------------------------------------------------------------
# 6. Save outputs
# --------------------------------------------------------------------------

saveRDS(dt, out_rds)
cat("\nSaved cleaned corpus:", out_rds, "\n")

log_cols <- c("pair_id", "DATE", "destination", "TITLE", "URL",
              "dominant_frame", "clean_dominant_frame",
              "wb_destination_ok", "clean_religious", "clean_tourism",
              "clean_scandal", "llm_flagged_false_positive",
              "cleaning_action", "cleaning_reason")
fwrite(dt[cleaning_action != "keep", ..log_cols], log_csv, bom = TRUE)
cat("Saved cleaning log (dropped rows only):", log_csv, "\n")
