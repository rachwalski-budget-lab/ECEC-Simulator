#-----------------------------------------------------------------------------
# Virginia's programme overlap, measured.
#
# VDSS publishes no address in its bulk register, which is why VA alone took
# the mean of the other four. Its search tool does publish one, so addresses
# are harvested separately and joined on facility_id here.
#
# Aggregation in base R on purpose: sum(x[flag]) inside dplyr::summarise()
# silently returns 0 or the whole column.
#-----------------------------------------------------------------------------
suppressPackageStartupMessages({library(dplyr); library(readr)})
SP <- Sys.getenv('SP'); R <- 'state_data'
chr <- cols(.default = col_character())
num <- function(x) suppressWarnings(as.numeric(x))
rd  <- function(p) read_csv(p, col_types = chr, show_col_types = FALSE)

SUFFIX <- '\\b(STREET|ST|AVENUE|AVE|ROAD|RD|DRIVE|DR|LANE|LN|BOULEVARD|BLVD|COURT|CT|PLACE|PL|HIGHWAY|HWY|PARKWAY|PKWY|CIRCLE|CIR|TERRACE|TER|WAY|SUITE|STE|UNIT|APT)\\b'
norm <- function(x) {
  y <- toupper(ifelse(is.na(x), '', x))
  y <- gsub('[^A-Z0-9 ]', ' ', y); y <- gsub(SUFFIX, ' ', y)
  gsub(' +', ' ', trimws(y))
}
key_of <- function(a, z) {
  s <- norm(a)
  nm <- sub('^([0-9]+).*$', '\\1', s); nm[!grepl('^[0-9]+$', nm)] <- NA
  w  <- sub('^[0-9]+ *', '', s); w <- sub('^([A-Z0-9]+).*$', '\\1', w)
  out <- paste(z, nm, w)
  out[is.na(nm) | w == '' | is.na(z) | z == ''] <- NA
  out
}

addr <- rd(file.path(SP, 'va_addresses.csv'))
reg  <- rd(file.path(R, 'by-state/VA/raw/VA_VDSS__licensed_providers_by_locality__2026-09.csv'))
j <- inner_join(reg[, 'facility_id'], addr, by = 'facility_id')
cat(sprintf('VA register %d rows; %d carry a harvested address (%.1f%%)\n',
            nrow(reg), nrow(j), 100*nrow(j)/nrow(reg)))
cat('localities harvested:', length(unique(addr$fips)), 'of 134\n\n')
reg_keys <- unique(na.omit(key_of(j$street, j$zip)))

## ---- Head Start and Early Head Start --------------------------------------
h <- rd(file.path(R, 'raw/US_HSSL__head_start_funded_slots_by_service_location__2026-09.csv'))
h <- h[h$status == 'Open' & h$state == 'VA', ]
h$slots <- num(h$funded_slots)
h$band  <- ifelse(h$program_type %in% c('1','3','5'), 'HS',
           ifelse(h$program_type %in% c('2','4','6'), 'EHS', 'other'))
h <- h[h$band %in% c('HS','EHS'), ]
h$key <- key_of(h$address_line_one, substr(gsub('[^0-9]','',h$zip),1,5))
h$m   <- !is.na(h$key) & h$key %in% reg_keys

## ---- public-school pre-K ---------------------------------------------------
pk <- rd(file.path(R, 'raw/US_CCD__public_school_prekindergarten_children_by_school__2018-19.csv'))
pk <- pk[pk$ST == 'VA', ]
pk$pk <- num(pk$STUDENT_COUNT)
pk <- pk[!is.na(pk$pk) & pk$pk > 0, ]
edge <- rd(file.path(R, 'raw/US_EDGE__public_school_geocodes__2018-19.csv'))
p <- merge(pk[, c('NCESSCH','pk')], edge[, c('NCESSCH','STREET','ZIP')],
           by = 'NCESSCH')
p$key <- key_of(p$STREET, p$ZIP)
p$m   <- !is.na(p$key) & p$key %in% reg_keys

out <- data.frame(
  programme = c('public pre-K', 'Head Start', 'Early Head Start'),
  units = c(nrow(p), sum(h$band=='HS'), sum(h$band=='EHS')),
  children = c(sum(p$pk),
               sum(h$slots[h$band=='HS'], na.rm=TRUE),
               sum(h$slots[h$band=='EHS'], na.rm=TRUE)),
  matched = c(sum(p$pk[p$m]),
              sum(h$slots[h$band=='HS'  & h$m], na.rm=TRUE),
              sum(h$slots[h$band=='EHS' & h$m], na.rm=TRUE)))
out$pct <- round(100*out$matched/out$children, 1)

cat('=== Virginia, measured against its own register ===\n\n')
print(out, row.names = FALSE)
cat('\nborrowed mean currently in the build:',
    'pre-K 44.0   Head Start 62.2   Early Head Start 64.7\n')
write.csv(out, file.path(SP, 'va_overlap_measured.csv'), row.names = FALSE)
