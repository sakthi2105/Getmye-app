const DeliveryPerson = require('../models/DeliveryPerson');
const LiveLocation = require('../models/LiveLocation');
const Order = require('../models/Order');
const WaitingCustomer = require('../models/WaitingCustomer');
const Notification = require('../models/Notification');
const { getNextSequence } = require('../models/Counter');

// Kumbakonam Town Geofence Definition
const KUMBAKONAM_GEOFENCE = {
  center: {
    latitude: 10.9601,
    longitude: 79.3845
  },
  maxRadiusKm: 10.0, // 10 km covers Kumbakonam town municipal corporation and adjoining suburbs
  errorMessage: "Sorry, our service is currently unavailable in your location. We’re planning to expand to your area in the future. Thank you for your patience and understanding!"
};

// Calculate Haversine distance in kilometers between two GPS coordinates
function calculateDistanceKm(lat1, lon1, lat2, lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return Infinity;
  const numLat1 = Number(lat1);
  const numLon1 = Number(lon1);
  const numLat2 = Number(lat2);
  const numLon2 = Number(lon2);
  if (isNaN(numLat1) || isNaN(numLon1) || isNaN(numLat2) || isNaN(numLon2)) return Infinity;

  const R = 6371; // Earth's radius in km
  const dLat = (numLat2 - numLat1) * Math.PI / 180;
  const dLon = (numLon2 - numLon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(numLat1 * Math.PI / 180) * Math.cos(numLat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Number((R * c).toFixed(2));
}

// Strict location-based check for Kumbakonam town
function isWithinKumbakonam(latitude, longitude) {
  if (latitude == null || longitude == null) return false;
  const numLat = Number(latitude);
  const numLng = Number(longitude);
  if (isNaN(numLat) || isNaN(numLng)) return false;

  const distance = calculateDistanceKm(
    numLat,
    numLng,
    KUMBAKONAM_GEOFENCE.center.latitude,
    KUMBAKONAM_GEOFENCE.center.longitude
  );

  return distance <= KUMBAKONAM_GEOFENCE.maxRadiusKm;
}

// Normalize and match partner IDs (e.g. dp_001 vs DP001 vs dp_1)
function partnerIdsMatch(id1, id2) {
  if (!id1 || !id2) return false;
  const s1 = id1.toString().trim().toLowerCase();
  const s2 = id2.toString().trim().toLowerCase();
  if (s1 === s2) return true;
  const num1 = s1.replace(/[^0-9]/g, '').replace(/^0+/, '');
  const num2 = s2.replace(/[^0-9]/g, '').replace(/^0+/, '');
  return (num1.length > 0 && num2.length > 0 && num1 === num2);
}

// Check if a partner ID exists in a list of partner IDs
function isPartnerInList(partnerId, list = []) {
  if (!partnerId || !Array.isArray(list)) return false;
  return list.some(item => partnerIdsMatch(partnerId, item));
}

/**
 * Helper to get a canonical clean identifier for a partner ID (lowercased without non-digits / leading zeros)
 */
function toCanonicalId(id) {
  if (!id) return '';
  const s = id.toString().trim().toLowerCase();
  const num = s.replace(/[^0-9]/g, '').replace(/^0+/, '');
  return num || s;
}

/**
 * Find all available delivery partners sorted by proximity to customer coordinates.
 * Excludes partners who:
 * 1. Are offline (dp_status !== 'online' or LiveLocation is_online !== true)
 * 2. Do not have active/valid GPS coordinates
 * 3. Already have an active ongoing order (status in ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'])
 * 4. Already have an active pending order offered to them
 * 5. Are in the excludedPartnerIds list (already declined or timed out for this specific order)
 */
async function findAvailablePartners(customerLat, customerLng, excludedPartnerIds = [], excludeOrderId = null) {
  try {
    // 1. Get all delivery persons who are registered and ONLINE (case-insensitive)
    const deliveryPersons = await DeliveryPerson.find({
      dp_status: { $regex: /^online$/i }
    }).select('DP_id name mobile_number dp_status').lean();

    // Also include partners actively online in LiveLocation
    try {
      const activeLiveLocs = await LiveLocation.find({ is_online: true }).select('partner_id').lean();
      const locIds = activeLiveLocs.map(l => l.partner_id).filter(Boolean);
      if (locIds.length > 0) {
        const extraDPs = await DeliveryPerson.find({
          $or: [
            { DP_id: { $in: locIds } },
            { mobile_number: { $in: locIds } }
          ]
        }).select('DP_id name mobile_number dp_status').lean();

        for (const extra of extraDPs) {
          if (!deliveryPersons.some(d => partnerIdsMatch(d.DP_id, extra.DP_id))) {
            deliveryPersons.push(extra);
          }
        }
      }
    } catch (_) {}

    if (!deliveryPersons || deliveryPersons.length === 0) {
      return [];
    }

    // 2. Find any partners currently engaged in active orders within the last 12 hours
    const recentThreshold = new Date(Date.now() - 12 * 60 * 60 * 1000);
    const activeOrders = await Order.find({
      status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] },
      created_at: { $gte: recentThreshold }
    }).select('partner_id').lean();

    // Also exclude partners who currently have an unexpired pending assignment for another order
    const pendingQuery = {
      status: 'pending',
      current_assigned_partner_id: { $ne: null },
      assignment_expires_at: { $gt: new Date() }
    };
    if (excludeOrderId) {
      pendingQuery.order_id = { $ne: excludeOrderId };
    }
    const pendingOrders = await Order.find(pendingQuery).select('current_assigned_partner_id').lean();

    const busyPartnerIds = new Set();
    for (const o of activeOrders) {
      if (o.partner_id) {
        busyPartnerIds.add(toCanonicalId(o.partner_id));
        busyPartnerIds.add(o.partner_id.toString().trim().toLowerCase());
      }
    }
    for (const o of pendingOrders) {
      if (o.current_assigned_partner_id) {
        busyPartnerIds.add(toCanonicalId(o.current_assigned_partner_id));
        busyPartnerIds.add(o.current_assigned_partner_id.toString().trim().toLowerCase());
      }
    }

    // 3. Fetch live locations for online partners
    const liveLocations = await LiveLocation.find({}).lean();
    const liveLocMap = new Map();
    for (const loc of liveLocations) {
      if (loc.partner_id) {
        const idLower = loc.partner_id.toString().trim().toLowerCase();
        liveLocMap.set(idLower, loc);
        const canon = toCanonicalId(loc.partner_id);
        if (canon) liveLocMap.set(canon, loc);
      }
    }

    // 4. Candidate matching and distance calculation
    const activeCandidates = [];
    const fallbackCandidates = [];
    const now = Date.now();
    const LOCATION_ACTIVE_WINDOW_MS = 25 * 60 * 1000; // 25 minutes freshness for location on

    const custLat = (customerLat != null && !isNaN(Number(customerLat))) ? Number(customerLat) : KUMBAKONAM_GEOFENCE.center.latitude;
    const custLng = (customerLng != null && !isNaN(Number(customerLng))) ? Number(customerLng) : KUMBAKONAM_GEOFENCE.center.longitude;

    for (const dp of deliveryPersons) {
      const dpId = dp.DP_id.toString().trim();
      const dpIdLower = dpId.toLowerCase();
      const canonId = toCanonicalId(dpId);

      // Check if busy with ongoing order or pending offer
      if (busyPartnerIds.has(dpIdLower) || (canonId && busyPartnerIds.has(canonId))) {
        continue;
      }

      // Check if excluded (declined or timed out for this order)
      if (isPartnerInList(dpId, excludedPartnerIds)) {
        continue;
      }

      // 🛑 LOCATION & ONLINE CHECK:
      // If partner is explicitly offline in LiveLocation, skip
      const loc = liveLocMap.get(dpIdLower) || (canonId ? liveLocMap.get(canonId) : null);
      if (loc && loc.is_online === false) {
        continue;
      }

      // Determine partner coordinates (from LiveLocation if valid, otherwise fallback to Kumbakonam town center)
      let partnerLat = KUMBAKONAM_GEOFENCE.center.latitude;
      let partnerLng = KUMBAKONAM_GEOFENCE.center.longitude;
      let hasValidGps = false;

      if (loc && loc.latitude != null && loc.longitude != null) {
        const pLat = Number(loc.latitude);
        const pLng = Number(loc.longitude);
        if (!isNaN(pLat) && !isNaN(pLng) && (pLat !== 0 || pLng !== 0)) {
          partnerLat = pLat;
          partnerLng = pLng;
          hasValidGps = true;
        }
      }

      const lastUpdate = loc && loc.last_updated ? new Date(loc.last_updated).getTime() : 0;
      const isLocationActiveNow = hasValidGps && loc && loc.is_online === true && (now - lastUpdate <= LOCATION_ACTIVE_WINDOW_MS);
      const distance = calculateDistanceKm(custLat, custLng, partnerLat, partnerLng);

      const candidateObj = {
        partner_id: dpId,
        name: dp.name || 'Delivery Partner',
        phone: dp.mobile_number || '',
        latitude: partnerLat,
        longitude: partnerLng,
        distance_km: distance
      };

      if (isLocationActiveNow) {
        activeCandidates.push(candidateObj);
      } else {
        fallbackCandidates.push(candidateObj);
      }
    }

    // 5. Strictly prioritize active partners whose status is online AND location is actively ON
    const selectedCandidates = activeCandidates.length > 0 ? activeCandidates : fallbackCandidates;
    selectedCandidates.sort((a, b) => a.distance_km - b.distance_km);
    return selectedCandidates;
  } catch (err) {
    console.error('Error finding available partners:', err);
    return [];
  }
}

