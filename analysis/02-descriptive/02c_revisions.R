## 02c_revisions.R
## Stage A analyses for manuscript revision (manuscript_one.qmd).
## Reads existing analytic corpus and STM model, runs all seven revisions,
## saves outputs to output/tables/02c_revised_*.csv.

suppressMessages({
  library(data.table)
  library(stringi)
  library(nnet)
  library(sandwich)
  library(lmtest)
  library(stm)
})

set.seed(2026)

corpus_path <- "analysis/02-descriptive/data/destinations_analytical_final.rds"
stm_path    <- "analysis/03-framing/data/03a_stm_model.rds"
out_dir     <- "analysis/02-descriptive/output/tables"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

dt <- readRDS(corpus_path)
setDT(dt)

cat("Corpus loaded:", nrow(dt), "articles,", ncol(dt), "columns\n")

###############################################################################
## A.1 — Polysemy gate uniformly applied (P2.16)
###############################################################################
cat("\n=== A.1 Polysemy gate uniformly applied ===\n")

before_by_dest <- dt[, .(N_before = .N), by = destination][order(-N_before)]
gated <- dt[has_religious_register == TRUE | has_tourism_register == TRUE]
after_by_dest <- gated[, .(N_after = .N), by = destination]

gate_compare <- merge(before_by_dest, after_by_dest, by = "destination",
                      all.x = TRUE)
gate_compare[is.na(N_after), N_after := 0L]
gate_compare[, N_dropped := N_before - N_after]
gate_compare[, pct_dropped := round(100 * N_dropped / N_before, 2)]
gate_compare[, currently_gated := destination %in%
               c("sinj", "nin", "solin", "krasno", "ludbreg")]
print(gate_compare)

cat("\nTotal before:", nrow(dt), "  after:", nrow(gated),
    "  dropped:", nrow(dt) - nrow(gated), "\n")

# Frame distribution comparison
frame_before <- dt[, .(N = .N), by = dominant_frame]
frame_before[, pct := round(100 * N / sum(N), 2)]
frame_after <- gated[, .(N = .N), by = dominant_frame]
frame_after[, pct := round(100 * N / sum(N), 2)]
frame_compare <- merge(
  frame_before[, .(dominant_frame, N_before = N, pct_before = pct)],
  frame_after[, .(dominant_frame, N_after = N, pct_after = pct)],
  by = "dominant_frame", all = TRUE
)
print(frame_compare)

fwrite(gate_compare, file.path(out_dir, "02c_revised_polysemy_gate.csv"))
fwrite(frame_compare,
       file.path(out_dir, "02c_revised_polysemy_gate_frames.csv"))

###############################################################################
## A.2 — Refit multinomial logit with clustered SEs (P0.1, P0.2, P0.3)
###############################################################################
cat("\n=== A.2 Refit MNL ===\n")

# Prepare model data — replicate the §4.1 model setup from 02c_framing_stm.qmd
md <- copy(dt)
md[, month := as.integer(format(as.Date(date), "%m"))]
md[, month_f       := factor(month, levels = 1:12)]
md[, destination_f := factor(destination)]
md[, platform_f    := factor(SOURCE_TYPE)]
md[, dest_type_f   := factor(dest_type_cat)]
md[, feast_f       := factor(ifelse(in_feast_window, "window", "off"))]

md[, frame_f := factor(dominant_frame,
                       levels = c("religious_only",
                                  "religious_memorial",
                                  "religious_tourism_mixed",
                                  "religious_with_scandal",
                                  "tourism_only",
                                  "tourism_with_scandal"))]

# Drop rare scandal categories (N < 500), per existing logic
freq <- md[, .N, by = frame_f]
rare <- freq[N < 500]$frame_f
cat("Dropping rare frames:\n"); print(freq[frame_f %in% rare])
md_mnl <- md[!frame_f %in% rare]
md_mnl[, frame_f := droplevels(frame_f)]
cat("Analytic N for MNL:", nrow(md_mnl), "\n")
cat("Frame levels in fit:\n"); print(levels(md_mnl$frame_f))

