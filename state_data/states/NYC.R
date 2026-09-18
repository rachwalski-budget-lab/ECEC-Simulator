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
    ~programme,          ~n_children,
    'public pre-K',      NYC_PREK_CCD,
    'Head Start',        NYC_HEAD_START,
    'Early Head Start',  NYC_EARLY_HEAD_START),

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
