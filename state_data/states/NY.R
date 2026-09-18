#------------------------------------------------------------------------------
# NY.R -- New York State, all 62 counties, city included.
#
# TWO REGULATORS, TWO REGISTERS. New York City's centres are permitted by NYC
# DOHMH under Health Code Article 47; OCFS licenses none of them -- the state
# register carries ZERO day care centre rows in the five boroughs. So a
# complete state build reads both files, and neither alone covers the state.
#
# OCFS does license family day care citywide, so homes come from the state
# register everywhere including the boroughs.
#
# NYC.R builds the five boroughs on their own, from this same code. The two
# outputs OVERLAP by design: each is a deliverable in its own right.
#
# BORROWED FILL RATES. New York publishes none. Its 2019 market rate survey
# asks enrollment in Appendix 1 and reports rates across all eleven tables.
# The national NSECE figures stand in, and the calibration then corrects the
# level.
#------------------------------------------------------------------------------


NYC_BOROUGHS <- c('Bronx', 'Kings', 'New York', 'Queens', 'Richmond')

# DOHMH writes boroughs in caps; OCFS and the population file name counties.
NYC_BOROUGH_TO_COUNTY <- c('BRONX' = 'Bronx', 'BROOKLYN' = 'Kings',
                           'MANHATTAN' = 'New York', 'QUEENS' = 'Queens',
                           'STATEN ISLAND' = 'Richmond')


# CAPACITY REBASED TO 2019, per programme type, against OCFS's own published
# 2015-2025 series of providers and capacity by modality.
#
# Registers are 2026 exports. Homes have fallen hard since 2019 and centres
# barely moved, so one blanket factor would misstate the mix. FDC runs the
# other way -- the 2026 file holds fewer FDC rows than 2019 did, so its factor
# is above one.
NY_DRIFT <- c(GCC = 141027/141091, DCC = 172924/185105, SDCC = 172924/185105,
              GFDC = 43386/50200,  FDC = 17358/12928)

# The city drifted differently from the rest of the state, and OCFS publishes
# it separately. Homes only -- the city's centres are DOHMH's.
NY_DRIFT_NYC <- c(GFDC = 79648/94393, FDC = 8982/5220)


# Public-school pre-K, CCD 2018-19: 54,451 children across all 62 counties,
# counted school by school. Supersedes an earlier modelled 55,016 built from
# NIEER's level x NYSED's setting share; the two agree to 1.0%, which
# validates that construction and retires it.
NY_PREK_CCD  <- 54451
NYC_PREK_CCD <- 26717   # CCD, five boroughs

# Head Start ages 3-4, NIEER 2018-19. GROSS of pre-K overlap.
#
# UNRESOLVED DOUBLE COUNT: New York Head Start centres commonly hold OCFS
# licences, so some of these children may already sit in the converted DCC
# capacity. Treat Unpaid Center-Based as an upper bound.
NY_HEAD_START  <- 36863
# City share taken from the Head Start service-location file's own funded slots,
# 7,194 of 20,285 statewide.
NYC_HEAD_START <- round(NY_HEAD_START * 7194 / 20285)   # 13,073

NY_EARLY_HEAD_START  <- 11433
NYC_EARLY_HEAD_START <- 5938



