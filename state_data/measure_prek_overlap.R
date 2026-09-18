#-----------------------------------------------------------------------------
# How much of public-school pre-K sits at an address the child care register
# also holds?
#
# Same method as the Head Start match: CCD school-level pre-K membership,
# geocoded by NCES EDGE, matched to each register on address and coordinates.
#-----------------------------------------------------------------------------
suppressPackageStartupMessages({library(dplyr); library(readr)})
SP <- Sys.getenv('SP'); R <- 'state_data'
chr <- cols(.default = col_character())
num <- function(x) suppressWarnings(as.numeric(x))
rd  <- function(p) read_csv(p, col_types = chr, show_col_types = FALSE)

pk <- rd(file.path(SP, 'ccd_pk.csv')) %>%
  transmute(ncessch = NCESSCH, st = ST, pk = num(STUDENT_COUNT)) %>%
  filter(!is.na(pk), pk > 0)
cat('schools with pre-K:', nrow(pk), '\n')
cat('CCD totals by state:\n')
print(pk %>% group_by(st) %>% summarise(schools = n(), children = sum(pk)))
cat('\nthe build uses: KY 28,465  NJ 41,305  NY 54,451  VA 33,790\n\n')

edge <- rd(file.path(SP, 'edge_4states.csv')) %>%
  transmute(ncessch = NCESSCH, addr = STREET, zip = ZIP,
            lat = num(LAT), lon = num(LON))

d <- inner_join(pk, edge, by = 'ncessch')
cat('pre-K schools geocoded:', nrow(d), 'of', nrow(pk),
    sprintf('(%.1f%% of children)\n\n', 100*sum(d$pk)/sum(pk$pk)))

SUFFIX <- '\\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|LANE|LN|BOULEVARD|BLVD|COURT|CT|PLACE|PL|HIGHWAY|HWY|PARKWAY|PKWY|CIRCLE|CIR|TERRACE|TER|WAY|SUITE|STE|UNIT|APT)\\b'
norm <- function(x) {
  y <- toupper(ifelse(is.na(x), '', x))
  y <- gsub('[^A-Z0-9 ]', ' ', y); y <- gsub(SUFFIX, ' ', y)
  gsub(' +', ' ', trimws(y))
}
key_of <- function(addr, zip5) {
  a <- norm(addr)
  nm <- sub('^([0-9]+).*$', '\\1', a); nm[!grepl('^[0-9]+$', nm)] <- NA
  w  <- sub('^[0-9]+ *', '', a); w <- sub('^([A-Z0-9]+).*$', '\\1', w)
  out <- paste(zip5, nm, w)
  out[is.na(nm) | w == '' | is.na(zip5) | zip5 == ''] <- NA
  out
}
dist_m <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000; p <- pi/180
  a <- sin((lat2-lat1)*p/2)^2 + cos(lat1*p)*cos(lat2*p)*sin((lon2-lon1)*p/2)^2
  2*r*asin(pmin(1, sqrt(a)))
}

ky <- bind_rows(
  rd(file.path(R,'by-state/KY/raw/KY_CCAOA__licensed_providers_by_county__2018-09.csv')) %>%
    transmute(addr=Location_Street1, zip=Location_Zip, lat=num(Latitude), lon=num(Longitude)),
  rd(file.path(R,'by-state/KY/raw/KY_CCAOA__certified_home_providers_by_county__2018-09.csv')) %>%
    transmute(addr=Location_Street1, zip=Location_Zip, lat=num(Latitude), lon=num(Longitude)))
nj <- rd(file.path(R,'by-state/NJ/raw/NJ_DCF__licensed_child_care_centers_by_county__2019-05.csv')) %>%
  transmute(addr=addr1, zip=zip, lat=NA_real_, lon=NA_real_)
ocfs <- rd(file.path(R,'by-state/NY/raw/NYS_OCFS__licensed_providers_by_county__2026-09.csv')) %>%
  transmute(addr=paste(street_number, street_name), zip=zip_code,
            lat=num(latitude), lon=num(longitude), county=county)
doh <- rd(file.path(R,'by-state/NY/raw/NYC_DOHMH__licensed_providers_by_borough__2026-09.csv')) %>%
  transmute(addr=address, zip=zipcode, lat=num(latitude), lon=num(longitude),
            county=NA_character_)
NYC_B <- c('Bronx','Kings','New York','Queens','Richmond')
va <- tibble(addr=character(0), zip=character(0), lat=numeric(0), lon=numeric(0))

regs <- list(
  KY = ky, NJ = nj,
  NY  = bind_rows(ocfs, doh) %>% select(addr, zip, lat, lon),
  NYC = bind_rows(filter(ocfs, county %in% NYC_B), doh) %>% select(addr, zip, lat, lon),
  VA  = va)

# NYC pre-K schools: the five borough counties, by NCESSCH county via EDGE CNTY
edge_cnty <- rd(file.path(SP, 'edge_4states.csv')) %>%
  transmute(ncessch = NCESSCH, cnty = CNTY)
NYC_FIPS <- c('36005','36047','36061','36081','36085')

ST_OF <- c(KY='KY', NJ='NJ', NY='NY', NYC='NY', VA='VA')
TOL <- 25

out <- NULL
for (g in names(regs)) {
  h <- d[d$st == ST_OF[[g]], ]
  if (g == 'NYC') {
    h <- left_join(h, edge_cnty, by = 'ncessch')
    h <- h[!is.na(h$cnty) & h$cnty %in% NYC_FIPS, ]
  }
  rg <- regs[[g]]
  if (nrow(rg) == 0) {
    out <- rbind(out, data.frame(geo=g, schools=nrow(h), children=sum(h$pk),
      pct_addr=NA, pct_xy=NA, pct_any=NA)); next
  }
  rz <- substr(gsub('[^0-9]','',rg$zip),1,5)
  rkey <- unique(na.omit(key_of(rg$addr, rz)))
  rxy <- rg[!is.na(rg$lat) & !is.na(rg$lon), ]

  hkey <- key_of(h$addr, substr(gsub('[^0-9]','',h$zip),1,5))
  m_addr <- !is.na(hkey) & hkey %in% rkey
  m_xy <- logical(nrow(h))
  if (nrow(rxy) > 0) {
    for (i in seq_len(nrow(h))) {
      if (is.na(h$lat[i]) || is.na(h$lon[i])) next
      m_xy[i] <- any(dist_m(h$lat[i], h$lon[i], rxy$lat, rxy$lon) <= TOL, na.rm = TRUE)
    }
  }
  m_any <- m_addr | m_xy
  tot <- sum(h$pk)
  out <- rbind(out, data.frame(geo=g, schools=nrow(h), children=tot,
    pct_addr = round(100*sum(h$pk[m_addr])/tot, 1),
    pct_xy   = round(100*sum(h$pk[m_xy])/tot, 1),
    pct_any  = round(100*sum(h$pk[m_any])/tot, 1)))
}
cat('=== share of public-school pre-K children at an address the register holds ===\n\n')
print(out, row.names = FALSE)
write.csv(out, file.path(SP, 'prek_overlap.csv'), row.names = FALSE)
