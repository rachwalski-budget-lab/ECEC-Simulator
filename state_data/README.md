# State-level demand inputs

Builds the demand file the simulator reads — `out/<GEO>.csv`, six rows, annual
hours by care type — from each state's own administrative data.

```bash
Rscript state_data/00_main.R --geo KY        # build one
Rscript state_data/00_main.R --all           # build all five
Rscript state_data/00_main.R --all --check   # build and run the invariants
```

**[METHOD.md](METHOD.md) is the document to read.** It says what every number
means, where it comes from, and how solid it is. This file is just the map.

## What is built

Five geographies: **KY, NJ, NY, NYC, VA**. New York is all 62 counties, city
included. New York City is the five boroughs, built again on its own — the two
overlap on purpose and will not match, for the reason `states/NYC.R` gives.

Supply stays national. This directory writes demand only.

## State level, not county level

County data is read once, in the population step, and it is read to be summed.
Nothing joins on county. There is no geography crosswalk, no county name
recoding, no per-county reconciliation, and no county output.

That is the whole difference from the earlier version of this pipeline, and it
removed about 3,000 lines.

## Layout

```
00_main.R                    the method, and the CLI. One file.
states/<GEO>.R               one per geography -- a spec plus the few
                               constants that geography measured for itself
METHOD.md                    how the build works and what it rests on
SOURCES.md                   every source, where it came from, its traps
raw/                         sources used by every geography, held once
by-state/<GEO>/raw/          that geography's own sources
raw/documentation/           PDFs behind any hand-extracted number
out/<GEO>.csv                the output
config_local.example.yaml    copy to config_local.yaml (git-ignored)
```

`by-state/GA/` and `by-state/NM/` hold raw sources for two states that are not
currently built. The files stay: they are the evidence behind numbers quoted in
`METHOD.md` and the earlier write-ups, and re-finding them costs more than the
disk does.

## Why this exists at all

NSECE — the survey that measures the child care mix — carries only Census region.
No state, no FIPS, in any of its four surveys. So the state mix cannot be
filtered out of it, and has to be rebuilt from outside. The simulator then does
the reconciling: `adjust_alpha_for_state()` solves one utility constant per care
type until the state's base-year hours match this file.

## Adding a geography

A state file is **data, not logic**. Copy the closest existing one.

1. Put the state's sources in `by-state/<GEO>/raw/`, named per `SOURCES.md`.
2. Write `states/<GEO>.R`: a `SPEC_<GEO>` list and one `assemble_providers()`
   returning `setting` and `cap_u5`.
3. Add the code to `GEOGRAPHIES` in `00_main.R`.
4. `Rscript state_data/00_main.R --geo <GEO> --check`

### The two things a geography must have

**A provider register** with a type column and a capacity column. Every state
licensing agency publishes one.

**A measured non-parental rate** — the share of children 0–4 in any non-parental
care, from a household survey carrying a state identifier. NSCH `k6q20` gives
this for all 51:

```
filter k6q20 in (1,2), sc_age_years <= 4, weight by fwc, subset fipsst
```

Without it there is no total to work against and the build has no anchor.

### Everything else improves coverage

| Declared | Buys you |
|---|---|
| `enrollment` | measured children per provider instead of a borrowed fill rate — the single biggest improvement available |
| `fill` | a fill rate per setting, the state's own if it published one |
| `home_add` | home care the register does not carry |
| `programmes` | actual programme enrolment replacing an estimate |
| `counties` | a sub-state geography, like NYC |

## Known traps

- **Registries are read all-character and coerced explicitly.** Type guesses
  vary by locale and by which rows land first.
- **Ages-served flags lie.** Check them against a programme field before
  trusting them.
- **Sites double-count.** A centre running Head Start also serves paying
  children. Programme counts are netted out of the register, not added.
- **Pick the pre-pandemic survey wave.** NSCH 2020 was fielded through the
  pandemic and its care rates collapse by 10 to 15 points.
- **`ocfs.ny.gov` blocks every non-browser client.** curl and WebFetch both
  fail; only a real browser loads it.

## The simulator wants seven rows, not six

`read_state_demand_targets()` in `src/shared_functions/adjust_alpha_for_state.R`
requires all seven care types, including centre care split into low- and
high-priced. This build writes six, because no state publishes the within-state
price dispersion that split needs.

Bridging the two is a mechanical step — divide the centre row on a national
share — and it is deliberately not part of this method.
