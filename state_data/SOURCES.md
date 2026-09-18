# Source acquisition

Builders never download. Every file below is fetched by hand and recorded here,
so a build is reproducible offline and a stale file is visible rather than
silently refreshed underneath a result.

## File naming

```
raw/                  US_<SOURCE_KEY>__<content>__<vintage>.<ext>
by-state/<ST>/raw/    <ST>_<SOURCE_KEY>__<content>__<vintage>.<ext>
```

Sources used by every state live in the top-level `raw/` and are held once. A
state's own files sit in its `raw/` folder, beside the `scripts/` that read them
and the `out/` they produce. Reports and codebooks go one level down in
`raw/documentation/` — the audit counts them as held but they are not data.

- `SOURCE_KEY` matches the `key` column in `SOURCES_<ST>` / `SOURCE_KEYS`
- `content` is lowercase snake_case
- **`vintage` is the year the DATA describes, never the download date** — ISO
  where a month matters, a school year as `2018-19`
- double underscores separate the three fields so the name parses back apart

Rename downloads on arrival. The file DECAL hands you is
`ProviderData_20260831200738.csv` — it encodes the one date that doesn't matter
and drops the state and source entirely. Across 51 states and several agencies
that each name things their own way, that doesn't survive.

Check what's present against what a state declares:

```bash
Rscript state_data/00_main.R --all --check        # build and check

```

`find_raw()` resolves files by `(source_key, content)` and errors if two
vintages of one source are held — silently taking the newest is wrong here,
since the right wave is usually the one nearest the 2019 base year. Pin one
with the optional `vintage` column in a spec's `raw` table. **Georgia needs
this**: it holds NDCP 2016 and 2018, and without the pin the Low/High split
falls back to the national ratio with only a passing message to say so.

Files that do not parse as `<SCOPE>_<SOURCE_KEY>__<content>__<vintage>` are
listed by `--audit` and otherwise ignored. Sources checked and rejected go in
`raw/documentation/`, which keeps the evidence without cluttering the audit —
New York's 47 monthly snapshots and survey PDFs sit there.

Base year is **2019**. Where a source's nearest vintage differs, that's noted —
carry it explicitly in the builder rather than treating it as 2019.

## Two roles a source can have

Each `SOURCES_<ST>` row declares a `role` and what it `feeds`, and `--audit`
reports them separately:

- **`file`** — read by the builder through a raw slot. Required on disk; a
  missing one fails the audit.
- **`constant`** — read by hand once, its value baked into a named constant in
  the state's spec. No code opens it, so the audit does not require it. The
  file is kept in `data/` for provenance where it is state-specific; NSCH is
  shared across all 51 and lives in the top-level `raw/`.

**A source checked and not used belongs in neither.** It goes in the
"evaluated and not used" list below, so nobody researches it twice.

## The shape of the problem

No source, at any geography, reports the simulator's seven NSECE-native
categories. Established by inspection:

- **NSECE** public-use (ICPSR 37941) has only Census region and urban density.
  No state, no FIPS, in any of the four surveys.
- **SIPP** 2014–2023 has `TST_INTV` (state) but its childcare variables
  (`EDAYCARE`, `EHEADST`, `TDPCAREAMT`) are binary program-receipt flags. No
  arrangement-type battery in any panel.
- **NSCH** has `FIPSST`, and `K6Q20` asks whether the child receives ≥10 hrs/wk
  of non-parental care — enumerating every arrangement type in the prompt and
  never asking which one. State-representative, so no sub-state use.
- **NHES ECPP** is the only survey that natively splits relative / nonrelative /
  center-based care. Public-use has no state; restricted geocode files exist for
  2016, 2019 unconfirmed.

So the informal categories — **Other Unpaid (13.0% of children 0–4), Other Paid
(7.7%), Unpaid Home-Based (0.75%)** — cannot be sourced from administrative
data at all: unlicensed relative and nanny care appears in no registry by
construction. Together that's ~43% of all non-parental care. Those categories
inherit the national NSECE mix via `fill_from_national()`, and every build
reports what share of each category is anchored versus inherited.

## Uniform across all 51

**In use:**

Four sources are the same everywhere, and all four are held **once** in the
top-level `raw/`. Every one of them is a single national file, so a per-state
copy would be 4 x 51 files of the same data.

