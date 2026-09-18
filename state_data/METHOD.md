# How the state demand files are built

Anna Rachwalski · 18 September 2026

The simulator needs one small file per state. Seven rows, one per care type, one
number each: annual hours of child care. This memo says where that number comes
from.

Everything happens at the **state level**. County data enters only as a sum.

---

## Why this is not just a survey lookup

The simulator needs to know what the mix of child care looks like in each state.
The survey that measures that mix, NSECE, does not say which state a family is
in. It reports Census region and nothing finer.

So I rebuild the mix from each state's own administrative records, and I use the
survey only for the things no state records can see.

---

## The build

### Step 1 — Count the children

Census population estimates, 2019. Children age 0 to 4.

| | Children 0–4 |
|---|---:|
| Kentucky | 272,610 |
| New Jersey | 514,690 |
| New York | 1,127,001 |
| New York City | 523,718 |
| Virginia | 505,477 |

- These are real children counted, not survey weights.
- **Ages 0 to 4.** The simulator uses that same cutoff. The demand file has to
  describe the same children.
- **New York City is counted twice on purpose.** It is inside New York, and it is
  also its own build. The city holds 47% of the state's young children.

### Step 2 — How many are in someone else's care

A household survey, NSCH 2019, asks whether the child was in non-parental care
last week. It records the state, so I can read one state at a time.

| | In non-parental care |
|---|---:|
| Kentucky | 59% |
| New Jersey | 60% |
| New York | 58% |
| Virginia | 52% |

Multiply the two. This is the **total** — the number everything else is a share
of.

| | Children | × Share | = In non-parental care |
|---|---:|---:|---:|
| Kentucky | 272,610 | 59% | **161,930** |
| New Jersey | 514,690 | 60% | **309,946** |
| New York | 1,127,001 | 58% | **649,829** |
| New York City | 523,718 | 58% | **301,976** |
| Virginia | 505,477 | 52% | **263,000** |

- **This total is always 2019**, because both inputs are 2019. That is what lets
  me use a provider list published in 2026: the list decides the *mix*, never the
  *level*.
- **New York City uses the state's share.** The survey does not go below state
  level. The city's own registers have to supply the difference.
- The survey reads about 120 families per state, so this share is the softest
  number in the build. Treat it as roughly right, not exact. Pooling more survey
  years would tighten it, and it was tested and rejected — see the sources
  section.

### Step 3 — Turn provider lists into children

Every state licenses child care providers and publishes the list. The list gives
capacity. I need children. Three things have to happen, and each state needs them
done differently.

**Remove the school-age capacity.** Every list mixes it in.

- **Kentucky** does not say which providers are centers and which are homes. I
  split on the state's own rule — a licensed home is capped at 12 children — so
  12 or fewer is a home. That gives 1,609 centers and 335 homes.
- **New Jersey** gives an age range per center. I drop the 1,035 centers that
  only serve ages 6 to 13.
- **New York** is the easy one. It publishes capacity by age, so infant plus
  toddler plus preschool is the answer directly.
- **Virginia** writes the age range as text. I read it, and drop anything that
  starts at age 5 or later.

**Bring the list back to 2019.** Two of them were published in 2026.

- **New York** shrinks, because family homes have closed in large numbers since
  2019. Group family day care scales to 0.86 of its current size, and 0.84 in the
  city.
- **Virginia** scales to **0.90**, measured against its own 2020 capacity report.
- **Kentucky and New Jersey need nothing.** Kentucky's list is from 2018 and New
  Jersey's from 2019 — both already the right vintage.

**Turn capacity into children.** Capacity is the legal maximum. Real enrollment
is lower.

- **Kentucky measured its own.** Its 2019 workforce study prints capacity and
  enrollment next to each other: 42 children per center, 9 per home. This is the
  best way to do it.
- **New Jersey measured its own too** — centers run at 67% full.
- **New York and Virginia have not published one**, so they borrow the national
  figures: centers 90% full, homes 60%.

Result:

| | | Providers | Under-5 capacity | Children |
|---|---|---:|---:|---:|
| Kentucky | Centers | 1,609 | 107,369 | 67,578 |
| Kentucky | Homes | 335 | 2,115 | 3,015 |
| New Jersey | Centers | 3,128 | 251,159 | 169,106 |
| New York | Centers (state) | 2,073 | 153,053 | 138,191 |
| New York | Centers (city) | 2,310 | 141,300 | 127,580 |
| New York | Homes | 11,918 | 117,401 | 93,381 |
| New York City | Centers | 2,310 | 141,300 | 127,580 |
| New York City | Homes | 4,580 | 46,057 | 36,634 |
| Virginia | Centers | 3,186 | 207,835 | 187,654 |
| Virginia | Homes | 1,935 | 12,633 | 7,604 |

