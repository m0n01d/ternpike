// Movie road trip seed for the /demo route. Pure data — no side effects.
//
// Shapes match Trip.encoder (src/Data/Trip.elm) and Expense.encoder
// (src/Data/Expense.elm) so the same decoders that read PouchDB docs
// accept these unchanged. lat/lon on expenses are what the Ledger map
// (<waypoint-map>) renders as a polyline.

const trip = ({ id, name, description, startDate, endDate, budget }) => ({
  _id: id,
  type: 'trip',
  name,
  description,
  coverPhotoUrl: '',
  startDate,
  endDate,
  budget,
})

const expense = ({ tripId, id, date, amount, category, merchant, note, lat, lon, createdAt }) => ({
  _id: id,
  type: 'expense',
  tripId,
  date,
  amount,
  category,
  merchant,
  note,
  address: '',
  longNote: '',
  createdAt: createdAt || `${date}T12:00:00.000Z`,
  createdBy: 'demo@ternpike.com',
  lat,
  lon,
})

// ── Dumb and Dumber: Mutt Cutts Express ────────────────────────────────
const dumbDumberId = 'trip::1994-12-18T00:00:00.000Z::dumbdumb'
const dumbDumber = trip({
  id: dumbDumberId,
  name: 'Mutt Cutts Express',
  description: "Lloyd and Harry deliver a briefcase to Aspen. What could go wrong?",
  startDate: '1994-12-19',
  endDate: '1994-12-26',
  budget: 800.00,
})
const dumbDumberExpenses = [
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-19T08:00:00.000Z::dd01',
    date: '1994-12-19', amount: 18.40, category: 'fuel',
    merchant: 'Providence Sunoco', note: 'Full tank before hitting the road',
    lat: 41.8240, lon: -71.4128 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-19T19:30:00.000Z::dd02',
    date: '1994-12-19', amount: 12.75, category: 'food',
    merchant: 'Roy Rogers', note: 'Big Gulps. All right!',
    lat: 40.7589, lon: -73.9851 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-20T09:15:00.000Z::dd03',
    date: '1994-12-20', amount: 42.00, category: 'lodging',
    merchant: 'Motel 6 Harrisburg', note: 'Single room, two beds',
    lat: 40.2732, lon: -76.8867 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-21T07:45:00.000Z::dd04',
    date: '1994-12-21', amount: 16.20, category: 'fuel',
    merchant: 'Marathon', note: 'Indianapolis, IN',
    lat: 39.7684, lon: -86.1581 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-22T11:00:00.000Z::dd05',
    date: '1994-12-22', amount: 14.10, category: 'fuel',
    merchant: 'Sinclair', note: 'Hutchinson KS. Took a wrong turn.',
    lat: 38.0608, lon: -97.9298 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-22T20:00:00.000Z::dd06',
    date: '1994-12-22', amount: 9.50, category: 'food',
    merchant: "Denny's", note: 'Grand Slams, two-for-one',
    lat: 38.0608, lon: -97.9298 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-23T18:30:00.000Z::dd07',
    date: '1994-12-23', amount: 89.00, category: 'lodging',
    merchant: 'Days Inn Denver', note: '',
    lat: 39.7392, lon: -104.9903 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-24T16:00:00.000Z::dd08',
    date: '1994-12-24', amount: 295.00, category: 'lodging',
    merchant: 'Hotel Jerome', note: 'Aspen at last',
    lat: 39.1911, lon: -106.8175 }),
  expense({ tripId: dumbDumberId, id: 'expense::1994-12-25T10:00:00.000Z::dd09',
    date: '1994-12-25', amount: 65.00, category: 'gear',
    merchant: 'Aspen Ski Rental', note: 'Salomon X-Scream, baby!',
    lat: 39.1911, lon: -106.8175 }),
]