| Key | Role | Held in | Source | Geography | Vintage | Feeds |
|---|---|---|---|---|---|---|
| `PEP` | file | `raw/` | Census Population Estimates, county by age | **county** | 2019 | children 0–4 denominator |
| `NDCP` | file | `raw/` | DOL National Database of Childcare Prices | **county** | 2008–2018 | Low/High centre split |
| `NONEMP` | file | `raw/` | Census Nonemployer Statistics, NAICS 6244 | **county** | 2019 | unlicensed home providers |
| `NSCH` | constant | `raw/` | National Survey of Children's Health | state | 2019 | `nonparental_rate` |

A spec declares `scope = 'US'` on the slot and the builder cuts the national
table to that state's FIPS — `pep_county_children_0_4()`,
`nonemp_county_establishments()` and `ndcp_state_prices()` in `00_main.R`, each
caching its parse per session so `--all` across 51 states reads each file once.

`NSCH` is the one source no state can do without: `k6q20` gives the share of
children 0–4 in any non-parental care, and without it there is no total to
residualise against. It is a plain download covering all 51, so it is held once
in the top-level `raw/` rather than copied per state. State cells run ~100–250 records —
record `n`, and note the uncertainty.

`NONEMP` counts sole proprietors in child day care, netted against the state's
licensed homes. It is what keeps Paid Home-Based from being understated roughly
tenfold in states that license home care only above a child threshold.

**The 2 children per unlicensed provider is Georgia's number, and Georgia is
now the only state that uses it.** It comes from the GA Market Rate Survey 2016
informal-provider rows, n = 164, measured against *Georgia's* licensing
threshold of three or more unrelated children. It does not transfer: New York
registers family day care at three to six, a different threshold and so a
different below-threshold population, and neither NY nor NM publishes a
children-per-provider count at all.

NY and NM therefore declare **no `unlicensed` slot**. Their Paid Home-Based
covers licensed home capacity only, and unlicensed home care falls into the
national residual — understated by construction rather than anchored on another
state's parameter. What that cost, measured 2026-09-02:

| | Paid Home-Based, annual hours | Anchored share |
|---|---|---|
| GA | unchanged (measured its own 2) | 59% → 59% |
| NY | 369.2M → 205.3M (−44%) | 66% → **53%** |
| NM | 9.7M → 3.9M (−59%) | 79% → **75%** |

`NONEMP` consequently feeds only Georgia. It stays in the shared `raw/` because
it is a national file, and GA reads it.

**A state-level signal for Other Paid does exist, contrary to what this file
said earlier.** CCDF FY2019 Data Table 3 (ACF Office of Child Care) publishes
the share of subsidised children by setting, per state, with a **Child's Home**
column — care in the child's own home. NY 11%, NM 1%.
<https://acf.gov/occ/data/fy-2019-preliminary-data-table-3>

