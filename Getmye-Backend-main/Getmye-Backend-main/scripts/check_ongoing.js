const { connectDB } = require('../db');
const Order = require('../models/Order');

async function check() {
  await new Promise(r => setTimeout(r, 2000));
  const ongoing = await Order.find({
    status: { $in: ['accepted', 'purchasing_food', 'bill_sent', 'picked_up', 'in_transit'] }
  });
  console.log('Ongoing orders count:', ongoing.length);
  for (const o of ongoing) {
    console.log({
      order_id: o.order_id,
      partner_id: o.partner_id,
      status: o.status,
      customer_name: o.customer_name,
      updated_at: o.updated_at
    });
  }
  process.exit(0);
}
check();
