suppressPackageStartupMessages({library(readr); library(dplyr)})
R <- 'state_data'
chr <- cols(.default = col_character())
num <- function(x) suppressWarnings(as.numeric(x))
rd  <- function(p) read_csv(p, col_types = chr, show_col_types = FALSE)

SUFFIX <- '\\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|LANE|LN|BOULEVARD|BLVD|COURT|CT|PLACE|PL|HIGHWAY|HWY|PARKWAY|PKWY|CIRCLE|CIR|TERRACE|TER|WAY|SUITE|STE|UNIT|APT)\\b'
norm <- function(x) {
  y <- toupper(ifelse(is.na(x), '', x))
  y <- gsub('[^A-Z0-9 ]', ' ', y)
  y <- gsub(SUFFIX, ' ', y)
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

hssl <- rd(file.path(R,'raw/US_HSSL__head_start_funded_slots_by_service_location__2026-09.csv'))
hssl <- hssl[hssl$status == 'Open', ]
hssl$zip5  <- substr(gsub('[^0-9]', '', hssl$zip), 1, 5)
hssl$slots <- num(hssl$funded_slots)
hssl$lat   <- num(hssl$latitude)
hssl$lon   <- num(hssl$longitude)
hssl$band  <- ifelse(hssl$program_type %in% c('1','3','5'), 'HS',
              ifelse(hssl$program_type %in% c('2','4','6'), 'EHS', 'other'))
hssl$key   <- key_of(hssl$address_line_one, hssl$zip5)

ky <- rd(file.path(R,'by-state/KY/raw/KY_CCAOA__licensed_providers_by_county__2018-09.csv'))
cat('--- sample keys ---\n')
cat('HSSL KY  :', paste(head(hssl$key[hssl$state=='KY'], 4), collapse=' | '), '\n')
kzip <- substr(gsub('[^0-9]','',ky$Location_Zip),1,5)
kk   <- key_of(ky$Location_Street1, kzip)
cat('KY reg   :', paste(head(kk, 4), collapse=' | '), '\n')
cat('KY reg keys non-NA:', sum(!is.na(kk)), 'of', length(kk), '\n')
cat('HSSL KY keys non-NA:', sum(!is.na(hssl$key[hssl$state=='KY'])), '\n')
hk <- hssl$key[hssl$state=='KY']
cat('intersect:', length(intersect(na.omit(hk), na.omit(kk))), '\n\n')

build <- function(addr, zip, lat = NULL, lon = NULL) {
  z <- substr(gsub('[^0-9]','',zip),1,5)
  list(key = unique(na.omit(key_of(addr, z))),
       lat = if (is.null(lat)) numeric(0) else lat[!is.na(lat)],
       lon = if (is.null(lon)) numeric(0) else lon[!is.na(lon)])
}
kyc <- rd(file.path(R,'by-state/KY/raw/KY_CCAOA__certified_home_providers_by_county__2018-09.csv'))
nj  <- rd(file.path(R,'by-state/NJ/raw/NJ_DCF__licensed_child_care_centers_by_county__2019-05.csv'))
ocfs<- rd(file.path(R,'by-state/NY/raw/NYS_OCFS__licensed_providers_by_county__2026-09.csv'))
doh <- rd(file.path(R,'by-state/NY/raw/NYC_DOHMH__licensed_providers_by_borough__2026-09.csv'))
NYC_B <- c('Bronx','Kings','New York','Queens','Richmond')
o_nyc <- ocfs[ocfs$county %in% NYC_B, ]

regs <- list(
  KY = build(c(ky$Location_Street1, kyc$Location_Street1),
             c(ky$Location_Zip, kyc$Location_Zip),
             c(num(ky$Latitude), num(kyc$Latitude)),
             c(num(ky$Longitude), num(kyc$Longitude))),
  NJ = build(nj$addr1, nj$zip),
  NY = build(c(paste(ocfs$street_number, ocfs$street_name), doh$address),
             c(ocfs$zip_code, doh$zipcode),
             c(num(ocfs$latitude), num(doh$latitude)),
             c(num(ocfs$longitude), num(doh$longitude))),
  NYC = build(c(paste(o_nyc$street_number, o_nyc$street_name), doh$address),
              c(o_nyc$zip_code, doh$zipcode),
              c(num(o_nyc$latitude), num(doh$latitude)),
              c(num(o_nyc$longitude), num(doh$longitude))))

ST <- c(KY='KY', NJ='NJ', NY='NY', NYC='NY')
NYC_HSSL <- c('Bronx County','Kings County','New York County','Queens County','Richmond County')
TOL <- 25
dist_m <- function(lat1, lon1, lat2, lon2) {
  r <- 6371000; p <- pi/180
  a <- sin((lat2-lat1)*p/2)^2 + cos(lat1*p)*cos(lat2*p)*sin((lon2-lon1)*p/2)^2
  2*r*asin(pmin(1, sqrt(a)))
}

out <- NULL
for (g in names(regs)) {
  h <- hssl[hssl$state == ST[[g]] & hssl$band %in% c('HS','EHS'), ]
  if (g == 'NYC') h <- h[h$county %in% NYC_HSSL, ]
  rg <- regs[[g]]
  m_addr <- !is.na(h$key) & h$key %in% rg$key
  m_xy <- logical(nrow(h))
  if (length(rg$lat) > 0) {
    for (i in seq_len(nrow(h))) {
      if (is.na(h$lat[i]) || is.na(h$lon[i])) next
      m_xy[i] <- any(dist_m(h$lat[i], h$lon[i], rg$lat, rg$lon) <= TOL, na.rm = TRUE)
    }
  }
  m_any <- m_addr | m_xy
  for (bd in c('HS','EHS')) {
    s <- h$band == bd
    out <- rbind(out, data.frame(geo = g, band = bd,
      locs = sum(s), slots = sum(h$slots[s], na.rm = TRUE),
      pct_addr = round(100*sum(h$slots[s & m_addr], na.rm=TRUE)/sum(h$slots[s], na.rm=TRUE), 1),
      pct_xy   = round(100*sum(h$slots[s & m_xy],   na.rm=TRUE)/sum(h$slots[s], na.rm=TRUE), 1),
      pct_any  = round(100*sum(h$slots[s & m_any],  na.rm=TRUE)/sum(h$slots[s], na.rm=TRUE), 1),
      loc_any  = round(100*mean(m_any[s]), 1)))
  }
}
cat('=== share of open Head Start funded slots at an address the register holds ===\n\n')
print(out, row.names = FALSE)
write.csv(out, file.path(Sys.getenv('SP'), 'overlap_measured.csv'), row.names = FALSE)
