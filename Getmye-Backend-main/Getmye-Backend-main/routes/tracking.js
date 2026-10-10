const express = require('express');
const router = express.Router();
const LiveLocation = require('../models/LiveLocation');

// POST /api/tracking/update - Partner sends live GPS coordinates
router.post('/update', async (req, res) => {
  try {
    const { partner_id, order_id, latitude, longitude, heading, speed, status } = req.body;
    if (!partner_id || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ error: 'partner_id, latitude, and longitude are required' });
    }

    const loc = await LiveLocation.findOneAndUpdate(
      { partner_id },
      {
        order_id: order_id || null,
        latitude: Number(latitude),
        longitude: Number(longitude),
        heading: Number(heading) || 0,
        speed: Number(speed) || 0,
        status: status || 'in_transit',
        is_online: req.body.is_online !== undefined ? Boolean(req.body.is_online) : true,
        last_updated: new Date()
      },
      { upsert: true, new: true }
    );

    res.json({ success: true, location: loc });
  } catch (err) {
    console.error('Error updating live location:', err);
    res.status(500).json({ error: 'Failed to update live location' });
  }
});

// GET /api/tracking/:partner_id - Customer gets live location of partner
router.get('/:partner_id', async (req, res) => {
  try {
    const loc = await LiveLocation.findOne({ partner_id: req.params.partner_id });
    if (!loc) {
      // Default to Coimbatore center if not found
      return res.json({
        success: true,
        location: {
          partner_id: req.params.partner_id,
          latitude: 11.0168,
          longitude: 76.9558,
          status: 'in_transit',
          is_online: true
        }
      });
    }
    res.json({ success: true, location: loc });
  } catch (err) {
    console.error('Error fetching live location:', err);
    res.status(500).json({ error: 'Failed to fetch live location' });
  }
});

module.exports = router;