// ── National Lampoon's Vacation: Wagon Queen Family Truckster ──────────
const vacationId = 'trip::1983-07-14T00:00:00.000Z::griswold'
const vacation = trip({
  id: vacationId,
  name: 'Walley World or Bust',
  description: "Clark Griswold takes the family across America. Detours likely.",
  startDate: '1983-07-15',
  endDate: '1983-07-25',
  budget: 2000.00,
})
const vacationExpenses = [
  expense({ tripId: vacationId, id: 'expense::1983-07-15T08:00:00.000Z::nv01',
    date: '1983-07-15', amount: 12000.00, category: 'transport',
    merchant: "Lou Glutz Motors", note: 'Wagon Queen Family Truckster (down payment)',
    lat: 41.8781, lon: -87.6298 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-16T14:30:00.000Z::nv02',
    date: '1983-07-16', amount: 22.50, category: 'fuel',
    merchant: 'Phillips 66', note: 'St. Louis fill-up',
    lat: 38.6270, lon: -90.1994 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-17T19:00:00.000Z::nv03',
    date: '1983-07-17', amount: 54.00, category: 'food',
    merchant: "Cousin Eddie's", note: 'Hamburger Helper. No helper.',
    lat: 37.6872, lon: -97.3301 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-19T11:00:00.000Z::nv04',
    date: '1983-07-19', amount: 18.00, category: 'parks',
    merchant: 'Grand Canyon NP', note: 'Two-minute look. "There it is."',
    lat: 36.0544, lon: -112.1401 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-20T22:00:00.000Z::nv05',
    date: '1983-07-20', amount: 320.00, category: 'misc',
    merchant: 'Sahara Hotel & Casino', note: 'Vegas detour. Lost it all.',
    lat: 36.1147, lon: -115.1728 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-22T08:30:00.000Z::nv06',
    date: '1983-07-22', amount: 26.40, category: 'fuel',
    merchant: 'Chevron Barstow', note: '',
    lat: 34.8958, lon: -117.0228 }),
  expense({ tripId: vacationId, id: 'expense::1983-07-23T15:00:00.000Z::nv07',
    date: '1983-07-23', amount: 145.00, category: 'activities',
    merchant: "Walley World", note: 'Closed. Two weeks for cleaning and repairs.',
    lat: 33.8121, lon: -117.9190 }),
]

// ── Road Trip: Ithaca to Austin ────────────────────────────────────────
const roadTripId = 'trip::2000-04-20T00:00:00.000Z::roadtrip'
const roadTrip = trip({
  id: roadTripId,
  name: "Operation Tape Recovery",
  description: "Josh, E.L., Rubin, and Barry. Ithaca to Austin in 36 hours. Allegedly.",
  startDate: '2000-04-21',
  endDate: '2000-04-25',
  budget: 400.00,
})
const roadTripExpenses = [
  expense({ tripId: roadTripId, id: 'expense::2000-04-21T09:00:00.000Z::rt01',
    date: '2000-04-21', amount: 24.50, category: 'fuel',
    merchant: 'Mobil Ithaca', note: 'Topped off the borrowed car',
    lat: 42.4440, lon: -76.5019 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-21T20:30:00.000Z::rt02',
    date: '2000-04-21', amount: 38.00, category: 'lodging',
    merchant: 'Super 8 State College', note: 'Crashed at a frat instead. Got the deposit back, not the dignity.',
    lat: 40.7934, lon: -77.8600 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-22T13:00:00.000Z::rt03',
    date: '2000-04-22', amount: 18.75, category: 'food',
    merchant: 'Waffle House', note: 'Knoxville. Pecan waffles, hash browns scattered.',
    lat: 35.9606, lon: -83.9207 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-22T22:00:00.000Z::rt04',
    date: '2000-04-22', amount: 27.00, category: 'fuel',
    merchant: 'Citgo', note: 'Memphis, just past Graceland',
    lat: 35.0468, lon: -90.0220 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-23T12:00:00.000Z::rt05',
    date: '2000-04-23', amount: 14.00, category: 'food',
    merchant: 'Little Rock BBQ', note: '',
    lat: 34.7465, lon: -92.2896 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-23T23:00:00.000Z::rt06',
    date: '2000-04-23', amount: 32.00, category: 'fuel',
    merchant: 'Texaco', note: 'Texarkana — Texas state line',
    lat: 33.4252, lon: -94.0477 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-24T10:00:00.000Z::rt07',
    date: '2000-04-24', amount: 9.50, category: 'food',
    merchant: 'Whataburger', note: 'Welcome to Texas',
    lat: 32.7767, lon: -96.7970 }),
  expense({ tripId: roadTripId, id: 'expense::2000-04-24T18:00:00.000Z::rt08',
    date: '2000-04-24', amount: 0.00, category: 'misc',
    merchant: 'University of Texas, Austin', note: 'Tape recovered. Mission accomplished.',
    lat: 30.2849, lon: -97.7341 }),
]

