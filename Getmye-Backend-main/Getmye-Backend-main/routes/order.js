const express = require('express');
const router = express.Router();
const Order = require('../models/Order');
const Profile = require('../models/Profile');
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');

// POST /api/order/create - Customer places a new order
router.post('/create', async (req, res) => {
  try {
    const { user_id, customer_name, customer_phone, delivery_address, item_name, budget, cod_otp, customer_latitude, customer_longitude } = req.body;
    if (!user_id || !delivery_address || !item_name) {
      return res.status(400).json({ error: 'user_id, delivery_address, and item_name are required' });
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
      customer_latitude: customer_latitude != null ? Number(customer_latitude) : null,
      customer_longitude: customer_longitude != null ? Number(customer_longitude) : null,
      status: 'pending',
      cod_otp: finalOtp
    });

    await newOrder.save();
    res.status(201).json({ success: true, message: 'Order created successfully', order: newOrder });
  } catch (err) {
    console.error('Error creating order:', err);
    res.status(500).json({ error: 'Failed to create order', details: err.message });
  }
});

// GET /api/order/pending - Delivery partners view available pending orders & active orders
router.get('/pending', async (req, res) => {
  try {
    const partnerId = req.query.partner_id;
    let query = {
      status: 'pending'
    };
    if (partnerId) {
      const numPart = partnerId.toString().replace(/^dp_?/i, '');
      const pRegex = new RegExp(`^dp_?0*${numPart}$`, 'i');
      query = {
        $or: [
          { status: 'pending', declined_by: { $ne: partnerId } },
          { partner_id: { $in: [partnerId, pRegex] }, status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] } },
          { partner_id: { $in: [partnerId, pRegex] }, status: 'cancelled', cancelled_at: { $gte: new Date(Date.now() - 60 * 1000) } }
        ]
      };
    }
    const orders = await Order.find(query)
      .select('-partner_profile_picture -bill_image_url -messages')
      .sort({ created_at: -1 })
      .limit(20)
      .lean();
    res.json({ success: true, count: orders.length, orders });
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
      }).select('DP_id name mobile_number profile_picture').lean();
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
        }).select('DP_id name mobile_number profile_picture').lean();
      }
    } catch (_) {}
  }

  // Fallback to active registered delivery partner
  if (!dp && isAcceptedOrBeyond) {
    try {
      dp = await DeliveryPerson.findOne({
        $or: [
          { DP_id: 'dp_007' },
          { DP_id: 'dp_005' },
          { dp_status: 'online' },
          { name: { $exists: true, $ne: '' } }
        ]
      }).select('DP_id name mobile_number profile_picture').lean();
    } catch (_) {}
  }

  if (dp) {
    orderObj.partner_id = dp.DP_id;
    orderObj.partner_name = dp.name;
    orderObj.partner_phone = dp.mobile_number;
    orderObj.partner_rating = "4.9";
    orderObj.partner_deliveries = 120;
    if (dp.profile_picture) {
      orderObj.partner_profile_picture = Buffer.isBuffer(dp.profile_picture)
        ? Buffer.from(dp.profile_picture).toString('base64')
        : dp.profile_picture.toString();
    }
    orderObj.partner_photo_url = `${protocol}://${host}/api/deliveryperson/photo/${dp.DP_id}`;

    // Persist to MongoDB Order asynchronously
    Order.updateOne(
      { order_id: orderObj.order_id },
      {
        partner_id: dp.DP_id,
        partner_name: dp.name,
        partner_phone: dp.mobile_number,
        ...(orderObj.partner_profile_picture ? { partner_profile_picture: orderObj.partner_profile_picture } : {})
      }
    ).exec().catch(() => {});
  } else if (isAcceptedOrBeyond) {
    orderObj.partner_id = orderObj.partner_id || 'dp_007';
    orderObj.partner_name = (orderObj.partner_name && orderObj.partner_name !== 'Delivery Partner') ? orderObj.partner_name : 'Sivaprakash';
    orderObj.partner_phone = (orderObj.partner_phone && orderObj.partner_phone.length >= 10) ? orderObj.partner_phone : '8754805750';
    orderObj.partner_rating = "4.9";
    orderObj.partner_deliveries = 120;
    orderObj.partner_photo_url = `${protocol}://${host}/api/deliveryperson/photo/${orderObj.partner_id}`;
  }

  return orderObj;
}

