const OfferBanner = require('../models/OfferBanner');

/**
 * Returns today's Indian Standard Time (IST, UTC+05:30) date key and UTC window,
 * plus seconds remaining until next 12:00 AM IST midnight.
 */
function getISTDayWindow(now = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  const parts = formatter.formatToParts(now);
  const map = {};
  for (const p of parts) {
    if (p.type !== 'literal') map[p.type] = p.value;
  }

  let hour = parseInt(map.hour, 10) || 0;
  if (hour === 24) hour = 0;
  const minute = parseInt(map.minute, 10) || 0;
  const second = parseInt(map.second, 10) || 0;

  const dateKey = `${map.year}-${map.month}-${map.day}`;
  const startOfDayUtc = new Date(`${dateKey}T00:00:00.000+05:30`);
  const endOfDayUtc = new Date(`${dateKey}T23:59:59.999+05:30`);
  const elapsedSecToday = hour * 3600 + minute * 60 + second;
  const secondsUntilMidnightIst = Math.max(1, 86400 - elapsedSecToday);

  return {
    dateKey,
    startOfDayUtc,
    endOfDayUtc,
    secondsUntilMidnightIst
  };
}

/**
 * Checks whether an order document is a welcome / daily offer order.
 */
function isWelcomeOfferOrderDoc(orderDoc) {
  if (!orderDoc) return false;
  return (
    orderDoc.is_welcome_offer === true ||
    orderDoc.order_type === 'welcome_offer' ||
    (typeof orderDoc.item_name === 'string' && /welcome\s*offer|crushing\s*offer/i.test(orderDoc.item_name))
  );
}

/**
 * Builds a MongoDB query matching a customer's user_id and/or phone number.
 */
function buildCustomerFilter(userId, mobile) {
  const orList = [];
  const cleanUserId = (userId || '').toString().trim();
  const cleanMobile = (mobile || '').toString().trim();

  if (cleanUserId && cleanUserId !== 'usr_001' && cleanUserId !== 'guest') {
    orList.push({ user_id: cleanUserId });
  }
  if (cleanMobile) {
    orList.push({ user_id: cleanMobile });
    orList.push({ customer_phone: cleanMobile });
    const digits = cleanMobile.replace(/\D/g, '');
    if (digits.length >= 10) {
      const last10 = digits.slice(-10);
      orList.push({ customer_phone: new RegExp(`${last10}$`) });
    }
  }

  if (orList.length === 0 && cleanUserId) {
    orList.push({ user_id: cleanUserId });
  }
  return orList.length > 0 ? { $or: orList } : null;
}

/**
 * Checks if the customer has already completed (delivered/completed) at least one
 * order during the current IST day (resets every day at 12:00 AM IST).
 */
async function hasCustomerCompletedOrderToday(OrderModel, userId, mobile) {
  const { dateKey, startOfDayUtc, endOfDayUtc, secondsUntilMidnightIst } = getISTDayWindow();
  const customerFilter = buildCustomerFilter(userId, mobile);
  if (!customerFilter) {
    return {
      hasCompletedToday: false,
      dateKey,
      secondsUntilMidnightIst,
      completedOrderId: null
    };
  }

  const completedOrder = await OrderModel.findOne({
    ...customerFilter,
    status: { $in: ['delivered', 'completed'] },
    $or: [
      { delivered_at: { $gte: startOfDayUtc, $lte: endOfDayUtc } },
      {
        $and: [
          { $or: [{ delivered_at: null }, { delivered_at: { $exists: false } }] },
          { created_at: { $gte: startOfDayUtc, $lte: endOfDayUtc } }
        ]
      }
    ]
  })
    .select('order_id status delivered_at created_at')
    .sort({ created_at: -1 })
    .lean();

  return {
    hasCompletedToday: Boolean(completedOrder),
    dateKey,
    secondsUntilMidnightIst,
    completedOrderId: completedOrder ? completedOrder.order_id : null
  };
}

/**
 * Atomically decrements the active OfferBanner's stock_remaining once when a
 * welcome/daily offer order reaches 'delivered' or 'completed'.
 * Uses offer_stock_decremented on Order to guarantee idempotency across endpoints.
 */
async function decrementOfferStockForCompletedOrder(OrderModel, orderId) {
  if (!orderId) return null;

  const claimedOrder = await OrderModel.findOneAndUpdate(
    {
      order_id: orderId,
      status: { $in: ['delivered', 'completed'] },
      offer_stock_decremented: { $ne: true },
      $or: [
        { is_welcome_offer: true },
        { order_type: 'welcome_offer' },
        { item_name: /welcome\s*offer|crushing\s*offer/i }
      ]
    },
    { $set: { offer_stock_decremented: true } },
    { returnDocument: 'before' }
  ).lean();

  if (!claimedOrder) {
    return null;
  }

  const qty = Math.max(1, parseInt(claimedOrder.quantity, 10) || 1);
  const activeBanner = await OfferBanner.findOne({ is_active: true }).sort({ updated_at: -1 });
  if (!activeBanner) {
    return null;
  }

  const currentStock = Math.max(0, Number(activeBanner.stock_remaining) || 0);
  const dec = Math.min(currentStock, qty);
  if (dec > 0) {
    const updated = await OfferBanner.findOneAndUpdate(
      { _id: activeBanner._id, stock_remaining: { $gte: dec } },
      { $inc: { stock_remaining: -dec } },
      { returnDocument: 'after' }
    ).lean();
    if (updated) {
      console.log(`📉 [Offer Stock] Order #${orderId} completed. Decremented active banner ${updated.banner_id} stock_remaining by ${dec} -> ${updated.stock_remaining}`);
      return updated;
    }
  }

  // Fallback clamp to 0 if concurrent update reduced stock below dec
  const clamped = await OfferBanner.findOneAndUpdate(
    { _id: activeBanner._id },
    { $set: { stock_remaining: 0 } },
    { returnDocument: 'after' }
  ).lean();
  return clamped;
}

module.exports = {
  getISTDayWindow,
  isWelcomeOfferOrderDoc,
  hasCustomerCompletedOrderToday,
  decrementOfferStockForCompletedOrder
};
