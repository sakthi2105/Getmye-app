const express = require('express');
const router = express.Router();
const Payment = require('../models/Payment');
const Bill = require('../models/Bill');
const Order = require('../models/Order');
const { getNextSequence } = require('../models/Counter');

// POST /api/payment/create - Customer initiates payment (UPI / COD / etc.)
router.post('/create', async (req, res) => {
  try {
    const { order_id, bill_id, user_id, amount, payment_method, transaction_reference } = req.body;
    if (!order_id || !amount || !payment_method) {
      return res.status(400).json({ error: 'order_id, amount, and payment_method are required' });
    }

    const paymentId = await getNextSequence('payment_id', 'PAY-', 4);

    let codOtp = null;
    let isCodVerified = false;
    let paymentStatus = 'pending';

    if (payment_method.toLowerCase() === 'cod') {
      codOtp = Math.floor(1000 + Math.random() * 9000).toString();
      paymentStatus = 'pending';
    } else {
      // UPI / GPay / PhonePe / Card
      paymentStatus = 'success';
      isCodVerified = true;
    }

    const payment = new Payment({
      payment_id: paymentId,
      order_id,
      bill_id,
      user_id: user_id || 'USER001',
      amount: Number(amount),
      payment_method,
      payment_status: paymentStatus,
      transaction_reference: transaction_reference || `TXN-${Date.now()}`,
      cod_otp: codOtp,
      is_cod_verified: isCodVerified,
      paid_at: paymentStatus === 'success' ? new Date() : null
    });

    await payment.save();

    if (paymentStatus === 'success') {
      if (bill_id) await Bill.findOneAndUpdate({ bill_id }, { status: 'paid' });
    }

    res.status(201).json({
      success: true,
      message: 'Payment recorded',
      payment,
      cod_otp: codOtp
    });
  } catch (err) {
    console.error('Error recording payment:', err);
    res.status(500).json({ error: 'Failed to record payment', details: err.message });
  }
});

// POST /api/payment/verify-cod - Delivery partner enters OTP to confirm COD
router.post('/verify-cod', async (req, res) => {
  try {
    const { order_id, entered_otp } = req.body;
    const payment = await Payment.findOne({ order_id, payment_method: 'cod' }).sort({ created_at: -1 });

    if (!payment) {
      return res.status(404).json({ error: 'No COD payment found for this order' });
    }

    if (payment.cod_otp !== entered_otp.toString().trim()) {
      return res.status(400).json({ success: false, error: 'Incorrect COD OTP PIN' });
    }

    payment.is_cod_verified = true;
    payment.payment_status = 'success';
    payment.paid_at = new Date();
    await payment.save();

    // Mark order delivered
    await Order.findOneAndUpdate({ order_id }, { status: 'delivered', delivered_at: new Date() });

    res.json({ success: true, message: 'COD verified successfully!', payment });
  } catch (err) {
    console.error('Error verifying COD OTP:', err);
    res.status(500).json({ error: 'Failed to verify COD OTP' });
  }
});

// GET /api/payment/:order_id - Get payment details for an order
router.get('/:order_id', async (req, res) => {
  try {
    const payment = await Payment.findOne({ order_id: req.params.order_id }).sort({ created_at: -1 });
    if (!payment) return res.status(404).json({ error: 'No payment found' });
    res.json({ success: true, payment });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch payment' });
  }
});

module.exports = router;
