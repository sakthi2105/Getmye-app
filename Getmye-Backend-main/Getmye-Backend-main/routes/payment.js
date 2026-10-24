const express = require('express');
const router = express.Router();
const axios = require('axios');
const Payment = require('../models/Payment');
const Bill = require('../models/Bill');
const Order = require('../models/Order');
const { getNextSequence } = require('../models/Counter');

// Cashfree Gateway Environment Credentials from .env
const CASHFREE_APP_ID = process.env.CASHFREE_APP_ID || '';
const CASHFREE_SECRET_KEY = process.env.CASHFREE_SECRET_KEY || '';
const CASHFREE_API_VERSION = process.env.CASHFREE_API_VERSION || '2023-08-01';

// Auto-detect production mode if explicit env variable is set or prod secret key format is used
const isProduction =
  (process.env.CASHFREE_ENV && process.env.CASHFREE_ENV.toUpperCase() === 'PRODUCTION') ||
  CASHFREE_SECRET_KEY.includes('_prod_') ||
  (process.env.CASHFREE_BASE_URL && process.env.CASHFREE_BASE_URL.includes('api.cashfree.com'));

const CASHFREE_ENV = isProduction ? 'PRODUCTION' : 'SANDBOX';

// Resolve BASE_URL correctly based on environment
let resolvedBaseUrl = process.env.CASHFREE_BASE_URL;
if (!resolvedBaseUrl || (isProduction && resolvedBaseUrl.includes('sandbox')) || (!isProduction && resolvedBaseUrl.includes('api.cashfree.com'))) {
  resolvedBaseUrl = isProduction ? 'https://api.cashfree.com/pg' : 'https://sandbox.cashfree.com/pg';
}
const CASHFREE_BASE_URL = resolvedBaseUrl;

console.log(`[Cashfree Config] Initialized in ${CASHFREE_ENV} mode -> ${CASHFREE_BASE_URL}`);

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

// Helper: Mark order as paid and synchronize Order, Bill, and Payment in MongoDB
async function markOrderAsPaid(order_id, transaction_reference, amount, paymentMethod = 'Cashfree Gateway') {
  const order = await Order.findOne({ order_id });
  let deliveryOtp = order?.cod_otp;
  if (!deliveryOtp || deliveryOtp === '1234') {
    deliveryOtp = Math.floor(1000 + Math.random() * 9000).toString();
  }

  if (order) {
    order.payment_status = 'paid';
    order.payment_method = paymentMethod;
    order.cod_otp = deliveryOtp;
    await order.save();
  }

  // Update Bill if exists
  await Bill.findOneAndUpdate({ order_id }, { status: 'paid' });

  // Record or update Payment
  let payment = await Payment.findOne({ order_id }).sort({ created_at: -1 });
  if (!payment) {
    const paymentId = await getNextSequence('payment_id', 'PAY-', 4);
    payment = new Payment({
      payment_id: paymentId,
      order_id,
      user_id: order?.user_id || 'USER001',
      amount: Number(amount) || order?.grand_total || order?.total_amount || 195,
      payment_method: paymentMethod,
      payment_status: 'success',
      transaction_reference: transaction_reference || `CF-${Date.now()}`,
      cod_otp: deliveryOtp,
      is_cod_verified: true,
      paid_at: new Date()
    });
    await payment.save();
  } else {
    payment.payment_status = 'success';
    payment.payment_method = paymentMethod;
    payment.transaction_reference = transaction_reference || payment.transaction_reference;
    payment.is_cod_verified = true;
    payment.paid_at = new Date();
    if (!payment.cod_otp) payment.cod_otp = deliveryOtp;
    await payment.save();
  }

  // Save notification in DB for customer
  try {
    const Notification = require('../models/Notification');
    const notifId = await getNextSequence('notification_id', 'NOTIF-', 4);
    const paidAmount = Number(amount) || order?.grand_total || order?.total_amount || 0;
    await Notification.create({
      notification_id: notifId,
      recipient_id: order?.user_id || 'customer',
      recipient_type: 'customer',
      order_id,
      title: '✅ Payment Successful',
      message: `Payment of ₹${paidAmount.toFixed(0)} confirmed for Order #${order_id}. Share Delivery OTP ${deliveryOtp} upon food delivery.`
    });
  } catch (notifErr) {
    console.error('Error saving payment notification in DB:', notifErr.message);
  }

  return { order, payment, deliveryOtp };
}

