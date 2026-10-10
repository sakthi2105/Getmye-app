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
      $or: [
        { status: 'pending' },
        { status: 'cancelled', cancelled_at: { $gte: new Date(Date.now() - 5 * 60 * 1000) } }
      ]
    };
    if (partnerId) {
      query = {
        $or: [
          { status: 'pending' },
          { partner_id: partnerId, status: { $in: ['accepted', 'purchasing_food'] } },
          { partner_id: partnerId, status: 'cancelled' },
          { status: 'cancelled', cancelled_at: { $gte: new Date(Date.now() - 5 * 60 * 1000) } }
        ],
        declined_by: { $ne: partnerId }
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
    if (orderObj.partner_id) {
      orderObj.partner_photo_url = `/api/deliveryperson/photo/${orderObj.partner_id}`;
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
          { mobile_number: partner_phone || partner_id }
        ]
      }).select('name mobile_number profile_picture').lean();
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
      { returnDocument: 'after' }
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
        { partner_id },
        { status: 'delivering', order_id: order.order_id }
      );
    } catch (_) {}

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
    const { order_id, status, grand_total, tip_amount, item_total, cod_otp, payment_method, payment_status } = req.body;
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

// GET /api/order/:order_id - Get specific order (fast lightweight query)
router.get('/:order_id', async (req, res) => {
  try {
    const order = await Order.findOne({ order_id: req.params.order_id })
      .select('-bill_image_url -partner_profile_picture')
      .lean();
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (order.partner_id) {
      order.partner_photo_url = `/api/deliveryperson/photo/${order.partner_id}`;
    }
    res.json({ success: true, order });
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

