const mongoose = require('mongoose');

const LiveLocationSchema = new mongoose.Schema({
  partner_id: {
    type: String,
    required: true,
    index: true
  },
  order_id: {
    type: String,
    default: null,
    index: true
  },
  latitude: {
    type: Number,
    required: true
  },
  longitude: {
    type: Number,
    required: true
  },
  heading: {
    type: Number,
    default: 0
  },
  speed: {
    type: Number,
    default: 0
  },
  status: {
    type: String,
    enum: ['idle', 'accepted', 'purchasing', 'picked_up', 'in_transit', 'delivered'],
    default: 'idle'
  },
  is_online: {
    type: Boolean,
    default: true
  },
  last_updated: {
    type: Date,
    default: Date.now
  }
}, {
  collection: 'live_locations',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('LiveLocation', LiveLocationSchema);
