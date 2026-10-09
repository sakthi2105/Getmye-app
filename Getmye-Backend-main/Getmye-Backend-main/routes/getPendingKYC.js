const express = require('express');
const router = express.Router();
const DeliveryPerson = require('../models/DeliveryPerson');

function toBase64(val) {
  if (!val) return '';
  if (Buffer.isBuffer(val)) return val.toString('base64');
  if (val.buffer && Buffer.isBuffer(val.buffer)) return val.buffer.toString('base64');
  if (typeof val.toString === 'function') {
    const res = val.toString('base64');
    if (res && res !== '[object Object]') return res;
  }
  return Buffer.from(val).toString('base64');
}

// GET: list of pending KYC
router.get('/pendingkyc', async (req, res) => {
  try {
    const list = await DeliveryPerson.find({
      know_your_partner_status: 'pending'
    })
      .select('DP_id name mobile_number email aadhar_number pancard_number dp_registered_time')
      .sort({ dp_registered_time: -1 })
      .lean();

    res.status(200).json(list);
  } catch (err) {
    console.error('Error fetching pending KYC:', err);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// GET: full details by DP_id
router.get('/:dp_id', async (req, res) => {
  const { dp_id } = req.params;

  try {
    const person = await DeliveryPerson.findOne({ DP_id: dp_id }).lean();

    if (!person) {
      return res.status(404).json({ error: 'Delivery person not found' });
    }

    // Convert BSON Binary / Buffers to Base64 strings for images
    ['profile_picture', 'aadhar_proof_picture', 'pancard_proof_picture'].forEach(field => {
      person[field] = toBase64(person[field]);
    });

    // Return as array containing the person object to maintain exact compatibility with Admin app
    res.status(200).json([person]);
  } catch (err) {
    console.error('Error fetching DP details:', err);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// POST: update KYC status
router.post('/updateKYCStatus', async (req, res) => {
  const { dpId, status } = req.body;

  if (!dpId || !status) {
    return res.status(400).json({ error: 'dpId and status are required' });
  }

  let newStatus;
  if (status === 'approved') {
    newStatus = 'completed';
  } else if (status === 'rejected') {
    newStatus = 'rejected';
  } else {
    return res.status(400).json({ error: 'Invalid status. Must be "approved" or "rejected"' });
  }

  try {
    const updateData = {
      know_your_partner_status: newStatus
    };

    if (newStatus === 'completed') {
      updateData.kyp_approved_time = new Date();
      updateData.aadhar_kyp = 'approved';
      updateData.pan_kyp = 'approved';
      updateData.profile_kyp = 'approved';
    }

    const updated = await DeliveryPerson.findOneAndUpdate(
      { DP_id: dpId },
      { $set: updateData },
      { returnDocument: 'after' }
    );

    if (!updated) {
      return res.status(404).json({ error: 'Delivery person not found' });
    }

    res.json({ message: 'KYC status updated successfully' });
  } catch (error) {
    console.error('Database error in updateKYCStatus:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
