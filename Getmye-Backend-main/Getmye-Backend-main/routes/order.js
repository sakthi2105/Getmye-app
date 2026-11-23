const express = require('express');
const router = express.Router();
const Order = require('../models/Order');
const Profile = require('../models/Profile');
const DeliveryPerson = require('../models/DeliveryPerson');
const LiveLocation = require('../models/LiveLocation');
const { getNextSequence } = require('../models/Counter');
const WaitingCustomer = require('../models/WaitingCustomer');
const {
  KUMBAKONAM_GEOFENCE,
  MAHAMAHAM_KULAM_CENTER,
  isWithinKumbakonam,
  partnerIdsMatch,
  isPartnerInList,
  assignNextClosestPartner,
  checkAndReassignExpiredOrders,
  getPartnerAvailabilityStats,
  notifyWaitingCustomersThatPartnerIsAvailable,
  calculateDeliveryFee
} = require('../services/orderDispatchService');

// POST /api/order/create - Customer places a new order
router.post('/create', async (req, res) => {
  try {
    const {
      user_id,
      customer_name,
      customer_phone,
      delivery_address,
      item_name,
      quantity,
      budget,
      cod_otp,
      customer_latitude,
      customer_longitude,
      is_welcome_offer,
      order_type
    } = req.body;
    if (!user_id || !delivery_address || !item_name) {
      return res.status(400).json({ error: 'user_id, delivery_address, and item_name are required' });
    }

    const isWelcomeOffer = is_welcome_offer === true ||
      order_type === 'welcome_offer' ||
      (item_name && /welcome\s*offer|crushing\s*offer/i.test(item_name));

    // 1. Location-Based Geo-Fencing: Exclusively in Kumbakonam Town
    let finalLat = customer_latitude != null ? Number(customer_latitude) : null;
    let finalLng = customer_longitude != null ? Number(customer_longitude) : null;

    if (finalLat != null && finalLng != null && !isNaN(finalLat) && !isNaN(finalLng) && (finalLat !== 0 || finalLng !== 0)) {
      const allowed = isWithinKumbakonam(finalLat, finalLng);
      if (!allowed) {
        console.log(`⛔ Geofence Blocked: Customer location (${finalLat}, ${finalLng}) is outside Kumbakonam.`);
        return res.status(400).json({
          success: false,
          error: 'GEOFENCE_RESTRICTION',
          message: KUMBAKONAM_GEOFENCE.errorMessage
        });
      }
    } else {
      // If coordinates are missing or zero, default to Kumbakonam town center so customer order never fails
      finalLat = KUMBAKONAM_GEOFENCE.center.latitude;
      finalLng = KUMBAKONAM_GEOFENCE.center.longitude;
    }

    const orderId = await getNextSequence('order_id', 'ORD-', 4);
    const finalOtp = (cod_otp || (Math.floor(1000 + Math.random() * 9000))).toString();
    const finalTip = (req.body.tip_amount != null && !isNaN(Number(req.body.tip_amount)) && Number(req.body.tip_amount) >= 10)
      ? Number(req.body.tip_amount)
      : 10;
    const finalBudget = Number(budget) || 0;
    const finalQuantity = Math.max(1, parseInt(quantity, 10) || 1);

    const newOrder = new Order({
      order_id: orderId,
      user_id,
      customer_name: customer_name || 'Customer',
      customer_phone: customer_phone || '',
      delivery_address,
      item_name,
      quantity: finalQuantity,
      budget: finalBudget,
      item_total: finalBudget,
      tip_amount: finalTip,
      grand_total: finalBudget + finalTip,
      customer_latitude: finalLat,
      customer_longitude: finalLng,
      is_welcome_offer: isWelcomeOffer,
      order_type: isWelcomeOffer ? 'welcome_offer' : (order_type || 'regular'),
      status: 'pending',
      items: [
        {
          name: item_name,
          quantity: finalQuantity,
          price: finalQuantity > 0 ? (finalBudget / finalQuantity) : finalBudget,
          is_collected: false
        }
      ],
      cod_otp: finalOtp,
      bill_confirmed: false,
      bill_image_url: null,
      bill_images: [],
      declined_partners: [],
      timed_out_partners: [],
      assignment_history: []
    });

    // 2. Proximity-Based Delivery Partner Assignment:
    // For Welcome Offer: Algorithm searches around Kumbakonam Mahamaham Kulam Center (500m -> 1km -> 2km)
    // For Regular Orders: Algorithm searches relative to customer delivery coordinates
    const originLat = isWelcomeOffer ? MAHAMAHAM_KULAM_CENTER.latitude : newOrder.customer_latitude;
    const originLng = isWelcomeOffer ? MAHAMAHAM_KULAM_CENTER.longitude : newOrder.customer_longitude;
    const assignedPartner = await assignNextClosestPartner(newOrder, originLat, originLng);

    await newOrder.save();
    const stats = await getPartnerAvailabilityStats();
    res.status(201).json({
      success: true,
      message: 'Order created successfully and routed to closest partner',
      assigned_partner_id: assignedPartner ? assignedPartner.partner_id : null,
      partner_stats: stats,
      order: newOrder
    });
  } catch (err) {
    console.error('Error creating order:', err);
    res.status(500).json({ error: 'Failed to create order', details: err.message });
  }
});

