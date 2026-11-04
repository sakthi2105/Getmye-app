const mongoose = require('mongoose');
const { connectDB } = require('../db');
const Order = require('../models/Order');
const DeliveryPerson = require('../models/DeliveryPerson');

async function check() {
  await new Promise(r => setTimeout(r, 2000));
  
  console.log('=== LATEST 5 ORDERS ===');
  const orders = await Order.find().sort({ created_at: -1 }).limit(5);
  for (const o of orders) {
    console.log({
      order_id: o.order_id,
      user_id: o.user_id,
      customer_name: o.customer_name,
      customer_phone: o.customer_phone,
      delivery_address: o.delivery_address,
      item_name: o.item_name,
      budget: o.budget,
      status: o.status,
      current_assigned_partner_id: o.current_assigned_partner_id,
      partner_id: o.partner_id,
      declined_partners: o.declined_partners,
      created_at: o.created_at
    });
  }

  console.log('\n=== ALL DELIVERY PERSONS ===');
  const dps = await DeliveryPerson.find();
  for (const dp of dps) {
    console.log({
      DP_id: dp.DP_id,
      name: dp.name,
      mobile_number: dp.mobile_number,
      dp_status: dp.dp_status,
      kyp: dp.know_your_partner_status
    });
  }

  process.exit(0);
}

check().catch(e => {
  console.error(e);
  process.exit(1);
});