/**
 * Assigns or reassigns an order to the next closest available delivery partner.
 * Sets a 2-minute (120 seconds) acceptance window.
 * Strictly assigns to ONE partner at a time.
 * If all partners decline or time out, loops back from the beginning.
 */
async function assignNextClosestPartner(orderDoc, originLat, originLng) {
  if (!orderDoc) return null;

  const excluded = [
    ...(orderDoc.declined_partners || []),
    ...(orderDoc.timed_out_partners || [])
  ];

  if (orderDoc.current_assigned_partner_id) {
    excluded.push(orderDoc.current_assigned_partner_id);
  }

  const refLat = originLat != null ? originLat : orderDoc.customer_latitude;
  const refLng = originLng != null ? originLng : orderDoc.customer_longitude;

  let candidates = await findAvailablePartners(
    refLat,
    refLng,
    excluded,
    orderDoc.order_id
  );

  // If no candidates found with exclusions, handle looping!
  if (candidates.length === 0) {
    // 1. Try looping back to partners who only timed out (giving them another chance)
    if ((orderDoc.timed_out_partners || []).length > 0) {
      console.log(`🔄 [Order Dispatch] Order ${orderDoc.order_id}: Resetting timed-out partners to continue dispatch loop...`);
      orderDoc.timed_out_partners = [];
      candidates = await findAvailablePartners(
        refLat,
        refLng,
        orderDoc.declined_partners || [],
        orderDoc.order_id
      );
    }

    // 2. If still no candidates and all available partners declined, restart loop from nearest partner!
    if (candidates.length === 0 && (orderDoc.declined_partners || []).length > 0) {
      console.log(`🔄 [Order Dispatch] Order ${orderDoc.order_id}: All available partners declined. Looping back to nearest partner!`);
      orderDoc.declined_partners = [];
      orderDoc.timed_out_partners = [];
      candidates = await findAvailablePartners(
        refLat,
        refLng,
        [],
        orderDoc.order_id
      );
    }

    // 3. Ultimate fallback: If proximity filtering returned 0 but online delivery persons exist in Kumbakonam,
    // dispatch to any online delivery partner so the order is never dropped!
    if (candidates.length === 0) {
      const anyOnlinePartner = await DeliveryPerson.findOne({
        dp_status: { $regex: /^online$/i }
      }).select('DP_id name mobile_number').lean();

      if (anyOnlinePartner) {
        console.log(`📍 [Order Dispatch] Order ${orderDoc.order_id}: Using online partner fallback -> ${anyOnlinePartner.DP_id}`);
        candidates.push({
          partner_id: anyOnlinePartner.DP_id,
          name: anyOnlinePartner.name || 'Delivery Partner',
          phone: anyOnlinePartner.mobile_number || '',
          latitude: KUMBAKONAM_GEOFENCE.center.latitude,
          longitude: KUMBAKONAM_GEOFENCE.center.longitude,
          distance_km: 1.0
        });
      }
    }
  }

  const timeoutSeconds = orderDoc.assignment_timeout_seconds || 120;
  const now = new Date();

  if (candidates.length > 0) {
    const nextPartner = candidates[0];
    orderDoc.current_assigned_partner_id = nextPartner.partner_id;
    orderDoc.assignment_expires_at = new Date(now.getTime() + timeoutSeconds * 1000);

    if (!orderDoc.assignment_history) {
      orderDoc.assignment_history = [];
    }

    orderDoc.assignment_history.push({
      partner_id: nextPartner.partner_id,
      partner_name: nextPartner.name,
      distance_km: nextPartner.distance_km,
      offered_at: now,
      status: 'offered'
    });

    console.log(`📍 [Order Dispatch] Order ${orderDoc.order_id} routed to closest partner: ${nextPartner.partner_id} (${nextPartner.distance_km} km away). 2-minute timer expires at ${orderDoc.assignment_expires_at.toISOString()}`);
    return nextPartner;
  } else {
    console.log(`⚠️ [Order Dispatch] Order ${orderDoc.order_id}: No available partners registered or online right now.`);
    orderDoc.current_assigned_partner_id = null;
    orderDoc.assignment_expires_at = null;
    return null;
  }
}