- **New York takes two lists.** The state licenses no centers inside New York
  City — the city permits its own. Neither list alone covers the state.

### Step 4 — Add the programs that count their own children

Head Start, Early Head Start and public pre-K publish actual enrollment. No
estimate needed.

| | Pre-K | Head Start | Early Head Start | Total |
|---|---:|---:|---:|---:|
| Kentucky | 28,465 | 12,307 | 3,004 | 43,776 |
| New Jersey | 41,305 | 11,940 | 3,578 | 56,823 |
| New York | 54,451 | 36,863 | 11,433 | 102,747 |
| New York City | 26,717 | 13,073 | 5,938 | 45,728 |
| Virginia | 33,790 | 11,579 | 2,507 | 47,876 |

- **These children come out of the licensed center count, not on top of it.** A
  Head Start center usually holds a state license, so its children are already
  inside step 3. Adding them would count them twice.
- A published count does not get adjusted in step 5. It is a count, not an
  estimate.

### Step 5 — Scale the level to match the survey

Provider lists are good at **shape** and bad at **level**. They say which care
types are common in a state; they overstate how many children are in formal care.

So I scale each state by one number until formal care matches the share the
survey finds — a little over half of all non-parental care. The program counts
from step 4 hold still. Everything else moves together, so the mix is untouched
and only the level changes.

| | Scaled by | Formal care | Informal care | Informal share |
|---|---:|---:|---:|---:|
| Kentucky | ×1.58 | 86,082 | 75,848 | 47% |
| New Jersey | ×1.04 | 175,212 | 134,734 | 44% |
| New York | ×1.03 | 367,348 | 282,481 | 44% |
| New York City | ×1.05 | 170,707 | 131,269 | 44% |
| Virginia | ×0.62 | 139,811 | 123,189 | 47% |

**This table is the best diagnostic in the build.** Read it this way:

- **New Jersey, New York and the city barely move.** Their raw counts already
  landed within a couple of points of the survey before anything was done to
  them. Three separate state registers agreeing with an independent national
  survey is the strongest evidence here that the method works.
- **Virginia gets cut by a third.** Its list is the most generous of the four —
  it includes unlicensed and voluntarily registered family homes that other
  states never record — and it borrows the national fill rate.
- **Kentucky goes up by half, and that is the useful one.** Kentucky is the only
  state that measured how full its centers really are: 57%, against the 90%
  national figure that New York and Virginia borrow. The borrowed figure is far
  too high. Kentucky moving up and Virginia moving down is exactly what that gap
  predicts, which says the scaling is fixing a known problem rather than papering
  over an unknown one.

### Step 6 — Finish the rows

**No price split.** Earlier versions divided center care into low-priced and
high-priced. Nothing in the state data supports that division — a state
publishes one price, so every state landed wholly on one side of the national
line. Center care is now one row. Paid center care runs 1,686 hours per child
per year, the national average across both price bands.

**Fill in the care nobody records.** Three of the seven types appear in no
register anywhere — unpaid relatives, nannies, informal arrangements. They are
whatever is left over after everything countable is subtracted, divided three
ways on the national pattern. That leftover runs 44% to 47% of non-parental care
here, against 47% nationally.

**Convert children to hours.** Each care type has a measured hours figure from
the national survey, running from about 1,440 hours a year for program center
care to about 2,120 for unpaid home care.

---

## The result

The build measures two things. Everything else is a subdivision of them.

| | Center-based | Not center-based | Total | Share center-based |
|---|---:|---:|---:|---:|
| Kentucky | 81,326 | 80,604 | 161,930 | 50% |
| New Jersey | 173,225 | 136,721 | 309,946 | 56% |
| New York | 270,982 | 378,847 | 649,829 | 42% |
| New York City | 132,065 | 169,911 | 301,976 | 44% |
| Virginia | 135,068 | 127,932 | 263,000 | 51% |

Not center-based is one part counted and one part left over:

| | Licensed home care | Informal, unrecorded |
|---|---:|---:|
| Kentucky | 4,756 | 75,848 |
| New Jersey | 1,987 | 134,734 |
| New York | 96,366 | 282,481 |
| New York City | 38,642 | 131,269 |
| Virginia | 4,743 | 123,189 |

- **New York's licensed home care is twenty times Kentucky's or Virginia's.**
  That is real. New York registers home care from three children up, so care
  that is invisible elsewhere sits inside its register.

Children, by care type:

