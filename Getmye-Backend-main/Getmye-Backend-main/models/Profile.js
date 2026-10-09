const mongoose = require('mongoose');

const ProfileSchema = new mongoose.Schema({
  user_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  mobile_number: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  password: {
    type: String,
    default: ''
  },
  name: {
    type: String,
    default: ''
  },
  email: {
    type: String,
    default: ''
  },
  profile_picture: {
    type: Buffer,
    default: null
  },
  fixed_order_otp: {
    type: String,
    default: null
  },
  login_otp: {
    type: String,
    default: null
  },
  login_otp_created_at: {
    type: Date,
    default: null
  },
  created_at: {
    type: Date,
    default: Date.now
  }
}, {
  collection: 'profile',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Profile', ProfileSchema);
