#------------------------------------------------------------------------------
# KY.R -- Kentucky
#
# MEASURED ENROLLMENT, and the only geography here that has it for both
# settings. Kentucky's own 2019 workforce survey prints capacity and enrollment
# side by side, so no fill rate is applied at all.
#
# THAT SURVEY IS WHY THE NATIONAL FILL RATE IS DISTRUSTED EVERYWHERE ELSE. Same
# table gives Kentucky's own centre fill rate -- 42/73 = 0.575 -- against the
# national 0.9029 this build would otherwise use. 1.57x too high.
#
# BEST REGISTRY VINTAGE IN THE PROJECT, by accident. Kentucky publishes no bulk
# provider file; kynect's search is a Salesforce app. What exists is Child Care
# Aware of America's republication of the state's two registers as ArcGIS
# feature services, never edited since 2018-09-26. So Kentucky's composition is
# a September 2018 snapshot, ten months before the base year.
#
# THE PRICE IS PROVENANCE: third-party republication, no extract date, no
# methodology, no facility-type column. Replace if the state opens a download.
#------------------------------------------------------------------------------


# Kentucky licenses Type II homes in the provider's residence for at most 12
# children; Type I centres have no cap. Register carries no type column, so 12
# is what separates them. 83 of 1,916 rows sit at or below it.
KY_HOME_CAPACITY_MAX <- 12


# Under-5 share of a mixed-age provider's lump capacity, measured INSIDE the
# register: mean capacity of a band against the same band w/out school age.
#
#   INFANT TO TWO_TO_SCHOOL     73.5 (n=187) vs INFANT TO SCHOOL_AGE   93.2 -> 0.789
#   TWO_TO_SCHOOL               52.5 (n=241) vs ... TO SCHOOL_AGE     107.8 -> 0.487
#   TODDLER TO TWO_TO_SCHOOL    80.7 (n=45)  vs TODDLER TO SCHOOL_AGE  97.6 -> 0.827
#
# Each band takes its OWN ratio -- the three disagree, and the middle disagrees
# hardest because a centre serving 2-through-12 is twice the size of one
# serving 2-to-4. Real difference in what those centres are, not noise.
KY_U5_SHARE <- c('INFANT TO SCHOOL_AGE'        = 0.789,
                 'TWO_TO_SCHOOL TO SCHOOL_AGE' = 0.487,
                 'TODDLER TO SCHOOL_AGE'       = 0.827)


# MEASURED ENROLLMENT. Child Care Aware of Kentucky, 2019 Workforce Study,
# Table 20 -- capacity AND enrollment by age band, fielded Feb-Mar 2019.
#
#              Capacity        Enrolled
#              Dir   FCC       Dir  FCC
#   Infant      9     3         5    3
#   Toddler    20     5        12    3
#   Preschool  44     4        25    3
#   School Age 35     3        18    2
#
# Under-5 = infant + toddler + preschool, school age excluded exactly:
#   centres 5 + 12 + 25 = 42        homes 3 + 3 + 3 = 9
#
# PRECISION. Directors n = 448 (31.7% of 1,417). FCC column rests on 48 (22.2%
# of 216) and is thin; its capacity row sums to 12, Kentucky's LICENSED home
# cap rather than the six-child certified cap, so it may describe licensed
# rather than certified homes. Home capacity is 2,280 against 165,712 for
# centres, so either reading moves the build well under a percent.
KY_ENROLLMENT <- c(CENTER = 42, HOME = 9)


# Public-school pre-K, CCD 2018-19, school-level membership joined to county:
# 28,465 children. NIEER reports the Kentucky Preschool Program at 21,351 for
# the same year -- CCD is 33% higher because its `Pre-Kindergarten` grade spans
# children KPP does not fund, incl. district-funded places and preschool
# special education. CCD used because it is a direct count.
KY_PREK_CCD <- 28465

# Head Start ages 3-4. NIEER State of Preschool 2019, KY profile (2018-19).
# GROSS of state pre-K overlap -- NIEER nets dual enrolment only out of its pie
# charts, not this row. State-funded Head Start in Kentucky: 0.
KY_HEAD_START <- 12307

