const mongoose = require('mongoose');

const AddressSchema = new mongoose.Schema({
  add_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  user_id: {
    type: String,
    required: true,
    index: true
  },
  line1: {
    type: String,
    required: true
  },
  line2: {
    type: String,
    default: ''
  },
  city: {
    type: String,
    required: true
  },
  district: {
    type: String,
    default: ''
  },
  state: {
    type: String,
    required: true
  },
  country: {
    type: String,
    required: true
  },
  pincode: {
    type: String,
    required: true
  }
}, {
  collection: 'address',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Address', AddressSchema);