**Table 3 is superseded by Table 6, and two of the objections above were
wrong.** Reviewed 2026-09-03 across the whole FY2019 series. Table 6 crosses
setting (child's home / family home / group home / centre) with regulated vs
legally operating without regulation, and within the unregulated cells with
relative vs non-relative — the model's own axis, since Paid Home-Based is
home-based with no prior relationship and Other Paid is in-home care by someone
with one. Table 1 supplies average monthly children served, so the series does
give **levels**, not only percentages; and Table 6 covers the whole unanchored
home/relative group at once, so it would not have mixed one state weight with
two national ones. Both of those were stated as blockers here earlier and are
not.

Two objections do survive, and they are why this is a floor and not an anchor.
**Selection:** subsidised children are of the order of 7% of children 0–4,
selected on income eligibility and on having applied, and subsidy rules pay
relatives, so relative and in-home care is over-represented by construction.
**The paid/unpaid line does not survive the mapping:** the model splits on
positive out-of-pocket cost, i.e. the family copay, and nothing in the series
reports copay by setting (Table 15 is average subsidy paid to the *provider*),
so these cells cannot be divided between Other Paid and Other Unpaid. Georgia's
row also remains unusable at 2 of 12 months and 48% Invalid/Not Reported.

**Adopted as a floor. Measured 2026-09-03: it does not bind.** Table 1 ×
Table 9 (age distribution) × Table 6 gives subsidised children 0–4 per cell. NY:
89,400 served, 54% aged 0–4, 26% unregulated → ~12,600 children 0–4, ~8,690 of
them in home settings. Table 5 counts unregulated children directly, excluding
unregulated centres — 16,104 all ages × 54% = 8,696, agreeing with the 8,690 to
six children by an independent route. Against that, NY's build assigns ~205,000
children 0–4 to the three unanchored types (74,029 Other Paid, 123,991 Other
Unpaid, 7,182 Unpaid Home-Based, converted from annual hours at the NSECE
ft/pt mix within each type). The floor clears 23.6×. It rules out a
catastrophic understatement and nothing finer — in particular it cannot see the
44% Paid Home-Based cut from dropping Georgia's 2-children parameter. NM's
floor is ~108 children, too low to bind.

**`acf.gov` filters on User-Agent, not on being a browser** — an earlier note
here said 403 to every non-browser client, which is wrong. A Chrome UA string
returns 200 from `curl`; the default client UA returns 403. All seven tables
used or evaluated (1, 3, 4, 5, 6, 9, 14) are archived as TSV with provenance
headers under `raw/documentation/`, named
`US_CCDF__preliminary_data_table_<n>_<content>__2019.tsv`.

**Table 14 (hours by age × setting) is national only** — no state rows — so it
cannot inform a per-state full/part-time split. That split stays national.

**How `NDCP_NATIONAL_MEDIAN_HOURLY_2016 = 3.1235` was computed.** NDCP 2016
extract, 2,641 counties in 43 states. Pool all three centre-age columns into
ONE vector of 7,923 weekly prices and take its median: $124.94/wk ÷ 40 =
$3.1235/hr. Reproduced from the held extract 2026-09-02. Age-specific medians ÷
40: infant 3.4167, toddler 3.0938, preschool 2.9173. Note the threshold is a
median of pooled price *observations* while what it is compared against is each
county's *mean* of three ages; median of county means is $125.42/wk → 3.1355,
0.38% higher, which flips zero counties in GA (2.2917–4.1250) or NY
(4.7100–8.3547). Recheck for any state whose counties land near $3.13.

**One NDCP table serves every state.** `raw/` holds the DOL workbook and a
six-column extract of it; each state's spec points its `prices` slot at that
extract with `scope = 'US'` and pins the wave it actually has data in. There is
no per-state price file and no per-state price script.

The workbook has 227 columns and cannot be parsed on a login node — readxl
decompresses the whole sheet and gets OOM-killed (exit 137) even reading only
the header — which is why the extract exists.

Coverage varies sharply. `NDCP` covers 2,641 counties in 43 states for 2016;
**Georgia has prices in 2016 only**, New York uses 2018, and **New Mexico and
Indiana are absent for every year** and so declare no `prices` slot at all.

A useful side effect: NDCP gave Georgia exactly three distinct price levels, and
the 14 counties at the top level are Camden plus greater metro Atlanta — which is
Georgia's market rate Zone 1 as its survey defines it. NDCP evidently sourced the
state's prices from that zone-based survey, so a zone crosswalk published only as
a map image is recoverable from NDCP price levels.

`PEP` is used rather than the ACS API because it needs no key and is a plain
download. Georgia: 656,566 children 0–4, against a 662,675 validation target of
2014 vintage — 0.9% apart.

The download is `cc-est2019-alldata.csv`, county characteristics 2010–2019: 80
columns, every county x YEAR x AGEGRP cell. Cut on arrival to `AGEGRP == 1`
(ages 0–4) and `YEAR == 12` (the 7/1/2019 estimate), keeping `STATE`, `COUNTY`,
`STNAME`, `CTYNAME`, `TOT_POP` — **3,142 counties, one row each, all 51**. The
Census file is Latin-1 and the extract is stored UTF-8, so Doña Ana keeps its
tilde; NM's `geo_recode` matches its registry side to that.

`CTYNAME` carries the legal suffix ("Appling County"); registries write the bare
name, so `strip_county_suffix()` removes it. Get this wrong and every county
silently fails to join.

`NONEMP` comes from the API rather than a download —
`api.census.gov/data/2019/nonemp?get=NAME,NESTAB&NAICS2017=6244&for=county:*`,
key from `~/.Renviron`. **3,038 rows, not 3,142**: a county with no NAICS 6244
establishment is ABSENT rather than zero — 29 of New Mexico's 33 counties, 158
of Georgia's 159. The join runs against population and drops what does not
match, so an absent county contributes nothing, which is the right answer.

**Held and not yet wired** — on disk in `raw/`, named per the convention, no
slot reads them yet. Recorded here so the acquisition work is not repeated and
so the derivation is reproducible.

| Key | Content | Geography | Vintage | Rows | Would feed |
|---|---|---|---|---|---|
| `CCD` | `public_school_prekindergarten_children_by_county` | **county** | 2018-19 | 3,003 | Unpaid Center-Based, county-measured |
| `CCD` | `public_school_county_geocode_crosswalk` | school | 2018-19 | 102,175 | school → county for any school-level source |
| `HSSL` | `head_start_funded_slots_by_service_location` | site | 2026-09 | 19,645 | Head Start county shares |

**`CCD` — NCES Common Core of Data, public-school pre-K by county.** Genuinely
2018-19, and the only county-resolved pre-K count reachable for the base year.
Derived from two downloads, neither of which is kept — both are stable URLs and
the source membership file is 2.5 GB as CSV:

1. `ccd_sch_052_1819_l_1a_091019.zip` from
   `https://nces.ed.gov/ccd/Data/zip/` — 177 MB compressed, one row per school ×
   grade × race × sex, **11,948,167 rows**. Streamed rather than unzipped.
2. Pre-K rows are `GRADE == 'Pre-Kindergarten'` **and
   `TOTAL_INDICATOR == 'Subtotal 4 - By Grade'`**. The obvious-looking
   `'Education Unit Total'` is wrong — those rows carry
   `GRADE == 'No Category Codes'` and return zero for every state.
3. `EDGE_GEOCODE_PUBLICSCH_1819.zip` from
   `https://nces.ed.gov/programs/edge/data/` supplies school → county. Its
   `.TXT` member is pipe-delimited with **no header row**, so fields are
   positional (0 `NCESSCH`, 6 state, 9 county FIPS, 10 county name), and it is
   **UTF-8** — the opposite convention from the Latin-1 PEP file.
4. The join is complete: 102,175 schools geocoded, **zero unmatched** in GA, NY
   and NM, every county covered. Counts are children, not records:

```
       pre-K children   schools reporting   counties matched
  GA   49,315           1,109               159 of 159
  NY   54,451           4,794                62 of 62
  NM   10,174             281                33 of 33
```

Two things that fall out of those numbers:

- **NY validates the existing model.** `NY.R` derives 55,016 public-school
  pre-K children from NIEER's level × NYSED's setting share, then spreads them
  by child population. CCD measures 54,451 — **1.0% apart** — and carries the
  county distribution.
- **NM contradicts an assumption.** `NM.R` anchors 5,626, from the market rate
  survey's 50/50 public/community split of NIEER's 11,251. CCD measures 10,174
  in public schools — **1.81×**. Either the 50/50 split understates the
  public-school share or CCD's pre-K spans a wider universe (3-year-olds,
  4410 preschool special education) than NIEER's state pre-K count. Unresolved,
  and until it is, NM's Unpaid Center-Based anchor is the least settled number
  in the three builds.
