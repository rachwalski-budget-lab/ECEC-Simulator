#------------------------------------------------------------------------------
# NYC.R -- New York City, the five boroughs.
#
# Not a state. A sub-state geography that gets its own build because it has its
# own regulator, its own register, and is asked about on its own.
#
# RUNS ON NY.R's CODE AND NY.R's SOURCES -- same two registers, cut to five
# counties. The only thing NYC declares for itself is its programme counts and
# its share of the population.
#
# THIS BUILD AND THE NY BUILD DISAGREE, ON PURPOSE. Each is calibrated to the
# Northeast formal share against its OWN non-parental total, so the five
# boroughs come out differently depending on which build produced them. The
# case for the city rake is that a city analysis wants the city internally
# consistent with the target it is calibrated against, rather than positioned
# inside a state distribution it is not being simulated as part of.
#
# WHOEVER READS BOTH FILES MUST KNOW THEY WILL NOT MATCH.
#
# THE CITY TAKES THE STATE'S NON-PARENTAL RATE. NSCH publishes no sub-state
# geography, so there is no city rate to measure. Everything distinguishing the
# city has to come from the registers, and does.
#------------------------------------------------------------------------------

source(file.path(STATE_DATA_ROOT, 'states', 'NY.R'))


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


SPEC_NYC <- list(
  geo      = 'NYC',
  name     = 'New York City',
  fips     = 36,
  counties = NYC_BOROUGHS,
  region   = 'northeast',

  assemble_providers = function(spec) ny_providers(NYC_BOROUGHS),

  fill = list(CENTER_OCFS  = NSECE_FILL[['center']],
              CENTER_DOHMH = NSECE_FILL[['center']],
              HOME         = NSECE_HOME_FILL_ONLY),

  programmes = tibble::tribble(
    ~programme,          ~n_children,                   ~overlap,
    'public pre-K',        NYC_PREK_CCD,                  1.000,
    'Head Start',          NYC_HEAD_START,                0.706,
    'Early Head Start',    NYC_EARLY_HEAD_START,          0.679),

  # New York's rate. See header.
  nonparental_rate = 0.5766
)


# LEGALLY EXEMPT CARE IN THE CITY, FFY2019 -- a FLOOR, not an anchor, and it
# does not bind. OCFS counts 2,254 LE Family, 5,051 LE In-Home and 175 LE Group
# providers in the city. Those are SUBSIDISED children of all ages. This build
# assigns far more than that to the informal types, as it should -- subsidy
# reaches a small minority of informal care. Recorded because it rules out a
# catastrophic understatement.
NYC_VALIDATION <- list(
  children_0_4                = 523718,  # PEP 2019, five boroughs
  dohmh_permits_active        = 2760,    # 2,310 GCC + 450 SBCC
  dohmh_gcc_capacity          = 141364,  # what this build converts
  ocfs_2019_nyc_dcc_providers = 2232,    # OCFS's own 2019 count, vs DOHMH 2,310
  ocfs_home_capacity_nyc      = 103163,  # FDC + GFDC, all ages
  le_family_providers_2019    = 2254,
  ccap_children_2019_monthly  = 67515,
  share_of_ny_children        = 0.465
)