let isReassigningExpired = false;

/**
 * Check all pending orders and automatically reassign any order where the
 * currently assigned partner failed to accept within 2 minutes.
 */
async function checkAndReassignExpiredOrders() {
  if (isReassigningExpired) return 0;
  isReassigningExpired = true;
  try {
    const now = new Date();
    const expiredOrders = await Order.find({
      status: 'pending',
      $or: [
        { current_assigned_partner_id: null },
        { current_assigned_partner_id: { $ne: null }, assignment_expires_at: { $lte: now } }
      ]
    });

    if (expiredOrders.length === 0) return 0;

    let reassignedCount = 0;
    for (const order of expiredOrders) {
      try {
        const timedOutPartnerId = order.current_assigned_partner_id;
        if (timedOutPartnerId) {
          console.log(`⏰ [Order Dispatch] Order ${order.order_id} offer to partner ${timedOutPartnerId} timed out (> 2 minutes without accept). Reassigning to next closest partner...`);

          // Record timeout in timed_out_partners and assignment_history
          if (!order.timed_out_partners) order.timed_out_partners = [];
          if (!isPartnerInList(timedOutPartnerId, order.timed_out_partners)) {
            order.timed_out_partners.push(timedOutPartnerId);
          }

          if (order.assignment_history && order.assignment_history.length > 0) {
            for (let i = order.assignment_history.length - 1; i >= 0; i--) {
              if (partnerIdsMatch(order.assignment_history[i].partner_id, timedOutPartnerId) && order.assignment_history[i].status === 'offered') {
                order.assignment_history[i].status = 'timeout';
                order.assignment_history[i].responded_at = now;
                break;
              }
            }
          }
        } else {
          console.log(`⏳ [Order Dispatch] Order ${order.order_id} has no assigned partner. Attempting to route to nearest available partner...`);
        }

        // Reassign to next closest partner relative to CUSTOMER LOCATION
        await assignNextClosestPartner(order, order.customer_latitude, order.customer_longitude);
        await order.save();
        reassignedCount++;
      } catch (orderSaveErr) {
        console.warn(`Safe handling for order ${order.order_id}:`, orderSaveErr.message);
      }
    }

    return reassignedCount;
  } catch (err) {
    console.error('Error during checkAndReassignExpiredOrders:', err);
    return 0;
  } finally {
    isReassigningExpired = false;
  }
}

