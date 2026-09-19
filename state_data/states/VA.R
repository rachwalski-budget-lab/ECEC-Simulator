#------------------------------------------------------------------------------
# VA.R -- Virginia
#
# THE MOST INCLUSIVE REGISTER IN THE PROJECT, and that shows in the output.
# VDSS lists Local Ordinance Approved, Voluntarily Registered and
# Unlicensed/Unregistered family day homes alongside licensed ones -- care that
# is invisible in every other state here. It also takes the borrowed national
# fill rate. Both push the same way, and Virginia is the geography the
# calibration cuts hardest, x0.62.
#
# VIRGINIA MEASURED WHY. Miller-Bains, Yu and Bassok (2024), EdWorkingPaper
# 24-983, surveyed 1,968 Virginia providers in fall 2022 and compared what they
# said they could actually serve against what they are licensed for:
#
#   centres  99 authorized -> 72 current   73%
#   homes   8.2 authorized -> 7.4 current   91%
#   all      62 authorized -> 45 current    74%
#
# In that sample 121,260 licensed slots against 89,374 providers could fill.
# NOT USED AS A RATE -- it is 2022, and it measures capacity rather than
# enrollment, so it would double-count against the fill rate. It is why the
# cut is believed rather than suspected. Held at
# raw/documentation/VA_EDWP__authorized_vs_current_capacity__2024.pdf.
#------------------------------------------------------------------------------


# Facility type -> setting. Every approval route VDSS publishes, incl. the ones
# below licensure. An unmapped type stops the build rather than vanishing.
VA_TYPE_SETTING <- c(
  'Child Day Center'                                      = 'CENTER',
  'Religious Exempt Child Day Center'                     = 'CENTER',
  'Short Term Child Day Center'                           = 'CENTER',
  'Local Government Approved CDC'                         = 'CENTER',
  'Certified Pre-School'                                  = 'CENTER',
  'Family Day Home'                                       = 'HOME',
  'Local Ordinance Approved FDH'                          = 'HOME',
  'Unlicensed/Unregistered FDH'                           = 'HOME',
  'System Approved FDH'                                   = 'HOME',
  'Voluntary Registration Registration Duration: Two Year' = 'HOME')

# The six approval routes VDSS's June 2020 capacity column covers, spelled as
# the current register spells them. Header abbreviations: CDC child day centre,
# FDH family day home, VR voluntary registration, RE religious exempt, CCS
# child care system, LOH local ordinance home. Used to match the rebase
# denominator to its numerator.
VA_TYPES_IN_2020_MATRIX <- c(
  'Child Day Center',
  'Family Day Home',
  'Voluntary Registration Registration Duration: Two Year',
  'Religious Exempt Child Day Center',
  'System Approved FDH',
  'Local Ordinance Approved FDH')

VA_SCHOOL_AGE_MONTHS <- 60   # span starting here or later is school-age only
VA_UNDER_SIX_MONTHS  <- 72   # span reaching past here is mixed

# Under-5 share of a mixed-span provider's capacity, measured in-file: mean
# capacity of a span ending under six against one running to nearly thirteen.
#
# RE-MEASURED 2026-09-18, after va_clean_ages() fixed the parse. Cleaned:
#
#   Child Day Center                   59.8 (n=372) vs 113.4 (n=2218) -> 0.527
#   Religious Exempt Child Day Center  63.8 (n=330) vs 105.6 (n= 531) -> 0.604
#   pooled, all centre types                                          -> 0.540
#
# Short Term, Local Government Approved, Certified Pre-School too thin to
# measure -- they take the pooled figure like everything else.
#
# 0.60 KEPT. It sits inside the measured range and above the pooled 0.540, so
# it is the conservative end. The earlier derivation reached the same value on
# Child Day Centre alone (0.597 / 0.607 / 0.408 by lower bound) but on the
# UNCLEANED strings, so agreement was luck: the same 0.60 now rests on a parse
# that reads every row.
#
# Homes keep all of it -- Virginia caps a family day home at 12 children
# whatever ages it serves, so the span says little about the age mix. Measured:
# 1.007 and 0.951 by lower bound.
VA_U5_SHARE_CENTER_MIXED <- 0.60
VA_U5_SHARE_HOME_MIXED   <- 1.00

# Register is a 2026 export. Rebased to June 2020 against VDSS's own locality
# capacity matrix -- one statewide factor, computed from the file rather than
# written down here, so it moves if either source is refreshed.

VA_PREK_CCD         <- 33790   # CCD 2018-19, public-school pre-K
VA_HEAD_START       <- 11579   # NIEER 2018-19, ages 3-4
VA_EARLY_HEAD_START <- 2507    # published; cross-checks against ACF FY2019



