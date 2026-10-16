const mongoose = require('mongoose');

const OrderSchema = new mongoose.Schema({
  order_id: {
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
  customer_name: {
    type: String,
    default: 'Customer'
  },
  customer_phone: {
    type: String,
    default: ''
  },
  customer_latitude: {
    type: Number,
    default: null
  },
  customer_longitude: {
    type: Number,
    default: null
  },
  delivery_address: {
    type: String,
    required: true
  },
  item_name: {
    type: String,
    required: true
  },
  budget: {
    type: Number,
    default: 0
  },
  partner_id: {
    type: String,
    default: null,
    index: true
  },
  partner_name: {
    type: String,
    default: null
  },
  partner_phone: {
    type: String,
    default: null
  },
  partner_profile_picture: {
    type: String,
    default: null
  },
  status: {
    type: String,
    enum: [
      'pending',
      'accepted',
      'purchasing_food',
      'bill_sent',
      'picked_up',
      'in_transit',
      'delivered',
      'cancelled',
      'declined',
      'rejected'
    ],
    default: 'pending',
    index: true
  },
  decline_reason: {
    type: String,
    default: null
  },
  declined_by: {
    type: String,
    default: null
  },
  current_assigned_partner_id: {
    type: String,
    default: null,
    index: true
  },
  assignment_expires_at: {
    type: Date,
    default: null,
    index: true
  },
  assignment_timeout_seconds: {
    type: Number,
    default: 120
  },
  declined_partners: {
    type: [String],
    default: []
  },
  timed_out_partners: {
    type: [String],
    default: []
  },
  assignment_history: [
    {
      partner_id: { type: String },
      partner_name: { type: String, default: '' },
      distance_km: { type: Number, default: 0 },
      offered_at: { type: Date, default: Date.now },
      responded_at: { type: Date, default: null },
      status: {
        type: String,
        enum: ['offered', 'accepted', 'declined', 'timeout'],
        default: 'offered'
      },
      decline_reason: { type: String, default: null }
    }
  ],
  delivery_fee: {
    type: Number,
    default: 0
  },
  item_total: {
    type: Number,
    default: 0
  },
  tip_amount: {
    type: Number,
    default: 0
  },
  grand_total: {
    type: Number,
    default: 0
  },
  bill_image_url: {
    type: String,
    default: null
  },
  cod_otp: {
    type: String,
    default: '1234'
  },
  payment_method: {
    type: String,
    default: 'Cash on Delivery (COD)'
  },
  payment_status: {
    type: String,
    enum: ['pending', 'paid', 'success', 'failed'],
    default: 'pending'
  },
  cancel_reason: {
    type: String,
    default: null
  },
  accepted_at: {
    type: Date,
    default: null
  },
  picked_up_at: {
    type: Date,
    default: null
  },
  delivered_at: {
    type: Date,
    default: null
  },
  messages: [
    {
      sender: { type: String, enum: ['customer', 'partner'], required: true },
      sender_name: { type: String, default: '' },
      text: { type: String, required: true },
      time: { type: String, default: '' },
      timestamp: { type: Date, default: Date.now }
    }
  ]
}, {
  collection: 'orders',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

OrderSchema.index({ partner_id: 1, created_at: -1 });
OrderSchema.index({ created_at: -1 });

module.exports = mongoose.model('Order', OrderSchema);