// GET /api/order/pending - Delivery partners view available pending orders & active orders
router.get('/pending', async (req, res) => {
  try {
    // 1. Process any expired 2-minute offers on the fly so orders transition immediately
    try {
      await checkAndReassignExpiredOrders();
    } catch (tickerErr) {
      console.error('Error ticking expired orders in /pending:', tickerErr);
    }

    const partnerId = req.query.partner_id ? req.query.partner_id.toString().trim() : null;
    const pendingThreshold = new Date(Date.now() - 24 * 60 * 60 * 1000); // 24 hours for pending orders in loop
    const cancelledThreshold = new Date(Date.now() - 30 * 60 * 1000);

    let query;
    if (partnerId) {
      const numPart = partnerId.replace(/[^0-9]/g, '');
      const numClean = numPart.replace(/^0+/, '');
      const pRegex = new RegExp(`^(dp_?0*)?${numClean || numPart}$`, 'i');

      // 🛑 STRICT REQUIREMENT: Delivery partner must be registered and ONLINE
      const partnerDoc = await DeliveryPerson.findOne({
        $or: [
          { DP_id: partnerId },
          { DP_id: pRegex },
          { mobile_number: partnerId }
        ]
      }).select('DP_id dp_status').lean();
      // Delivery partner's LiveLocation must not be explicitly offline
      const liveLoc = await LiveLocation.findOne({
        $or: [
          { partner_id: partnerId },
          { partner_id: pRegex }
        ]
      }).lean();

      // Delivery partner is considered online if marked online in DeliveryPerson OR LiveLocation is_online is true
      const isPartnerOnline = (partnerDoc && /^online$/i.test(partnerDoc.dp_status || '')) || (liveLoc && liveLoc.is_online === true);
      const isLocationEligible = !liveLoc || liveLoc.is_online !== false;

      // Collect all partner ID formats for this partner
      const partnerMatchList = [partnerId, pRegex];
      if (partnerDoc && partnerDoc.DP_id) {
        partnerMatchList.push(partnerDoc.DP_id);
        partnerMatchList.push(new RegExp(`^${partnerDoc.DP_id}$`, 'i'));
      }
      if (numClean) {
        partnerMatchList.push(numClean);
        partnerMatchList.push(`dp_${numClean}`);
        partnerMatchList.push(`DP${numClean.padStart(3, '0')}`);
        partnerMatchList.push(`dp_${numClean.padStart(3, '0')}`);
      }

      // Check if this delivery partner currently has an active ongoing delivery
      const recentActiveThreshold = new Date(Date.now() - 12 * 60 * 60 * 1000);
      const hasActiveOngoing = await Order.exists({
        partner_id: { $in: partnerMatchList },
        status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] },
        created_at: { $gte: recentActiveThreshold }
      });

      const orConditions = [
        // Ongoing accepted active orders for this partner (always allow them to view and complete their ongoing order)
        {
          partner_id: { $in: partnerMatchList },
          status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
        },
        {
          partner_id: { $in: partnerMatchList },
          status: 'cancelled',
          cancelled_at: { $gte: cancelledThreshold }
        },
        {
          status: 'cancelled',
          cancelled_at: { $gte: cancelledThreshold }
        }
      ];

      // 🛑 STRICT PROXIMITY SEQUENTIAL DISPATCH:
      // An unaccepted pending order is offered to the currently assigned nearest partner, or any online partner if unassigned!
      if (!hasActiveOngoing && isPartnerOnline && isLocationEligible) {
        orConditions.unshift({
          status: 'pending',
          created_at: { $gte: pendingThreshold },
          $or: [
            { current_assigned_partner_id: { $in: partnerMatchList } },
            { current_assigned_partner_id: null },
            { current_assigned_partner_id: '' }
          ],
          declined_partners: { $nin: partnerMatchList },
          timed_out_partners: { $nin: partnerMatchList }
        });
      }

      query = { $or: orConditions };
    } else {
      // If no partner_id is provided, DO NOT return pending orders
      query = {
        status: 'cancelled',
        cancelled_at: { $gte: cancelledThreshold }
      };
    }

    const orders = await Order.find(query)
      .select('-partner_profile_picture -bill_image_url -messages')
      .sort({ created_at: -1 })
      .limit(25)
      .lean();

    // Query recently cancelled orders explicitly to guarantee they are never missed
    const cancelledOrders = await Order.find({
      status: 'cancelled',
      cancelled_at: { $gte: cancelledThreshold }
    })
      .select('order_id status cancel_reason cancelled_by cancelled_at partner_id')
      .sort({ cancelled_at: -1 })
      .limit(30)
      .lean();

    res.json({ success: true, count: orders.length, orders, cancelled_orders: cancelledOrders });
  } catch (err) {
    console.error('Error fetching pending orders:', err);
    res.status(500).json({ error: 'Failed to fetch pending orders' });
  }
});

// Helper to enrich any order document with real DeliveryPerson name, phone, photo & rating
async function enrichOrderWithPartner(orderObj, req) {
  if (!orderObj) return orderObj;
  const isAcceptedOrBeyond = orderObj.status && orderObj.status !== 'pending';
  if (!isAcceptedOrBeyond && !orderObj.partner_id) {
    return orderObj;
  }

  const host = req.get('host');
  const protocol = req.protocol;

  let dp = null;
  if (orderObj.partner_id) {
    const numPart = orderObj.partner_id.toString().replace(/^dp_?/i, '');
    try {
      dp = await DeliveryPerson.findOne({
        $or: [
          { DP_id: orderObj.partner_id },
          { DP_id: new RegExp(`^${orderObj.partner_id}$`, 'i') },
          { DP_id: new RegExp(`^dp_?0*${numPart}$`, 'i') }
        ]
      }).select('DP_id name mobile_number').lean();
    } catch (_) {}
  }

  // If not matched, try LiveLocation
  if (!dp && isAcceptedOrBeyond) {
    try {
      const LiveLocation = require('../models/LiveLocation');
      const live = await LiveLocation.findOne({ order_id: orderObj.order_id, status: 'delivering' }).lean();
      if (live && live.partner_id) {
        const numPart = live.partner_id.toString().replace(/^dp_?/i, '');
        dp = await DeliveryPerson.findOne({
          $or: [
            { DP_id: live.partner_id },
            { DP_id: new RegExp(`^${live.partner_id}$`, 'i') },
            { DP_id: new RegExp(`^dp_?0*${numPart}$`, 'i') }
          ]
        }).select('DP_id name mobile_number').lean();
      }
    } catch (_) {}
  }

  if (dp) {
    orderObj.partner_id = dp.DP_id;
    orderObj.partner_name = dp.name || orderObj.partner_name || 'Delivery Partner';
    orderObj.partner_phone = dp.mobile_number || orderObj.partner_phone || '';
    orderObj.partner_rating = "4.9";
    orderObj.partner_deliveries = 120;
    const photoUrl = `${protocol}://${host}/api/deliveryperson/photo/${dp.DP_id}`;
    orderObj.partner_photo_url = photoUrl;
    orderObj.partner_profile_picture = photoUrl;
  } else if (orderObj.partner_id) {
    const photoUrl = `${protocol}://${host}/api/deliveryperson/photo/${orderObj.partner_id}`;
    orderObj.partner_photo_url = photoUrl;
    orderObj.partner_profile_picture = photoUrl;
    orderObj.partner_rating = "4.9";
    orderObj.partner_deliveries = 120;
  }

  return orderObj;
}

// GET /api/order/active/:user_id - Customer gets current active order (with partner photo & details enrichment)
router.get('/active/:user_id', async (req, res) => {
  try {
    const rawUserId = (req.params.user_id || '').toString().trim();
    const targetOrderId = req.query.order_id ? req.query.order_id.toString().trim() : null;
    if (!rawUserId && !targetOrderId) return res.json({ success: true, order: null });

    let query;
    if (targetOrderId) {
      query = {
        order_id: targetOrderId,
        status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit', 'delivered', 'completed'] }
      };
    } else {
      query = {
        $or: [
          { user_id: rawUserId },
          { customer_phone: rawUserId },
          { customer_phone: new RegExp(rawUserId.replace(/\D/g, '') + '$') }
        ],
        status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
      };
    }

    const activeOrder = await Order.findOne(query).sort({ created_at: -1 });

    if (!activeOrder) {
      return res.json({ success: true, order: null });
    }

    const orderObj = await enrichOrderWithPartner(activeOrder.toObject(), req);
    res.json({ success: true, order: orderObj });
  } catch (err) {
    console.error('Error fetching active order:', err);
    res.status(500).json({ error: 'Failed to fetch active order' });
  }
});

