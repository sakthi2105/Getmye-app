const express = require('express');
const router = express.Router();
const Bill = require('../models/Bill');
const Order = require('../models/Order');
const LiveLocation = require('../models/LiveLocation');
const { getNextSequence } = require('../models/Counter');
const { calculateDistanceKm, calculateDeliveryFee } = require('../services/orderDispatchService');

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

    // ✅ Fetch the order for customer coordinates + existing tip
    const existingOrder = await Order.findOne({ order_id }).lean();

    // 🛑 STRICT BATCH CHECK: First order MUST be completed & delivered before submitting bill for 2nd queued order!
    if (existingOrder && (existingOrder.status === 'queued_accepted' || existingOrder.queued_behind_order_id)) {
      const activeFirstOrder = await Order.findOne({
        $or: [
          { order_id: existingOrder.queued_behind_order_id },
          {
            partner_id: existingOrder.partner_id || partner_id,
            order_id: { $ne: order_id },
            status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
          }
        ]
      }).select('order_id status').lean();

      if (activeFirstOrder && activeFirstOrder.status !== 'delivered' && activeFirstOrder.status !== 'cancelled') {
        return res.status(400).json({
          success: false,
          error: 'FIRST_ORDER_INCOMPLETE',
          message: `Please complete and deliver your first active order (#${activeFirstOrder.order_id}) before submitting the bill for this queued order.`
        });
      }
    }
    const effectiveTip = (Number(tip_amount) && Number(tip_amount) >= 10)
      ? Number(tip_amount)
      : (existingOrder && existingOrder.tip_amount && existingOrder.tip_amount >= 10 ? existingOrder.tip_amount : 10);
    const finalItemTotal = Number(item_total) || 0;

    // ✅ DELIVERY FEE: Auto-calculate from partner GPS (hotel) → customer location at Send Bill moment
    // This is the accurate fee — partner is at the hotel when Send Bill is clicked
    let finalDelFee = 20; // default minimum ₹20
    let feeDistanceKm = null;
    let partnerHotelLat = null;
    let partnerHotelLng = null;

    try {
      const resolvedPartnerId = partner_id || (existingOrder && existingOrder.partner_id) || (existingOrder && existingOrder.current_assigned_partner_id);
      const customerLat = existingOrder && existingOrder.customer_latitude ? Number(existingOrder.customer_latitude) : null;
      const customerLng = existingOrder && existingOrder.customer_longitude ? Number(existingOrder.customer_longitude) : null;

      if (resolvedPartnerId && customerLat && customerLng && !isNaN(customerLat) && !isNaN(customerLng)) {
        // Fetch partner's current GPS (they are at the hotel right now)
        const partnerLoc = await LiveLocation.findOne({ partner_id: resolvedPartnerId }).lean();

        if (partnerLoc && partnerLoc.latitude != null && partnerLoc.longitude != null) {
          const pLat = Number(partnerLoc.latitude);
          const pLng = Number(partnerLoc.longitude);

          if (!isNaN(pLat) && !isNaN(pLng) && (pLat !== 0 || pLng !== 0)) {
            const distKm = calculateDistanceKm(pLat, pLng, customerLat, customerLng);
            const calculatedFee = calculateDeliveryFee(distKm);
            finalDelFee = calculatedFee;
            feeDistanceKm = distKm;
            partnerHotelLat = pLat;
            partnerHotelLng = pLng;
            console.log('[Bill Submit] Order ' + order_id + ': Hotel GPS (' + pLat + ',' + pLng + ') -> Customer (' + customerLat + ',' + customerLng + ') = ' + distKm + 'km, Fee: Rs.' + calculatedFee);
          }
        } else {
          console.log(`[Bill Submit] Order ${order_id}: Partner GPS not found - applying minimum fee Rs.20`);
        }
      }
    } catch (feeErr) {
      console.error('[Bill Submit] Delivery fee calculation error:', feeErr.message);
      // Don't block bill submit — use minimum ₹20
    }

    const finalGrandTotal = finalItemTotal + finalDelFee + effectiveTip;

    const newBill = new Bill({
      bill_id: billId,
      order_id,
      partner_id: partner_id || 'DP001',
      user_id: user_id || 'USER001',
      shop_name: shop_name || 'Restaurant',
      items: processedItems,
      item_total: finalItemTotal,
      delivery_fee: finalDelFee,
      tip_amount: effectiveTip,
      grand_total: finalGrandTotal,
      bill_image_url: primaryBillImage,
      bill_images: imagesList,
      status: 'submitted'
    });

    await newBill.save();

    // ✅ Update order: status → bill_sent, lock delivery fee, store hotel GPS snapshot
    const orderUpdatePayload = {
      status: 'bill_sent',
      bill_confirmed: true,
      grand_total: finalGrandTotal,
      item_total: finalItemTotal,
      tip_amount: effectiveTip,
      delivery_fee: finalDelFee,              // ✅ Auto-calculated at Send Bill moment
      delivery_fee_locked_at: new Date(),     // ✅ Fee lock timestamp
      bill_image_url: primaryBillImage,
      bill_images: imagesList,
      items: processedItems.map(it => ({
        name: it.name,
        quantity: it.quantity,
        price: it.price,
        is_collected: true
      }))
    };

    // ✅ Store hotel GPS snapshot + distance (if calculated)
    if (feeDistanceKm !== null) {
      orderUpdatePayload.delivery_fee_distance_km  = feeDistanceKm;
      orderUpdatePayload.partner_hotel_latitude    = partnerHotelLat;
      orderUpdatePayload.partner_hotel_longitude   = partnerHotelLng;
    }

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
    const tip = Math.max(10, Number(tip_amount) || 10);
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