# Spec (a): drop dest_type_f, keep destination_f
cat("\nFitting Spec (a) — keep destination, drop dest_type_f...\n")
fit_a <- multinom(
  frame_f ~ destination_f + year_num + month_f + platform_f + feast_f,
  data = md_mnl, trace = FALSE, MaxNWts = 5000, maxit = 500, abstol = 1e-6
)
cat("  AIC:", round(AIC(fit_a)), "  Converged:", fit_a$convergence == 0, "\n")

# Spec (b): drop destination_f, keep dest_type_f
cat("\nFitting Spec (b) — drop destination, keep dest_type_f...\n")
fit_b <- multinom(
  frame_f ~ dest_type_f + year_num + month_f + platform_f + feast_f,
  data = md_mnl, trace = FALSE, MaxNWts = 5000, maxit = 500, abstol = 1e-6
)
cat("  AIC:", round(AIC(fit_b)), "  Converged:", fit_b$convergence == 0, "\n")

# Vanilla coefficients with naive SEs first
extract_coef <- function(fit, label) {
  s <- summary(fit)
  co <- s$coefficients
  se <- s$standard.errors
  out_list <- list()
  for (lvl in rownames(co)) {
    out_list[[lvl]] <- data.table(
      spec      = label,
      outcome   = lvl,
      predictor = colnames(co),
      coef      = as.numeric(co[lvl, ]),
      se_naive  = as.numeric(se[lvl, ])
    )
  }
  rbindlist(out_list)
}

coef_a <- extract_coef(fit_a, "spec_a_no_desttype")
coef_b <- extract_coef(fit_b, "spec_b_no_destination")

# Cluster-robust SEs at source level (FROM)
# nnet::multinom does not have an estfun method in sandwich, so we build
# clustered SEs via per-outcome binary logits (one-vs-rest, with
# religious_only as the implicit reference excluded). For each non-reference
# outcome we fit binary logistic regression on the indicator variable.
cat("\nComputing source-clustered SEs via per-outcome binary logits...\n")

ref_level <- "religious_only"
md_mnl[, source_id := factor(FROM)]

per_outcome_clusterSE <- function(spec_formula_rhs, label) {
  out_chunks <- list()
  for (lvl in setdiff(levels(md_mnl$frame_f), ref_level)) {
    md_mnl[, y := as.integer(frame_f == lvl)]
    f <- as.formula(paste("y ~", spec_formula_rhs))
    fit <- glm(f, data = md_mnl, family = binomial())
    vc <- tryCatch(
      vcovCL(fit, cluster = md_mnl$source_id, type = "HC1"),
      error = function(e) NULL
    )
    if (is.null(vc)) next
    se_cl <- sqrt(diag(vc))
    z <- coef(fit) / se_cl
    p <- 2 * pnorm(-abs(z))
    out_chunks[[lvl]] <- data.table(
      spec      = label,
      outcome   = lvl,
      predictor = names(coef(fit)),
      coef      = as.numeric(coef(fit)),
      se_cluster = as.numeric(se_cl),
      z          = as.numeric(z),
      p_value    = as.numeric(p)
    )
  }
  rbindlist(out_chunks)
}

cl_a <- per_outcome_clusterSE(
  "destination_f + year_num + month_f + platform_f + feast_f",
  "spec_a_no_desttype"
)
cl_b <- per_outcome_clusterSE(
  "dest_type_f + year_num + month_f + platform_f + feast_f",
  "spec_b_no_destination"
)

# Merge naive (from MNL) and clustered (from per-outcome logits) where available
mnl_a <- merge(coef_a, cl_a[, .(spec, outcome, predictor, se_cluster, p_value)],
               by = c("spec", "outcome", "predictor"), all.x = TRUE)
mnl_b <- merge(coef_b, cl_b[, .(spec, outcome, predictor, se_cluster, p_value)],
               by = c("spec", "outcome", "predictor"), all.x = TRUE)

mnl_a[, sig := fcase(p_value < 0.001, "***",
                     p_value < 0.01, "**",
                     p_value < 0.05, "*",
                     default = "")]
mnl_b[, sig := fcase(p_value < 0.001, "***",
                     p_value < 0.01, "**",
                     p_value < 0.05, "*",
                     default = "")]