// POST /api/order/accept - Partner accepts an order
router.post('/accept', async (req, res) => {
  try {
    let { order_id, partner_id, partner_name, partner_phone } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }
    partner_id = (partner_id || '').toString().trim();

    let actualPartnerName = (partner_name && partner_name !== 'Delivery Partner') ? partner_name.toString().trim() : null;
    let actualPartnerPhone = (partner_phone && partner_phone.toString().trim().length >= 10) ? partner_phone.toString().trim() : null;
    let resolvedPartnerId = partner_id;

    if (partner_id || actualPartnerPhone) {
      try {
        const numPart = partner_id.replace(/^dp_?/i, '');
        const dpIdRegex = new RegExp(`^dp_?0*${numPart}$`, 'i');
        const dp = await DeliveryPerson.findOne({
          $or: [
            { DP_id: partner_id },
            { DP_id: new RegExp(`^${partner_id}$`, 'i') },
            { DP_id: dpIdRegex },
            { mobile_number: actualPartnerPhone || partner_id }
          ]
        }).select('DP_id name mobile_number').lean();

        if (dp) {
          resolvedPartnerId = dp.DP_id;
          actualPartnerName = dp.name || actualPartnerName;
          actualPartnerPhone = dp.mobile_number || actualPartnerPhone;
        }
      } catch (dpErr) {
        console.warn('DeliveryPerson lookup warning:', dpErr);
      }
    }

    if (!resolvedPartnerId) resolvedPartnerId = 'dp_001';
    if (!actualPartnerName) actualPartnerName = 'Delivery Partner';
    if (!actualPartnerPhone) actualPartnerPhone = '';

    const host = req.get('host');
    const protocol = req.protocol;
    const partnerPhotoUrl = `${protocol}://${host}/api/deliveryperson/photo/${resolvedPartnerId}`;

    // Check if order was cancelled before accepting
    const existing = await Order.findOne({
      $or: [
        { order_id },
        { order_id: new RegExp(`^${order_id}$`, 'i') }
      ]
    });
    if (existing && existing.status === 'cancelled') {
      const isSystemTimeout = existing.cancelled_by === 'system_no_rider' ||
          (existing.cancel_reason && existing.cancel_reason.includes('busy with ongoing deliveries'));
      const isWithinGrace = existing.cancelled_at && (Date.now() - new Date(existing.cancelled_at).getTime() < 180000); // 3 minutes grace

      if (isSystemTimeout && isWithinGrace) {
        console.log(`🔄 [Order Accept] Order ${order_id} was auto-cancelled by system, but partner ${resolvedPartnerId} accepted within grace! Reviving order to accepted...`);
        existing.status = 'pending';
        existing.cancelled_at = null;
        existing.cancel_reason = null;
        existing.cancelled_by = null;
        await existing.save();
      } else {
        console.log(`⚠️ Order ${order_id} accept blocked: Order was already cancelled by customer: ${existing.cancel_reason}`);
        return res.status(400).json({
          success: false,
          error: 'ORDER_CANCELLED',
          cancelled: true,
          cancel_reason: existing.cancel_reason || 'Customer cancelled the order',
          cancelled_by: existing.cancelled_by || 'customer',
          message: `Order #${order_id} was cancelled by the customer. Reason: ${existing.cancel_reason || 'Customer cancelled the order'}`
        });
      }
    }

    // 🛑 STRICT DISPATCH GUARD: Ensure only the currently assigned partner can accept
    if (existing && existing.status === 'pending' && existing.current_assigned_partner_id) {
      if (!partnerIdsMatch(existing.current_assigned_partner_id, resolvedPartnerId)) {
        console.warn(`⚠️ Order ${order_id} accept blocked: Assigned to ${existing.current_assigned_partner_id}, but accept attempted by ${resolvedPartnerId}`);
        return res.status(403).json({
          success: false,
          error: 'ORDER_ASSIGNED_TO_ANOTHER_PARTNER',
          message: 'This order is currently offered to the nearest delivery partner.'
        });
      }
    }

    const order = await Order.findOneAndUpdate(
      { order_id, status: { $in: ['pending', 'accepted', 'purchasing_food'] } },
      {
        partner_id: resolvedPartnerId,
        partner_name: actualPartnerName,
        partner_phone: actualPartnerPhone,
        partner_profile_picture: partnerPhotoUrl,
        partner_photo_url: partnerPhotoUrl,
        status: 'accepted',
        bill_confirmed: false,
        bill_image_url: null,
        bill_images: [],
        accepted_at: new Date(),
        assignment_expires_at: null
      },
      { returnDocument: 'after' }
    );

    if (!order) {
      return res.status(400).json({
        success: false,
        error: 'ORDER_NOT_AVAILABLE',
        message: 'Order not found or has already been accepted by another delivery partner.'
      });
    }

    // Update assignment history status to accepted
    if (order.assignment_history && order.assignment_history.length > 0) {
      for (let i = order.assignment_history.length - 1; i >= 0; i--) {
        if (partnerIdsMatch(order.assignment_history[i].partner_id, resolvedPartnerId)) {
          order.assignment_history[i].status = 'accepted';
          order.assignment_history[i].responded_at = new Date();
          break;
        }
      }
      await order.save();
    }

    // Update partner's LiveLocation in MongoDB so status is 'delivering'
    try {
      const LiveLocation = require('../models/LiveLocation');
      await LiveLocation.updateMany(
        { partner_id: resolvedPartnerId },
        { status: 'delivering', order_id: order.order_id }
      );
    } catch (_) {}

    // Save notification in DB for customer
    try {
      const Notification = require('../models/Notification');
      const { getNextSequence } = require('../models/Counter');
      const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
      await Notification.create({
        notification_id: notifId,
        recipient_id: order.user_id || 'customer',
        recipient_type: 'customer',
        order_id: order.order_id,
        title: '🎉 Delivery Partner Assigned!',
        message: `${actualPartnerName} has accepted your order #${order.order_id} and is heading to the store.`
      });
    } catch (notifErr) {
      console.error('Error saving accepted notification in DB:', notifErr.message);
    }

    const orderObj = await enrichOrderWithPartner(order.toObject(), req);
    res.json({ success: true, message: 'Order accepted successfully', order: orderObj });
  } catch (err) {
    console.error('Error accepting order:', err);
    res.status(500).json({ error: 'Failed to accept order' });
  }
});

// POST /api/order/price-range/send - Delivery partner sends estimated price range acknowledgement to customer
router.post('/price-range/send', async (req, res) => {
  try {
    const { order_id, price_range } = req.body;
    if (!order_id || !price_range) {
      return res.status(400).json({ error: 'order_id and price_range are required' });
    }

    const rawId = order_id.toString().trim();
    const order = await Order.findOneAndUpdate(
      {
        $or: [
          { order_id: rawId },
          { order_id: rawId.toUpperCase() },
          { order_id: new RegExp(`^${rawId}$`, 'i') }
        ]
      },
      {
        price_range: price_range.toString().trim(),
        price_range_status: 'pending',
        price_range_sent_at: new Date()
      },
      { returnDocument: 'after' }
    );

    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const orderObj = await enrichOrderWithPartner(order.toObject(), req);
    console.log(`💰 Price range "${price_range}" sent for order ${order.order_id} by partner`);
    res.json({ success: true, message: 'Price range sent to customer successfully', order: orderObj });
  } catch (err) {
    console.error('Error sending price range:', err);
    res.status(500).json({ error: 'Failed to send price range' });
  }
});

