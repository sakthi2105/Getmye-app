const mongoose = require('mongoose');
require('dotenv').config();
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');

const partnersToAdd = [
  {
    name: 'Vivin',
    mobile_number: '9025583122',
    email: 'vivinvincent575@gmail.com',
    password: 'Vivin2004',
    address: 'Kumbakonam'
  },
  {
    name: 'Yaseen',
    mobile_number: '8220177221',
    email: 'yaseenguy410@gmail.com',
    password: 'Yaseen2005',
    address: 'Kumbakonam'
  },
  {
    name: 'Vinith',
    mobile_number: '9787163367',
    email: 'sakthivelvinith962@gmail.com',
    password: 'Vinith2005',
    address: 'Kumbakonam'
  },
  {
    name: 'Jagath',
    mobile_number: '7448465021',
    email: 'jagathratchagan5025@gmail.com',
    password: 'Jagath2005',
    address: 'Kumbakonam'
  }
];

async function addDeliveryPersons() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('Connected to MongoDB');

    for (const p of partnersToAdd) {
      let existing = await DeliveryPerson.findOne({
        $or: [
          { mobile_number: p.mobile_number },
          { email: p.email }
        ]
      });

      if (existing) {
        existing.name = p.name;
        existing.mobile_number = p.mobile_number;
        existing.email = p.email;
        existing.password = p.password;
        existing.know_your_partner_status = 'approved';
        existing.dp_status = 'online';
        await existing.save();
        console.log(`Updated existing Delivery Person [${existing.DP_id}]: ${existing.name} (${existing.mobile_number})`);
      } else {
        const dpId = await getNextSequence('dp_id', 'dp_', 3);
        const newDp = await DeliveryPerson.create({
          DP_id: dpId,
          mobile_number: p.mobile_number,
          email: p.email,
          password: p.password,
          name: p.name,
          address: p.address,
          know_your_partner_status: 'approved',
          dp_status: 'online',
          dp_registered_time: new Date()
        });
        console.log(`Created new Delivery Person [${newDp.DP_id}]: ${newDp.name} (${newDp.mobile_number})`);
      }
    }

    const allDps = await DeliveryPerson.find({}).select('DP_id name mobile_number email password dp_status know_your_partner_status').lean();
    console.log('\n=== All Delivery Persons in MongoDB ===');
    console.log(JSON.stringify(allDps, null, 2));

    process.exit(0);
  } catch (err) {
    console.error('Error adding delivery persons:', err);
    process.exit(1);
  }
}

addDeliveryPersons();
