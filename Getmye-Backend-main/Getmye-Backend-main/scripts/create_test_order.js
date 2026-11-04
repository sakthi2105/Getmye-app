const { connectDB } = require('../db');
const Order = require('../models/Order');

async function testOrder() {
  await new Promise(r => setTimeout(r, 2000));

  const testId = 'TEST-ORD-' + Date.now().toString().slice(-4);
  const ord = new Order({
    order_id: testId,
    user_id: 'usr_test',
    customer_name: 'Test Customer',
    customer_phone: '8754805750',
    customer_latitude: 10.95602,
    customer_longitude: 79.37944,
    delivery_address: 'Nageswaran South Street, Kumbakonam - 612001',
    item_name: 'Test Coffee',
    budget: 30,
    status: 'pending',
    current_assigned_partner_id: 'dp_007',
    assignment_expires_at: new Date(Date.now() + 120000),
    assignment_timeout_seconds: 120,
    declined_partners: [],
    created_at: new Date()
  });

  await ord.save();
  console.log('Created test order:', testId);
  process.exit(0);
}

testOrder();