ny_providers <- function(counties = NULL) {

  #----------------------------------------------------------------------------
  # Composes New York's provider table from both registers, rebased to 2019.
  #
  # SACC -- School-Age Child Care, 2,731 providers -- never enters: outside a
  # universe stopping at four.
  #
  # Homes report one lump total, but OCFS publishes school-age capacity
  # separately, so under-5 home capacity subtracts rather than being scaled.
  # That is why the home conversion uses the fill rate ALONE, w/out the age
  # correction -- applying 0.6019 here would remove school age twice.
  #
  # Params:
  #   - counties (chr vec|NULL): NULL for the whole state
  #
  # Returns: (tibble) setting, cap_u5
  #----------------------------------------------------------------------------

  ocfs  <- read_chr(geo_raw_path('NY',
            'NYS_OCFS__licensed_providers_by_county__2026-09.csv'))
  dohmh <- read_chr(geo_raw_path('NY',
            'NYC_DOHMH__licensed_providers_by_borough__2026-09.csv'))

  gcc <- dohmh %>%
    dplyr::filter(facility_type == 'GCC') %>%
    dplyr::transmute(county       = unname(NYC_BOROUGH_TO_COUNTY[borough]),
                     program_type = 'GCC',
                     nyc_capacity = capacity) %>%
    dplyr::filter(!is.na(county))
  cat('    DOHMH ', nrow(gcc), ' Article 47 centres (OCFS licenses none in ',
      'the five boroughs)\n', sep = '')

  d <- dplyr::bind_rows(ocfs, gcc)
  if (!is.null(counties)) d <- dplyr::filter(d, county %in% counties)

  in_nyc <- d$county %in% NYC_BOROUGHS
  f      <- unname(NY_DRIFT[d$program_type])
  f_nyc  <- unname(NY_DRIFT_NYC[d$program_type])
  f      <- dplyr::if_else(in_nyc & !is.na(f_nyc), f_nyc, f)
  f      <- tidyr::replace_na(f, 1)

  g <- function(col) tidyr::replace_na(num(d[[col]]), 0) * f

  centre_u5 <- g('infant_capacity') + g('toddler_capacity') + g('preschool_capacity')
  home_u5   <- pmax(g('total_capacity') - g('school_age_capacity'), 0)

  out <- dplyr::bind_rows(
    tibble::tibble(setting = 'CENTER_OCFS',
                   cap_u5  = centre_u5[d$program_type %in% c('DCC', 'SDCC')]),
    tibble::tibble(setting = 'CENTER_DOHMH',
                   cap_u5  = g('nyc_capacity')[d$program_type == 'GCC']),
    tibble::tibble(setting = 'HOME',
                   cap_u5  = home_u5[d$program_type %in% c('GFDC', 'FDC')]))

  cat('    rebased to 2019 -- GFDC x', round(NY_DRIFT[['GFDC']], 3),
      ', FDC x', round(NY_DRIFT[['FDC']], 3),
      ', centres x', round(NY_DRIFT[['DCC']], 3), '\n', sep = '')
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


SPEC_NY <- list(
  geo    = 'NY',
  name   = 'New York State',
  fips   = 36,
  region = 'northeast',

  assemble_providers = function(spec) ny_providers(NULL),

  # Borrowed. Homes take the fill rate ALONE -- OCFS already stripped school
  # age, so the under-5 correction must not be applied a second time.
  fill = list(CENTER_OCFS  = NSECE_FILL[['center']],
              CENTER_DOHMH = NSECE_FILL[['center']],
              HOME         = NSECE_HOME_FILL_ONLY),

  # NO unlicensed home count. Nonemployer counts 49,173 child day care
  # businesses in New York, but converting a BUSINESS count to a CHILD count
  # needs children per provider, which New York does not publish. Note the
  # register already reaches low -- family day care registers from three
  # children up -- so the gap is smaller here than elsewhere.

  programmes = tibble::tribble(
    ~programme,          ~n_children,                   ~overlap,
    'public pre-K',        NY_PREK_CCD,                   1.000,
    'Head Start',          NY_HEAD_START,                 0.773,
    'Early Head Start',    NY_EARLY_HEAD_START,           0.775),

  # NSCH 2019 k6q20, children 0-4, child-weighted. n = 112 records.
  # Single wave; see METHOD.md. New York's 2020 rate holds up better than the
  # other three (62.1%) but the pool still fails on the other two states.
  nonparental_rate = 0.5766
)


NY_VALIDATION <- list(
  children_0_4              = 1127001,  # PEP 2019, 62 counties
  licensed_capacity_total   = 690115,   # OCFS register, all ages
  licensed_capacity_under5  = 166051,   # infant + toddler + preschool
  nonemployer_estab         = 49173,    # Census Nonemployer 2019 -- NOT used
  state_prek_enrolled       = 126302,   # NIEER 2018-19, both settings
  ccap_children_2019_monthly = 105390   # OCFS CCAP by district, 2019 mean
)