va_clean_ages <- function(x) {

  #----------------------------------------------------------------------------
  # Strips contact block VDSS appends to age range:
  #   '1 month - 12 years 11 months VDSS Contact: Tara K Martin: (804) 588-2312'
  #
  # MUST RUN BEFORE va_months(). Upper bound parses as text after the LAST
  # hyphen, and phone number carries one -- so an uncleaned string yields a
  # tail w/ no 'year' or 'month', upper bound 0 months, row reads as NOT mixed
  # and keeps 100% of capacity incl. school age.
  #
  # 1,055 rows, 78,486 places, 21.2% of register. 861 Religious Exempt centres,
  # 173 voluntarily registered homes, 21 certified pre-schools. Most span
  # '1 month - 12 years 11 months' -- squarely mixed, silently unscaled.
  #
  # Params:
  #   - x (chr vec)
  #
  # Returns: (chr vec) age range alone
  #----------------------------------------------------------------------------

  trimws(sub(' *VDSS Contact:.*$', '', x))
}



va_months <- function(x) {

  #----------------------------------------------------------------------------
  # Age string -> months. 'Birth' is zero; '2 years - 6 years 11 months' parses
  # both ends. Unparseable stays NA and the row keeps full capacity.
  #
  # Params:
  #   - x (chr vec): cleaned by va_clean_ages() first
  #
  # Returns: (num vec) months
  #----------------------------------------------------------------------------

  y <- num(sub('.*?([0-9]+) *year.*',  '\\1', x))
  m <- num(sub('.*?([0-9]+) *month.*', '\\1', x))
  y[is.na(y) | !grepl('year',  x)] <- 0
  m[is.na(m) | !grepl('month', x)] <- 0
  out <- y * 12 + m
  out[grepl('^[[:space:]]*Birth', x)] <- 0
  out[is.na(x) | x == ''] <- NA_real_
  out
}



va_assemble_providers <- function(spec) {

  #----------------------------------------------------------------------------
  # Reads VDSS, cuts to under five, rebases to 2020.
  #
  # Params:
  #   - spec (list)
  #
  # Returns: (tibble) setting, cap_u5
  #----------------------------------------------------------------------------

  d <- read_chr(geo_raw_path('VA',
         'VA_VDSS__licensed_providers_by_locality__2026-09.csv'))

  unknown <- setdiff(unique(d$facility_type), names(VA_TYPE_SETTING))
  if (length(unknown) > 0) {
    stop('VA: facility type(s) not mapped: ', paste(unknown, collapse = ', '),
         '. The register added a type -- map it to CENTER or HOME.')
  }

  ages    <- va_clean_ages(d$ages)
  lo      <- va_months(sub(' *-.*$', '', ages))
  hi      <- va_months(sub('^.*- *', '', ages))
  setting <- unname(VA_TYPE_SETTING[d$facility_type])

  # Tripwire: an upper bound of 0 months means the string did not parse. Before
  # va_clean_ages() 1,055 rows landed here and silently kept school-age capacity.
  n_zero <- sum(!is.na(hi) & hi == 0)
  if (n_zero > 0) {
    stop('VA: ', n_zero, ' age ranges parse to an upper bound of 0 months. ',
         'Register changed the field. Check va_clean_ages().')
  }

  school_only <- !is.na(lo) & lo >= VA_SCHOOL_AGE_MONTHS
  mixed       <- !is.na(hi) & hi >= VA_UNDER_SIX_MONTHS & !school_only
  share <- dplyr::case_when(!mixed              ~ 1,
                            setting == 'CENTER' ~ VA_U5_SHARE_CENTER_MIXED,
                            TRUE                ~ VA_U5_SHARE_HOME_MIXED)

  cat('    VDSS ', nrow(d), ' facilities, ', sum(school_only),
      ' school-age-only dropped, ', sum(mixed), ' mixed-span scaled\n', sep = '')

  # Rebase to June 2020: VDSS's own published child care slots over the current
  # register's capacity. One statewide factor -- county factors are what the
  # old county build needed, and nothing here is below the state.
  #
  # DENOMINATOR MATCHES THE NUMERATOR'S UNIVERSE. The 2020 column names it in
  # its own header -- 'CC Slots (age range birth to 12 yrs) (CDC, FDH, VR, RE,
  # CCS, LOH)' -- so the current register is cut to those six routes before
  # dividing. Dividing by all ten put 4,597 places in the denominator that the
  # 2020 figure never counted (3,922 Short Term centre, 675 Certified
  # Pre-School), understating the factor: 0.9006 against 0.9120 like for like.
  m20 <- read_chr(geo_raw_path('VA',
           'VA_VDSS20__locality_capacity_and_program_slots__2020-06.csv'))
  cc <- grep('^CC Slots', names(m20), value = TRUE)
  if (length(cc) != 1) {
    stop('VA: expected one "CC Slots" column in the 2020 matrix, found ',
         length(cc))
  }
  in_2020 <- d$facility_type %in% VA_TYPES_IN_2020_MATRIX
  f <- sum(num(m20[[cc]]), na.rm = TRUE) /
         sum(num(d$capacity)[in_2020], na.rm = TRUE)
  cat(sprintf('    capacity rebased to Jun 2020, statewide x%.4f (%d of %d ',
              f, sum(in_2020), nrow(d)))
  cat('facilities match the 2020 universe)\n')

  tibble::tibble(setting = setting, school_only = school_only,
                 cap_u5  = num(d$capacity) * share * f) %>%
    dplyr::filter(!school_only, !is.na(setting)) %>%
    dplyr::select(setting, cap_u5)
}