// GET /api/payment/cashfree-return - Handles Cashfree redirect after payment (legacy link support)
router.get('/cashfree-return', async (req, res) => {
  try {
    const order_id = req.query.order_id;
    const link_id = req.query.link_id;

    if (!order_id) {
      return res.status(400).send('Missing order_id');
    }

    const { deliveryOtp } = await markOrderAsPaid(order_id, link_id, null, 'Cashfree Gateway');

    // Render HTML page that redirects to getmye app
    res.send(`
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Payment Successful - GetMye</title>
        <style>
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            background: #F8FAFC;
            color: #1E293B;
            padding: 20px;
          }
          .card {
            background: white;
            padding: 36px 24px;
            border-radius: 24px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.08);
            text-align: center;
            max-width: 380px;
            width: 100%;
          }
          .icon {
            width: 72px;
            height: 72px;
            background: #DCFCE7;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 18px;
            color: #16A34A;
            font-size: 36px;
            font-weight: bold;
          }
          h2 { margin: 0 0 8px; font-size: 22px; color: #0F172A; }
          p { margin: 0 0 24px; color: #64748B; font-size: 14px; line-height: 1.5; }
          .otp-badge {
            background: #F0FDF4;
            border: 1.5px dashed #86EFAC;
            border-radius: 12px;
            padding: 12px;
            margin-bottom: 24px;
          }
          .otp-title { font-size: 11px; font-weight: 800; color: #15803D; letter-spacing: 0.5px; }
          .otp-val { font-size: 28px; font-weight: 900; color: #166534; letter-spacing: 4px; margin-top: 4px; }
          .btn {
            display: block;
            width: 100%;
            background: #142B4A;
            color: white;
            padding: 16px;
            border-radius: 14px;
            text-decoration: none;
            font-weight: 800;
            font-size: 16px;
            border: none;
            cursor: pointer;
            box-shadow: 0 4px 12px rgba(20, 43, 74, 0.3);
          }
          .btn:active { background: #0C1B30; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">✓</div>
          <h2>Payment Successful!</h2>
          <p>Your payment via Cashfree was successful. Redirecting you back to your order tracking page...</p>
          <div class="otp-badge">
            <div class="otp-title">DELIVERY VERIFICATION OTP</div>
            <div class="otp-val">${deliveryOtp}</div>
          </div>
          <a class="btn" href="getmye://payment/success?order_id=${encodeURIComponent(order_id)}">Back to Order Tracking</a>
        </div>
        <script>
          setTimeout(function() {
            window.location.href = "getmye://payment/success?order_id=" + encodeURIComponent("${order_id}");
          }, 800);
        </script>
      </body>
      </html>
    `);
  } catch (err) {
    console.error('Error in cashfree-return:', err);
    res.status(500).send('Error processing payment return');
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

// GET /api/payment/success/:order_id - Return order and payment details after successful payment
router.get('/success/:order_id', async (req, res) => {
  try {
    const order = await Order.findOne({ order_id: req.params.order_id }).lean();
    const payment = await Payment.findOne({ order_id: req.params.order_id }).sort({ created_at: -1 }).lean();
    if (!order) return res.status(404).json({ error: 'Order not found' });
    if (!payment) return res.status(404).json({ error: 'Payment not found' });
    const response = {
      success: true,
      order,
      payment,
      payment_status: payment.payment_status,
      message: payment.payment_status === 'success' ? 'Payment successful' : 'Payment pending'
    };
    res.json(response);
  } catch (err) {
    console.error('Error fetching payment success info:', err);
    res.status(500).json({ error: 'Failed to fetch payment success info' });
  }
});

// GET /api/payment/cashfree/config - Expose public Cashfree configuration
router.get('/cashfree/config', (req, res) => {
  res.json({
    success: true,
    app_id: CASHFREE_APP_ID,
    api_version: CASHFREE_API_VERSION,
    base_url: CASHFREE_BASE_URL,
    environment: CASHFREE_ENV
  });
});

// POST /api/payment/cashfree/create-order - Securely create Cashfree order server-side and return payment_session_id
router.post('/cashfree/create-order', async (req, res) => {
  try {
    const { order_id, amount, customer_id, customer_name, customer_phone, customer_email } = req.body;

    if (!order_id) {
      return res.status(400).json({ error: 'order_id is required' });
    }

    // 1. Check if order exists in DB and prevent duplicate payment
    const existingOrder = await Order.findOne({ order_id });
    if (existingOrder && (existingOrder.payment_status === 'paid' || existingOrder.payment_status === 'success')) {
      return res.status(200).json({
        success: true,
        already_paid: true,
        order_id,
        delivery_otp: existingOrder.cod_otp,
        message: 'Order is already marked as paid'
      });
    }

    // 2. Validate amount
    let orderAmount = Number(amount);
    if (!orderAmount || isNaN(orderAmount) || orderAmount <= 0) {
      orderAmount = existingOrder?.grand_total || existingOrder?.budget || 195.0;
    }
    const formattedAmount = Number(orderAmount.toFixed(2));

    // 3. Format customer details per Cashfree requirements
    let custId = (customer_id || existingOrder?.user_id || 'USER001').toString().replace(/[^a-zA-Z0-9_-]/g, '_');
    if (custId.length < 3) custId = `cust_${custId}`;
    if (custId.length > 50) custId = custId.substring(0, 50);

    let custPhone = (customer_phone || existingOrder?.customer_phone || '').toString().replace(/\D/g, '');
    if (custPhone.length > 10) custPhone = custPhone.slice(-10);
    if (custPhone.length !== 10) custPhone = '9999999999';

    const custName = (customer_name || existingOrder?.customer_name || 'GetMye Customer').toString().trim() || 'Customer';
    const custEmail = (customer_email || `${custId}@getmye.com`).toString().trim();

    // 4. Generate unique Cashfree order ID (allows retry if customer cancels checkout)
    const sanitizedOrderId = order_id.toString().replace(/[^a-zA-Z0-9_-]/g, '_');
    const cfOrderId = `cf_${sanitizedOrderId}_${Date.now().toString().slice(-6)}`;

    // 5. Configure order_meta: Cashfree strictly requires HTTPS for notify_url.
    // In local development (http://192.168.x.x), omit notify_url unless an explicit HTTPS webhook is provided.
    const orderMeta = {};
    const configuredNotifyUrl = process.env.CASHFREE_NOTIFY_URL;
    const reqNotifyUrl = `${req.protocol}://${req.get('host')}/api/payment/cashfree/webhook`;

    if (configuredNotifyUrl && configuredNotifyUrl.startsWith('https://')) {
      orderMeta.notify_url = configuredNotifyUrl;
    } else if (reqNotifyUrl.startsWith('https://')) {
      orderMeta.notify_url = reqNotifyUrl;
    }

    const payload = {
      order_id: cfOrderId,
      order_amount: formattedAmount,
      order_currency: 'INR',
      customer_details: {
        customer_id: custId,
        customer_name: custName,
        customer_phone: custPhone,
        customer_email: custEmail
      },
      order_note: `Getmye Order #${order_id}`,
      order_tags: {
        brand: 'Getmye',
        business_name: 'Getmye',
        merchant_name: 'Getmye'
      }
    };

    if (Object.keys(orderMeta).length > 0) {
      payload.order_meta = orderMeta;
    }

    console.log(`[Cashfree] Creating server order: ${cfOrderId} for ₹${formattedAmount}`);

    const response = await axios.post(`${CASHFREE_BASE_URL}/orders`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'x-client-id': CASHFREE_APP_ID,
        'x-client-secret': CASHFREE_SECRET_KEY,
        'x-api-version': CASHFREE_API_VERSION
      },
      timeout: 10000
    });

    console.log(`[Cashfree] Order created: ${cfOrderId}, session: ${response.data.payment_session_id ? 'obtained' : 'missing'}`);

    res.json({
      success: true,
      order_id: order_id,
      cf_order_id: cfOrderId,
      payment_session_id: response.data.payment_session_id,
      order_amount: response.data.order_amount,
      order_currency: response.data.order_currency || 'INR',
      environment: CASHFREE_ENV
    });
  } catch (err) {
    const errorDetails = err.response?.data || err.message;
    console.error('[Cashfree] Order creation error:', errorDetails);
    res.status(err.response?.status || 500).json({
      error: 'Failed to create Cashfree payment order',
      details: errorDetails
    });
  }
});

// POST /api/payment/cashfree/verify-order - Server-side payment verification using Cashfree Orders API
router.post('/cashfree/verify-order', async (req, res) => {
  try {
    const { order_id, cf_order_id } = req.body;
    if (!order_id || !cf_order_id) {
      return res.status(400).json({ error: 'order_id and cf_order_id are required' });
    }

    console.log(`[Cashfree] Verifying order server-side: cf_order_id=${cf_order_id}, app_order_id=${order_id}`);

    // Query Cashfree server-side API
    const response = await axios.get(`${CASHFREE_BASE_URL}/orders/${cf_order_id}`, {
      headers: {
        'x-client-id': CASHFREE_APP_ID,
        'x-client-secret': CASHFREE_SECRET_KEY,
        'x-api-version': CASHFREE_API_VERSION
      },
      timeout: 10000
    });

    const cfOrder = response.data;
    let isPaid = (cfOrder.order_status === 'PAID');
    let paidAmount = cfOrder.order_amount;
    let transactionId = cf_order_id;

    // If order_status is not directly PAID, inspect payments endpoint
    if (!isPaid) {
      try {
        const paymentsRes = await axios.get(`${CASHFREE_BASE_URL}/orders/${cf_order_id}/payments`, {
          headers: {
            'x-client-id': CASHFREE_APP_ID,
            'x-client-secret': CASHFREE_SECRET_KEY,
            'x-api-version': CASHFREE_API_VERSION
          },
          timeout: 8000
        });
        const payments = paymentsRes.data || [];
        const successPayment = payments.find(p => p.payment_status === 'SUCCESS');
        if (successPayment) {
          isPaid = true;
          paidAmount = successPayment.payment_amount || paidAmount;
          transactionId = successPayment.cf_payment_id ? String(successPayment.cf_payment_id) : transactionId;
        }
      } catch (payErr) {
        console.warn(`[Cashfree] Could not fetch payments list for ${cf_order_id}:`, payErr.message);
      }
    }

    if (isPaid) {
      const { order, deliveryOtp } = await markOrderAsPaid(order_id, transactionId, paidAmount, 'Cashfree Gateway');
      return res.json({
        success: true,
        payment_status: 'paid',
        order_id,
        cf_order_id,
        transaction_id: transactionId,
        delivery_otp: deliveryOtp,
        amount: paidAmount,
        message: 'Payment verified and confirmed successfully'
      });
    }

    const currentStatus = cfOrder.order_status?.toLowerCase() || 'pending';
    res.json({
      success: false,
      payment_status: currentStatus,
      order_id,
      cf_order_id,
      message: `Cashfree order status is ${cfOrder.order_status || 'PENDING'}`
    });
  } catch (err) {
    const errorDetails = err.response?.data || err.message;
    console.error('[Cashfree] Order verification error:', errorDetails);
    res.status(err.response?.status || 500).json({
      error: 'Failed to verify Cashfree payment status',
      details: errorDetails
    });
  }
});

// GET /api/payment/cashfree/status/:orderId - Check order status in DB and fallback to Cashfree
router.get('/cashfree/status/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const order = await Order.findOne({ order_id: orderId });
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const payment = await Payment.findOne({ order_id: orderId }).sort({ created_at: -1 });

    res.json({
      success: true,
      order_id: orderId,
      payment_status: order.payment_status,
      payment_method: order.payment_method,
      delivery_otp: order.cod_otp,
      amount: order.grand_total || order.budget,
      payment_details: payment
    });
  } catch (err) {
    console.error('[Cashfree] Status fetch error:', err.message);
    res.status(500).json({ error: 'Failed to fetch payment status' });
  }
});

