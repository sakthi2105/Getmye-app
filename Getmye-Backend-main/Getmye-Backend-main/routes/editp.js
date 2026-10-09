const express = require('express');
const router = express.Router();
const multer = require('multer');
const Profile = require('../models/Profile');

const upload = multer({ storage: multer.memoryStorage() });

// PUT /api/editp/update
router.put('/update', upload.single('profile_picture'), async (req, res) => {
  try {
    const { name, mobile_number, email } = req.body;
    const profilePictureBuffer = req.file ? req.file.buffer : null;

    if (!mobile_number) {
      return res.status(400).json({ message: 'mobile_number is required' });
    }

    const updateFields = {};
    if (name !== undefined) updateFields.name = name;
    if (email !== undefined) updateFields.email = email;
    if (profilePictureBuffer) updateFields.profile_picture = profilePictureBuffer;

    const updated = await Profile.findOneAndUpdate(
      { mobile_number },
      { $set: updateFields },
      { returnDocument: 'after' }
    );

    if (!updated) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ message: '✅ Profile updated successfully' });
  } catch (err) {
    console.error('❌ Update error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

module.exports = router;
