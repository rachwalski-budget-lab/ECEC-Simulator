#------------------------------------------------------------------------------
# 00_main.R -- builds state-level demand inputs for the simulator.
#
# Writes one file per geography: out/<GEO>.csv, six rows, annual hours by care
# type. See METHOD.md for what each number means and where it comes from.
#
# STATE LEVEL ONLY. County data enters once, as a sum, in the population step.
# Nothing joins on county, so no geography crosswalk, no name recoding, no
# per-county reconciliation.
#
# Per-geography code lives in states/<GEO>.R and is DATA: a spec declaring
# sources, the few state-specific constants, one function assembling providers.
# The method itself lives here and reaches every geography at once.
#
# Usage:
#   Rscript state_data/00_main.R --geo KY
#   Rscript state_data/00_main.R --all
#   Rscript state_data/00_main.R --all --check
#------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(tibble)
})

STATE_DATA_ROOT <- 'state_data'
BASE_YEAR       <- 2019    # simulator calibration year -- every input pins here

`%||%` <- function(x, y) if (is.null(x)) y else x



#=============================================================================
# CONSTANTS
#=============================================================================

# Care types written out. NO PRICE SPLIT: a state publishes one price, so
# splitting centres into low- and high-priced put every state wholly on one
# side of the national line. Centre care is one row.
#
# Simulator's own reader wants seven types w/ that split -- see
# adjust_alpha_for_state.R. Bridging is separate, mechanical, deliberately not
# part of this method.
ECEC_TYPES <- c('Center-Based', 'Unpaid Center-Based', 'Paid Home-Based',
                'Other Unpaid', 'Other Paid', 'Unpaid Home-Based')

# Hours per child per year, NSECE 2019 -- child-weighted mean weekly hours in
# the child's primary arrangement, x 50 weeks.
#
# Centre-Based is one figure now: the child-weighted mean across the two price
# bands the survey distinguishes, 1372.74 (high, national share .07008) and
# 2020.25 (low, .06556).
NSECE_ANNUAL_HOURS <- c(
  'Center-Based'        = (0.07008 * 1372.7406701055859 +
                           0.06556 * 2020.2520448799016) / (0.07008 + 0.06556),
  'Unpaid Center-Based' = 1436.6520603991025,
  'Paid Home-Based'     = 1919.4541094822120,
  'Other Unpaid'        = 1929.3856418055460,
  'Other Paid'          = 1554.2653530244168,
  'Unpaid Home-Based'   = 2121.8214323768390)

# National fill rates, NSECE 2019 provider surveys. Used ONLY where a state
# publishes no enrollment figure of its own.
#
#   centre 0.9029 -- ACF, Measuring Supply Capacity at Center-based CCEE,
#                    Exhibit 1, five under-5 bands summed
#   home   0.6019 -- 0.7954 fill x 0.7567 published under-5 share. The age half
#                    exists because most registers publish one home figure
#                    covering school-age children.
#
# A register publishing its OWN school-age capacity takes HOME_FILL_ONLY -- the
# fill rate w/out the age correction. Applying 0.6019 to capacity already
# stripped of school age removes it twice. New York is the only such register.
#
# BOTH ARE TOO HIGH, and two states measured how much. Kentucky's 2019 workforce
# study puts its centres at 57% full, not 90%. Virginia's 2022 provider survey
# (n=1,968) puts current capacity at 73% of authorized for centres, 91% for
# homes. Neither is used as a rate -- Kentucky's is Kentucky's, Virginia's is
# out of vintage and measures capacity not enrollment -- but both say the
# national rate leaves too much in, which is what the calibration then removes.
NSECE_FILL <- c(center = 0.9029, home = 0.6019)
NSECE_HOME_FILL_ONLY <- 0.7954

# Share of non-parental care that is FORMAL -- the types an administrative
# source can see. Calibration target. NSECE 2019, by Census region: the survey
# carries no state, so this is as local as it gets.
NSECE_FORMAL_SHARE <- c(northeast = 0.5653, midwest = 0.5292,
                        south     = 0.5316, west    = 0.4835)

