#!/usr/bin/env Rscript

# letter-dist-moodle.R — summarize and plot letter-grade distribution
# Default: uses "Course total (Letter)" if present.

usage <- function(exit_status = 0) {
  cat("
Usage:
  letter-dist-moodle.R <grades_file.csv> [--letter-col <name>]

Options:
  --letter-col <name>   Column to use for letter grades (case-insensitive).
                        Default is \"Course total (Letter)\" if present.

Examples:
  letter-dist-moodle.R CSI3450-grades.csv
  letter-dist-moodle.R CSI3450-grades.csv --letter-col \"Letter grade\"
\n")
  quit(status = exit_status, save = "no")
}

# --- helpers -----------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b
trim <- function(x) sub("^[[:space:]]+|[[:space:]]+$", "", x)
normalize_name <- function(x) tolower(gsub("[[:space:][:punct:]]+", "", x))

looks_like_letter <- function(v) {
  grepl("^([A-F][+-]?|P|NP|S|U|I|W)$", toupper(trim(v)))
}

pick_letter_col <- function(df, override = NULL, prefer = NULL) {
  nms <- colnames(df)

  # 1) honor explicit override
  if (!is.null(override)) {
    norm <- normalize_name(override)
    match_idx <- which(normalize_name(nms) == norm)
    if (length(match_idx) == 1) return(match_idx)
    cat("Warning: --letter-col '", override, "' not found; attempting auto-detect...\n", sep = "")
  }

  # 2) check preferred default column
  if (!is.null(prefer)) {
    match_idx <- which(nms == prefer)
    if (length(match_idx) == 1) return(match_idx)
  }

  # 3) heuristics
  scores <- rep(0, length(nms))
  ln <- tolower(nms)
  scores[grepl("\\bletter\\b", ln)] <- scores[grepl("\\bletter\\b", ln)] + 3
  scores[grepl("\\bgrade\\b", ln)]  <- scores[grepl("\\bgrade\\b", ln)]  + 1
  scores[grepl("\\bletter\\s*grade\\b|\\bgrade\\s*letter\\b", ln)] <- scores[grepl("\\bletter\\s*grade\\b|\\bgrade\\s*letter\\b", ln)] + 4

  for (i in seq_along(nms)) {
    vs <- na.omit(as.character(df[[i]]))
    if (length(vs) == 0) next
    scores[i] <- scores[i] + mean(looks_like_letter(vs)) * 3
  }

  best <- order(scores, decreasing = TRUE)[1]
  if (scores[best] > 0) return(best)
  NA_integer_
}

canonical_order <- function(levels_found) {
  base <- c("A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F",
            "P", "NP", "S", "U", "I", "W")
  c(intersect(base, levels_found), sort(setdiff(levels_found, base)))
}

# --- args parsing ------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || any(args %in% c("-h", "--help"))) usage(0)

letter_col_arg <- NULL
pos <- which(args == "--letter-col")
if (length(pos) == 1) {
  if (pos == length(args)) {
    cat("Error: --letter-col requires a column name.\n\n")
    usage(1)
  }
  letter_col_arg <- args[pos + 1]
  args <- args[-c(pos, pos + 1)]
}

if (length(args) != 1) {
  cat("Error: please provide exactly one CSV file.\n\n")
  usage(1)
}

infile <- args[1]
if (!file.exists(infile)) {
  cat("Error: file not found:", infile, "\n\n")
  usage(1)
}

# --- load data ---------------------------------------------------------------
df <- tryCatch(
  {
    tmp <- read.csv(infile, header = TRUE, sep = ",", check.names = FALSE, na.strings = c("", "NA"))
    all_na <- apply(tmp, 1, function(r) all(is.na(r) | trim(as.character(r)) == ""))
    if (any(all_na)) tmp <- tmp[!all_na, , drop = FALSE]
    tmp
  },
  error = function(e) stop(sprintf("Failed to read CSV: %s", conditionMessage(e)), call. = FALSE)
)

if (nrow(df) == 0) stop("CSV appears to be empty.", call. = FALSE)

# --- detect letter-grade column ---------------------------------------------
idx <- pick_letter_col(df, override = letter_col_arg, prefer = "Course total (Letter)")
if (is.na(idx)) {
  cat("Error: could not find a letter-grade column.\n",
      "Try using --letter-col \"Letter grade\" with the exact header name.\n\n")
  usage(1)
}

lname <- colnames(df)[idx]
cat("Using letter-grade column:", lname, "\n")

letters_clean <- toupper(trim(as.character(df[[idx]])))
letters_clean <- letters_clean[letters_clean != "" & !is.na(letters_clean)]

if (length(letters_clean) == 0) stop(sprintf("Column '%s' contains no letter-grade values.", lname), call. = FALSE)

# --- distribution ------------------------------------------------------------
tab <- sort(table(letters_clean))
dist <- data.frame(Letter = names(tab), Frequency = as.integer(tab))

ord <- match(canonical_order(dist$Letter), dist$Letter)
ord <- ord[!is.na(ord)]
dist <- dist[ord, , drop = FALSE]

# --- output ------------------------------------------------------------------
print(dist, row.names = FALSE)

# Percentages
tot <- sum(dist$Frequency)
pct <- (dist$Frequency / tot) * 100
pct_lbl <- sprintf("%.1f%%", pct)

# Make a bar plot with a bit of headroom for labels
ymax <- max(dist$Frequency)
bp <- barplot(
  height = dist$Frequency,
  names.arg = dist$Letter,
  main = "Letter Grade Distribution",
  xlab  = "Letter Grade",
  ylab  = "Frequency",
  ylim  = c(0, ymax * 1.15)   # add 15% headroom for labels above bars
)

# Put percentage labels at the top of each bar
text(
  x = bp,
  y = dist$Frequency,
  labels = pct_lbl,
  pos = 3,        # above the bar; use pos = 3 for top, or NA + custom 'y' for center
  cex = 0.9
)

# If you prefer labels centered inside the bars instead, comment the block above
# and use this instead:
# text(
#   x = bp,
#   y = dist$Frequency / 2,
#   labels = pct_lbl,
#   cex = 0.9
# )
