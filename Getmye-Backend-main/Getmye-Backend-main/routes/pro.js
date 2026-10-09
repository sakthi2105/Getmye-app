const express = require('express');
const router = express.Router();
const Profile = require('../models/Profile');

// GET /api/pro/:user_id
router.get('/:user_id', async (req, res) => {
  const { user_id } = req.params;

  try {
    const user = await Profile.findOne({ user_id });

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    let profilePictureUrl = user.profile_picture
      ? `data:image/png;base64,${Buffer.from(user.profile_picture).toString('base64')}`
      : null;

    res.json({
      name: user.name,
      mobile_number: user.mobile_number,
      profile_picture_url: profilePictureUrl
    });
  } catch (err) {
    console.error('Error fetching profile in /api/pro:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