/**
 * Calculates current real-time delivery partner availability metrics.
 */
async function getPartnerAvailabilityStats() {
  try {
    const onlineDPs = await DeliveryPerson.find({
      dp_status: { $regex: /^online$/i }
    }).select('DP_id mobile_number').lean();

    const onlineLiveLocs = await LiveLocation.find({ is_online: true }).select('partner_id').lean();
    const onlinePartnersMap = new Map();

    for (const dp of onlineDPs) {
      const canon = toCanonicalId(dp.DP_id);
      if (canon) onlinePartnersMap.set(canon, dp);
    }
    for (const loc of onlineLiveLocs) {
      const canon = toCanonicalId(loc.partner_id);
      if (canon && !onlinePartnersMap.has(canon)) {
        onlinePartnersMap.set(canon, { DP_id: loc.partner_id });
      }
    }

    const totalOnline = onlinePartnersMap.size;

    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
    const activeOrders = await Order.find({
      status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] },
      created_at: { $gte: twoHoursAgo }
    }).select('partner_id').lean();

    const busyPartners = new Set();
    for (const o of activeOrders) {
      if (o.partner_id) {
        const canon = toCanonicalId(o.partner_id);
        if (canon && onlinePartnersMap.has(canon)) {
          busyPartners.add(canon);
        }
      }
    }

    const busyCount = busyPartners.size;
    const freeCount = Math.max(0, totalOnline - busyCount);
    const zeroOnline = totalOnline === 0;
    const allBusy = totalOnline > 0 && freeCount === 0;

    return {
      total_online: totalOnline,
      busy_count: busyCount,
      free_count: freeCount,
      zero_online: zeroOnline,
      all_busy: allBusy
    };
  } catch (err) {
    console.error('Error getting partner availability stats:', err);
    return {
      total_online: 0,
      busy_count: 0,
      free_count: 0,
      zero_online: true,
      all_busy: false
    };
  }
}