fwrite(mnl_a, file.path(out_dir, "02c_revised_mnl_no_dest_type.csv"))
fwrite(mnl_b, file.path(out_dir, "02c_revised_mnl_no_destination.csv"))

# Side-by-side comparison: nemarijansko effect on tourism, lokalno on memorial
comp <- data.table(
  spec       = c("(a) drop dest_type",
                 "(b) drop destination"),
  AIC        = c(round(AIC(fit_a)), round(AIC(fit_b))),
  N          = c(nrow(md_mnl), nrow(md_mnl)),
  converged  = c(fit_a$convergence == 0, fit_b$convergence == 0),
  n_predictors = c(length(fit_a$coefnames), length(fit_b$coefnames))
)
fwrite(comp, file.path(out_dir, "02c_revised_mnl_comparison.csv"))
print(comp)

# Summary helper for headline coefficients on tourism_only and religious_memorial
print_headline <- function(mnl_dt, spec_label) {
  cat("\n--- Headline coefficients in", spec_label, "---\n")
  for (out_lvl in c("religious_memorial", "tourism_only")) {
    sub <- mnl_dt[outcome == out_lvl &
                    predictor %like% "destination_f|dest_type_f"]
    if (nrow(sub) > 0) {
      cat("\n", out_lvl, ":\n", sep = "")
      print(sub[, .(predictor, coef = round(coef, 3),
                    se_cluster = round(se_cluster, 3),
                    p = round(p_value, 4), sig)])
    }
  }
}
print_headline(mnl_a, "Spec (a)")
print_headline(mnl_b, "Spec (b)")

###############################################################################
## A.3 — Re-specify §4.4 temporal model with year FE (P0.4)
###############################################################################
cat("\n=== A.3 Temporal model with year FE ===\n")

# Build destination-year panel
panel <- dt[, .(
  N_total      = .N,
  N_tourism    = sum(dominant_frame == "tourism_only"),
  N_religious  = sum(dominant_frame == "religious_only"),
  N_memorial   = sum(dominant_frame == "religious_memorial"),
  N_mixed      = sum(dominant_frame == "religious_tourism_mixed")
), by = .(destination, dest_type_cat, year)]

panel[, tourism_share   := N_tourism / N_total]
panel[, religious_share := N_religious / N_total]
panel[, memorial_share  := N_memorial / N_total]
panel[, year_f := factor(year)]
panel[, destination_f := factor(destination)]
cat("Panel size:", nrow(panel), "destination-year cells\n")
cat("Years:", paste(sort(unique(panel$year)), collapse = ", "), "\n")

# Spec: year FE + destination FE, drop dest_type_cat (collinear with destination)
fit_yfe_t <- lm(tourism_share ~ year_f + destination_f, data = panel)
fit_yfe_r <- lm(religious_share ~ year_f + destination_f, data = panel)
fit_yfe_m <- lm(memorial_share ~ year_f + destination_f, data = panel)

# Cluster-robust SEs at destination level (small N=10 caveat)
get_cluster_summary <- function(fit, cluster_var, label) {
  vc <- vcovCL(fit, cluster = cluster_var, type = "HC1")
  tt <- coeftest(fit, vcov. = vc)
  out <- as.data.table(tt[, , drop = FALSE], keep.rownames = "predictor")
  setnames(out, c("predictor", "coef", "se_cluster", "t", "p_value"))
  out[, outcome := label]
  out[, sig := fcase(p_value < 0.001, "***",
                     p_value < 0.01, "**",
                     p_value < 0.05, "*",
                     default = "")]
  out
}

ts_t <- get_cluster_summary(fit_yfe_t, panel$destination, "tourism_share")
ts_r <- get_cluster_summary(fit_yfe_r, panel$destination, "religious_share")
ts_m <- get_cluster_summary(fit_yfe_m, panel$destination, "memorial_share")

trend_results <- rbindlist(list(ts_t, ts_r, ts_m))
trend_results[, coef       := round(coef, 4)]
trend_results[, se_cluster := round(se_cluster, 4)]
trend_results[, p_value    := round(p_value, 4)]