# Early Head Start, birth to three -- inside a universe stopping at four, and
# absent from every earlier build. NIEER, The State(s) of Head Start and Early
# Head Start (2023), KY profile p.126, 2018-19 bar.
#
# Cross-checks EXACTLY against ACF Head Start Program Facts FY2019: 12,163 +
# 3,004 = 15,167, the published state total. Kentucky has no AIAN component.
KY_EARLY_HEAD_START <- 3004



ky_assemble_providers <- function(spec) {

  #----------------------------------------------------------------------------
  # Composes Kentucky's provider table from its two registers.
  #
  # School-age-only rows dropped -- 224 providers, 27,433 capacity, outside a
  # universe stopping at four. Rows w/ NO age band recorded KEPT at full
  # capacity: 33 of them, nearly all small. Dropping an unrecorded field reads
  # a reporting gap as a closed provider.
  #
  # Params:
  #   - spec (list)
  #
  # Returns: (tibble) setting, cap_u5
  #----------------------------------------------------------------------------

  lic  <- read_chr(geo_raw_path('KY',
            'KY_CCAOA__licensed_providers_by_county__2018-09.csv'))
  cert <- read_chr(geo_raw_path('KY',
            'KY_CCAOA__certified_home_providers_by_county__2018-09.csv'))

  n_sa <- sum(lic$Age_Range_of_Service == 'SCHOOL_AGE', na.rm = TRUE)
  cat('    licensed ', nrow(lic), ' providers, ', n_sa,
      ' school-age-only dropped\n', sep = '')

  l <- lic %>%
    dplyr::filter(is.na(Age_Range_of_Service) |
                    Age_Range_of_Service != 'SCHOOL_AGE') %>%
    dplyr::transmute(
      setting = dplyr::if_else(num(Capacity) <= KY_HOME_CAPACITY_MAX,
                               'HOME', 'CENTER', missing = 'CENTER'),
      cap_u5  = num(Capacity) *
                  tidyr::replace_na(unname(KY_U5_SHARE[Age_Range_of_Service]), 1))

  c_ <- dplyr::transmute(cert, setting = 'HOME', cap_u5 = num(Capacity))
  cat('    certified ', nrow(c_), ' family homes\n', sep = '')

  dplyr::bind_rows(l, c_)
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


SPEC_KY <- list(
  geo    = 'KY',
  name   = 'Kentucky',
  fips   = 21,
  region = 'south',

  assemble_providers = ky_assemble_providers,

  # NO FILL RATE. Both settings measured -- see KY_ENROLLMENT.
  enrollment = as.list(KY_ENROLLMENT),

  # NO unlicensed home count. Converting Census Nonemployer's 5,387 child day
  # care businesses to a child count needs a children-per-provider figure
  # Kentucky does not publish.

  programmes = tibble::tribble(
    ~programme,          ~n_children,                   ~overlap,
    'public pre-K',        KY_PREK_CCD,                   0.370,
    'Head Start',          KY_HEAD_START,                 0.371,
    'Early Head Start',    KY_EARLY_HEAD_START,           0.506),

  # NSCH 2019 k6q20, children 0-4, child-weighted. n = 147 records.
  # SINGLE WAVE, deliberately. Pooling 2018+2019+2020 would centre exactly on
  # 2019 and cut the error ~40%, but NSCH 2020 was fielded through the pandemic
  # and Kentucky's rate collapses to 45.8% against 57-59% either side. Pooling
  # 2018+2019 alone centres on mid-2018 while every other input is pinned to
  # 2019. Tested, rejected, documented in METHOD.md.
  nonparental_rate = 0.5940,

  # Standard error on that rate, sqrt(p(1-p)/n_eff) with Kish effective n
  # from the same 147 records. Step 2 carries it through to an interval on
  # every output row; nothing else in the build reads it.
  nonparental_rate_se = 0.0488
)


KY_VALIDATION <- list(
  children_0_4               = 272610,  # PEP 2019
  licensed_providers         = 1916,    # CCAoA, Sep 2018
  licensed_capacity_all_ages = 165712,
  certified_homes            = 252,
  nonemployer_estab          = 5387,    # Census Nonemployer 2019 -- NOT used
  state_prek_enrolled        = 21351,   # NIEER KPP 2018-19
  own_center_fill_rate       = 0.575    # vs national 0.9029
)