/**
 * Notifies all customers who previously placed an order but couldn't get a delivery partner,
 * as soon as any delivery partner comes online or completes a delivery.
 */
async function notifyWaitingCustomersThatPartnerIsAvailable(partnerInfo = {}) {
  try {
    const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000);
    const waitingList = await WaitingCustomer.find({
      notified: false,
      requested_at: { $gte: fourHoursAgo }
    }).sort({ requested_at: -1 });

    if (!waitingList || waitingList.length === 0) return 0;

    console.log(`🔔 [Partner Available] Notifying ${waitingList.length} unserved waiting customer(s) that a delivery partner is now available!`);

    let notifiedCount = 0;
    for (const customer of waitingList) {
      try {
        const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
        await Notification.create({
          notification_id: notifId,
          recipient_id: customer.user_id,
          recipient_type: 'customer',
          title: '🛵 Delivery Partner Available Now!',
          message: 'A delivery partner is now online and available in Kumbakonam! You can place your order now on GETMYE.',
          is_read: false
        });

        customer.notified = true;
        await customer.save();
        notifiedCount++;
      } catch (err) {
        console.error(`Error notifying waiting customer ${customer.user_id}:`, err.message);
      }
    }
    return notifiedCount;
  } catch (err) {
    console.error('Error in notifyWaitingCustomersThatPartnerIsAvailable:', err);
    return 0;
  }
}

module.exports = {
  KUMBAKONAM_GEOFENCE,
  calculateDistanceKm,
  isWithinKumbakonam,
  partnerIdsMatch,
  isPartnerInList,
  findAvailablePartners,
  assignNextClosestPartner,
  checkAndReassignExpiredOrders,
  getPartnerAvailabilityStats,
  notifyWaitingCustomersThatPartnerIsAvailable
};