- **GA must not add it.** Georgia Pre-K runs heavily through private centres the
  registry already captures via `Funded_PreK_Slots`. CCD's 49,315 is
  public-school delivery only, so it is a subset — useful as a cross-check on
  the `LSS` portion, not as an addition.

**`HSSL` — Head Start service locations.** Every row carries `county` and
`funded_slots` at site level, plus program type, latitude, longitude and open /
closed status. That is the county resolution Head Start has been missing in all
three builds, where it currently enters as a statewide NIEER total allocated by
child population.

- Download: `https://s3foa.s3.us-east-1.amazonaws.com/HS_Service_Locations.csv`.
  `headstart.gov` itself returns **403 to every non-browser client**, so the S3
  link had to be recovered from a real browser; the link then works anywhere.
- **Use it for shares, not for the level.** The file is updated daily, so its
  vintage is current, and its slot totals run 22–28% below NIEER's 2018-19
  enrolment. Keep the NIEER level, distribute by each county's share of open
  funded slots — the same 2019-level / current-vintage-mix pattern the rest of
  the pipeline uses.
- Filtering to `status == 'Open'`: GA 291 sites / 14,252 slots / 122 counties;
  NY 713 / 28,899 / 60; NM 177 / 4,798 / 23. Against the NIEER levels in use:
  GA 19,842, NY 36,863 (not anchored), NM 7,427.
