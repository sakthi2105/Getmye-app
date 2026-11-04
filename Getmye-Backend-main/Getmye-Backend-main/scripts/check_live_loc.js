const mongoose = require('mongoose');
const { connectDB } = require('../db');
const Order = require('../models/Order');
const DeliveryPerson = require('../models/DeliveryPerson');
const LiveLocation = require('../models/LiveLocation');

async function check() {
  await new Promise(r => setTimeout(r, 2000));
  
  console.log('=== LIVE LOCATIONS ===');
  const locs = await LiveLocation.find();
  for (const l of locs) {
    console.log({
      partner_id: l.partner_id,
      latitude: l.latitude,
      longitude: l.longitude,
      is_online: l.is_online,
      status: l.status,
      updated_at: l.updated_at
    });
  }

  process.exit(0);
}

check().catch(e => {
  console.error(e);
  process.exit(1);
});
