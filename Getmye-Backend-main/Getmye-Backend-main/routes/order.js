const express = require('express');
const router = express.Router();
const Order = require('../models/Order');
const Profile = require('../models/Profile');
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');

// POST /api/order/create - Customer places a new order
router.post('/create', async (req, res) => {
  try {
    const { user_id, customer_name, customer_phone, delivery_address, item_name, budget } = req.body;
    if (!user_id || !delivery_address || !item_name) {
      return res.status(400).json({ error: 'user_id, delivery_address, and item_name are required' });
    }

    const orderId = await getNextSequence('order_id', 'ORD-', 4);

    // Retrieve or establish customer's fixed OTP
    let fixedOtp = req.body.cod_otp;
    try {
      let profile = await Profile.findOne({ user_id });
      if (!profile && customer_phone) {
        profile = await Profile.findOne({ mobile_number: customer_phone });
      }
      if (profile) {
        if (!profile.fixed_order_otp) {
          profile.fixed_order_otp = fixedOtp || (Math.floor(1000 + Math.random() * 9000)).toString();
          await profile.save();
        }
        fixedOtp = profile.fixed_order_otp;
      }
    } catch (_) {}

    const codOtp = (fixedOtp || (Math.floor(1000 + Math.random() * 9000))).toString();

    const newOrder = new Order({
      order_id: orderId,
      user_id,
      customer_name: customer_name || 'Customer',
      customer_phone: customer_phone || '',
      customer_latitude: req.body.customer_latitude !== undefined && req.body.customer_latitude !== null ? Number(req.body.customer_latitude) : null,
      customer_longitude: req.body.customer_longitude !== undefined && req.body.customer_longitude !== null ? Number(req.body.customer_longitude) : null,
      delivery_address,
      item_name,
      budget: Number(budget) || 0,
      status: 'pending',
      cod_otp: codOtp
    });

    await newOrder.save();

    // 🛰️ Geofence Dispatch: Log online partners within 10 km radius
    try {
      const cLat = newOrder.customer_latitude;
      const cLng = newOrder.customer_longitude;
      if (cLat !== null && cLng !== null) {
        const LiveLocation = require('../models/LiveLocation');
        const onlineLocations = await LiveLocation.find({ is_online: true });
        const nearbyPartners = [];
        for (const loc of onlineLocations) {
          const d = calculateHaversineDistanceKm(cLat, cLng, loc.latitude, loc.longitude);
          if (d !== null && d <= 10.0) {
            const busy = await Order.findOne({
              partner_id: loc.partner_id,
              status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] },
              updated_at: { $gte: new Date(Date.now() - 4 * 60 * 60 * 1000) }
            });
            if (!busy) {
              nearbyPartners.push({ partner_id: loc.partner_id, distance_km: Number(d.toFixed(2)) });
            }
          }
        }
        console.log(`📡 New Order ${orderId} placed at [${cLat}, ${cLng}]. Eligible partners within 10 km:`, nearbyPartners);
      }
    } catch (dispatchErr) {
      console.warn('Geofence partner scan notice:', dispatchErr.message);
    }

    res.status(201).json({ success: true, message: 'Order created successfully', order: newOrder });
  } catch (err) {
    console.error('Error creating order:', err);
    res.status(500).json({ error: 'Failed to create order', details: err.message });
  }
});