- **Traps.** 2,059 rows are `status == 'Not Reported'` and 844 are `'Closed'`;
  including them moves the totals materially. `county` carries the legal suffix,
  so `strip_county_suffix()` applies, and the file writes "Dona Ana County" with
  the tilde flattened, so NM's `geo_recode` applies to this source too.
- For NY specifically the latitude and longitude make the open double-count
  question checkable: NY Head Start centres commonly hold OCFS licences and may
  already sit inside `DCC` capacity, which is why NY's 36,863 is unanchored.

**Two more that would help and are not on disk.**

- **NSECE 2019 Level-1 restricted-use files** (ICPSR 38445). The NSECE ships in
  five tiers; the two public tiers stop at Census region, and Level 1 adds the
  geography plus the variables recoded or dropped from the public file. This is
  the only route to Other Unpaid, Other Paid and Unpaid Home-Based — the ~43% of
  non-parental care at 0% anchored everywhere — computed from the instrument the
  simulator is already calibrated on. Needs a Restricted Data Use Agreement plus
  IRB approval or an exemption notice; a Virtual Data Enclave route exists.
  Weeks of lead time, so start it before it is needed.
- **NSCH 2018 and 2020 waves.** DOWNLOADED AND TESTED, AND THE POOL WAS
  REJECTED. Both now sit in `raw/` beside the 2019 file. Pooling three waves
  would cut each state's `nonparental_rate` error by 40-47%, and it is the one
  pool that centres exactly on 2019. It fails on content: NSCH 2020 was fielded
  through the pandemic and the rates collapse -- KY 45.8%, NJ 42.6%, VA 46.7%,
  against 57-62% in the two years either side. Pooling 2018+2019 alone centres
  on mid-2018 while every other input is pinned to 2019. The waves are held so
  the rejection is reproducible, not so the pool can be used.

**Within-county price dispersion needs no download.** The Low/High split is a
step function — each county lands entirely on one side of the NDCP national
median — and NDCP cannot fix it, publishing one price per county. The state
market rate surveys can, and all three are already in
`by-state/*/raw/documentation/`: each reports rates at both the median and the
75th percentile by region, type, age band and full- vs part-time. Two points of
one distribution identify a lognormal spread, which gives the share of a
county's centres above the national median instead of a zero-or-one indicator.
New Mexico gains twice, since its survey's metro / rural regions are its only
price signal at all.

**Added and wired in, September 2026.** Two national county files now feed the
builds through the optional `allocator` column on `statewide_add`, which names
a raw slot carrying measured county counts instead of falling back to child
population.

| Key | Role | Agency | Geography | Vintage | Feeds |
|---|---|---|---|---|---|
| `CCD` | file | U.S. Dept of Education, NCES | **county** | 2018-19 | `prek` — NY and NM pre-K level and distribution |
| `HSSL` | file | HHS ACF, Office of Head Start | **county** | 2026-09 | `hs_slots` — Head Start county shares, all three states |

`CCD` is Common Core of Data school-level pre-K membership joined to county via
the NCES EDGE geocode file: keep grade `Pre-Kindergarten` and total indicator
`Subtotal 4 - By Grade`, then join `NCESSCH` to county FIPS. 3,003 counties
nationally, zero schools unmatched in GA/NY/NM. Genuinely 2018-19.

`HSSL` is the Office of Head Start service-location file, filtered to **open**
locations — 2,059 of 19,645 rows carry `Not Reported` and 844 are `Closed`, and
including them moves totals materially. Current vintage, so it supplies county
**shares** only; the level stays NIEER 2018-19.

Effect on the anchored share: GA 59% → 59% (reallocation only), NY 61% → 66%
(Head Start anchored for the first time), NM 75% → 79% (pre-K 5,626 → 10,174).
Counties scaled back at the 95% ceiling rose from 0/2/2 to 8/5/9 — worth
treating as a diagnostic, especially for NM.