| | KY | NJ | NY | NYC | VA |
|---|---:|---:|---:|---:|---:|
| Center-Based | 37,550 | 116,402 | 168,235 | 86,337 | 87,192 |
| Unpaid Center-Based | 43,776 | 56,823 | 102,747 | 45,728 | 47,876 |
| Paid Home-Based | 4,756 | 1,987 | 96,366 | 38,642 | 4,743 |
| Other Unpaid | 45,830 | 81,411 | 170,686 | 79,318 | 74,436 |
| Other Paid | 27,363 | 48,607 | 101,909 | 47,357 | 44,442 |
| Unpaid Home-Based | 2,655 | 4,715 | 9,886 | 4,594 | 4,311 |
| **Total** | **161,930** | **309,946** | **649,829** | **301,976** | **263,000** |

Annual hours, in millions. This is the output file:

| | KY | NJ | NY | NYC | VA |
|---|---:|---:|---:|---:|---:|
| Center-Based | 63.3 | 196.2 | 283.6 | 145.5 | 147.0 |
| Unpaid Center-Based | 62.9 | 81.6 | 147.6 | 65.7 | 68.8 |
| Paid Home-Based | 9.1 | 3.8 | 185.0 | 74.2 | 9.1 |
| Other Unpaid | 88.4 | 157.1 | 329.3 | 153.0 | 143.6 |
| Other Paid | 42.5 | 75.5 | 158.4 | 73.6 | 69.1 |
| Unpaid Home-Based | 5.6 | 10.0 | 21.0 | 9.7 | 9.1 |

**The simulator still expects seven rows**, with center care split by price. It
rejects a file that has six. Bridging that is a separate, mechanical step —
divide the center row on a national share — and it is deliberately not part of
this method.

---

## What each number rests on

| | Where it comes from | How solid |
|---|---|---|
| Children 0–4 | Census, 2019 | Counted |
| Share in non-parental care | Household survey, 2019, ~120 families per state | Soft. Pooling more waves was tested and rejected — see below |
| Provider capacity | State licensing list | Counted, but a legal maximum. Virginia providers say they can serve **27% fewer children than they are licensed for** |
| How full providers are — KY, NJ | The state's own survey | Measured in state |
| How full providers are — NY, VA | National survey | Borrowed. Two states' own data say it is too high |
| Program enrollment | Federal and state reporting | Counted |
| Informal split, hours per child | National survey | Borrowed |

### The two soft rows, and what is known about them

**The non-parental share stays a single 2019 wave.** Pooling would cut the
sampling error by 30% to 45%. I tested it and rejected it, on the standard that
every input matches the simulator's 2019 base year.

- **2018 + 2019 + 2020** would center exactly on 2019, which is the one pool that
  passes the vintage test. It fails on content. NSCH 2020 was fielded through the
  pandemic and child care use collapsed: Kentucky 45.8%, New Jersey 42.6%,
  Virginia 46.7%, against 57% to 62% in the two years before. That is a real
  shock, not sampling noise, and pooling it in would push every state's level
  down by several points.
- **2018 + 2019** centers on mid-2018. Every other input is pinned to 2019.
- So the rate keeps its full sampling error, and that error is stated rather than
  traded away for a bias nothing downstream could recover.

**The borrowed fill rates are too high, and by a measurable amount.** Two states
have published their own figures, and both point the same way.

- **Kentucky** measured its centers at **57% full** in 2019, against the national
  90% that New York and Virginia borrow.
- **Virginia** measured something different but related in 2022: what providers
  say they can actually serve, against what they are licensed for. Centers came
  in at **73%** of their authorized capacity and homes at **91%**, across 1,968
  providers. Statewide in that sample, 121,260 licensed slots against 89,374
  providers said they could fill.

Neither figure is used as a rate. Kentucky's applies to Kentucky only. Virginia's
is a 2022 survey and measures capacity rather than enrollment, so it would
double-count against the fill rate. Both are evidence about **direction and
size**, and they agree: licensed capacity overstates real supply by roughly a
quarter to a third, and the national fill rate does not remove enough of it.

This is why step 5 scales Virginia down by 0.62 and Kentucky up by 1.58. The
scaling is correcting a bias two states have independently measured.

---

## What this does not do

- **It cannot see unpaid relative care**, the biggest informal category. That
  number is a leftover, not a measurement.
- **The mix carries the provider list's date.** The level is 2019; how it divides
  across care types reflects whenever the state last published.
- **New York and Virginia borrow two national rates.** Kentucky measured its
  centers at 57% full against the borrowed 90%. Virginia measured its providers
  at 73% of licensed capacity. Both states would move if they published a fill
  rate of their own for 2019.
- **The program row is an upper bound.** Head Start and state pre-K overlap by an
  amount nobody publishes.
- **The scaling in step 5 is provisional.** It forces each state to match the
  survey exactly. That is a choice, and it is worth revisiting.