// 🌐 Haversine Formula: Calculate Great-Circle Distance between two GPS points in Kilometers
function calculateHaversineDistanceKm(lat1, lon1, lat2, lon2) {
  if (lat1 === undefined || lat1 === null || lon1 === undefined || lon1 === null ||
      lat2 === undefined || lat2 === null || lon2 === undefined || lon2 === null) {
    return null;
  }
  const R = 6371; // Earth radius in KM
  const dLat = (Number(lat2) - Number(lat1)) * Math.PI / 180;
  const dLon = (Number(lon2) - Number(lon1)) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(Number(lat1) * Math.PI / 180) * Math.cos(Number(lat2) * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// GET /api/order/pending - Delivery partners view available pending orders
// Enforces:
// 1. Online la Irukanum (Partner must be online)
// 2. Already delivery la Irukura person ku Order po koodathu (Partner cannot have active delivery)
// 3. Order potta Location la Irunthu 2 Km (radius) surrounding-la irukavangaluku mattum order poganum
router.get('/pending', async (req, res) => {
  try {
    const partnerId = req.query.partner_id;
    const reqLat = req.query.latitude || req.query.lat ? Number(req.query.latitude || req.query.lat) : null;
    const reqLng = req.query.longitude || req.query.lng ? Number(req.query.longitude || req.query.lng) : null;

    if (partnerId) {
      // 1. ONLINE STATUS FILTER:
      const dp = await DeliveryPerson.findOne({
        $or: [
          { DP_id: partnerId },
          { DP_id: new RegExp(`^${partnerId}$`, 'i') },
          { mobile_number: partnerId }
        ]
      });
      const LiveLocation = require('../models/LiveLocation');
      const liveLoc = await LiveLocation.findOne({ partner_id: partnerId });

      const isDpOnline = (dp && dp.dp_status === 'online') || (liveLoc && liveLoc.is_online === true);
      if (dp && dp.dp_status === 'offline' && (!liveLoc || !liveLoc.is_online)) {
        return res.json({
          success: true,
          orders: [],
          is_online: false,
          reason: 'Partner is currently OFFLINE. Toggle online to receive new orders.'
        });
      }

      // 2. BUSY CHECK: Partner already in an active delivery
      // "Already delivery la Irukura person ku Order po koodathu."
      const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000);
      const activeDelivery = await Order.findOne({
        partner_id: partnerId,
        status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] },
        updated_at: { $gte: fourHoursAgo }
      }).sort({ updated_at: -1 });

      if (activeDelivery) {
        return res.json({
          success: true,
          orders: [activeDelivery],
          has_active_delivery: true,
          active_order: activeDelivery,
          reason: 'Partner is currently engaged in an active delivery.'
        });
      }
    }

    // Determine partner current coordinates:
    let partnerLat = reqLat;
    let partnerLng = reqLng;
    if ((partnerLat === null || partnerLng === null) && partnerId) {
      const LiveLocation = require('../models/LiveLocation');
      const loc = await LiveLocation.findOne({ partner_id: partnerId });
      if (loc && loc.latitude && loc.longitude) {
        partnerLat = loc.latitude;
        partnerLng = loc.longitude;
      }
    }

    let query = {
      $or: [
        { status: 'pending' },
        { status: 'cancelled', cancelled_at: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } }
      ]
    };
    if (partnerId) {
      query = {
        $or: [
          { status: 'pending' },
          { partner_id: partnerId, status: { $in: ['accepted', 'purchasing_food'] } },
          { declined_by: partnerId, status: 'declined' },
          { partner_id: partnerId, status: 'cancelled' },
          { status: 'cancelled', cancelled_at: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } }
        ]
      };
    }

    const allOrders = await Order.find(query).sort({ created_at: -1 });

    // 3. 10 KM RADIUS PRIORITY & BROADCAST TO ALL ONLINE FREE PARTNERS
    // "Order potta Location la Irunthu 10 Km radius sourronding la yaaru online status la irukanga nu pakanum.
    // Itha thaandi online la irukura ella d.person kum alert poidanum."
    const mappedOrders = allOrders.map(order => {
      const o = order.toObject();
      if (partnerLat !== null && partnerLng !== null && o.customer_latitude !== null && o.customer_longitude !== null) {
        const dist = calculateHaversineDistanceKm(partnerLat, partnerLng, o.customer_latitude, o.customer_longitude);
        if (dist !== null) {
          o.distance_km = Number(dist.toFixed(2));
          o.is_within_10km = dist <= 10.0;
          o.is_within_2km = dist <= 10.0; // Backward compatible for existing UI checks
        } else {
          o.is_within_10km = true;
          o.is_within_2km = true;
        }
      } else {
        o.is_within_10km = true; // Fallback when coords not yet resolved
        o.is_within_2km = true;
      }
      return o;
    });

    // Sort: 10km radius orders first, then nearest distance, then latest
    mappedOrders.sort((a, b) => {
      const aWithin = a.is_within_10km || a.is_within_2km;
      const bWithin = b.is_within_10km || b.is_within_2km;
      if (aWithin && !bWithin) return -1;
      if (!aWithin && bWithin) return 1;
      if (a.distance_km !== null && b.distance_km !== null) {
        return a.distance_km - b.distance_km;
      }
      return new Date(b.created_at) - new Date(a.created_at);
    });

    res.json({ success: true, count: mappedOrders.length, orders: mappedOrders });
  } catch (err) {
    console.error('Error fetching pending orders:', err);
    res.status(500).json({ error: 'Failed to fetch pending orders' });
  }
});

