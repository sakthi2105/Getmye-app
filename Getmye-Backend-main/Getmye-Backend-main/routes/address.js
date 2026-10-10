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
    state: doc.state || 'Tamil Nadu',
    country: doc.country || 'India',
    pincode: doc.pincode || '',
    latitude: doc.latitude !== undefined ? doc.latitude : null,
    longitude: doc.longitude !== undefined ? doc.longitude : null,
    is_default: Boolean(doc.is_default)
  };
}

// GET /api/address/list?user_id=usr_123
router.get('/list', async (req, res) => {
  try {
    const userId = req.query.user_id;
    if (!userId) return res.status(400).json({ message: 'Missing user_id' });

    const addresses = await Address.find({ user_id: userId }).sort({ is_default: -1, created_at: -1 });

    res.json({ success: true, addresses: addresses.map(formatAddress) });
  } catch (err) {
    console.error('❌ GET /api/address/list error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// POST /api/address/set-default
router.post('/set-default', async (req, res) => {
  try {
    const { add_id, user_id } = req.body;
    if (!add_id || !user_id) {
      return res.status(400).json({ message: 'Missing add_id or user_id' });
    }

    // Unset current defaults for user
    await Address.updateMany({ user_id }, { is_default: false });

    const updated = await Address.findOneAndUpdate(
      { add_id, user_id },
      { is_default: true },
      { returnDocument: 'after' }
    );

    res.json({ success: true, message: 'Default address updated', address: formatAddress(updated) });
  } catch (err) {
    console.error('❌ Set default address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// PUT /api/address/update
router.put('/update', async (req, res) => {
  const { add_id, user_id, line1, line2, city, district, state, country, pincode, latitude, longitude, is_default } = req.body;
  if (!add_id || !user_id || !line1) {
    return res.status(400).json({ message: 'Missing required fields: add_id, user_id, line1' });
  }

  try {
    if (is_default) {
      await Address.updateMany({ user_id }, { is_default: false });
    }

    const updated = await Address.findOneAndUpdate(
      { add_id, user_id },
      {
        line1: line1.trim(),
        line2: (line2 || '').trim(),
        city: (city || line1).trim(),
        district: (district || '').trim(),
        state: (state || 'Tamil Nadu').trim(),
        country: (country || 'India').trim(),
        pincode: (pincode || '').toString().trim(),
        latitude: latitude !== undefined && latitude !== null ? Number(latitude) : null,
        longitude: longitude !== undefined && longitude !== null ? Number(longitude) : null,
        is_default: Boolean(is_default)
      },
      { returnDocument: 'after' }
    );

    if (!updated) {
      return res.status(404).json({ message: 'Address not found' });
    }

    res.json({
      success: true,
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
    res.json({ success: true, message: 'Address deleted successfully' });
  } catch (err) {
    console.error('❌ Delete address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// POST /api/address/add
router.post('/add', async (req, res) => {
  const { user_id, line1, line2, city, district, state, country, pincode, latitude, longitude, is_default } = req.body;

  if (!user_id || !line1) {
    return res.status(400).json({ message: 'user_id and line1 (address/location) are required' });
  }

  try {
    const addId = await getNextSequence('add_id', 'add_', 3);

    if (is_default) {
      await Address.updateMany({ user_id }, { is_default: false });
    }

    const newAddress = await Address.create({
      add_id: addId,
      user_id,
      line1: line1.trim(),
      line2: (line2 || '').trim(),
      city: (city || line1).trim(),
      district: (district || '').trim(),
      state: (state || 'Tamil Nadu').trim(),
      country: (country || 'India').trim(),
      pincode: (pincode || '').toString().trim(),
      latitude: latitude !== undefined && latitude !== null ? Number(latitude) : null,
      longitude: longitude !== undefined && longitude !== null ? Number(longitude) : null,
      is_default: Boolean(is_default)
    });

    res.json({
      success: true,
      message: 'Address added successfully',
      added: formatAddress(newAddress)
    });
  } catch (err) {
    console.error('❌ Insert address error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

module.exports = router;
