#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#| label: setup
#| include: false

library(data.table)
library(stringi)
library(ggplot2)
library(knitr)
library(digest)
library(patchwork)

for (d in c("data", "output/tables", "output/figures", "output/reports")) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#| label: config

config_2a <- list(
  timestamp       = Sys.time(),
  input_corpus    = "data/destinations_analytical_cleaned.rds",
  output_metadata = "data/phase2a_metadata.rds",
  top_n_sources   = 10L,
  syndication_n_chars = 500L,
  scandal_audit_n = 30L,
  concentration_threshold = 0.50,
  seed = 2026L
)

set.seed(config_2a$seed)
saveRDS(config_2a, "data/config_phase2a.rds")
cat("Phase 2a configuration saved.\n")
#
#
#
#
#
#| label: load

long <- readRDS(config_2a$input_corpus)
setDT(long)
long <- long[cleaning_action == "keep"]

if (!"yearmonth" %in% names(long))
  long[, yearmonth := as.Date(format(date, "%Y-%m-01"))]

cat("Analytical corpus loaded.\n")
cat("  Rows (pairs):", format(nrow(long), big.mark = ","), "\n")
cat("  Unique articles:", format(uniqueN(long$article_id),
                                 big.mark = ","), "\n")
cat("  Date range:", format(min(long$date)), "to",
    format(max(long$date)), "\n")
cat("  Destinations:", length(unique(long$destination)), "\n\n")
#
#
#
#
#
#| label: frequency

analysis_months <- uniqueN(long$yearmonth)

freq_profile <- long[, .(
  pairs = .N,
  articles = uniqueN(article_id),
  sources = uniqueN(FROM),
  months_active = uniqueN(yearmonth)
), by = .(destination, dest_type)]

freq_profile[, pairs_per_month := round(pairs / months_active, 1)]
freq_profile[, articles_per_month := round(articles / months_active, 1)]
freq_profile[, coverage_rate := round(months_active / analysis_months * 100, 1)]
freq_profile <- freq_profile[order(-pairs)]

kable(freq_profile, format.args = list(big.mark = ","),
      caption = "Frequency profile per destination")

fwrite(freq_profile, "output/tables/02a_frequency_profile.csv")
#
#
#
#| label: frequency-plot

p_freq <- ggplot(freq_profile,
                 aes(reorder(destination, pairs), pairs, fill = dest_type)) +
  geom_col() +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Article pairs per destination",
       subtitle = paste0("Analytical corpus, ",
                         format(nrow(long), big.mark = ","),
                         " pairs total"),
       x = NULL, y = "Pairs", fill = "Type") +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave("output/figures/02a_frequency_profile.png", p_freq,
       width = 10, height = 6)
p_freq
#
#
#
#
#
#| label: platform

platform_tbl <- long[, .N, by = .(destination, SOURCE_TYPE)]
platform_wide <- dcast(platform_tbl, destination ~ SOURCE_TYPE,
                        value.var = "N", fill = 0L)

platform_cols <- setdiff(names(platform_wide), "destination")
platform_wide[, total := rowSums(.SD), .SDcols = platform_cols]
platform_wide <- platform_wide[order(-total)]

kable(platform_wide, format.args = list(big.mark = ","),
      caption = "Platform distribution per destination (counts)")

platform_pct <- copy(platform_wide)
for (col in platform_cols) {
  platform_pct[, (col) := round(get(col) / total * 100, 1)]
}
platform_pct[, total := NULL]
kable(platform_pct, caption = "Platform distribution per destination (percent)")

fwrite(platform_wide, "output/tables/02a_platform_counts.csv")
fwrite(platform_pct, "output/tables/02a_platform_percent.csv")
#
#
#
#| label: platform-plot

platform_long <- melt(platform_wide, id.vars = c("destination", "total"),
                      variable.name = "platform", value.name = "n")
platform_long[, pct := n / total * 100]
platform_long[, destination := factor(destination,
                                       levels = freq_profile[order(-pairs),
                                                              destination])]

p_platform <- ggplot(platform_long,
                     aes(destination, pct, fill = platform)) +
  geom_col() +
  scale_fill_brewer(palette = "Set3") +
  labs(title = "Platform composition by destination",
       x = NULL, y = "Percent of pairs", fill = "Platform") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        legend.position = "bottom")