# Relative shares of the three types NO register anywhere records -- unpaid
# relatives, nannies, informal arrangements. NSECE national, ft + pt summed,
# renormalised. Contributes a RATIO only; the level is the residual.
NSECE_RESIDUAL_MIX <- local({
  w <- c('Other Unpaid'      = 0.0918407 + 0.0379474,
         'Other Paid'        = 0.0553130 + 0.0221776,
         'Unpaid Home-Based' = 0.0066467 + 0.0008707)
  w / sum(w)
})

FORMAL_TYPES <- c('Center-Based', 'Unpaid Center-Based', 'Paid Home-Based')

# A calibration factor outside this range is a join or parse failure, not a
# calibration. Tripwire, not a parameter: the five builds run 0.62 to 1.58.
CALIBRATION_SANE <- c(0.2, 5)



#=============================================================================
# SHARED INPUTS
#=============================================================================

# WHERE THE DATA IS. Defaults sit inside this directory, which is what a fresh
# clone wants. The cluster keeps 54MB of sources outside the code tree, so
# config_local.yaml (git-ignored) overrides both roots there. Two keys, no
# validation ceremony -- a wrong path fails on the first read with the path in
# the message.
PATHS <- local({
  f <- file.path(STATE_DATA_ROOT, 'config_local.yaml')
  d <- list(raw      = file.path(STATE_DATA_ROOT, 'raw'),
            by_state = file.path(STATE_DATA_ROOT, 'by-state'))
  if (!file.exists(f) || !requireNamespace('yaml', quietly = TRUE)) return(d)
  cfg <- yaml::read_yaml(f)$paths
  list(raw      = cfg$raw      %||% d$raw,
       by_state = cfg$by_state %||% d$by_state)
})


raw_path <- function(...) file.path(PATHS$raw, ...)

geo_raw_path <- function(geo, ...) file.path(PATHS$by_state, geo, 'raw', ...)


read_chr <- function(path) {

  #----------------------------------------------------------------------------
  # Reads a registry all-character. Type guesses vary by locale, by which rows
  # land first -- coercion stays explicit.
  #
  # Params:
  #   - path (chr)
  #
  # Returns: (tibble)
  #----------------------------------------------------------------------------

  if (!file.exists(path)) stop('missing raw file: ', path)
  readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                  show_col_types = FALSE)
}


num <- function(x) suppressWarnings(as.numeric(x))


population_0_4 <- function(fips, counties = NULL) {

  #----------------------------------------------------------------------------
  # Children 0-4, Census PEP vintage 2019, summed to the geography.
  #
  # The ONLY place county data is read, and it is read to be summed. `counties`
  # names a sub-state geography (NYC's five boroughs); NULL takes the state.
  #
  # Params:
  #   - fips (int): state FIPS
  #   - counties (chr vec|NULL): county names w/out the 'County' suffix
  #
  # Returns: (num) children 0-4
  #----------------------------------------------------------------------------

  pep <- read_chr(raw_path(
    'US_PEP__population_children_age_0_4_by_county__2019.csv')) %>%
    dplyr::filter(num(STATE) == fips) %>%
    dplyr::mutate(county = sub(' County$', '', CTYNAME), pop = num(TOT_POP))

  if (!is.null(counties)) {
    missing <- setdiff(counties, pep$county)
    if (length(missing) > 0) {
      stop('population: county not found -- ', paste(missing, collapse = ', '))
    }
    pep <- dplyr::filter(pep, county %in% counties)
  }

  sum(pep$pop)
}



#=============================================================================
# THE BUILD
#=============================================================================