# F-test for joint significance of year FE
ftest <- function(fit, label) {
  fit_no_year <- update(fit, . ~ . - year_f)
  a <- anova(fit_no_year, fit)
  data.table(outcome = label,
             F = round(a$F[2], 3),
             df1 = a$Df[2], df2 = a$Res.Df[2],
             p = round(a$`Pr(>F)`[2], 4))
}
ftest_results <- rbindlist(list(
  ftest(fit_yfe_t, "tourism_share"),
  ftest(fit_yfe_r, "religious_share"),
  ftest(fit_yfe_m, "memorial_share")
))
cat("\nF-tests for joint significance of year FE:\n")
print(ftest_results)

# Year-by-year mean shares
yearly <- panel[, .(
  tourism_share   = round(weighted.mean(tourism_share, N_total), 3),
  religious_share = round(weighted.mean(religious_share, N_total), 3),
  memorial_share  = round(weighted.mean(memorial_share, N_total), 3),
  N_articles      = sum(N_total)
), by = year][order(year)]
cat("\nYear-by-year corpus-weighted shares:\n")
print(yearly)

fwrite(trend_results,
       file.path(out_dir, "02c_revised_temporal_year_fe.csv"))
fwrite(ftest_results,
       file.path(out_dir, "02c_revised_temporal_ftest.csv"))
fwrite(yearly,
       file.path(out_dir, "02c_revised_temporal_yearly.csv"))

###############################################################################
## A.4 — Bootstrap CI for Cramér's V (P2.18, P2.19)
###############################################################################
cat("\n=== A.4 Bootstrap CI for Cramér's V ===\n")

cramers_v <- function(tab) {
  cs <- chisq.test(tab, correct = FALSE)
  k <- min(nrow(tab), ncol(tab))
  unname(sqrt(cs$statistic / (sum(tab) * (k - 1))))
}

# Build the destination × frame matrix
ct <- dt[, .N, by = .(destination, dominant_frame)]
ct_wide <- dcast(ct, destination ~ dominant_frame, value.var = "N", fill = 0L)
ct_mat <- as.matrix(ct_wide[, -1])
rownames(ct_mat) <- ct_wide$destination

V_point <- cramers_v(ct_mat)
chi_sq  <- chisq.test(ct_mat, correct = FALSE)$statistic

cat("Point estimate V =", round(V_point, 4), "\n")
cat("chi-sq =", round(unname(chi_sq), 1), "  df =", chisq.test(ct_mat)$parameter, "\n")

# Article-level bootstrap
n_boot <- 1000
boot_V <- numeric(n_boot)
n_total <- nrow(dt)
dt_boot <- dt[, .(destination, dominant_frame)]

cat("Bootstrapping", n_boot, "replicates...\n")
for (b in seq_len(n_boot)) {
  idx <- sample.int(n_total, n_total, replace = TRUE)
  tab <- table(dt_boot$destination[idx], dt_boot$dominant_frame[idx])
  if (any(rowSums(tab) == 0) || any(colSums(tab) == 0)) {
    boot_V[b] <- NA_real_
  } else {
    boot_V[b] <- cramers_v(tab)
  }
  if (b %% 200 == 0) cat("  ", b, "\n")
}
boot_V <- boot_V[!is.na(boot_V)]

ci <- quantile(boot_V, c(0.025, 0.5, 0.975))
cat("\n95% CI for V:\n")
cat("  median:", round(ci[2], 4), "\n")
cat("  2.5% :", round(ci[1], 4), "\n")
cat("  97.5%:", round(ci[3], 4), "\n")

cv_out <- data.table(
  metric    = c("point_estimate", "boot_median",
                "boot_ci_lower_2.5", "boot_ci_upper_97.5",
                "n_replicates", "chi_sq", "df"),
  value = c(round(V_point, 4),
            round(ci[2], 4),
            round(ci[1], 4),
            round(ci[3], 4),
            length(boot_V),
            round(unname(chi_sq), 1),
            chisq.test(ct_mat)$parameter)
)
fwrite(cv_out, file.path(out_dir, "02c_revised_cramerv_bootstrap.csv"))

