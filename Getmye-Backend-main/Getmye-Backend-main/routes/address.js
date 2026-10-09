const express = require('express');
const router = express.Router();
const Address = require('../models/Address');
const { getNextSequence } = require('../models/Counter');

// Helper to format address document for frontend compatibility
function formatAddress(doc) {
  if (!doc) return null;
  return {
    add_id: doc.add_id,
    user_id: doc.user_id,
    line1: doc.line1,
    line2: doc.line2 || '',
    city: doc.city,
    district: doc.district || '',
    state: doc.state,
    country: doc.country,
    pincode: doc.pincode
  };
}

// GET /api/address/list?user_id=usr_123
router.get('/list', async (req, res) => {
  try {
    const userId = req.query.user_id;
    if (!userId) return res.status(400).json({ message: 'Missing user_id' });

    const addresses = await Address.find({ user_id: userId }).sort({ created_at: -1 });

    res.json({ addresses: addresses.map(formatAddress) });
  } catch (err) {
    console.error('❌ GET /api/address/list error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// PUT /api/address/update
router.put('/update', async (req, res) => {
  const { add_id, user_id, line1, line2, city, district, state, country, pincode } = req.body;
  if (!add_id || !user_id || !line1 || !city || !state || !country || !pincode) {
    return res.status(400).json({ message: 'Missing required fields' });
  }

  try {
    const updated = await Address.findOneAndUpdate(
      { add_id, user_id },
      {
        line1,
        line2: line2 || '',
        city,
        district: district || '',
        state,
        country,
        pincode
      },
      { returnDocument: 'after' }
    );

    if (!updated) {
      return res.status(404).json({ message: 'Address not found' });
    }

    res.json({
      message: 'Address updated successfully',
      updated: formatAddress(updated)
    });
  } catch (err) {
    console.error('❌ Update address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// DELETE /api/address/delete/:add_id
router.delete('/delete/:add_id', async (req, res) => {
  const { add_id } = req.params;
  if (!add_id) return res.status(400).json({ message: 'Missing add_id' });

  try {
    const deleted = await Address.findOneAndDelete({ add_id });
    if (!deleted) {
      return res.status(404).json({ message: 'Address not found' });
    }
    res.json({ message: 'Address deleted successfully' });
  } catch (err) {
    console.error('❌ Delete address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// POST /api/address/add
router.post('/add', async (req, res) => {
  console.log('✅ Received add request body:', req.body);
  const { user_id, line1, line2, city, district, state, country, pincode } = req.body;

  if (!user_id || !line1 || !city || !state || !country || !pincode) {
    return res.status(400).json({ message: 'Missing required fields' });
  }

  try {
    const addId = await getNextSequence('add_id', 'add_', 3);

    const newAddress = await Address.create({
      add_id: addId,
      user_id,
      line1,
      line2: line2 || '',
      city,
      district: district || '',
      state,
      country,
      pincode
    });

    res.json({
      message: 'Address added successfully',
      added: formatAddress(newAddress)
    });
  } catch (err) {
    console.error('❌ Insert address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

module.exports = router;
