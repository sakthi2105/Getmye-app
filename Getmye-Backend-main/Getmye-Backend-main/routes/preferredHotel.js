const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PreferredHotel = require('../models/PreferredHotel');
const Counter = require('../models/Counter');

// Helper to generate custom sequence ID e.g. HTL-001
async function getNextSequence(name, prefix = 'HTL-', pad = 3) {
  try {
    const counter = await Counter.findByIdAndUpdate(
      name,
      { $inc: { seq: 1 } },
      { new: true, upsert: true }
    );
    const seqStr = String(counter.seq).padStart(pad, '0');
    return `${prefix}${seqStr}`;
  } catch (err) {
    const random = Math.floor(100 + Math.random() * 900);
    return `${prefix}${Date.now().toString().slice(-4)}${random}`;
  }
}

// Helper to safely query either hotel_id or _id without Mongoose CastError
function buildHotelFilter(id) {
  if (!id) return { _id: null };
  const cleanId = String(id).trim();
  if (mongoose.isValidObjectId(cleanId)) {
    return { $or: [{ hotel_id: cleanId }, { _id: cleanId }] };
  }
  return { hotel_id: cleanId };
}

const DEFAULT_HOTELS = [
  { name: 'Hotel Saravana Bhavan', area: 'Kumbakonam', order_index: 0 },
  { name: 'Hotel A2B', area: 'Kumbakonam', order_index: 1 },
  { name: 'Hotel Aryaas', area: 'Kumbakonam', order_index: 2 },
  { name: 'Hotel Sri Balaji Bhavan', area: 'Kumbakonam', order_index: 3 },
  { name: 'Hotel Rayas', area: 'Kumbakonam', order_index: 4 },
];

// GET /api/preferred-hotels/active - Used by Customer App dropdown
router.get('/active', async (req, res) => {
  try {
    const totalCount = await PreferredHotel.countDocuments();
    if (totalCount === 0) {
      for (const h of DEFAULT_HOTELS) {
        const hid = await getNextSequence('preferred_hotel_id', 'HTL-', 3);
        await PreferredHotel.create({ hotel_id: hid, ...h, is_active: true });
      }
    }

    const hotels = await PreferredHotel.find({ is_active: true })
      .sort({ order_index: 1, created_at: 1 });

    res.json({ success: true, count: hotels.length, hotels });
  } catch (err) {
    console.error('Error fetching active preferred hotels:', err);
    res.status(500).json({ error: 'Failed to fetch active preferred hotels' });
  }
});

// GET /api/preferred-hotels/all - Used by Admin Portal
router.get('/all', async (req, res) => {
  try {
    const totalCount = await PreferredHotel.countDocuments();
    if (totalCount === 0) {
      for (const h of DEFAULT_HOTELS) {
        const hid = await getNextSequence('preferred_hotel_id', 'HTL-', 3);
        await PreferredHotel.create({ hotel_id: hid, ...h, is_active: true });
      }
    }

    const hotels = await PreferredHotel.find().sort({ order_index: 1, created_at: 1 });
    res.json({ success: true, count: hotels.length, hotels });
  } catch (err) {
    console.error('Error fetching all preferred hotels:', err);
    res.status(500).json({ error: 'Failed to fetch preferred hotels' });
  }
});

// POST /api/preferred-hotels/add - Admin adds a new preferred hotel
router.post('/add', async (req, res) => {
  try {
    const { name, area, order_index } = req.body;
    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: 'Hotel name is required' });
    }

    const hotelId = await getNextSequence('preferred_hotel_id', 'HTL-', 3);
    const total = await PreferredHotel.countDocuments();

    const hotel = await PreferredHotel.create({
      hotel_id: hotelId,
      name: String(name).trim(),
      area: area ? String(area).trim() : '',
      order_index: typeof order_index === 'number' ? order_index : total,
      is_active: true
    });

    res.status(201).json({ success: true, hotel });
  } catch (err) {
    console.error('Error adding preferred hotel:', err);
    res.status(500).json({ error: 'Failed to add preferred hotel' });
  }
});

// PUT /api/preferred-hotels/:id - Admin edits hotel
router.put('/:id', async (req, res) => {
  try {
    const { name, area, is_active, order_index } = req.body;
    const hotel = await PreferredHotel.findOne(buildHotelFilter(req.params.id));
    if (!hotel) {
      return res.status(404).json({ error: 'Preferred hotel not found' });
    }

    if (name !== undefined && String(name).trim()) hotel.name = String(name).trim();
    if (area !== undefined) hotel.area = String(area).trim();
    if (is_active !== undefined) hotel.is_active = Boolean(is_active);
    if (order_index !== undefined) hotel.order_index = Number(order_index);

    await hotel.save();
    res.json({ success: true, hotel });
  } catch (err) {
    console.error('Error updating preferred hotel:', err);
    res.status(500).json({ error: 'Failed to update preferred hotel' });
  }
});

// PATCH /api/preferred-hotels/toggle/:id - Admin toggles active/inactive
router.patch('/toggle/:id', async (req, res) => {
  try {
    const hotel = await PreferredHotel.findOne(buildHotelFilter(req.params.id));
    if (!hotel) {
      return res.status(404).json({ error: 'Preferred hotel not found' });
    }
    hotel.is_active = !hotel.is_active;
    await hotel.save();
    res.json({ success: true, hotel });
  } catch (err) {
    console.error('Error toggling preferred hotel:', err);
    res.status(500).json({ error: 'Failed to toggle preferred hotel' });
  }
});

// DELETE /api/preferred-hotels/:id - Admin deletes hotel
router.delete('/:id', async (req, res) => {
  try {
    const deleted = await PreferredHotel.findOneAndDelete(buildHotelFilter(req.params.id));
    if (!deleted) {
      return res.status(404).json({ error: 'Preferred hotel not found' });
    }
    res.json({ success: true, message: 'Preferred hotel deleted' });
  } catch (err) {
    console.error('Error deleting preferred hotel:', err);
    res.status(500).json({ error: 'Failed to delete preferred hotel' });
  }
});

module.exports = router;