// POST /api/payment/cashfree/webhook - Handle Cashfree asynchronous webhook events
router.post('/cashfree/webhook', async (req, res) => {
  try {
    const event = req.body;
    console.log('[Cashfree Webhook] Event received:', event?.type || event?.event_time);

    const orderData = event?.data?.order;
    const paymentData = event?.data?.payment;
    const cfOrderId = orderData?.order_id || event?.data?.order_id;

    if (paymentData?.payment_status === 'SUCCESS' || orderData?.order_status === 'PAID') {
      if (cfOrderId) {
        let appOrderId = cfOrderId;
        const match = cfOrderId.match(/^cf_(.*?)_\d+$/);
        if (match && match[1]) {
          appOrderId = match[1];
        }

        const paidAmount = paymentData?.payment_amount || orderData?.order_amount;
        const txnId = paymentData?.cf_payment_id ? String(paymentData.cf_payment_id) : cfOrderId;

        await markOrderAsPaid(appOrderId, txnId, paidAmount, 'Cashfree Gateway');
        console.log(`[Cashfree Webhook] Successfully marked order ${appOrderId} as paid`);
      }
    }

    res.status(200).json({ status: 'OK' });
  } catch (err) {
    console.error('[Cashfree Webhook] Error processing webhook:', err.message);
    res.status(200).json({ status: 'ERROR', message: err.message });
  }
});

