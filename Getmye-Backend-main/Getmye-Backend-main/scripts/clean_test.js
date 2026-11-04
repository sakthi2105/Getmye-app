const { connectDB } = require('../db');
const Order = require('../models/Order');

async function clean() {
  await new Promise(r => setTimeout(r, 2000));
  await Order.deleteMany({ order_id: /^TEST-ORD-/ });
  console.log('Cleaned test orders');
  process.exit(0);
}
clean();
