const express = require('express');
const router = express.Router();
const Bill = require('../models/Bill');
const Order = require('../models/Order');
const { getNextSequence } = require('../models/Counter');

// POST /api/bill/submit - Delivery partner submits bill after buying food
router.post('/submit', async (req, res) => {
  try {
    const {
      order_id,
      partner_id,
      user_id,
      shop_name,
      items,
      item_total,
      delivery_fee,
      tip_amount,
      grand_total,
      bill_image_url,
      bill_images
    } = req.body;

    if (!order_id || !items || !grand_total) {
      return res.status(400).json({ error: 'order_id, items, and grand_total are required' });
    }

    let imagesList = [];
    if (Array.isArray(bill_images) && bill_images.length > 0) {
      imagesList = bill_images.filter(Boolean);
    } else if (bill_image_url) {
      try {
        const parsed = JSON.parse(bill_image_url);
        if (Array.isArray(parsed)) imagesList = parsed.filter(Boolean);
        else imagesList = [bill_image_url];
      } catch (_) {
        imagesList = [bill_image_url];
      }
    }
    const primaryBillImage = imagesList.length > 0 ? imagesList[0] : (bill_image_url || null);

    const processedItems = (items || []).map(item => ({
      name: item.name || 'Item',
      quantity: Number(item.quantity) || 1,
      price: Number(item.price) || 0,
      total: Number(item.total) !== undefined && !isNaN(Number(item.total)) && Number(item.total) > 0
        ? Number(item.total)
        : ((Number(item.price) || 0) * (Number(item.quantity) || 1))
    }));

    const billId = await getNextSequence('bill_id', 'BILL-', 4);

    const newBill = new Bill({
      bill_id: billId,
      order_id,
      partner_id: partner_id || 'DP001',
      user_id: user_id || 'USER001',
      shop_name: shop_name || 'Restaurant',
      items: processedItems,
      item_total: Number(item_total) || 0,
      delivery_fee: Number(delivery_fee) || 0,
      tip_amount: Number(tip_amount) || 0,
      grand_total: Number(grand_total) || 0,
      bill_image_url: primaryBillImage,
      bill_images: imagesList,
      status: 'submitted'
    });

    await newBill.save();

    // Update order status to 'bill_sent' with bill_confirmed: true, updated items and bill image(s)
    const orderUpdatePayload = {
      status: 'bill_sent',
      bill_confirmed: true,
      grand_total: Number(grand_total),
      item_total: Number(item_total) || 0,
      tip_amount: Number(tip_amount) || 0,
      delivery_fee: Number(delivery_fee) || 0,
      bill_image_url: primaryBillImage,
      bill_images: imagesList,
      items: processedItems.map(it => ({
        name: it.name,
        quantity: it.quantity,
        price: it.price,
        is_collected: true
      }))
    };
    if (partner_id) {
      orderUpdatePayload.partner_id = partner_id;
    }
    await Order.findOneAndUpdate({ order_id }, orderUpdatePayload);

    try {
      const Notification = require('../models/Notification');
      const updatedOrder = await Order.findOne({ order_id });
      const targetUserId = (updatedOrder && updatedOrder.user_id) ? updatedOrder.user_id : (user_id || 'customer');
      const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
      await Notification.create({
        notification_id: notifId,
        recipient_id: targetUserId,
        recipient_type: 'customer',
        order_id: order_id,
        title: '🧾 Order Confirmed & Bill Sent',
        message: `Delivery Partner has confirmed order #${order_id} and sent the store bill (₹${Number(grand_total).toFixed(0)}). Tap to review and pay!`
      });
    } catch (notifErr) {
      console.error('Error saving bill notification in DB:', notifErr.message);
    }

    res.status(201).json({ success: true, message: 'Bill submitted successfully', bill: newBill });
  } catch (err) {
    console.error('Error submitting bill:', err);
    res.status(500).json({ error: 'Failed to submit bill', details: err.message });
  }
});

// POST /api/bill/upload-image - Update or upload bill receipt image(s)
router.post('/upload-image', async (req, res) => {
  try {
    const { order_id, bill_image_url, bill_images } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }
    let imagesList = [];
    if (Array.isArray(bill_images) && bill_images.length > 0) {
      imagesList = bill_images.filter(Boolean);
    } else if (bill_image_url) {
      try {
        const parsed = JSON.parse(bill_image_url);
        if (Array.isArray(parsed)) imagesList = parsed.filter(Boolean);
        else imagesList = [bill_image_url];
      } catch (_) {
        imagesList = [bill_image_url];
      }
    }
    const primaryBillImage = imagesList.length > 0 ? imagesList[0] : (bill_image_url || null);
    await Bill.findOneAndUpdate(
      { order_id },
      { bill_image_url: primaryBillImage, bill_images: imagesList },
      { sort: { created_at: -1 } }
    );
    await Order.findOneAndUpdate(
      { order_id },
      { bill_image_url: primaryBillImage, bill_images: imagesList, bill_confirmed: true }
    );
    res.json({ success: true, message: 'Bill image(s) uploaded and synced successfully', bill_images: imagesList });
  } catch (err) {
    console.error('Error updating bill image:', err);
    res.status(500).json({ error: 'Failed to update bill image' });
  }
});

// POST /api/bill/tip - Update tip for an order bill
router.post('/tip', async (req, res) => {
  try {
    const { order_id, tip_amount } = req.body;
    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }
    const tip = Number(tip_amount) || 0;
    const bill = await Bill.findOne({ order_id }).sort({ created_at: -1 });
    let foodPrice = 0;
    let delFee = 0;
    if (bill) {
      bill.tip_amount = tip;
      bill.grand_total = (Number(bill.item_total) || 0) + (Number(bill.delivery_fee) || 0) + tip;
      await bill.save();
      foodPrice = Number(bill.item_total) || 0;
      delFee = Number(bill.delivery_fee) || 0;
    }

    const order = await Order.findOne({ order_id });
    if (order) {
      if (!foodPrice && order.item_total) foodPrice = order.item_total;
      if (!foodPrice && order.budget) foodPrice = order.budget;
      if (!delFee && order.delivery_fee) delFee = order.delivery_fee;

      order.tip_amount = tip;
      order.item_total = foodPrice;
      order.delivery_fee = delFee;
      order.grand_total = foodPrice + delFee + tip;
      await order.save();
      return res.json({ success: true, message: 'Tip updated', bill: bill || null, order });
    }

    if (bill) {
      return res.json({ success: true, message: 'Tip updated', bill });
    }
    res.status(404).json({ error: 'Order and bill not found' });
  } catch (err) {
    console.error('Error updating tip:', err);
    res.status(500).json({ error: 'Failed to update tip', details: err.message });
  }
});

// GET /api/bill/:order_id - Customer gets bill for an order
router.get('/:order_id', async (req, res) => {
  try {
    const bill = await Bill.findOne({ order_id: req.params.order_id }).sort({ created_at: -1 });
    if (!bill) {
      return res.status(404).json({ error: 'Bill not yet submitted for this order' });
    }
    res.json({ success: true, bill });
  } catch (err) {
    console.error('Error fetching bill:', err);
    res.status(500).json({ error: 'Failed to fetch bill' });
  }
});

module.exports = router;