// Legacy backward-compatibility endpoints
router.post('/cashfree/create-link', async (req, res) => {
  try {
    const { link_id, amount, order_id, customer_phone, customer_name, return_url } = req.body;
    const payload = {
      link_id: link_id || `cf_${Date.now()}`,
      link_amount: Number(amount) || 195,
      link_currency: 'INR',
      link_purpose: `Food Order #${order_id || 'GetMye'}`,
      customer_details: {
        customer_phone: customer_phone || '9999999999',
        customer_name: customer_name || 'Customer'
      }
    };

    const finalReturnUrl = return_url || (req.protocol === 'https' ? `${req.protocol}://${req.get('host')}/api/payment/cashfree-return?order_id=${order_id}&link_id={link_id}` : null);
    if (finalReturnUrl && finalReturnUrl.startsWith('https://')) {
      payload.link_meta = { return_url: finalReturnUrl };
    }

    const response = await axios.post(`${CASHFREE_BASE_URL}/links`, payload, {
      headers: {
        'Content-Type': 'application/json',
        'x-client-id': CASHFREE_APP_ID,
        'x-client-secret': CASHFREE_SECRET_KEY,
        'x-api-version': CASHFREE_API_VERSION
      },
      timeout: 10000
    });

    res.json(response.data);
  } catch (err) {
    res.status(err.response?.status || 500).json({
      error: 'Failed to create Cashfree link',
      details: err.response?.data || err.message
    });
  }
});

router.get('/cashfree/status-link/:linkId', async (req, res) => {
  try {
    const { linkId } = req.params;
    const response = await axios.get(`${CASHFREE_BASE_URL}/links/${linkId}`, {
      headers: {
        'x-client-id': CASHFREE_APP_ID,
        'x-client-secret': CASHFREE_SECRET_KEY,
        'x-api-version': CASHFREE_API_VERSION
      },
      timeout: 8000
    });
    res.json(response.data);
  } catch (err) {
    res.status(err.response?.status || 500).json({
      error: 'Failed to verify Cashfree link status',
      details: err.response?.data || err.message
    });
  }
});

module.exports = router;
