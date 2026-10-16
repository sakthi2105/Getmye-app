const assert = require('assert');
const {
  KUMBAKONAM_GEOFENCE,
  calculateDistanceKm,
  isWithinKumbakonam,
  partnerIdsMatch,
  isPartnerInList
} = require('./services/orderDispatchService');

console.log('🧪 Starting Order Flow & Geofencing Verification Unit Tests...\n');

// 1. Test Geofence Distance Calculation
console.log('1️⃣ Testing calculateDistanceKm...');
const centerToCenter = calculateDistanceKm(
  KUMBAKONAM_GEOFENCE.center.latitude,
  KUMBAKONAM_GEOFENCE.center.longitude,
  KUMBAKONAM_GEOFENCE.center.latitude,
  KUMBAKONAM_GEOFENCE.center.longitude
);
assert.strictEqual(centerToCenter, 0, 'Distance to same point must be 0');
console.log('   Distance to self is 0 km ✅');

// Kumbakonam Mahamaham tank (10.9585, 79.3820)
const mahamahamDist = calculateDistanceKm(
  KUMBAKONAM_GEOFENCE.center.latitude,
  KUMBAKONAM_GEOFENCE.center.longitude,
  10.9585,
  79.3820
);
console.log(`   Distance to Mahamaham Tank: ${mahamahamDist} km`);
assert(mahamahamDist < 2.0, 'Mahamaham must be within 2km of Kumbakonam center');

// Thanjavur (10.7870, 79.1378)
const thanjavurDist = calculateDistanceKm(
  KUMBAKONAM_GEOFENCE.center.latitude,
  KUMBAKONAM_GEOFENCE.center.longitude,
  10.7870,
  79.1378
);
console.log(`   Distance to Thanjavur: ${thanjavurDist} km`);
assert(thanjavurDist > 30, 'Thanjavur must be > 30km away');

// Chennai (13.0827, 80.2707)
const chennaiDist = calculateDistanceKm(
  KUMBAKONAM_GEOFENCE.center.latitude,
  KUMBAKONAM_GEOFENCE.center.longitude,
  13.0827,
  80.2707
);
console.log(`   Distance to Chennai: ${chennaiDist} km`);
assert(chennaiDist > 200, 'Chennai must be > 200km away');
console.log('   calculateDistanceKm tests passed ✅\n');

// 2. Test isWithinKumbakonam (Strict location-based check)
console.log('2️⃣ Testing isWithinKumbakonam...');

// Inside: Kumbakonam Town Center
assert.strictEqual(isWithinKumbakonam(10.9601, 79.3845), true, 'Center must be inside');
// Inside: Darasuram (approx 4 km away)
assert.strictEqual(isWithinKumbakonam(10.9500, 79.3550), true, 'Darasuram must be inside');
// Inside: Swamimalai (approx 7 km away)
assert.strictEqual(isWithinKumbakonam(10.9550, 79.3250), true, 'Swamimalai must be inside');

// Outside: Thanjavur
assert.strictEqual(isWithinKumbakonam(10.7870, 79.1378), false, 'Thanjavur must be outside');
// Outside: Mayiladuthurai
assert.strictEqual(isWithinKumbakonam(11.1075, 79.6522), false, 'Mayiladuthurai must be outside');
// Outside: Chennai
assert.strictEqual(isWithinKumbakonam(13.0827, 80.2707), false, 'Chennai must be outside');
// Null or invalid coordinates
assert.strictEqual(isWithinKumbakonam(null, null), false, 'Null coordinates must be rejected');
assert.strictEqual(isWithinKumbakonam(undefined, 79.3845), false, 'Undefined lat must be rejected');
console.log('   isWithinKumbakonam tests passed ✅\n');

// 3. Test Partner ID Matching Logic
console.log('3️⃣ Testing partnerIdsMatch and isPartnerInList...');
assert.strictEqual(partnerIdsMatch('dp_001', 'DP001'), true, 'dp_001 should match DP001');
assert.strictEqual(partnerIdsMatch('DP_001', 'dp_1'), true, 'DP_001 should match dp_1');
assert.strictEqual(partnerIdsMatch('DP002', 'dp_001'), false, 'Different numbers should not match');
assert.strictEqual(isPartnerInList('dp_001', ['DP002', 'DP001']), true, 'List matching should succeed');
assert.strictEqual(isPartnerInList('dp_003', ['DP002', 'DP001']), false, 'List matching should reject unlisted');
console.log('   partnerIdsMatch tests passed ✅\n');

// 4. Test Geofence Error Message Exact Match
console.log('4️⃣ Testing Geofence Restriction Message...');
const EXPECTED_MSG = "Sorry, our service is currently unavailable in your location. We’re planning to expand to your area in the future. Thank you for your patience and understanding!";
assert.strictEqual(KUMBAKONAM_GEOFENCE.errorMessage, EXPECTED_MSG, 'Geofence error message must match requirement exactly');
console.log('   Geofence error message matches exact prompt requirement ✅\n');

console.log('🎉 ALL UNIT TESTS PASSED SUCCESSFULLY! 🎉');
