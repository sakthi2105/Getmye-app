const { connectDB } = require('../db');
const Order = require('../models/Order');

async function check() {
  await new Promise(r => setTimeout(r, 2000));
  const o = await Order.findOne({ order_id: 'ORD-0398' });
  console.log(JSON.stringify(o, null, 2));
  process.exit(0);
}
check();