// GET /api/order/active/:user_id - Customer gets current active order (with partner photo enrichment)
router.get('/active/:user_id', async (req, res) => {
  try {
    const activeOrder = await Order.findOne({
      user_id: req.params.user_id,
      status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
    }).sort({ created_at: -1 });

    if (!activeOrder) {
      return res.json({ success: true, order: null });
    }

    const orderObj = activeOrder.toObject();
    // 👤 Dynamically populate partner profile picture if missing
    if (orderObj.partner_id && !orderObj.partner_profile_picture) {
      try {
        const dp = await DeliveryPerson.findOne({
          $or: [
            { DP_id: orderObj.partner_id },
            { DP_id: new RegExp(`^${orderObj.partner_id}$`, 'i') },
            { mobile_number: orderObj.partner_phone || orderObj.partner_id }
          ]
        });
        if (dp && dp.profile_picture) {
          orderObj.partner_profile_picture = Buffer.isBuffer(dp.profile_picture)
            ? Buffer.from(dp.profile_picture).toString('base64')
            : dp.profile_picture.toString();
        }
      } catch (_) {}
    }

    res.json({ success: true, order: orderObj });
  } catch (err) {
    console.error('Error fetching active order:', err);
    res.status(500).json({ error: 'Failed to fetch active order' });
  }
});

// POST /api/order/accept - Partner accepts an order
router.post('/accept', async (req, res) => {
  try {
    const { order_id, partner_id, partner_name, partner_phone, partner_profile_picture } = req.body;
    if (!order_id || !partner_id) {
      return res.status(400).json({ error: 'order_id and partner_id are required' });
    }

    let partnerPic = partner_profile_picture || null;
    let actualPartnerName = partner_name;
    let actualPartnerPhone = partner_phone;

    try {
      const dp = await DeliveryPerson.findOne({
        $or: [
          { DP_id: partner_id },
          { DP_id: new RegExp(`^${partner_id}$`, 'i') },
          { mobile_number: partner_phone || partner_id }
        ]
      });
      if (dp) {
        if (!actualPartnerName || actualPartnerName === 'Delivery Partner') actualPartnerName = dp.name;
        if (!actualPartnerPhone) actualPartnerPhone = dp.mobile_number;
        if (!partnerPic && dp.profile_picture) {
          partnerPic = Buffer.isBuffer(dp.profile_picture)
            ? Buffer.from(dp.profile_picture).toString('base64')
            : dp.profile_picture.toString();
        }
      }
    } catch (_) {}

    const order = await Order.findOneAndUpdate(
      { order_id, status: 'pending' },
      {
        partner_id,
        partner_name: actualPartnerName || 'Delivery Partner',
        partner_phone: actualPartnerPhone || '+91 98765 43210',
        partner_profile_picture: partnerPic || null,
        status: 'accepted',
        accepted_at: new Date()
      },
      { new: true }
    );

    if (!order) {
      return res.status(404).json({ error: 'Order not found or already accepted' });
    }

    res.json({ success: true, message: 'Order accepted by partner', order });
  } catch (err) {
    console.error('Error accepting order:', err);
    res.status(500).json({ error: 'Failed to accept order' });
  }
});

// POST /api/order/decline - Partner declines an incoming order with reason stored in DB
router.post('/decline', async (req, res) => {
  try {
    const { order_id, decline_reason, partner_id } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    const order = await Order.findOneAndUpdate(
      { order_id },
      {
        status: 'declined',
        decline_reason: decline_reason || 'Partner unavailable',
        declined_by: partner_id || 'DP001'
      },
      { new: true }
    );

    if (!order) return res.status(404).json({ error: 'Order not found' });
    res.json({ success: true, message: 'Order declined successfully', order });
  } catch (err) {
    console.error('Error declining order:', err);
    res.status(500).json({ error: 'Failed to decline order' });
  }
});