ggsave("output/figures/02a_platform_composition.png", p_platform,
       width = 12, height = 6)
p_platform
#
#
#
#
#
#
#
#
#
#| label: concentration

source_ranking <- long[, .N, by = .(destination, FROM)]
source_ranking[, rank := frank(-N, ties.method = "first"),
               by = destination]
source_ranking[, total_dest := sum(N), by = destination]
source_ranking[, share := N / total_dest]

top_n <- config_2a$top_n_sources

concentration <- source_ranking[rank <= top_n,
  .(top_n_share = sum(share),
    top_source_share = max(share)),
  by = destination]

concentration[, top_n_share := round(top_n_share * 100, 1)]
concentration[, top_source_share := round(top_source_share * 100, 1)]
concentration <- merge(concentration, freq_profile[, .(destination, sources)],
                       by = "destination")
concentration <- concentration[order(-top_n_share)]

kable(concentration, format.args = list(big.mark = ","),
      caption = paste0("Source concentration (top ", top_n,
                       " share of pairs)"))

fwrite(concentration, "output/tables/02a_source_concentration.csv")
#
#
#
#| label: top-sources-per-dest

top_sources <- source_ranking[rank <= 5,
  .(destination, rank, FROM, N, share = round(share * 100, 1))]
kable(top_sources, format.args = list(big.mark = ","),
      caption = "Top 5 sources per destination")
fwrite(top_sources, "output/tables/02a_top_sources_per_destination.csv")
#
#
#
#
#
#
#
#
#
#
#| label: syndication

# use pre-existing content_hash; fill any missing values with synthetic ids
if (!"content_hash" %in% names(long) || all(is.na(long$content_hash))) {
  long[, text_head := substr(FULL_TEXT, 1, config_2a$syndication_n_chars)]
  long[, text_norm := tolower(text_head)]
  long[, text_norm := stri_replace_all_regex(text_norm, "[^\\p{L} ]", "")]
  long[, text_norm := stri_replace_all_regex(text_norm, "\\s+", " ")]
  long[, text_norm := stri_trim_both(text_norm)]
  long[, hashable := !is.na(text_norm) & nchar(text_norm) >= 50]
  hash_vec <- rep(NA_character_, nrow(long))
  hash_vec[long$hashable] <- sapply(
    long$text_norm[long$hashable], digest, algo = "xxhash64")
  long[, content_hash := hash_vec]
  long[is.na(content_hash), content_hash := paste0("nohash_", seq_len(.N))]
} else {
  long[is.na(content_hash), content_hash := paste0("nohash_", .I)]
}

# cluster size per content hash (across unique articles only)
article_level <- unique(long, by = c("article_id", "content_hash"))
article_level[, cluster_size_new := .N, by = content_hash]

# syndication metrics at article level
synd_summary <- article_level[, .(
  total_articles = .N,
  unique_clusters = uniqueN(content_hash),
  duplicated_articles = sum(cluster_size_new > 1),
  syndication_rate = round(sum(cluster_size_new > 1) / .N * 100, 1)
)]
kable(synd_summary, format.args = list(big.mark = ","),
      caption = "Corpus level syndication estimate")

# per destination
synd_per_dest <- long[, .(
  pairs = .N,
  unique_contents = uniqueN(content_hash),
  syndication_rate = round((1 - uniqueN(content_hash) / .N) * 100, 1)
), by = destination][order(-pairs)]

kable(synd_per_dest, format.args = list(big.mark = ","),
      caption = "Syndication rate per destination")

fwrite(synd_per_dest, "output/tables/02a_syndication_per_destination.csv")

# attach updated cluster_size to long if not already present
if (!"cluster_size" %in% names(long)) {
  hash_cluster_map <- unique(article_level[, .(content_hash, cluster_size_new)],
                              by = "content_hash")
  long <- merge(long, hash_cluster_map, by = "content_hash", all.x = TRUE)
  setnames(long, "cluster_size_new", "cluster_size")
  long[is.na(cluster_size), cluster_size := 1L]
}