// POST /api/order/price-range/respond - Customer accepts, finds another partner, or stops order
router.post('/price-range/respond', async (req, res) => {
  try {
    const { order_id, action } = req.body; // action: 'accept' | 'find_another' | 'stop_order' | 'reject'
    if (!order_id || !action) {
      return res.status(400).json({ error: 'order_id and action are required' });
    }

    const rawId = order_id.toString().trim();
    const actionStr = action.toString().toLowerCase().trim();

    const order = await Order.findOne({
      $or: [
        { order_id: rawId },
        { order_id: rawId.toUpperCase() },
        { order_id: new RegExp(`^${rawId}$`, 'i') }
      ]
    });

    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // 1. Customer chooses: Find Another Delivery Partner
    if (actionStr === 'find_another' || actionStr === 'reassign') {
      const currentPartnerId = order.partner_id || order.current_assigned_partner_id;
      if (currentPartnerId) {
        if (!order.declined_partners) order.declined_partners = [];
        if (!isPartnerInList(currentPartnerId, order.declined_partners)) {
          order.declined_partners.push(currentPartnerId);
        }
        order.declined_by = currentPartnerId;
        order.decline_reason = 'Customer declined price range';

        // Free current partner's LiveLocation
        try {
          const LiveLocation = require('../models/LiveLocation');
          await LiveLocation.updateMany(
            { partner_id: currentPartnerId },
            { status: 'idle', order_id: null }
          );
        } catch (_) {}
      }

      order.partner_id = null;
      order.partner_name = null;
      order.partner_phone = null;
      order.partner_profile_picture = null;
      order.partner_photo_url = null;
      order.price_range = null;
      order.price_range_status = 'none';
      order.status = 'pending';

      const nextPartner = await assignNextClosestPartner(order);
      await order.save();

      console.log(`🔄 Customer requested another partner for order ${order.order_id}. Assigned to next closest partner: ${nextPartner ? nextPartner.partner_id : 'None available'}`);
      return res.json({
        success: true,
        message: 'Order moved to next nearest delivery partner',
        reassigned_to: nextPartner ? nextPartner.partner_id : null,
        order
      });
    }

    // 2. Customer chooses: Stop Order
    if (actionStr === 'stop_order' || actionStr === 'cancel') {
      const currentPartnerId = order.partner_id || order.current_assigned_partner_id;
      if (currentPartnerId) {
        try {
          const LiveLocation = require('../models/LiveLocation');
          await LiveLocation.updateMany(
            { partner_id: currentPartnerId },
            { status: 'idle', order_id: null }
          );
        } catch (_) {}
      }

      order.status = 'cancelled';
      order.cancel_reason = 'Cancelled by customer - Price range declined';
      order.cancelled_by = 'customer';
      order.cancelled_at = new Date();
      order.price_range_status = 'rejected';
      await order.save();

      if (currentPartnerId) {
        try {
          const Notification = require('../models/Notification');
          const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
          await Notification.create({
            notification_id: notifId,
            recipient_id: currentPartnerId,
            recipient_type: 'partner',
            order_id: order.order_id,
            title: '🚨 Order Cancelled by Customer',
            message: `Order #${order.order_id} was cancelled by customer. Reason: Price range declined`
          });
        } catch (notifErr) {
          console.error('Error saving cancel notification in DB:', notifErr.message);
        }
      }

      console.log(`❌ Order ${order.order_id} stopped by customer during price range acknowledgement`);
      return res.json({
        success: true,
        message: 'Order stopped and cancelled successfully',
        order
      });
    }

    // 3. Customer chooses: Accept — Lock delivery fee from partner's current GPS (hotel location) to customer
    const isAccepted = (actionStr === 'accept');
    order.price_range_status = isAccepted ? 'accepted' : 'rejected';
    order.price_range_accepted_at = new Date();

    if (isAccepted) {
      order.status = 'purchasing_food';

      // 🔒 DELIVERY FEE LOCK: Snapshot partner GPS at hotel → calculate distance to customer → lock fee
      // This runs ONLY once when customer clicks Proceed to Pay. Fee never changes after this point.
      try {
        const partnerId = order.partner_id || order.current_assigned_partner_id;
        if (partnerId) {
          const partnerLoc = await LiveLocation.findOne({ partner_id: partnerId }).lean();
          if (partnerLoc && partnerLoc.latitude != null && partnerLoc.longitude != null) {
            const pLat = Number(partnerLoc.latitude);
            const pLng = Number(partnerLoc.longitude);
            const cLat = Number(order.customer_latitude);
            const cLng = Number(order.customer_longitude);

            if (!isNaN(pLat) && !isNaN(pLng) && !isNaN(cLat) && !isNaN(cLng)) {
              const { calculateDistanceKm } = require('../services/orderDispatchService');
              const distanceKm = calculateDistanceKm(pLat, pLng, cLat, cLng);
              const fee = calculateDeliveryFee(distanceKm);

              // Lock the fee — store partner snapshot + fee in order
              order.delivery_fee = fee;
              order.delivery_fee_distance_km = distanceKm;
              order.delivery_fee_locked_at = new Date();
              order.partner_hotel_latitude  = pLat;
              order.partner_hotel_longitude = pLng;
              order.grand_total = (order.item_total || 0) + (order.tip_amount || 0) + fee;

              console.log(`💰 [Delivery Fee] Order ${order.order_id}: Partner at hotel (${pLat},${pLng}) → Customer (${cLat},${cLng}) = ${distanceKm}km → Fee: ₹${fee} | Grand Total: ₹${order.grand_total}`);
            }
          } else {
            // Partner GPS not available — apply minimum fee
            order.delivery_fee = 20;
            order.grand_total = (order.item_total || 0) + (order.tip_amount || 0) + 20;
            console.log(`⚠️ [Delivery Fee] Order ${order.order_id}: Partner GPS unavailable, applying minimum fee ₹20`);
          }
        }
      } catch (feeErr) {
        console.error('Delivery fee calculation error:', feeErr.message);
        // Don't block the accept — just log and continue without fee update
      }
    }

    await order.save();

    const orderObj = await enrichOrderWithPartner(order.toObject(), req);
    console.log(`✅ Customer ${actionStr}ed price range for order ${order.order_id}`);
    res.json({ success: true, message: `Price range ${actionStr}ed successfully`, order: orderObj });
  } catch (err) {
    console.error('Error responding to price range:', err);
    res.status(500).json({ error: 'Failed to respond to price range' });
  }
});

// POST /api/order/checklist/update - Delivery partner updates items checklist in real-time
router.post('/checklist/update', async (req, res) => {
  try {
    const { order_id, items } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }
    const rawId = order_id.toString().trim();
    const order = await Order.findOne({
      $or: [
        { order_id: rawId },
        { order_id: rawId.toUpperCase() },
        { order_id: new RegExp(`^${rawId}$`, 'i') }
      ]
    });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    if (Array.isArray(items)) {
      order.items = items.map(it => ({
        name: (it.name || 'Food Item').toString(),
        quantity: Math.max(1, parseInt(it.quantity) || 1),
        price: Math.max(0, parseFloat(it.price) || 0),
        is_collected: Boolean(it.is_collected ?? it.isCollected)
      }));
      const totalItemQty = order.items.reduce((sum, it) => sum + (it.quantity || 1), 0);
      if (totalItemQty > 0) {
        order.quantity = totalItemQty;
      }
      await order.save();
    }

    const orderObj = await enrichOrderWithPartner(order.toObject(), req);
    res.json({ success: true, message: 'Checklist updated successfully', items: order.items, order: orderObj });
  } catch (err) {
    console.error('Error updating checklist:', err);
    res.status(500).json({ error: 'Failed to update checklist', details: err.message });
  }
});

