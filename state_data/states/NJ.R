#------------------------------------------------------------------------------
# NJ.R -- New Jersey
#
# CENTRES ONLY. DCF licenses child care centres and publishes them; family child
# care in New Jersey is registered through county-level sponsor agencies and
# there is no state register to read. So Paid Home-Based has no registry anchor
# here at all, and the one figure that exists comes from a survey -- see
# NJ_PAID_HOME_BASED below.
#
# OWN FILL RATE, unlike New York and Virginia. New Jersey's 2021 market rate
# survey publishes centre utilisation, so the national 0.9029 is not used.
#
# REGISTER FROZEN AT MAY 2019, so no drift correction. Best vintage after
# Kentucky, and it needs nothing done to it.
#------------------------------------------------------------------------------


# Age spans in the register. School-age-only centres are dropped outright;
# spans reaching to 13 keep the under-5 share below.
NJ_AGES_SCHOOL_ONLY <- '6 to 13'
NJ_AGES_MIXED       <- c('0 to 13', '2½ to 13', '2 to 13')

# Under-5 share of a mixed-span centre's lump capacity.
NJ_U5_SHARE_MIXED <- 0.820

# MEASURED FILL RATE. NJ market rate survey 2021, Figure 7, 2020 column,
# slot-weighted under-5. Used instead of the national 0.9029.
NJ_FILL_CENTER <- 0.6733


# PAID HOME-BASED, from a survey rather than a register, because no register
# exists. NJ family child care study: 1,396 children under five reported across
# 913 responding providers, scaled to the 1,254 registered providers.
NJ_FCC_PROVIDERS   <- 1254
NJ_FCC_RESPONDENTS <- 913
NJ_FCC_CHILDREN_U5 <- 1396
NJ_PAID_HOME_BASED <- round(NJ_FCC_CHILDREN_U5 * NJ_FCC_PROVIDERS /
                              NJ_FCC_RESPONDENTS)   # 1,917


NJ_PREK_CCD         <- 41305   # CCD 2018-19, public-school pre-K
NJ_HEAD_START       <- 11940   # NIEER 2018-19, ages 3-4
NJ_EARLY_HEAD_START <- 3578    # NIEER State(s) of Head Start, 2018-19



nj_assemble_providers <- function(spec) {

  #----------------------------------------------------------------------------
  # Reads the DCF register and scales each centre's lump capacity to its
  # under-5 share, from the licensed age span.
  #
  # Params:
  #   - spec (list)
  #
  # Returns: (tibble) setting, cap_u5
  #----------------------------------------------------------------------------

  d <- read_chr(geo_raw_path('NJ',
         'NJ_DCF__licensed_child_care_centers_by_county__2019-05.csv'))

  n_sa   <- sum(d$ages == NJ_AGES_SCHOOL_ONLY, na.rm = TRUE)
  cap_sa <- sum(num(d$capacity[d$ages == NJ_AGES_SCHOOL_ONLY]), na.rm = TRUE)
  cat('    DCF ', nrow(d), ' licensed centres, ', n_sa, ' school-age-only ',
      'dropped (', format(cap_sa, big.mark = ','), ' capacity)\n', sep = '')

  out <- d %>%
    dplyr::filter(is.na(ages) | ages != NJ_AGES_SCHOOL_ONLY) %>%
    dplyr::transmute(
      setting = 'CENTER',
      cap_u5  = num(capacity) * dplyr::if_else(ages %in% NJ_AGES_MIXED,
                                               NJ_U5_SHARE_MIXED, 1, missing = 1))

  cat('    ', sum(d$ages %in% NJ_AGES_MIXED, na.rm = TRUE), ' mixed-span ',
      'centres scaled to ', NJ_U5_SHARE_MIXED, '\n', sep = '')
  out
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


SPEC_NJ <- list(
  geo    = 'NJ',
  name   = 'New Jersey',
  fips   = 34,
  region = 'northeast',

  assemble_providers = nj_assemble_providers,

  fill = list(CENTER = NJ_FILL_CENTER),

  # Survey-derived, added to the (empty) registry home count.
  home_add = NJ_PAID_HOME_BASED,

  programmes = tibble::tribble(
    ~programme,          ~n_children,                   ~overlap,
    'public pre-K',        NJ_PREK_CCD,                   0.554,
    'Head Start',          NJ_HEAD_START,                 0.647,
    'Early Head Start',    NJ_EARLY_HEAD_START,           0.627),

  # NSCH 2019 k6q20, children 0-4, child-weighted. n = 101 records -- thinnest
  # cell in the build. Single wave; see METHOD.md on why pooling was rejected.
  # New Jersey's 2020 rate collapses to 42.6% against 58-60% either side.
  nonparental_rate = 0.6022,

  # Standard error on that rate, sqrt(p(1-p)/n_eff) with Kish effective n
  # from the same 101 records. Step 2 carries it through to an interval on
  # every output row; nothing else in the build reads it.
  nonparental_rate_se = 0.0624
)


NJ_VALIDATION <- list(
  children_0_4             = 514690,  # PEP 2019
  licensed_centers         = 4163,    # DCF, frozen 2019-05
  capacity_all_ages        = 386436,
  capacity_school_age_only = 99468,   # dropped
  nonemployer_estab        = 13617,   # Census Nonemployer 2019 -- NOT used
  state_prek_enrolled      = 52553    # NIEER 2018-19, incl. contracted seats
)
