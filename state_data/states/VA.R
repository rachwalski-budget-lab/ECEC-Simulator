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

VA_SCHOOL_AGE_MONTHS <- 60   # span starting here or later is school-age only
VA_UNDER_SIX_MONTHS  <- 72   # span reaching past here is mixed

# Under-5 share of a mixed-span provider's capacity. Homes keep all of it --
# Virginia caps a family day home at 12 children of mixed ages, so the span
# says little about the age mix.
VA_U5_SHARE_CENTER_MIXED <- 0.60
VA_U5_SHARE_HOME_MIXED   <- 1.00

# Register is a 2026 export. Rebased to June 2020 against VDSS's own locality
# capacity matrix -- one statewide factor, computed from the file rather than
# written down here, so it moves if either source is refreshed.

VA_PREK_CCD         <- 33790   # CCD 2018-19, public-school pre-K
VA_HEAD_START       <- 11579   # NIEER 2018-19, ages 3-4
VA_EARLY_HEAD_START <- 2507    # published; cross-checks against ACF FY2019



va_months <- function(x) {

  #----------------------------------------------------------------------------
  # Age string -> months. 'Birth' is zero; '2 years - 6 years 11 months' parses
  # both ends. Unparseable stays NA and the row keeps full capacity.
  #
  # Params:
  #   - x (chr vec)
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

  lo      <- va_months(sub(' *-.*$', '', d$ages))
  hi      <- va_months(sub('^.*- *', '', d$ages))
  setting <- unname(VA_TYPE_SETTING[d$facility_type])

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
  m20 <- read_chr(geo_raw_path('VA',
           'VA_VDSS20__locality_capacity_and_program_slots__2020-06.csv'))
  cc <- grep('^CC Slots', names(m20), value = TRUE)
  if (length(cc) != 1) {
    stop('VA: expected one "CC Slots" column in the 2020 matrix, found ',
         length(cc))
  }
  f <- sum(num(m20[[cc]]), na.rm = TRUE) / sum(num(d$capacity), na.rm = TRUE)
  cat(sprintf('    capacity rebased to Jun 2020, statewide x%.4f\n', f))

  tibble::tibble(setting = setting, school_only = school_only,
                 cap_u5  = num(d$capacity) * share * f) %>%
    dplyr::filter(!school_only, !is.na(setting)) %>%
    dplyr::select(setting, cap_u5)
}



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
    ~programme,          ~n_children,
    'public pre-K',      VA_PREK_CCD,
    'Head Start',        VA_HEAD_START,
    'Early Head Start',  VA_EARLY_HEAD_START),

  # NSCH 2019 k6q20, children 0-4, child-weighted. n = 121 records.
  # Single wave. Virginia moves most between waves of any state here -- 61.7%
  # in 2018, 52.0% in 2019, 46.7% in 2020 -- so pooling would do the most
  # damage to the level precisely where the level is least stable.
  nonparental_rate = 0.5203
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