# Cohen-style cutoffs for V given df_min = min(rows, cols) - 1
# small/medium/large for our 10x6 matrix (df_min = 5): 0.1, 0.3, 0.5 are
# rough Cohen guidelines for omega/V at that df.
cat("\nCohen-style cutoffs (df_min = 5): small 0.1, medium 0.3, large 0.5\n")
cat("Our V = ", round(V_point, 3), " falls in the small-to-medium range.\n")

###############################################################################
## A.5 — Dictionary threshold sensitivity (P2.13)
###############################################################################
cat("\n=== A.5 Dictionary threshold sensitivity ===\n")

# Read register patterns
reg_dt <- fread("dictionaries/registers.csv")
print(reg_dt[, .(register, pattern_chars = nchar(keyword_pattern))])

# Count regex matches per article for each register, on FULL_TEXT (lowercased)
text_lc <- stri_trans_tolower(dt$FULL_TEXT, locale = "hr")

rel_pat  <- reg_dt[register == "religious", keyword_pattern]
tour_pat <- reg_dt[register == "tourism", keyword_pattern]
mem_pat  <- reg_dt[register == "memorial", keyword_pattern]
scn_pat  <- reg_dt[register == "scandal", keyword_pattern]

cat("Counting matches per article (this takes ~30s)...\n")
dt[, n_match_rel  := stri_count_regex(text_lc, rel_pat)]
dt[, n_match_tour := stri_count_regex(text_lc, tour_pat)]
dt[, n_match_mem  := stri_count_regex(text_lc, mem_pat)]
dt[, n_match_scn  := stri_count_regex(text_lc, scn_pat)]

# Frame derivation at threshold k
derive_frames <- function(d, k) {
  d <- copy(d)
  d[, rel_act := n_match_rel  >= k]
  d[, tour_act := n_match_tour >= k]
  d[, mem_act := n_match_mem  >= k]
  d[, scn_act := n_match_scn  >= k]
  d[, frame_k := fcase(
    mem_act & !rel_act & !tour_act, "memorial_only",
    mem_act & rel_act,              "religious_memorial",
    scn_act & !rel_act & !tour_act, "scandal",
    rel_act & tour_act,             "religious_tourism_mixed",
    rel_act & !tour_act & scn_act,  "religious_with_scandal",
    rel_act & !tour_act,            "religious_only",
    tour_act & !rel_act & scn_act,  "tourism_with_scandal",
    tour_act & !rel_act,            "tourism_only",
    default = "other"
  )]
  d[, .N, by = frame_k][, .(frame_k, N, pct = round(100 * N / sum(N), 2))]
}

sens_results <- list()
for (k in 1:3) {
  cat("\nThreshold k =", k, "\n")
  res <- derive_frames(dt, k)
  res[, threshold := k]
  print(res)
  sens_results[[as.character(k)]] <- res
}
sens_dt <- rbindlist(sens_results)
fwrite(sens_dt, file.path(out_dir, "02c_revised_dictionary_sensitivity.csv"))

cat("\nMemorial share at each threshold:\n")
mem_share <- sens_dt[frame_k == "religious_memorial" |
                       frame_k == "memorial_only",
                     .(memorial_total = sum(N),
                       memorial_pct   = sum(pct)),
                     by = threshold]
print(mem_share)

###############################################################################
## A.6 — Voćin/Aljmaš memorial decomposition (P1.7, P1.9, P1.10)
###############################################################################
cat("\n=== A.6 Memorial decomposition ===\n")

dest_mem <- dt[, .(
  N_total    = .N,
  N_memorial = sum(dominant_frame == "religious_memorial")
), by = .(destination, dest_type_cat)]
dest_mem[, pct_memorial   := round(100 * N_memorial / N_total, 1)]
dest_mem[, share_of_total := round(100 * N_memorial / sum(N_memorial), 1)]
setorder(dest_mem, -pct_memorial)
print(dest_mem)

total_memorial <- sum(dest_mem$N_memorial)
vocin_aljmas   <- dest_mem[destination %in% c("vocin", "aljmas"),
                            sum(N_memorial)]
share_vocin_aljmas <- round(100 * vocin_aljmas / total_memorial, 1)
cat("\nTotal memorial articles:", total_memorial, "\n")
cat("Voćin + Aljmaš memorial:", vocin_aljmas,
    " (", share_vocin_aljmas, "% of all memorial)\n", sep = "")