build_geo <- function(spec) {

  #----------------------------------------------------------------------------
  # Runs one geography's spec. Six steps, in the order METHOD.md gives them.
  #
  # Params:
  #   - spec (list): from states/<GEO>.R
  #
  # Returns: (tibble) ecec_type, children, annual_hours + attributes carrying
  #          the diagnostics
  #----------------------------------------------------------------------------

  cat('\n== ', spec$geo, ' -- ', spec$name, '\n', sep = '')

  ## 1. children -------------------------------------------------------------
  n_children <- population_0_4(spec$fips, spec$counties)
  cat('  children 0-4          ', format(n_children, big.mark = ','), '\n')

  ## 2. how many in someone else's care --------------------------------------
  np_total <- round(n_children * spec$nonparental_rate)
  cat('  x non-parental rate   ', sprintf('%.1f%%', 100 * spec$nonparental_rate),
      ' -> ', format(np_total, big.mark = ','), '\n', sep = '')

  ## 3. registry -> children -------------------------------------------------
  prov <- spec$assemble_providers(spec)
  stopifnot(all(c('setting', 'cap_u5') %in% names(prov)))

  by_setting <- prov %>%
    dplyr::group_by(setting) %>%
    dplyr::summarise(providers = dplyr::n(),
                     cap_u5    = sum(cap_u5, na.rm = TRUE), .groups = 'drop') %>%
    dplyr::mutate(children = convert_to_children(setting, providers, cap_u5, spec))

  for (i in seq_len(nrow(by_setting))) {
    cat(sprintf('  %-20s %6d providers, %9s under-5 capacity -> %9s children\n',
                by_setting$setting[i], by_setting$providers[i],
                format(round(by_setting$cap_u5[i]), big.mark = ','),
                format(round(by_setting$children[i]), big.mark = ',')))
  }

  reg_centre <- sum(by_setting$children[grepl('^CENTER', by_setting$setting)])
  reg_home   <- sum(by_setting$children[by_setting$setting == 'HOME']) +
                  (spec$home_add %||% 0)

  ## 4. programmes -- published enrolment, counted not estimated -------------
  programme <- sum(spec$programmes$n_children)
  cat('  programmes            ', format(programme, big.mark = ','),
      ' (', paste(spec$programmes$programme, collapse = ', '), ')\n', sep = '')

  # NETTED OUT OF THE REGISTRY CENTRES, NOT ADDED -- but only the share that
  # actually sits in the register. A programme site holding a state licence is
  # already inside the converted capacity, and adding it counts it twice. A
  # site the register never lists is not, and subtracting it removes children
  # that were never there.
  #
  # `overlap` is that share, per programme, measured where it can be. See each
  # state file. Subtracting everything -- what this build did until 18 Sep
  # 2026 -- overstates the duplication and pushes the calibration to extremes:
  # Kentucky ran x1.578 and now runs x1.174.
  duplicated_in_register <- sum(spec$programmes$n_children *
                                  spec$programmes$overlap)
  cat(sprintf('  of which in register   %s (%.0f%% -- the rest are not licensed)\n',
              format(round(duplicated_in_register), big.mark = ','),
              100 * duplicated_in_register / programme))

  paid_centre <- max(reg_centre - duplicated_in_register, 0)

  ## 5. calibrate the level --------------------------------------------------
  # Registers measure SHAPE well, LEVEL badly. One factor per geography scales
  # the capacity-derived counts until formal care matches the NSECE regional
  # share. Programme counts hold -- a published count is a census.
  target_formal <- NSECE_FORMAL_SHARE[[spec$region]] * np_total
  movable       <- paid_centre + reg_home
  k             <- (target_formal - programme) / movable

  if (k < CALIBRATION_SANE[1] || k > CALIBRATION_SANE[2]) {
    stop(spec$geo, ': calibration factor ', round(k, 3),
         ' outside [', CALIBRATION_SANE[1], ', ', CALIBRATION_SANE[2], ']. ',
         'That is a parse failure, not a calibration.')
  }
  cat('  calibration           x', sprintf('%.3f', k),
      ' (formal -> ', sprintf('%.1f%%', 100 * NSECE_FORMAL_SHARE[[spec$region]]),
      ' of non-parental)\n', sep = '')

  ## 6. residual + hours -----------------------------------------------------
  anchored <- c('Center-Based'        = paid_centre * k,
                'Unpaid Center-Based' = programme,
                'Paid Home-Based'     = reg_home * k)

  residual <- np_total - sum(anchored)
  if (residual <= 0) {
    stop(spec$geo, ': nothing left for informal care. Anchored counts exceed ',
         'the non-parental total, which the calibration should have prevented.')
  }

  children <- c(anchored, residual * NSECE_RESIDUAL_MIX)[ECEC_TYPES]
  cat('  residual (informal)   ', format(round(residual), big.mark = ','),
      sprintf(' -- %.1f%% of non-parental care\n', 100 * residual / np_total))

  out <- tibble::tibble(ecec_type    = ECEC_TYPES,
                        children     = unname(children),
                        annual_hours = unname(children) *
                                         unname(NSECE_ANNUAL_HOURS[ECEC_TYPES]))

  structure(out,
            diagnostics = list(geo = spec$geo, children_0_4 = n_children,
                               nonparental_total = np_total,
                               calibration = k, residual = residual,
                               centre_based = paid_centre * k + programme,
                               licensed_home = reg_home * k))
}


