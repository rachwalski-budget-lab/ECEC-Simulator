import io, re

def parse_rows(html):
    """One record per <tr> that carries a Details link."""
    out = []
    for row in re.split(r'<tr[^>]*>', html, flags=re.I)[1:]:
        row = row.split('</tr>')[0]
        m = re.search(r'rm=Details;ID=(\d+)', row)
        if not m:
            continue
        fid = m.group(1)
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.S | re.I)
        def clean(c):
            c = re.sub(r'<!--.*?-->', ' ', c, flags=re.S)
            c = re.sub(r'<br\s*/?>', '\n', c, flags=re.I)
            c = re.sub(r'<[^>]+>', ' ', c)
            c = (c.replace('&amp;', '&').replace('&#39;', "'")
                  .replace('&nbsp;', ' ').replace('&quot;', '"'))
            return [l.strip() for l in c.split('\n') if l.strip()]
        name = ' '.join(clean(cells[0])) if cells else ''
        addr = clean(cells[1]) if len(cells) > 1 else []
        street = addr[0] if addr else ''
        csz = addr[1] if len(addr) > 1 else ''
        z = re.search(r'\b(\d{5})\b', csz)
        out.append({'facility_id': fid, 'name': name, 'street': street,
                    'city_state_zip': csz, 'zip': z.group(1) if z else ''})
    return out


if __name__ == '__main__':
    SP = r'C:\Users\agr55\AppData\Local\Temp\claude\C--Users-agr55-Desktop-github\59e7a1bf-9320-4448-a786-6a0326677c81\scratchpad'
    h = io.open(SP + r'\va_search.html', encoding='utf-8', errors='replace').read()
    rows = parse_rows(h)
    print('records parsed from the Accomack page:', len(rows))
    print('with a street:', sum(1 for r in rows if r['street']))
    print('with a ZIP:   ', sum(1 for r in rows if r['zip']))
    for r in rows[:4]:
        print('  %-6s %-34s %-28s %s' % (r['facility_id'], r['name'][:34],
                                         r['street'][:28], r['zip']))
