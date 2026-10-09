const mongoose = require('mongoose');

const NotificationSchema = new mongoose.Schema({
  notification_id: {
    type: String,
    required: true,
    unique: true
  },
  recipient_id: {
    type: String,
    required: true,
    index: true
  },
  recipient_type: {
    type: String,
    enum: ['customer', 'partner'],
    required: true
  },
  order_id: {
    type: String,
    default: null
  },
  title: {
    type: String,
    required: true
  },
  message: {
    type: String,
    required: true
  },
  is_read: {
    type: Boolean,
    default: false
  }
}, {
  collection: 'notifications',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Notification', NotificationSchema);