// ── Fear and Loathing in Las Vegas: The Great American Dream ───────────
const fearLoathingId = 'trip::1971-03-21T00:00:00.000Z::falas'
const fearLoathing = trip({
  id: fearLoathingId,
  name: 'Savage Journey to the Heart of the American Dream',
  description: "Raoul Duke and Dr. Gonzo cover the Mint 400. Expense account: not generous enough.",
  startDate: '1971-03-22',
  endDate: '1971-03-26',
  budget: 300.00,
})
const fearLoathingExpenses = [
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-22T10:00:00.000Z::fl01',
    date: '1971-03-22', amount: 75.00, category: 'transport',
    merchant: 'Convertible Rental', note: 'The Red Shark. Top down, full tank.',
    lat: 34.0195, lon: -118.4912 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-22T14:00:00.000Z::fl02',
    date: '1971-03-22', amount: 4.20, category: 'food',
    merchant: 'Baker desert stop', note: 'Grapefruit. Possibly bats.',
    lat: 35.2683, lon: -116.0739 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-22T22:00:00.000Z::fl03',
    date: '1971-03-22', amount: 48.00, category: 'lodging',
    merchant: 'Mint Hotel', note: 'Suite 1850. Carpet may have been chewed.',
    lat: 36.1699, lon: -115.1398 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-23T11:00:00.000Z::fl04',
    date: '1971-03-23', amount: 12.00, category: 'misc',
    merchant: 'Mint 400 press credentials', note: 'Sports Illustrated. Allegedly.',
    lat: 36.1699, lon: -115.1398 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-23T20:00:00.000Z::fl05',
    date: '1971-03-23', amount: 86.50, category: 'food',
    merchant: 'Bazooko Circus Casino', note: 'Tab from the bar. Do not investigate.',
    lat: 36.1486, lon: -115.1693 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-24T14:00:00.000Z::fl06',
    date: '1971-03-24', amount: 220.00, category: 'lodging',
    merchant: 'Flamingo Hotel', note: 'Switched hotels. Long story.',
    lat: 36.1163, lon: -115.1722 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-25T18:00:00.000Z::fl07',
    date: '1971-03-25', amount: 9.00, category: 'fuel',
    merchant: 'Baker again', note: 'Heading back. Or away. Time has stopped.',
    lat: 35.2683, lon: -116.0739 }),
  expense({ tripId: fearLoathingId, id: 'expense::1971-03-26T09:00:00.000Z::fl08',
    date: '1971-03-26', amount: 0.00, category: 'misc',
    merchant: 'LAX', note: "He who makes a beast of himself gets rid of the pain of being a man.",
    lat: 33.9416, lon: -118.4085 }),
]

// ── Little Miss Sunshine: The Yellow VW Bus ────────────────────────────
const lmsId = 'trip::2006-07-25T00:00:00.000Z::lms'
const lms = trip({
  id: lmsId,
  name: 'Hoovers to Redondo Beach',
  description: "Olive's Little Miss Sunshine qualifier. Bus is mostly working.",
  startDate: '2006-07-26',
  endDate: '2006-07-30',
  budget: 500.00,
})
const lmsExpenses = [
  expense({ tripId: lmsId, id: 'expense::2006-07-26T07:00:00.000Z::lm01',
    date: '2006-07-26', amount: 28.00, category: 'fuel',
    merchant: 'Albuquerque 76', note: 'Filled up before launch',
    lat: 35.0844, lon: -106.6504 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-26T13:00:00.000Z::lm02',
    date: '2006-07-26', amount: 19.50, category: 'food',
    merchant: "Joe & Aggie's Cafe", note: 'Holbrook AZ. Diner stop.',
    lat: 34.9022, lon: -110.1582 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-27T10:00:00.000Z::lm03',
    date: '2006-07-27', amount: 64.00, category: 'lodging',
    merchant: 'Flagstaff Travelodge', note: 'One room. Six people.',
    lat: 35.1983, lon: -111.6513 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-27T19:00:00.000Z::lm04',
    date: '2006-07-27', amount: 0.00, category: 'medical',
    merchant: 'Flagstaff hospital', note: "Grandpa. We'll talk later.",
    lat: 35.1983, lon: -111.6513 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-28T11:00:00.000Z::lm05',
    date: '2006-07-28', amount: 31.50, category: 'fuel',
    merchant: 'Kingman Shell', note: '',
    lat: 35.1894, lon: -114.0530 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-28T20:00:00.000Z::lm06',
    date: '2006-07-28', amount: 42.00, category: 'food',
    merchant: 'Barstow Del Taco', note: 'Everyone is hungry. Frank is sad.',
    lat: 34.8958, lon: -117.0228 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-29T09:00:00.000Z::lm07',
    date: '2006-07-29', amount: 55.00, category: 'lodging',
    merchant: 'Redondo Beach Inn', note: 'Made it.',
    lat: 33.8492, lon: -118.3884 }),
  expense({ tripId: lmsId, id: 'expense::2006-07-29T14:00:00.000Z::lm08',
    date: '2006-07-29', amount: 75.00, category: 'activities',
    merchant: 'Little Miss Sunshine Pageant', note: 'Entry fee. Worth every penny.',
    lat: 33.8492, lon: -118.3884 }),
]

// ── Exported seed ──────────────────────────────────────────────────────

const allExpenses = [
  ...dumbDumberExpenses,
  ...vacationExpenses,
  ...roadTripExpenses,
  ...fearLoathingExpenses,
  ...lmsExpenses,
]

const trips = Object.fromEntries(
  [dumbDumber, vacation, roadTrip, fearLoathing, lms].map(t => [t._id, t])
)

const expensesByTrip = {}
for (const e of allExpenses) {
  if (!expensesByTrip[e.tripId]) expensesByTrip[e.tripId] = {}
  expensesByTrip[e.tripId][e._id] = e
}

export const demoSeed = { trips, expensesByTrip }
