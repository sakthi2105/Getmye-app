const DeliveryPerson = require('../models/DeliveryPerson');
const LiveLocation = require('../models/LiveLocation');
const Order = require('../models/Order');

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
    // 1. Get all delivery persons who are registered and strictly ONLINE
    const deliveryPersons = await DeliveryPerson.find({
      dp_status: 'online'
    }).select('DP_id name mobile_number dp_status').lean();

    if (!deliveryPersons || deliveryPersons.length === 0) {
      return [];
    }

    // 2. Find any partners currently engaged in active orders
    const activeOrders = await Order.find({
      status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
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
        const idLower = o.partner_id.toString().trim().toLowerCase();
        busyPartnerIds.add(idLower);
        const numClean = idLower.replace(/[^0-9]/g, '').replace(/^0+/, '');
        if (numClean) busyPartnerIds.add(numClean);
      }
    }
    for (const o of pendingOrders) {
      if (o.current_assigned_partner_id) {
        const idLower = o.current_assigned_partner_id.toString().trim().toLowerCase();
        busyPartnerIds.add(idLower);
        const numClean = idLower.replace(/[^0-9]/g, '').replace(/^0+/, '');
        if (numClean) busyPartnerIds.add(numClean);
      }
    }

    // 3. Fetch live locations for online partners
    const liveLocations = await LiveLocation.find({ is_online: true }).lean();
    const liveLocMap = new Map();
    for (const loc of liveLocations) {
      if (loc.partner_id) {
        const idLower = loc.partner_id.toString().trim().toLowerCase();
        liveLocMap.set(idLower, loc);
        const numClean = idLower.replace(/[^0-9]/g, '').replace(/^0+/, '');
        if (numClean) liveLocMap.set(numClean, loc);
      }
    }

    // 4. Candidate matching and distance calculation
    const candidates = [];
    const custLat = (customerLat != null && !isNaN(Number(customerLat))) ? Number(customerLat) : KUMBAKONAM_GEOFENCE.center.latitude;
    const custLng = (customerLng != null && !isNaN(Number(customerLng))) ? Number(customerLng) : KUMBAKONAM_GEOFENCE.center.longitude;

    for (const dp of deliveryPersons) {
      const dpId = dp.DP_id.toString().trim();
      const dpIdLower = dpId.toLowerCase();
      const numClean = dpIdLower.replace(/[^0-9]/g, '').replace(/^0+/, '');

      // Check if busy with ongoing order or pending offer
      if (busyPartnerIds.has(dpIdLower) || (numClean && busyPartnerIds.has(numClean))) {
        continue;
      }

      // Check if excluded (declined or timed out for this order)
      if (isPartnerInList(dpId, excludedPartnerIds)) {
        continue;
      }

      // 🛑 STRICT REQUIREMENT: Partner must have active LiveLocation with status online and valid GPS
      const loc = liveLocMap.get(dpIdLower) || (numClean ? liveLocMap.get(numClean) : null);
      if (!loc || loc.is_online !== true) {
        continue;
      }

      if (loc.latitude == null || loc.longitude == null) {
        continue;
      }

      const partnerLat = Number(loc.latitude);
      const partnerLng = Number(loc.longitude);
      if (isNaN(partnerLat) || isNaN(partnerLng) || (partnerLat === 0 && partnerLng === 0)) {
        continue;
      }

      const distance = calculateDistanceKm(custLat, custLng, partnerLat, partnerLng);

      candidates.push({
        partner_id: dpId,
        name: dp.name || 'Delivery Partner',
        phone: dp.mobile_number || '',
        latitude: partnerLat,
        longitude: partnerLng,
        distance_km: distance
      });
    }

    // 5. Sort by distance ascending (strictly closest partner first)
    candidates.sort((a, b) => a.distance_km - b.distance_km);
    return candidates;
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

module.exports = {
  KUMBAKONAM_GEOFENCE,
  calculateDistanceKm,
  isWithinKumbakonam,
  partnerIdsMatch,
  isPartnerInList,
  findAvailablePartners,
  assignNextClosestPartner,
  checkAndReassignExpiredOrders
};