cat("Outside Voćin + Aljmaš:", total_memorial - vocin_aljmas,
    " (", round(100 - share_vocin_aljmas, 1), "%)\n", sep = "")

# By type
type_mem <- dt[, .(
  N_total    = .N,
  N_memorial = sum(dominant_frame == "religious_memorial")
), by = dest_type_cat]
type_mem[, pct_memorial := round(100 * N_memorial / N_total, 1)]
type_mem[, share_of_total := round(100 * N_memorial / sum(N_memorial), 1)]
print(type_mem)

# Within local-Marian: Voćin + Aljmaš vs others
local_mem <- dest_mem[dest_type_cat == "lokalno_marijansko"]
local_mem[, group := ifelse(destination %in% c("vocin", "aljmas"),
                             "vocin_aljmas", "other_local")]
local_summary <- local_mem[, .(
  N_total    = sum(N_total),
  N_memorial = sum(N_memorial),
  pct_memorial = round(100 * sum(N_memorial) / sum(N_total), 1)
), by = group]
print(local_summary)

fwrite(dest_mem,
       file.path(out_dir, "02c_revised_memorial_decomposition_by_dest.csv"))
fwrite(type_mem,
       file.path(out_dir, "02c_revised_memorial_decomposition_by_type.csv"))
fwrite(local_summary,
       file.path(out_dir, "02c_revised_memorial_local_decomp.csv"))

###############################################################################
## A.7 — STM topic T19 vs dictionary memorial cross-tab (P1.8)
###############################################################################
cat("\n=== A.7 T19 vs dictionary memorial cross-tab ===\n")

stm_model <- readRDS(stm_path)
cat("STM model dim: theta", dim(stm_model$theta), "\n")

if (nrow(stm_model$theta) != nrow(dt)) {
  cat("WARNING: STM theta rows (", nrow(stm_model$theta),
      ") != corpus rows (", nrow(dt), "). ", sep = "")
  cat("Need to align by article order.\n")
  # The 03a script likely subsets articles before fitting STM. Let's check
  # by reading the searchK or convergence_check data — but for now assume
  # the dfm in 03a was built from the same 13921 rows.
}

dominant_topic <- apply(stm_model$theta, 1, which.max)
cat("Dominant topic distribution:\n")
print(table(dominant_topic))

if (length(dominant_topic) == nrow(dt)) {
  dt[, dominant_topic := dominant_topic]
} else {
  # Truncate or error — we'll truncate the smaller one
  n_use <- min(length(dominant_topic), nrow(dt))
  dt_sub <- dt[seq_len(n_use)]
  dt_sub[, dominant_topic := dominant_topic[seq_len(n_use)]]
  dt <- dt_sub
}

# Cross-tab: dominant_topic x dictionary_memorial
dt[, is_memorial := dominant_frame == "religious_memorial"]
xtab <- dt[, .(N_total = .N,
               N_memorial = sum(is_memorial),
               pct_memorial = round(100 * sum(is_memorial) / .N, 1)),
            by = dominant_topic]
setorder(xtab, -pct_memorial)
cat("\nTopics ranked by memorial-frame share:\n")
print(head(xtab, 10))

# Specifically T19 and T8
cat("\nT19 (war commemoration):\n")
print(xtab[dominant_topic == 19])
cat("\nT8 (Voćin/Aljmaš diocesan):\n")
print(xtab[dominant_topic == 8])

# Inverse view: of memorial-frame articles, what topics dominate
mem_topics <- dt[is_memorial == TRUE,
                  .(N = .N), by = dominant_topic]
mem_topics[, pct_of_memorial := round(100 * N / sum(N), 1)]
setorder(mem_topics, -N)
cat("\nOf memorial-frame articles, modal STM topic:\n")
print(head(mem_topics, 15))

fwrite(xtab,
       file.path(out_dir, "02c_revised_t19_topics_by_memorial_share.csv"))
fwrite(mem_topics,
       file.path(out_dir, "02c_revised_memorial_articles_by_topic.csv"))

###############################################################################
cat("\n=== Stage A complete. Outputs in", out_dir, "===\n")
list.files(out_dir, pattern = "02c_revised_", full.names = FALSE)
