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
      bill_image_url
    } = req.body;

    if (!order_id || !items || !grand_total) {
      return res.status(400).json({ error: 'order_id, items, and grand_total are required' });
    }

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
      bill_image_url: bill_image_url || null,
      status: 'submitted'
    });

    await newBill.save();

    // Update order status to 'bill_sent' / 'purchasing_food' with bill_image_url
    await Order.findOneAndUpdate(
      { order_id },
      {
        status: 'bill_sent',
        grand_total: Number(grand_total),
        bill_image_url: bill_image_url || null
      }
    );

    res.status(201).json({ success: true, message: 'Bill submitted successfully', bill: newBill });
  } catch (err) {
    console.error('Error submitting bill:', err);
    res.status(500).json({ error: 'Failed to submit bill', details: err.message });
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
    if (bill) {
      bill.tip_amount = tip;
      bill.grand_total = (Number(bill.item_total) || 0) + (Number(bill.delivery_fee) || 0) + tip;
      await bill.save();
      // Also update Order grand_total
      await Order.findOneAndUpdate(
        { order_id },
        { grand_total: bill.grand_total }
      );
      return res.json({ success: true, message: 'Tip updated', bill });
    }
    res.status(404).json({ error: 'Bill not found' });
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