Two things the wire-in did **not** settle: NY Head Start may double-count
against OCFS-licensed centres already in the converted capacity, so NY's Unpaid
Center-Based is an upper bound; and NM's CCD pre-K is 1.81× the previous
figure, which is either a bad 50/50 split in the NM MRS or a wider CCD grade
definition. Georgia deliberately does not use `CCD`, since its funded pre-K
slots already capture private-centre delivery.

**Evaluated and not used** — recorded so nobody researches them twice. None are
held on disk.

*Nationally:* Head Start PIR reports cumulative rather than point-in-time
enrolment; NIEER and NCES CCD are state/district and overlap PIR where Head
Start is state-blended; CCDF-801 covers only subsidised children — but see the CCDF note below, which
corrects an earlier overstatement; OEWS is supply-side, out of scope while
supply stays national; NHES ECPP splits
arrangement types natively but its public file carries no state; SIPP's
childcare variables across all panels 2014–2023 are binary program-receipt
flags, not arrangement types. Note NSCH is used only for its rate — `k6q20`
enumerates every arrangement type in the question and never asks which one, so
it cannot supply a care mix.

*Per state:*

- **GA** — the 2021 and 2023 market rate waves (pandemic-era enrolment,
  sensitivity only); PDG B-5 Report 5 (statewide validation); County Business
  Patterns (superseded by Nonemployer, which counts sole proprietors); NDCP
  2018 (no Georgia prices in it).
- **NY** — the market rate survey, all three waves. It asks enrolment in
  Appendix 1 Q1 and publishes only rates. Also checked and rejected: 40 monthly
  `LR-Provider-Snapshot` files, KWIC, the DOL Tableau dashboard, Cornell's
  Buffalo Co-Lab republication, and County Business Patterns.
- **NM** — the 2025 LFC accountability report (no county detail beyond what
  the childcare brief carries); County Business Patterns; the UNM CCPI FY19
  Tableau, whose host no longer resolves from any network tried.

## Per state

Removed for now. The per-state source tables described the earlier county
build, including two states that are no longer built, and had drifted from
what is on disk.

Each geography's own sources are declared in its `states/<GEO>.R`, next to the
code that reads them, and the constants that geography measured for itself are
documented there with their derivation.

## Removed when the build moved to the state level

These were read by the county build and are read by nothing now. They are
recorded here so they can be fetched again rather than re-found.

| File | Why it went | Where it came from |
|---|---|---|
| `US_NDCP__center_prices_ages_0_4_by_county_extract__2008-2022.csv` | the Low/High price split was dropped; a state publishes one price | DOL Women's Bureau, National Database of Childcare Prices |
| `US_NDCP__national_median_hourly_center_price__2016.csv` | same | derived from the workbook above |
| `US_NONEMP__nonemployer_childcare_businesses_by_county__2019.csv` | never used. Converting a business count to a child count needs a children-per-provider figure no state here publishes | Census API, `2019/nonemp`, NAICS2017 6244 |
| `US_CCD__public_school_county_geocode_crosswalk__2018-19.csv` | school to county only, no addresses, so it cannot support an address match | NCES EDGE |
| `by-state/GA/`, `by-state/NM/` | neither state is built | see the state files in the county build's history |

The two NSCH waves either side of 2019 are NOT in this table. They stay, so the
pooling test that rejected them can be repeated.

## Added for the programme-overlap match

| File | What it is | Where it came from |
|---|---|---|
| `US_EDGE__public_school_geocodes__2018-19.csv` | street, ZIP and coordinates for every public school in KY, NJ, NY and VA — 11,169 rows, cut from a 63MB national SAS file | NCES EDGE, `EDGE_GEOCODE_PUBLICSCH_1819.zip` |
| `US_CCD__public_school_prekindergarten_children_by_school__2018-19.csv` | pre-K membership school by school, 7,292 rows, cut from a 2.5GB national file on `GRADE = Pre-Kindergarten` and `TOTAL_INDICATOR = Subtotal 4 - By Grade` | NCES CCD, `ccd_sch_052_1819_l_1a_091019.zip` |

Both are extracts, not the source files, which are far too large to hold. The
school-level pre-K counts sum to exactly the county totals already held, which
is what makes the extract safe to trust.