cat("Syndication metadata ready.\n")
cat("  Rows: ", format(nrow(long), big.mark = ","), "\n", sep = "")
#
#
#
#
#
#| label: daily-distribution

daily_volume <- long[, .N, by = .(destination, date)]
# articles with zero days are invisible here, that is expected

daily_stats <- daily_volume[, .(
  mean_per_day = round(mean(N), 2),
  median_per_day = as.double(median(N)),
  p90 = as.double(quantile(N, 0.90)),
  p99 = as.double(quantile(N, 0.99)),
  max = as.double(max(N)),
  days_active = as.double(.N)
), by = destination][order(-mean_per_day)]

kable(daily_stats, format.args = list(big.mark = ","),
      caption = "Daily volume distribution per destination")

fwrite(daily_stats, "output/tables/02a_daily_stats.csv")
#
#
#
#| label: daily-distribution-plot

daily_volume[, destination := factor(destination,
                                      levels = freq_profile[order(-pairs),
                                                             destination])]

p_daily <- ggplot(daily_volume, aes(N)) +
  geom_histogram(bins = 30, fill = "#2E4057", alpha = 0.85) +
  facet_wrap(~ destination, scales = "free", ncol = 3) +
  scale_x_continuous(trans = "log1p",
                     breaks = c(1, 5, 20, 100, 500)) +
  labs(title = "Daily volume distribution per destination",
       subtitle = "log1p scaled x axis. Heavy right tails indicate spike driven coverage.",
       x = "Pairs per day (log1p scale)", y = "Number of days") +
  theme_minimal()

ggsave("output/figures/02a_daily_distribution.png", p_daily,
       width = 12, height = 8)
p_daily
#
#
#
#
#
#
#
#
#
#| label: scandal-audit-sample

scandal_pairs <- long[has_scandal_register == TRUE]
cat("Pairs with scandal register tag:",
    format(nrow(scandal_pairs), big.mark = ","), "\n\n")

# stratified sample across destinations with at least some scandal hits
dests_with_scandal <- scandal_pairs[, .N, by = destination][N >= 10]$destination

set.seed(config_2a$seed)
audit_sample <- scandal_pairs[destination %in% dests_with_scandal,
                                .SD[sample(.N, min(.N, 3))],
                                by = destination]

audit_sample <- audit_sample[, .(
  destination,
  date = format(date),
  source = substr(FROM, 1, 25),
  title = substr(TITLE, 1, 100),
  snippet = substr(MENTION_SNIPPET, 1, 250),
  has_religious_register,
  has_tourism_register
)]

cat("Stratified audit sample (3 per destination with scandal tags):\n\n")
for (i in seq_len(nrow(audit_sample))) {
  cat("[", audit_sample$destination[i], "] ",
      audit_sample$date[i], " | ", audit_sample$source[i], "\n", sep = "")
  cat("  TITLE:   ", audit_sample$title[i], "\n", sep = "")
  cat("  SNIPPET: ", audit_sample$snippet[i], "\n", sep = "")
  cat("  REG:     rel=", audit_sample$has_religious_register[i],
      " tour=", audit_sample$has_tourism_register[i], "\n\n", sep = "")
}

fwrite(audit_sample, "output/tables/02a_scandal_audit_sample.csv")
cat("Audit sample saved. Inspect output/tables/02a_scandal_audit_sample.csv\n")
cat("Mark each row as TRUE_SCANDAL or NOISE and compute noise rate.\n")
#
#
#
#| label: scandal-root-check

# diagnostic of which scandal root is firing most often
scandal_roots <- c(
  "nesreć", "poginuo", "poginul", "stradal",
  "skandal", "afer",
  "istraga", "optužn", "\\bsud\\b", "suda ", "sudu ",
  "korupcij", "pronevjer", "zloporab",
  "sukob", "kriminal",
  "pljačk", "krađ",
  "prevar", "šok"
)

root_hits <- sapply(scandal_roots, function(r) {
  sum(stri_detect_regex(scandal_pairs$FULL_TEXT, r,
                         opts_regex = list(case_insensitive = TRUE)),
      na.rm = TRUE)
})

scandal_root_table <- data.table(
  root = scandal_roots,
  n_hits = root_hits,
  pct_of_scandal_pairs = round(root_hits / nrow(scandal_pairs) * 100, 1)
)[order(-n_hits)]