// POST /api/order/decline - Partner declines an incoming order; automatically forwards/reassigns to next closest partner
router.post('/decline', async (req, res) => {
  try {
    const { order_id, decline_reason, partner_id } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    const order = await Order.findOne({ order_id });
    if (!order) return res.status(404).json({ error: 'Order not found' });

    if (order.status !== 'pending') {
      return res.json({
        success: true,
        message: `Order is not pending (current status: ${order.status})`,
        order
      });
    }

    const pId = (partner_id || 'DP001').toString().trim();
    if (!order.declined_partners) order.declined_partners = [];
    if (!isPartnerInList(pId, order.declined_partners)) {
      order.declined_partners.push(pId);
    }
    if (order.current_assigned_partner_id && partnerIdsMatch(order.current_assigned_partner_id, pId)) {
      if (!isPartnerInList(order.current_assigned_partner_id, order.declined_partners)) {
        order.declined_partners.push(order.current_assigned_partner_id);
      }
    }
    try {
      const numPart = pId.replace(/[^0-9]/g, '');
      const numClean = numPart.replace(/^0+/, '');
      const pRegex = new RegExp(`^(dp_?0*)?${numClean || numPart}$`, 'i');
      const dpDoc = await DeliveryPerson.findOne({
        $or: [{ DP_id: pId }, { DP_id: pRegex }, { mobile_number: pId }]
      }).select('DP_id').lean();
      if (dpDoc && dpDoc.DP_id && !isPartnerInList(dpDoc.DP_id, order.declined_partners)) {
        order.declined_partners.push(dpDoc.DP_id);
      }
    } catch (_) {}
    order.declined_by = pId;
    order.decline_reason = decline_reason || 'Partner declined';

    // Mark current partner offer in history as declined
    if (order.assignment_history && order.assignment_history.length > 0) {
      for (let i = order.assignment_history.length - 1; i >= 0; i--) {
        if (partnerIdsMatch(order.assignment_history[i].partner_id, pId) && order.assignment_history[i].status === 'offered') {
          order.assignment_history[i].status = 'declined';
          order.assignment_history[i].responded_at = new Date();
          order.assignment_history[i].decline_reason = decline_reason || 'Declined by partner';
          break;
        }
      }
    }

    // Immediately route and reassign to the next closest available partner to CUSTOMER LOCATION
    const nextPartner = await assignNextClosestPartner(order, order.customer_latitude, order.customer_longitude);
    await order.save();

    console.log(`🚴 Order ${order_id} declined by ${pId}. Automatically reassigned to next closest partner to customer: ${nextPartner ? nextPartner.partner_id : 'None available'}`);

    res.json({
      success: true,
      message: 'Order declined successfully and routed to next closest partner',
      reassigned_to: nextPartner ? nextPartner.partner_id : null,
      order
    });
  } catch (err) {
    console.error('Error declining order:', err);
    res.status(500).json({ error: 'Failed to decline order' });
  }
});