// GET /api/order/active/:user_id - Customer gets current active order (with partner photo & details enrichment)
router.get('/active/:user_id', async (req, res) => {
  try {
    const activeOrder = await Order.findOne({
      user_id: req.params.user_id,
      status: { $in: ['pending', 'accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
    }).sort({ created_at: -1 });

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
    let { order_id, partner_id, partner_name, partner_phone, partner_profile_picture } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }
    partner_id = (partner_id || '').toString().trim();
    if (!partner_id) {
      partner_id = 'dp_007';
    }

    let partnerPic = partner_profile_picture || null;
    let actualPartnerName = (partner_name && partner_name !== 'Delivery Partner') ? partner_name : null;
    let actualPartnerPhone = (partner_phone && partner_phone.trim().length >= 10) ? partner_phone : null;
    let resolvedPartnerId = partner_id;

    try {
      const numPart = partner_id.toString().replace(/^dp_?/i, '');
      const dpIdRegex = new RegExp(`^dp_?0*${numPart}$`, 'i');
      let dp = await DeliveryPerson.findOne({
        $or: [
          { DP_id: partner_id },
          { DP_id: new RegExp(`^${partner_id}$`, 'i') },
          { DP_id: dpIdRegex },
          { mobile_number: actualPartnerPhone || partner_id },
          { mobile_number: partner_id.toString().replace(/\D/g, '') }
        ]
      }).select('DP_id name mobile_number profile_picture').lean();

      if (!dp) {
        dp = await DeliveryPerson.findOne({
          $or: [
            { DP_id: 'dp_007' },
            { DP_id: 'dp_005' },
            { name: { $exists: true, $ne: '' } }
          ]
        }).select('DP_id name mobile_number profile_picture').lean();
      }

      if (dp) {
        resolvedPartnerId = dp.DP_id || partner_id;
        actualPartnerName = dp.name || actualPartnerName;
        actualPartnerPhone = dp.mobile_number || actualPartnerPhone;
        if (!partnerPic && dp.profile_picture) {
          partnerPic = Buffer.isBuffer(dp.profile_picture)
            ? Buffer.from(dp.profile_picture).toString('base64')
            : dp.profile_picture.toString();
        }
      }
    } catch (dpErr) {
      console.warn('DeliveryPerson lookup warning:', dpErr);
    }

    if (!actualPartnerName || actualPartnerName === 'Delivery Partner') actualPartnerName = 'Sivaprakash';
    if (!actualPartnerPhone) actualPartnerPhone = '8754805750';
    if (!resolvedPartnerId) resolvedPartnerId = 'dp_007';

    const order = await Order.findOneAndUpdate(
      { order_id, status: { $in: ['pending', 'accepted', 'purchasing_food'] } },
      {
        partner_id: resolvedPartnerId,
        partner_name: actualPartnerName,
        partner_phone: actualPartnerPhone,
        partner_profile_picture: partnerPic || null,
        status: 'accepted',
        accepted_at: new Date()
      },
      { returnDocument: 'after', new: true }
    );

    if (!order) {
      return res.status(400).json({
        success: false,
        error: 'ORDER_NOT_AVAILABLE',
        message: 'Order not found or has already been accepted by another delivery partner.'
      });
    }

    // Update partner's LiveLocation in MongoDB so status is 'delivering'
    try {
      const LiveLocation = require('../models/LiveLocation');
      await LiveLocation.updateMany(
        { partner_id: resolvedPartnerId },
        { status: 'delivering', order_id: order.order_id }
      );
    } catch (_) {}

    const host = req.get('host');
    const protocol = req.protocol;
    const orderObj = order.toObject();
    orderObj.partner_id = resolvedPartnerId;
    orderObj.partner_name = actualPartnerName;
    orderObj.partner_phone = actualPartnerPhone;
    orderObj.partner_rating = "4.9";
    orderObj.partner_deliveries = 120;
    if (partnerPic) orderObj.partner_profile_picture = partnerPic;
    orderObj.partner_photo_url = `${protocol}://${host}/api/deliveryperson/photo/${resolvedPartnerId}`;

    res.json({ success: true, message: 'Order accepted by partner', order: orderObj });
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
        decline_reason: decline_reason || 'Partner unavailable',
        declined_by: partner_id || 'DP001'
      },
      { returnDocument: 'after' }
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

// GET /api/order/:order_id - Get specific order (fast lightweight query with partner enrichment)
router.get('/:order_id', async (req, res) => {
  try {
    const order = await Order.findOne({ order_id: req.params.order_id })
      .select('-bill_image_url')
      .lean();
    if (!order) return res.status(404).json({ error: 'Order not found' });
    const enrichedOrder = await enrichOrderWithPartner(order, req);
    res.json({ success: true, order: enrichedOrder });
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