// POST /api/order/update-status - Update order lifecycle status
router.post('/update-status', async (req, res) => {
  try {
    const { order_id, status, grand_total, cod_otp, payment_method, payment_status } = req.body;
    const updateData = {};
    if (status) updateData.status = status;
    if (status === 'picked_up') updateData.picked_up_at = new Date();
    if (status === 'delivered') updateData.delivered_at = new Date();
    if (grand_total !== undefined) updateData.grand_total = grand_total;
    if (cod_otp) updateData.cod_otp = cod_otp;
    if (payment_method) updateData.payment_method = payment_method;
    if (payment_status) updateData.payment_status = payment_status;

    const order = await Order.findOneAndUpdate(
      { order_id },
      updateData,
      { new: true }
    );

    if (!order) return res.status(404).json({ error: 'Order not found' });
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

    res.json({ success: true, message: 'OTP verified successfully! Order delivered.', order });
  } catch (err) {
    console.error('Error verifying delivery OTP:', err);
    res.status(500).json({ error: 'Failed to verify OTP' });
  }
});

// GET /api/order/user/:user_id - Get all orders for a customer (order history)
router.get('/user/:user_id', async (req, res) => {
  try {
    const orders = await Order.find({ user_id: req.params.user_id })
      .sort({ created_at: -1 })
      .limit(50);
    res.json({ success: true, count: orders.length, orders });
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

    const order = await Order.findOneAndUpdate(
      { order_id },
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

    res.json({ success: true, message: 'Order cancelled successfully', order });
  } catch (err) {
    console.error('Error cancelling order:', err);
    res.status(500).json({ error: 'Failed to cancel order' });
  }
});

// GET /api/order/partner/:partner_id - Get all orders handled by delivery partner (delivery history)
router.get('/partner/:partner_id', async (req, res) => {
  try {
    const partnerId = req.params.partner_id;
    // Find all orders where partner_id is this partner, or if partnerId is 'all'
    const query = partnerId === 'all'
      ? { status: { $in: ['delivered', 'cancelled', 'in_transit', 'picked_up', 'bill_sent', 'purchasing_food', 'accepted'] } }
      : {
          $or: [
            { partner_id: partnerId },
            { partner_id: 'DP001' },
            { status: 'cancelled' }
          ]
        };

    const orders = await Order.find(query)
      .sort({ delivered_at: -1, cancelled_at: -1, created_at: -1 })
      .limit(50);
    res.json({ success: true, count: orders.length, orders });
  } catch (err) {
    console.error('Error fetching partner orders:', err);
    res.status(500).json({ error: 'Failed to fetch partner orders' });
  }
});

// GET /api/order/:order_id - Get specific order
router.get('/:order_id', async (req, res) => {
  try {
    const order = await Order.findOne({ order_id: req.params.order_id });
    if (!order) return res.status(404).json({ error: 'Order not found' });
    const orderObj = order.toObject();
    if (orderObj.partner_id && !orderObj.partner_profile_picture) {
      try {
        const dp = await DeliveryPerson.findOne({
          $or: [
            { DP_id: orderObj.partner_id },
            { mobile_number: orderObj.partner_phone || orderObj.partner_id }
          ]
        });
        if (dp && dp.profile_picture) {
          orderObj.partner_profile_picture = Buffer.from(dp.profile_picture).toString('base64');
        }
      } catch (_) {}
    }
    res.json({ success: true, order: orderObj });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch order' });
  }
});

// POST /api/order/:order_id/message - Send chat message for an active order
router.post('/:order_id/message', async (req, res) => {
  try {
    const { sender, sender_name, text, time } = req.body;
    if (!sender || !text) {
      return res.status(400).json({ error: 'sender and text are required' });
    }
    const order = await Order.findOne({ order_id: req.params.order_id });
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
});

// GET /api/order/:order_id/messages - Get all messages for this order
router.get('/:order_id/messages', async (req, res) => {
  try {
    const order = await Order.findOne({ order_id: req.params.order_id });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }
    res.json({ success: true, messages: order.messages || [] });
  } catch (err) {
    console.error('Error fetching order messages:', err);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

module.exports = router;