// POST /api/order/update-status - Update order lifecycle status
router.post('/update-status', async (req, res) => {
  try {
    const { order_id, status, grand_total, tip_amount, item_total, cod_otp, payment_method, payment_status, partner_id, partner_name, partner_phone, partner_profile_picture } = req.body;
    const updateData = {};
    if (status) updateData.status = status;
    if (status === 'picked_up') updateData.picked_up_at = new Date();
    if (status === 'delivered') updateData.delivered_at = new Date();
    if (grand_total !== undefined) updateData.grand_total = Number(grand_total);
    if (tip_amount !== undefined) updateData.tip_amount = Number(tip_amount);
    if (item_total !== undefined) updateData.item_total = Number(item_total);
    if (cod_otp) updateData.cod_otp = cod_otp;
    if (payment_method) updateData.payment_method = payment_method;
    if (payment_status) updateData.payment_status = payment_status;
    if (partner_id) updateData.partner_id = partner_id;
    if (partner_name && partner_name !== 'Delivery Partner') updateData.partner_name = partner_name;
    if (partner_phone) updateData.partner_phone = partner_phone;
    if (partner_profile_picture) updateData.partner_profile_picture = partner_profile_picture;

    const existing = await Order.findOne({ order_id });
    if (!existing) return res.status(404).json({ error: 'Order not found' });
    if (existing.status === 'cancelled') {
      return res.status(400).json({
        error: 'ORDER_CANCELLED',
        cancelled: true,
        cancel_reason: existing.cancel_reason || 'Order was cancelled by customer',
        message: 'Order was cancelled by customer'
      });
    }

    const order = await Order.findOneAndUpdate(
      { order_id, status: { $ne: 'cancelled' } },
      updateData,
      { returnDocument: 'after' }
    );

    if (!order) return res.status(404).json({ error: 'Order not found or was cancelled' });

    if (status === 'delivered') {
      try {
        const LiveLocation = require('../models/LiveLocation');
        if (order.partner_id) {
          await LiveLocation.updateMany(
            { partner_id: order.partner_id },
            { status: 'idle', order_id: null }
          );
        }
        const Notification = require('../models/Notification');
        if (order.user_id) {
          const notifIdCust = await getNextSequence('notification_id', 'NOTIF-', 4);
          await Notification.create({
            notification_id: notifIdCust,
            recipient_id: order.user_id,
            recipient_type: 'customer',
            order_id: order.order_id,
            title: '🎉 Order Delivered!',
            message: `Your order #${order.order_id} has been delivered successfully. Enjoy your food! Thank you for ordering with GETMYE.`
          });
        }
        if (order.partner_id) {
          const notifIdPartner = await getNextSequence('notification_id', 'NOTIF-', 4);
          await Notification.create({
            notification_id: notifIdPartner,
            recipient_id: order.partner_id,
            recipient_type: 'partner',
            order_id: order.order_id,
            title: '✅ Delivery Completed!',
            message: `Great job! Order #${order.order_id} has been delivered successfully.`
          });
        }

        // Notify any waiting customers who couldn't get a delivery partner earlier
        notifyWaitingCustomersThatPartnerIsAvailable().catch(e => console.warn('Notification trigger warn:', e.message));
      } catch (notifErr) {
        console.error('Error creating delivered notifications in update-status:', notifErr.message);
      }
    }

    res.json({ success: true, order });
  } catch (err) {
    console.error('Error updating order status:', err);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

// POST /api/order/verify-delivery-otp - Partner enters customer OTP (COD or Online) to complete delivery
router.post('/verify-delivery-otp', async (req, res) => {
  try {
    const { order_id, entered_otp } = req.body;
    if (!order_id || !entered_otp) {
      return res.status(400).json({ error: 'order_id and entered_otp are required' });
    }

    const order = await Order.findOne({ order_id });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    if (order.cod_otp && order.cod_otp.toString().trim() !== entered_otp.toString().trim()) {
      return res.status(400).json({ success: false, error: 'Incorrect delivery OTP' });
    }

    order.status = 'delivered';
    order.delivered_at = new Date();
    order.payment_status = 'success';
    await order.save();

    // Release partner's LiveLocation to idle
    try {
      if (order.partner_id) {
        const LiveLocation = require('../models/LiveLocation');
        await LiveLocation.updateMany(
          { partner_id: order.partner_id },
          { status: 'idle', order_id: null }
        );
      }
    } catch (_) {}

    // Create notifications for BOTH customer and delivery partner in DB
    try {
      const Notification = require('../models/Notification');
      if (order.user_id) {
        const notifIdCust = await getNextSequence('notification_id', 'NOTIF-', 4);
        await Notification.create({
          notification_id: notifIdCust,
          recipient_id: order.user_id,
          recipient_type: 'customer',
          order_id: order.order_id,
          title: '🎉 Order Delivered!',
          message: `Your order #${order.order_id} has been delivered successfully. Enjoy your food! Thank you for ordering with GETMYE.`
        });
      }
      if (order.partner_id) {
        const notifIdPartner = await getNextSequence('notification_id', 'NOTIF-', 4);
        await Notification.create({
          notification_id: notifIdPartner,
          recipient_id: order.partner_id,
          recipient_type: 'partner',
          order_id: order.order_id,
          title: '✅ Delivery Completed!',
          message: `Great job! Order #${order.order_id} has been delivered successfully.`
        });
      }
    } catch (notifErr) {
      console.error('Error saving delivered notification in DB:', notifErr.message);
    }

    // Notify any waiting customers who couldn't get a delivery partner earlier
    try {
      notifyWaitingCustomersThatPartnerIsAvailable().catch(e => console.warn('Notification trigger warn:', e.message));
    } catch (_) {}

    res.json({ success: true, message: 'OTP verified successfully! Order delivered.', order });
  } catch (err) {
    console.error('Error verifying delivery OTP:', err);
    res.status(500).json({ error: 'Failed to verify OTP' });
  }
});

// GET /api/order/user/:user_id - Get paginated orders for a customer (order history)
router.get('/user/:user_id', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const skip = (page - 1) * limit;

    const query = { user_id: req.params.user_id };
    const orders = await Order.find(query)
      .sort({ created_at: -1 })
      .skip(skip)
      .limit(limit)
      .lean();
    const total = await Order.countDocuments(query);
    res.json({ success: true, page, limit, total, count: orders.length, orders });
  } catch (err) {
    console.error('Error fetching customer orders:', err);
    res.status(500).json({ error: 'Failed to fetch customer orders' });
  }
});

// POST /api/order/arrived-at-location - Delivery partner arrives at customer location (starts 15-minute wait timer)
router.post('/arrived-at-location', async (req, res) => {
  try {
    const { order_id, partner_id } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    const orderIdStr = order_id.toString().trim();
    let order = await Order.findOne({
      $or: [
        { order_id: orderIdStr },
        { order_id: new RegExp(`^${orderIdStr}$`, 'i') }
      ]
    });

    if (!order) return res.status(404).json({ error: 'Order not found' });

    // Record arrival timestamp if not already recorded
    if (!order.arrived_at_customer_at) {
      order.arrived_at_customer_at = new Date();
      await order.save();
      console.log(`📍 Delivery partner ${partner_id || order.partner_id} arrived at customer location for order #${order.order_id} at ${order.arrived_at_customer_at}`);
    }

    const elapsedMs = Date.now() - new Date(order.arrived_at_customer_at).getTime();
    const CUSTOMER_WAIT_MINUTES = parseInt(process.env.CUSTOMER_WAIT_MINUTES || '15', 10);
    const requiredMs = CUSTOMER_WAIT_MINUTES * 60 * 1000; // wait duration (15 minutes)
    const remainingSec = Math.max(0, Math.ceil((requiredMs - elapsedMs) / 1000));
    const canCancel = remainingSec === 0;

    res.json({
      success: true,
      order_id: order.order_id,
      arrived_at: order.arrived_at_customer_at,
      can_cancel: canCancel,
      seconds_remaining: remainingSec,
      elapsed_seconds: Math.floor(elapsedMs / 1000)
    });
  } catch (err) {
    console.error('Error marking arrival at customer location:', err);
    res.status(500).json({ error: 'Failed to record arrival time: ' + err.message });
  }
});

// POST /api/order/cancel - Customer or delivery partner cancels an active order
router.post('/cancel', async (req, res) => {
  try {
    const { order_id, cancel_reason, cancelled_by } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    const defaultReason = cancelled_by === 'partner'
      ? 'Customer unavailable'
      : 'Cancelled by customer';

    const orderIdStr = order_id.toString().trim();
    const existing = await Order.findOne({
      $or: [
        { order_id: orderIdStr },
        { order_id: new RegExp(`^${orderIdStr}$`, 'i') }
      ]
    });

    if (!existing) return res.status(404).json({ error: 'Order not found' });

    if (existing.status === 'delivered' || existing.status === 'completed') {
      return res.status(400).json({ error: 'Order is already delivered and cannot be cancelled.' });
    }
    if (existing.status === 'cancelled') {
      return res.status(400).json({ error: 'Order is already cancelled.' });
    }

    // Backend validation: Delivery partner can ONLY cancel after waiting required minutes at customer location
    if (cancelled_by === 'partner') {
      const CUSTOMER_WAIT_MINUTES = parseInt(process.env.CUSTOMER_WAIT_MINUTES || '15', 10);
      const requiredMs = CUSTOMER_WAIT_MINUTES * 60 * 1000;

      if (!existing.arrived_at_customer_at) {
        return res.status(400).json({
          error: `Delivery partner must wait at customer location for ${CUSTOMER_WAIT_MINUTES} minutes before cancelling.`,
          can_cancel: false,
          seconds_remaining: CUSTOMER_WAIT_MINUTES * 60
        });
      }

      const elapsedMs = Date.now() - new Date(existing.arrived_at_customer_at).getTime();
      if (elapsedMs < requiredMs) {
        const remainingSec = Math.ceil((requiredMs - elapsedMs) / 1000);
        const remainingMins = Math.ceil(remainingSec / 60);
        console.log(`⚠️ Partner cancel rejected: ${remainingSec}s remaining of ${CUSTOMER_WAIT_MINUTES}m timer for order ${order_id}`);
        return res.status(400).json({
          error: `Cannot cancel yet. Customer waiting time remaining: ${remainingMins} minute(s).`,
          can_cancel: false,
          seconds_remaining: remainingSec
        });
      }
    }

    existing.status = 'cancelled';
    existing.cancel_reason = cancel_reason || defaultReason;
    existing.cancelled_by = cancelled_by || 'customer';
    existing.cancelled_at = new Date();
    await existing.save();

    console.log(`❌ Order ${order_id} cancelled by ${cancelled_by || 'customer'}: ${cancel_reason || defaultReason}`);

    // Free the delivery partner so they immediately become available to accept new incoming orders
    try {
      const partnerIdToFree = existing.partner_id || existing.current_assigned_partner_id;
      if (partnerIdToFree) {
        const LiveLocation = require('../models/LiveLocation');
        await LiveLocation.updateMany(
          { partner_id: partnerIdToFree },
          { status: 'idle', order_id: null, is_online: true }
        );
        const DeliveryPerson = require('../models/DeliveryPerson');
        await DeliveryPerson.findOneAndUpdate(
          { DP_id: partnerIdToFree },
          { dp_status: 'online' }
        );
      }
    } catch (freeErr) {
      console.warn('Error releasing partner on cancel:', freeErr.message);
    }

    // Create notification in DB for customer if cancelled by partner
    try {
      const Notification = require('../models/Notification');
      if (cancelled_by === 'partner' && existing.user_id) {
        const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
        await Notification.create({
          notification_id: notifId,
          recipient_id: existing.user_id,
          recipient_type: 'customer',
          order_id: existing.order_id,
          title: '🚨 Order Cancelled: Customer Unavailable',
          message: `Delivery partner waited 15 minutes at delivery location. Order #${existing.order_id} was cancelled because customer was unavailable.`
        });
      } else {
        const targetPartner = existing.partner_id || existing.current_assigned_partner_id;
        if (targetPartner) {
          const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
          await Notification.create({
            notification_id: notifId,
            recipient_id: targetPartner,
            recipient_type: 'partner',
            order_id: existing.order_id,
            title: '🚨 Order Cancelled by Customer',
            message: `Order #${existing.order_id} was cancelled by customer. Reason: ${cancel_reason || defaultReason}`
          });
        }
      }
    } catch (notifErr) {
      console.error('Error saving cancel notification in DB:', notifErr.message);
    }

    res.json({
      success: true,
      message: 'Order cancelled successfully',
      order: existing
    });
  } catch (err) {
    console.error('Error cancelling order:', err);
    res.status(500).json({ error: 'Failed to cancel order' });
  }
});

// GET /api/order/partner/:partner_id - Get all orders handled by delivery partner (delivery history)
// GET /api/order/partner/:partner_id - Get all orders handled by delivery partner (delivery history) with pagination
router.get('/partner/:partner_id', async (req, res) => {
  try {
    const partnerId = (req.params.partner_id || '').trim();
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 50));
    const skip = (page - 1) * limit;

    // Build resilient query strictly for this partner
    let query;
    if (!partnerId || partnerId === 'all') {
      query = { status: { $in: ['delivered', 'cancelled', 'in_transit', 'picked_up', 'bill_sent', 'purchasing_food', 'accepted'] } };
    } else {
      query = {
        $or: [
          { partner_id: partnerId },
          { partner_id: new RegExp(`^${partnerId}$`, 'i') }
        ]
      };
    }

    // High performance projection: select only lightweight metadata fields (skip massive base64 images)
    const projection = 'order_id user_id customer_name customer_phone delivery_address item_name quantity budget partner_id partner_name partner_phone status decline_reason delivery_fee item_total tip_amount grand_total payment_method payment_status cancel_reason accepted_at picked_up_at delivered_at cod_otp price_range price_range_status created_at updated_at items';

    let orders = await Order.find(query)
      .select(projection)
      .sort({ _id: -1 })
      .skip(skip)
      .limit(limit)
      .allowDiskUse(true)
      .lean();

    const total = await Order.countDocuments(query);
    res.json({
      success: true,
      page,
      limit,
      total: Math.max(total, orders.length),
      count: orders.length,
      orders
    });
  } catch (err) {
    console.error('Error fetching partner orders:', err);
    res.status(500).json({ error: 'Failed to fetch partner orders', message: err.message });
  }
});

