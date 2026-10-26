const express = require('express');
const router = express.Router();
const Order = require('../models/Order');
const Profile = require('../models/Profile');
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');
const {
  KUMBAKONAM_GEOFENCE,
  isWithinKumbakonam,
  partnerIdsMatch,
  isPartnerInList,
  assignNextClosestPartner,
  checkAndReassignExpiredOrders
} = require('../services/orderDispatchService');

// POST /api/order/create - Customer places a new order
router.post('/create', async (req, res) => {
  try {
    const { user_id, customer_name, customer_phone, delivery_address, item_name, budget, cod_otp, customer_latitude, customer_longitude } = req.body;
    if (!user_id || !delivery_address || !item_name) {
      return res.status(400).json({ error: 'user_id, delivery_address, and item_name are required' });
    }

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

    const newOrder = new Order({
      order_id: orderId,
      user_id,
      customer_name: customer_name || 'Customer',
      customer_phone: customer_phone || '',
      delivery_address,
      item_name,
      budget: Number(budget) || 0,
      customer_latitude: finalLat,
      customer_longitude: finalLng,
      status: 'pending',
      cod_otp: finalOtp,
      bill_confirmed: false,
      bill_image_url: null,
      bill_images: [],
      declined_partners: [],
      timed_out_partners: [],
      assignment_history: []
    });

    // 2. Proximity-Based Delivery Partner Assignment: Route first to closest available partner relative to customer coordinates
    const assignedPartner = await assignNextClosestPartner(newOrder, newOrder.customer_latitude, newOrder.customer_longitude);

    await newOrder.save();
    res.status(201).json({
      success: true,
      message: 'Order created successfully and routed to closest partner',
      assigned_partner_id: assignedPartner ? assignedPartner.partner_id : null,
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

      query = {
        $or: [
          // Strictly single partner routing: Pending order must ONLY match the currently assigned partner!
          {
            status: 'pending',
            created_at: { $gte: pendingThreshold },
            current_assigned_partner_id: { $in: [partnerId, pRegex] },
            declined_partners: { $nin: [partnerId, pRegex] },
            timed_out_partners: { $nin: [partnerId, pRegex] }
          },
          // Ongoing accepted active orders for this partner
          {
            partner_id: { $in: [partnerId, pRegex] },
            status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
          },
          {
            partner_id: { $in: [partnerId, pRegex] },
            status: 'cancelled',
            cancelled_at: { $gte: cancelledThreshold }
          },
          {
            status: 'cancelled',
            cancelled_at: { $gte: cancelledThreshold }
          }
        ]
      };
    } else {
      query = {
        $or: [
          { status: 'pending', created_at: { $gte: pendingThreshold } },
          { status: 'cancelled', cancelled_at: { $gte: cancelledThreshold } }
        ]
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

    // Check if order was cancelled by customer before accepting
    const existing = await Order.findOne({
      $or: [
        { order_id },
        { order_id: new RegExp(`^${order_id}$`, 'i') }
      ]
    });
    if (existing && existing.status === 'cancelled') {
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

    // 3. Customer chooses: Accept
    const isAccepted = (actionStr === 'accept');
    order.price_range_status = isAccepted ? 'accepted' : 'rejected';
    order.price_range_accepted_at = new Date();
    if (isAccepted) {
      order.status = 'purchasing_food';
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

    const pId = (partner_id || 'DP001').toString().trim();
    if (!order.declined_partners) order.declined_partners = [];
    if (!isPartnerInList(pId, order.declined_partners)) {
      order.declined_partners.push(pId);
    }
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

    const order = await Order.findOneAndUpdate(
      { order_id },
      updateData,
      { returnDocument: 'after' }
    );

    if (!order) return res.status(404).json({ error: 'Order not found' });

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

// POST /api/order/cancel - Customer or delivery partner cancels an active order
router.post('/cancel', async (req, res) => {
  try {
    const { order_id, cancel_reason, cancelled_by } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    const defaultReason = cancelled_by === 'partner'
      ? 'Cancelled by delivery partner'
      : 'Cancelled by customer';

    // Disallow delivery partner cancellation if order has already been accepted
    if (cancelled_by === 'partner') {
      const existing = await Order.findOne({ order_id });
      if (existing) {
        const acceptedStatuses = ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit', 'delivered', 'completed'];
        if (acceptedStatuses.includes(existing.status)) {
          console.log(`⚠️ Cancellation rejected: Delivery partner cannot cancel accepted order ${order_id} (status: ${existing.status})`);
          return res.status(400).json({
            error: 'Delivery partner cannot cancel order after accepting it.',
            status: existing.status
          });
        }
      }
    }

    const orderIdStr = order_id.toString().trim();
    const order = await Order.findOneAndUpdate(
      {
        $or: [
          { order_id: orderIdStr },
          { order_id: new RegExp(`^${orderIdStr}$`, 'i') }
        ]
      },
      {
        status: 'cancelled',
        cancel_reason: cancel_reason || defaultReason,
        cancelled_by: cancelled_by || 'customer',
        cancelled_at: new Date()
      },
      { returnDocument: 'after' }
    );

    if (!order) return res.status(404).json({ error: 'Order not found' });
    console.log(`❌ Order ${order_id} cancelled by ${cancelled_by || 'customer'}: ${cancel_reason || defaultReason}`);

    // Free the partner's LiveLocation if partner was assigned
    try {
      if (order.partner_id) {
        const LiveLocation = require('../models/LiveLocation');
        await LiveLocation.updateMany(
          { partner_id: order.partner_id },
          { status: 'idle', order_id: null }
        );
      }
    } catch (_) {}

    // Create notification in DB for delivery partner if assigned or offered
    const targetPartner = order.partner_id || order.current_assigned_partner_id;
    if (targetPartner) {
      try {
        const Notification = require('../models/Notification');
        const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
        await Notification.create({
          notification_id: notifId,
          recipient_id: targetPartner,
          recipient_type: 'partner',
          order_id: order.order_id,
          title: '🚨 Order Cancelled by Customer',
          message: `Order #${order.order_id} was cancelled by customer. Reason: ${cancel_reason || defaultReason}`
        });
      } catch (notifErr) {
        console.error('Error saving cancel notification in DB:', notifErr.message);
      }
    }

    res.json({ success: true, message: 'Order cancelled successfully', order });
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
    const projection = 'order_id user_id customer_name customer_phone delivery_address item_name budget partner_id partner_name partner_phone status decline_reason delivery_fee item_total tip_amount grand_total payment_method payment_status cancel_reason accepted_at picked_up_at delivered_at cod_otp price_range price_range_status created_at updated_at';

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
    res.json({ success: true, order: enrichedOrder });
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

module.exports = router;