convert_to_children <- function(setting, providers, cap_u5, spec) {

  #----------------------------------------------------------------------------
  # Capacity is a regulatory ceiling. Real enrollment is lower. Two ways down,
  # and a geography declares exactly one per setting.
  #
  #   enrollment -- measured children per provider, from the state's own
  #                 survey. PREFERRED. Kentucky, and New Jersey's centres.
  #   fill       -- capacity x a fill rate. Weaker. Everything else.
  #
  # Params:
  #   - setting (chr vec), providers (num vec), cap_u5 (num vec), spec (list)
  #
  # Returns: (num vec) children
  #----------------------------------------------------------------------------

  vapply(seq_along(setting), function(i) {
    s <- setting[i]
    if (!is.null(spec$enrollment) && s %in% names(spec$enrollment)) {
      return(providers[i] * spec$enrollment[[s]])
    }
    rate <- spec$fill[[s]]
    if (is.null(rate)) stop(spec$geo, ': no conversion declared for setting ', s)
    cap_u5[i] * rate
  }, numeric(1))
}



#=============================================================================
# ORCHESTRATION
#=============================================================================

GEOGRAPHIES <- c('KY', 'NJ', 'NY', 'NYC', 'VA')


load_spec <- function(geo) {
  f <- file.path(STATE_DATA_ROOT, 'states', paste0(geo, '.R'))
  if (!file.exists(f)) stop('no spec for ', geo, ' at ', f)
  source(f, local = FALSE)
  get(paste0('SPEC_', geo))
}


write_geo <- function(res, geo) {
  dir.create(file.path(STATE_DATA_ROOT, 'out'), showWarnings = FALSE,
             recursive = TRUE)
  f <- file.path(STATE_DATA_ROOT, 'out', paste0(geo, '.csv'))
  readr::write_csv(dplyr::select(res, ecec_type, annual_hours), f)
  cat('  wrote                 ', f, '\n')
  f
}