// GET /api/order/:order_id & /api/order/details/:order_id - Get specific order (fast lightweight query with partner enrichment)
const handleGetOrder = async (req, res) => {
  try {
    const rawId = (req.params.order_id || '').toString().trim();
    const order = await Order.findOne({
      $or: [
        { order_id: rawId },
        { order_id: rawId.toUpperCase() },
        { order_id: new RegExp(`^${rawId}$`, 'i') }
      ]
    })
      .lean();
    if (!order) return res.status(404).json({ error: 'Order not found' });
    const enrichedOrder = await enrichOrderWithPartner(order, req);
    let partnerStats = null;
    try {
      partnerStats = await getPartnerAvailabilityStats();
    } catch (_) {}
    res.json({ success: true, order: enrichedOrder, partner_stats: partnerStats });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch order' });
  }
};
router.get('/details/:order_id', handleGetOrder);
router.get('/:order_id', handleGetOrder);

// POST /api/order/:order_id/message & /api/order/details/:order_id/message - Send chat message for an active order
const handlePostOrderMessage = async (req, res) => {
  try {
    const { sender, sender_name, text, time } = req.body;
    if (!sender || !text) {
      return res.status(400).json({ error: 'sender and text are required' });
    }
    const rawId = (req.params.order_id || '').toString().trim();
    const order = await Order.findOne({
      $or: [
        { order_id: rawId },
        { order_id: rawId.toUpperCase() },
        { order_id: new RegExp(`^${rawId}$`, 'i') }
      ]
    });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }
    const newMsg = {
      sender,
      sender_name: sender_name || (sender === 'customer' ? order.customer_name : (order.partner_name || 'Delivery Partner')),
      text,
      time: time || new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      timestamp: new Date()
    };
    if (!order.messages) order.messages = [];
    order.messages.push(newMsg);
    await order.save();
    res.json({ success: true, message: newMsg, messages: order.messages });
  } catch (err) {
    console.error('Error posting order message:', err);
    res.status(500).json({ error: 'Failed to post message' });
  }
};
router.post('/details/:order_id/message', handlePostOrderMessage);
router.post('/:order_id/message', handlePostOrderMessage);

// GET /api/order/:order_id/messages & /api/order/details/:order_id/messages - Get all messages for this order
const handleGetOrderMessages = async (req, res) => {
  try {
    const rawId = (req.params.order_id || '').toString().trim();
    const order = await Order.findOne({
      $or: [
        { order_id: rawId },
        { order_id: rawId.toUpperCase() },
        { order_id: new RegExp(`^${rawId}$`, 'i') }
      ]
    });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }
    res.json({ success: true, messages: order.messages || [] });
  } catch (err) {
    console.error('Error fetching order messages:', err);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
};
router.get('/details/:order_id/messages', handleGetOrderMessages);
router.get('/:order_id/messages', handleGetOrderMessages);

// GET /api/order/admin/all - Comprehensive orders list for Admin Portal
router.get('/admin/all', async (req, res) => {
  try {
    const { status, limit = 200, timeframe } = req.query;
    const filter = {};

    if (timeframe === 'today') {
      const startOfToday = new Date();
      startOfToday.setHours(0, 0, 0, 0);
      filter.created_at = { $gte: startOfToday };
    }

    if (status && status !== 'all') {
      if (status === 'remaining' || status === 'active_pending') {
        filter.status = { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] };
      } else {
        filter.status = status;
      }
    }

    const orders = await Order.find(filter)
      .sort({ created_at: -1 })
      .limit(Number(limit))
      .lean();

    res.json({
      success: true,
      count: orders.length,
      orders
    });
  } catch (err) {
    console.error('Error fetching admin orders:', err);
    res.status(500).json({ error: 'Failed to fetch orders', details: err.message });
  }
});