kable(scandal_root_table, format.args = list(big.mark = ","),
      caption = "Scandal register root frequency in tagged pairs")

fwrite(scandal_root_table, "output/tables/02a_scandal_root_hits.csv")

cat("\nIf 'sud' or broad stems dominate, the scandal register has lexical noise.\n")
cat("Recommend tightening to eksplicitly scandalous roots only in Phase 2c.\n")
#
#
#
#
#
#| label: decision-gate

cat(strrep("=", 60), "\n")
cat("DECISION GATE 2a\n")
cat(strrep("=", 60), "\n\n")

checks <- list()

# 1. all destinations present
checks$all_present <- nrow(freq_profile) == 10
cat("1. All 10 destinations present: ",
    ifelse(checks$all_present, "PASS", "FAIL"), "\n", sep = "")

# 2. no destination has a single dominant source above concentration threshold
# without at least 3 secondary sources
single_source_risk <- concentration[top_source_share >
                                      config_2a$concentration_threshold * 100]
checks$source_diversity <- nrow(single_source_risk) == 0
cat("2. No destination has a single source above ",
    config_2a$concentration_threshold * 100, "% of coverage: ",
    ifelse(checks$source_diversity, "PASS", "NOTE"), "\n", sep = "")
if (!checks$source_diversity) {
  for (i in seq_len(nrow(single_source_risk))) {
    cat("   ", single_source_risk$destination[i],
        " top source = ", single_source_risk$top_source_share[i], "%\n",
        sep = "")
  }
}

# 3. syndication rate below 40% corpus wide
checks$syndication_ok <- synd_summary$syndication_rate < 40
cat("3. Corpus syndication below 40%: ",
    ifelse(checks$syndication_ok, "PASS", "NOTE"),
    " (", synd_summary$syndication_rate, "%)\n", sep = "")

# 4. all destinations active in at least 50% of analysis months
checks$temporal_coverage <- all(freq_profile$coverage_rate >= 50)
cat("4. All destinations active in at least 50% of months: ",
    ifelse(checks$temporal_coverage, "PASS", "NOTE"), "\n", sep = "")
if (!checks$temporal_coverage) {
  thin <- freq_profile[coverage_rate < 50,
                        .(destination, coverage_rate)]
  for (i in seq_len(nrow(thin))) {
    cat("   ", thin$destination[i], ": ",
        thin$coverage_rate[i], "% of months\n", sep = "")
  }
}

# 5. scandal register top root is not lexically ambiguous stem 'sud'
top_scandal_root <- scandal_root_table[1]$root
checks$scandal_not_sud_dominated <- !grepl("sud", top_scandal_root,
                                             ignore.case = TRUE)
cat("5. Scandal register not dominated by 'sud' stem: ",
    ifelse(checks$scandal_not_sud_dominated, "PASS", "REVIEW"),
    " (top = ", top_scandal_root, ")\n", sep = "")

cat("\n")
n_pass <- sum(unlist(checks))
cat("Passed:", n_pass, "of", length(checks), "\n")
if (all(unlist(checks))) {
  cat("ALL CHECKS PASSED. Phase 2b can proceed.\n")
} else {
  failed <- names(checks)[!unlist(checks)]
  cat("Attention needed:", paste(failed, collapse = ", "), "\n")
}
cat(strrep("=", 60), "\n")
#
#
#
#
#
#| label: save

meta_2a <- list(
  timestamp        = Sys.time(),
  phase            = "2a_descriptive_profile",
  config           = config_2a,
  freq_profile     = freq_profile,
  platform_counts  = platform_wide,
  platform_pct     = platform_pct,
  concentration    = concentration,
  top_sources      = top_sources,
  synd_summary     = synd_summary,
  synd_per_dest    = synd_per_dest,
  daily_stats      = daily_stats,
  scandal_roots    = scandal_root_table,
  checks           = checks,
  analysis_months  = analysis_months
)
saveRDS(meta_2a, config_2a$output_metadata)

# save enriched corpus with content_hash and cluster_size attached
saveRDS(long, "data/destinations_analytical_enriched.rds")
cat("Phase 2a metadata and enriched corpus saved.\n")
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