write_interval <- function(spec, point, geo) {

  #----------------------------------------------------------------------------
  # Sidecar carrying the sampling error of the one soft input through to every
  # output row.
  #
  # The non-parental rate rests on ~120 families per geography and carries a
  # standard error of five to six points. Every count is a share of the total
  # that rate produces, so that error reaches every row. It is NOT proportional:
  # programme counts hold fixed while the calibration absorbs the difference, so
  # the build is re-run at each bound rather than the point estimate scaled.
  #
  # The interval covers sampling error in the rate ALONE. It says nothing about
  # the borrowed fill rates, the register's vintage, or the programme overlap.
  # Those are larger and are not quantified anywhere.
  #
  # Params:
  #   - spec (list), point (tibble) the central build, geo (chr)
  #
  # Returns: (chr) path written
  #----------------------------------------------------------------------------

  se <- spec$nonparental_rate_se
  if (is.null(se)) {
    cat('  no interval           ', geo, 'declares no standard error\n')
    return(invisible(NULL))
  }

  at <- function(rate) {
    s <- spec
    s$nonparental_rate <- rate
    quiet <- utils::capture.output(r <- build_geo(s))
    setNames(r$annual_hours, r$ecec_type)
  }
  lo <- at(spec$nonparental_rate - 1.96 * se)
  hi <- at(spec$nonparental_rate + 1.96 * se)

  out <- tibble::tibble(ecec_type    = point$ecec_type,
                        annual_hours = point$annual_hours,
                        low          = unname(lo[point$ecec_type]),
                        high         = unname(hi[point$ecec_type]))
  f <- file.path(STATE_DATA_ROOT, 'out', paste0(geo, '_interval.csv'))
  readr::write_csv(out, f)
  cat(sprintf('  interval              rate %.1f%% (%.1f to %.1f), hours +/- %.0f%%\n',
              100 * spec$nonparental_rate,
              100 * (spec$nonparental_rate - 1.96 * se),
              100 * (spec$nonparental_rate + 1.96 * se),
              100 * (sum(out$high) / sum(out$annual_hours) - 1)))
  f
}


check_geo <- function(res, geo) {

  #----------------------------------------------------------------------------
  # Invariants every build must hold. Cheap, so they run on every build.
  #
  # Params:
  #   - res (tibble), geo (chr)
  #
  # Returns: (int) failures
  #----------------------------------------------------------------------------

  d <- attr(res, 'diagnostics')
  fail <- 0
  say  <- function(ok, msg) {
    cat('   ', if (ok) '[ok]  ' else '[FAIL]', msg, '\n'); if (!ok) 1 else 0
  }

  fail <- fail + say(all(res$children > 0), 'every care type positive')
  fail <- fail + say(nrow(res) == length(ECEC_TYPES),
                     paste(length(ECEC_TYPES), 'rows'))
  fail <- fail + say(abs(sum(res$children) - d$nonparental_total) < 1,
                     'children sum to the non-parental total')
  fail <- fail + say(d$residual / d$nonparental_total > 0.2 &&
                       d$residual / d$nonparental_total < 0.7,
                     'informal share between 20% and 70%')
  fail <- fail + say(all(res$annual_hours > 0), 'hours positive')
  fail
}


main <- function(args = commandArgs(trailingOnly = TRUE)) {

  geos <- if ('--all' %in% args) {
    GEOGRAPHIES
  } else if ('--geo' %in% args) {
    strsplit(args[which(args == '--geo') + 1], ',')[[1]]
  } else {
    cat('usage: Rscript state_data/00_main.R [--geo KY[,NJ]] [--all] [--check]\n')
    cat('geographies: ', paste(GEOGRAPHIES, collapse = ', '), '\n')
    return(invisible(NULL))
  }

  run_checks    <- '--check' %in% args
  want_interval <- '--interval' %in% args
  results <- list()
  failures <- 0

  for (g in geos) {
    spec <- load_spec(g)
    res  <- build_geo(spec)
    write_geo(res, g)
    if (want_interval) write_interval(spec, res, g)
    if (run_checks) failures <- failures + check_geo(res, g)
    results[[g]] <- res
  }

  cat('\n== summary\n')
  summ <- dplyr::bind_rows(lapply(names(results), function(g) {
    d <- attr(results[[g]], 'diagnostics')
    tibble::tibble(geo = g, children_0_4 = d$children_0_4,
                   non_parental = d$nonparental_total,
                   centre_based = round(d$centre_based),
                   licensed_home = round(d$licensed_home),
                   informal = round(d$residual),
                   calibration = round(d$calibration, 3))
  }))
  print(as.data.frame(summ), row.names = FALSE)

  if (run_checks) {
    cat('\n', if (failures == 0) 'ALL CHECKS PASS' else
        paste(failures, 'CHECK(S) FAILED'), '\n')
    if (failures > 0) quit(status = 1)
  }
  invisible(results)
}


if (sys.nframe() == 0) main()