# HOW MUCH OF EACH PROGRAMME ALREADY SITS IN THE REGISTER.
#
# Step 4 subtracts a programme's children from the converted register capacity,
# to avoid counting a licensed Head Start centre twice. That is only right for
# the share of the programme the register actually lists.
#
# MEASURED for Head Start and Early Head Start, 18 Sep 2026: every open service
# location in ACF's file matched to the register on ZIP plus street number plus
# street name, and on coordinates within 25 metres where both carry them.
# Weighted by funded places.
#
#   KY   Head Start 37.1%   Early Head Start 50.6%
#   NJ              64.7%                    62.7%
#   NY              77.3%                    77.5%
#   NYC             70.6%                    67.9%
#   VA              mean of the four -- its register publishes no address
#
# CHECKS OUT against the earlier county build, which measured the same quantity
# independently: KY 38.1% against 37.1% here, NJ 63.0% against 64.7%. New York
# differs -- 49.3% there against 77.3% here -- because this match reads both
# regulators, OCFS and DOHMH, and much of the state's Head Start is in the city.
#
# PRE-K IS NOT MEASURED, and it is 53% to 73% of each programme total, so it
# carries most of the remaining uncertainty. It stays at 1 -- the assumption
# the whole step used to make -- so this change only ever reduces the
# subtraction. Public-school pre-K is generally exempt from child care
# licensing, so the true figure is probably well below 1. Settling it needs
# NCES's EDGE school geocode file, which is not held here.


SPEC_VA <- list(
  geo    = 'VA',
  name   = 'Virginia',
  fips   = 51,
  region = 'south',

  assemble_providers = va_assemble_providers,

  # Borrowed, and known too high -- see header for Virginia's own measurement.
  fill = list(CENTER = NSECE_FILL[['center']],
              HOME   = NSECE_FILL[['home']]),

  # NO unlicensed home count. Census Nonemployer counts 13,449 child day care
  # businesses in Virginia, but the register already reaches below licensure,
  # so the gap it would fill is smaller here than elsewhere and the
  # children-per-provider figure to convert it does not exist.

  programmes = tibble::tribble(
    ~programme,          ~n_children,                   ~overlap,
    'public pre-K',        VA_PREK_CCD,                   0.440,
    'Head Start',          VA_HEAD_START,                 0.622,
    'Early Head Start',    VA_EARLY_HEAD_START,           0.647),

  # NSCH 2019 k6q20, children 0-4, child-weighted. n = 121 records.
  # Single wave. Virginia moves most between waves of any state here -- 61.7%
  # in 2018, 52.0% in 2019, 46.7% in 2020 -- so pooling would do the most
  # damage to the level precisely where the level is least stable.
  nonparental_rate = 0.5203,

  # Standard error on that rate, sqrt(p(1-p)/n_eff) with Kish effective n
  # from the same 121 records. Step 2 carries it through to an interval on
  # every output row; nothing else in the build reads it.
  nonparental_rate_se = 0.0588
)


VA_VALIDATION <- list(
  children_0_4           = 505477,  # PEP 2019, 133 localities
  facilities_harvested   = 5474,    # VDSS detail pages
  capacity_all_ages      = 369556,  # as published, before age scaling
  facilities_no_capacity = 454,     # approved routes publishing no number
  nonemployer_estab      = 13449,   # Census Nonemployer 2019 -- NOT used
  state_prek_enrolled    = 17657,   # NIEER VPI 2018-19
  own_center_capacity_ratio = 0.73  # EDWP 2024, current / authorized
)