// GET /api/order/admin/overview - Real-time statistics for Admin Dashboard
router.get('/admin/overview', async (req, res) => {
  try {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    // Active fleet heartbeat cutoff: 30 minutes
    const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

    const [
      totalOrdersToday,
      todayRemainingOrders,
      todayDeliveredOrders,
      todayCancelledOrders,
      totalOrdersAllTime,
      pendingOrders,
      activeOrders,
      completedOrders,
      cancelledOrders,
      pendingKYCCount,
      liveOnlineLocations
    ] = await Promise.all([
      Order.countDocuments({ created_at: { $gte: startOfToday } }),
      Order.countDocuments({
        created_at: { $gte: startOfToday },
        status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
      }),
      Order.countDocuments({ created_at: { $gte: startOfToday }, status: 'delivered' }),
      Order.countDocuments({ created_at: { $gte: startOfToday }, status: 'cancelled' }),
      Order.countDocuments({ status: { $ne: 'cancelled' } }),
      Order.countDocuments({ status: 'pending' }),
      Order.countDocuments({ status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] } }),
      Order.countDocuments({ status: 'delivered' }),
      Order.countDocuments({ status: 'cancelled' }),
      DeliveryPerson.countDocuments({ know_your_partner_status: 'pending' }),
      LiveLocation.find({
        is_online: true,
        last_updated: { $gte: thirtyMinutesAgo }
      }).select('partner_id').lean()
    ]);

    // Accurate active fleet: ONLY count partners who sent a live heartbeat AND have approved KYC
    const activePartnerIds = (liveOnlineLocations || []).map(l => l.partner_id).filter(Boolean);
    let onlinePartners = 0;
    if (activePartnerIds.length > 0) {
      onlinePartners = await DeliveryPerson.countDocuments({
        know_your_partner_status: { $in: ['approved', 'completed'] },
        dp_status: { $regex: /^online$/i },
        $or: [
          { DP_id: { $in: activePartnerIds } },
          { mobile_number: { $in: activePartnerIds } }
        ]
      });
    }

    // Aggregate today's gross revenue
    const revenueAgg = await Order.aggregate([
      { $match: { created_at: { $gte: startOfToday }, status: { $ne: 'cancelled' } } },
      { $group: { _id: null, total: { $sum: '$grand_total' } } }
    ]);
    const todayRevenue = (revenueAgg[0] && revenueAgg[0].total) ? revenueAgg[0].total : 0;

    // Aggregate all-time gross revenue
    const totalRevenueAgg = await Order.aggregate([
      { $match: { status: { $ne: 'cancelled' } } },
      { $group: { _id: null, total: { $sum: '$grand_total' } } }
    ]);
    const totalRevenueAllTime = (totalRevenueAgg[0] && totalRevenueAgg[0].total) ? totalRevenueAgg[0].total : 0;

    res.json({
      success: true,
      today_orders: totalOrdersToday,
      today_remaining_orders: todayRemainingOrders,
      today_delivered_orders: todayDeliveredOrders,
      today_cancelled_orders: todayCancelledOrders,
      total_orders_all_time: totalOrdersAllTime,
      pending_orders: pendingOrders,
      active_orders: activeOrders,
      completed_orders: completedOrders,
      cancelled_orders: cancelledOrders,
      today_revenue: todayRevenue,
      total_revenue_all_time: totalRevenueAllTime,
      online_partners: onlinePartners,
      pending_kyc: pendingKYCCount
    });
  } catch (err) {
    console.error('Error fetching admin overview:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/order/admin/active-fleet - Real-time list of verified online delivery partners
router.get('/admin/active-fleet', async (req, res) => {
  try {
    const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
    const liveOnlineLocations = await LiveLocation.find({
      is_online: true,
      last_updated: { $gte: thirtyMinutesAgo }
    }).select('partner_id status last_updated latitude longitude').lean();

    const activePartnerIds = (liveOnlineLocations || []).map(l => l.partner_id).filter(Boolean);
    if (activePartnerIds.length === 0) {
      return res.json({ success: true, count: 0, fleet: [] });
    }

    const verifiedPartners = await DeliveryPerson.find({
      know_your_partner_status: { $in: ['approved', 'completed'] },
      dp_status: { $regex: /^online$/i },
      $or: [
        { DP_id: { $in: activePartnerIds } },
        { mobile_number: { $in: activePartnerIds } }
      ]
    }).select('DP_id name mobile_number email dp_status know_your_partner_status').lean();

    const fleet = verifiedPartners.map(p => {
      const loc = liveOnlineLocations.find(l => l.partner_id === p.DP_id || l.partner_id === p.mobile_number);
      return {
        dp_id: p.DP_id,
        name: p.name,
        mobile_number: p.mobile_number,
        live_status: loc?.status || 'idle',
        last_updated: loc?.last_updated || null,
        latitude: loc?.latitude || null,
        longitude: loc?.longitude || null
      };
    });

    res.json({ success: true, count: fleet.length, fleet });
  } catch (err) {
    console.error('Error fetching active fleet:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/order/debug/list-all - Inspect all recent orders for diagnostics
router.get('/debug/list-all', async (req, res) => {
  try {
    const orders = await Order.find({}).select('order_id user_id customer_name customer_phone status partner_id partner_name customer_latitude customer_longitude created_at updated_at').sort({ created_at: -1 }).limit(20);
    const LiveLocation = require('../models/LiveLocation');
    const locations = await LiveLocation.find({}).select('partner_id is_online status latitude longitude');
    const dps = await DeliveryPerson.find({}).select('DP_id name mobile_number dp_status');
    res.json({
      success: true,
      orders,
      locations,
      delivery_persons: dps
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/order/debug/reset-all - Cancel all stuck/abandoned test orders
router.post('/debug/reset-all', async (req, res) => {
  try {
    const result = await Order.updateMany(
      { status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] } },
      { status: 'cancelled', cancel_reason: 'Admin test cleanup', cancelled_at: new Date() }
    );
    const LiveLocation = require('../models/LiveLocation');
    await LiveLocation.updateMany({}, { is_online: true, status: 'idle' });
    await DeliveryPerson.updateMany({}, { dp_status: 'online' });
    res.json({ success: true, message: 'All stuck test orders cancelled', modifiedCount: result.modifiedCount });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/order/waiting-customer - Register customer when no delivery partner is available
router.post('/waiting-customer', async (req, res) => {
  try {
    const { user_id, customer_name, customer_phone, reason, order_id } = req.body;
    if (!user_id && !customer_phone) {
      return res.status(400).json({ error: 'user_id or customer_phone is required' });
    }
    const updatePayload = {
      user_id: user_id || '',
      customer_name: customer_name || 'Customer',
      customer_phone: customer_phone || '',
      reason: reason || 'no_partner_available',
      order_id: order_id || '',
      requested_at: new Date(),
      notified: false
    };

    const record = await WaitingCustomer.findOneAndUpdate(
      {
        $or: [
          ...(user_id ? [{ user_id }] : []),
          ...(customer_phone ? [{ customer_phone }] : [])
        ],
        notified: false
      },
      updatePayload,
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    console.log(`📝 Saved unserved customer waiting notification entry for user: ${user_id || customer_phone} (reason: ${reason})`);
    res.json({ success: true, waiting_customer: record });
  } catch (err) {
    console.error('Error saving waiting customer:', err);
    res.status(500).json({ error: 'Failed to save waiting customer' });
  }
});

// GET /api/order/notifications/:user_id - Get unread customer notifications (e.g., partner now online)
router.get('/notifications/:user_id', async (req, res) => {
  try {
    const Notification = require('../models/Notification');
    const { user_id } = req.params;
    const notifs = await Notification.find({
      recipient_id: user_id,
      recipient_type: 'customer',
      is_read: false
    }).sort({ created_at: -1 }).limit(10);
    res.json({ success: true, notifications: notifs || [] });
  } catch (err) {
    console.error('Error fetching customer notifications:', err);
    res.status(500).json({ error: 'Failed to get notifications' });
  }
});

// POST /api/order/notifications/mark-read - Mark customer notifications as read
router.post('/notifications/mark-read', async (req, res) => {
  try {
    const Notification = require('../models/Notification');
    const { notification_ids, user_id } = req.body;
    if (notification_ids && Array.isArray(notification_ids) && notification_ids.length > 0) {
      await Notification.updateMany(
        { notification_id: { $in: notification_ids } },
        { is_read: true }
      );
    } else if (user_id) {
      await Notification.updateMany(
        { recipient_id: user_id, recipient_type: 'customer' },
        { is_read: true }
      );
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Error marking notifications as read:', err);
    res.status(500).json({ error: 'Failed to mark notifications read' });
  }
});

module.exports = router;

