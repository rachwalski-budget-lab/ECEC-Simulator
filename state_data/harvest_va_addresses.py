#-----------------------------------------------------------------------------
# Harvest the street address of every facility in the VDSS child care search.
#
# Resumable: appends after each locality, and skips any already in the file.
#-----------------------------------------------------------------------------
import io, os, re, csv, sys, urllib.request, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from va_parse import parse_rows

SP = r'C:\Users\agr55\AppData\Local\Temp\claude\C--Users-agr55-Desktop-github\59e7a1bf-9320-4448-a786-6a0326677c81\scratchpad'
OUT = SP + r'\va_addresses.csv'
URL = 'https://legacy.dss.virginia.gov/facility/search/cc2.cgi'
FIELDS = ['facility_id', 'name', 'street', 'city_state_zip', 'zip', 'fips']

FIPS = "001,003,510,005,007,009,011,013,015,017,515,019,021,023,520,025,027,029,530,031,033,035,036,037,540,550,041,043,570,580,045,047,049,590,051,053,595,057,600,059,610,061,063,065,620,067,069,630,640,071,073,075,077,079,081,083,650,085,660,087,089,091,670,093,095,097,099,101,103,105,678,107,109,111,680,113,683,685,690,115,117,119,121,125,127,700,710,131,133,720,135,137,139,141,730,143,735,740,145,147,149,153,155,750,157,760,159,770,161,163,165,167,775,169,171,173,175,177,179,790,800,181,183,185,810,187,191,820,193,830,840,195,197,199".split(',')
CODES = ['2101', '2102', '2104', '2105', '2106', '2201',
         '3001', '3002', '3003', '3004']

done_fips, seen_ids = set(), set()
if os.path.exists(OUT):
    with io.open(OUT, encoding='utf-8') as fh:
        for r in csv.DictReader(fh):
            done_fips.add(r['fips'])
            seen_ids.add(r['facility_id'])
    sys.stderr.write('resuming: %d localities, %d facilities already held\n'
                     % (len(done_fips), len(seen_ids)))
else:
    with io.open(OUT, 'w', encoding='utf-8', newline='') as fh:
        csv.DictWriter(fh, fieldnames=FIELDS).writeheader()

todo = [f for f in FIPS if f not in done_fips]
sys.stderr.write('%d localities to fetch\n' % len(todo))

for n, f in enumerate(todo, 1):
    data = [('rm', 'Search'), ('search_keywords_name', ''),
            ('search_exact_fips', f), ('search_contains_zip', ''),
            ('search_modifiers_mod_cde', '')]
    data += [('search_require_client_code-' + c, '1') for c in CODES]
    req = urllib.request.Request(
        URL, data=urllib.parse.urlencode(data).encode(),
        headers={'User-Agent': 'Mozilla/5.0',
                 'Content-Type': 'application/x-www-form-urlencoded'})
    try:
        html = urllib.request.urlopen(req, timeout=120).read().decode('utf-8', 'replace')
    except Exception as e:
        sys.stderr.write('  fips %s FAILED: %s\n' % (f, e))
        continue

    rows = [r for r in parse_rows(html) if r['facility_id'] not in seen_ids]
    for r in rows:
        r['fips'] = f
        seen_ids.add(r['facility_id'])
    if rows:
        with io.open(OUT, 'a', encoding='utf-8', newline='') as fh:
            csv.DictWriter(fh, fieldnames=FIELDS).writerows(rows)
    sys.stderr.write('  %3d/%d  fips %s  +%d  (total %d)\n'
                     % (n, len(todo), f, len(rows), len(seen_ids)))
    sys.stderr.flush()

sys.stderr.write('DONE: %d facilities with an address\n' % len(seen_ids))
