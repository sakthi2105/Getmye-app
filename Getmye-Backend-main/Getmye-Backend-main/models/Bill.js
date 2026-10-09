const mongoose = require('mongoose');

const BillItemSchema = new mongoose.Schema({
  name: { type: String, required: true },
  quantity: { type: Number, default: 1 },
  price: { type: Number, required: true },
  total: {
    type: Number,
    default: function() {
      return (this.price || 0) * (this.quantity || 1);
    }
  }
}, { _id: false });

const BillSchema = new mongoose.Schema({
  bill_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  order_id: {
    type: String,
    required: true,
    index: true
  },
  partner_id: {
    type: String,
    required: true,
    index: true
  },
  user_id: {
    type: String,
    required: true,
    index: true
  },
  shop_name: {
    type: String,
    default: 'Local Shop / Restaurant'
  },
  items: [BillItemSchema],
  item_total: {
    type: Number,
    required: true
  },
  delivery_fee: {
    type: Number,
    default: 0
  },
  tip_amount: {
    type: Number,
    default: 0
  },
  grand_total: {
    type: Number,
    required: true
  },
  bill_image_url: {
    type: String,
    default: null
  },
  status: {
    type: String,
    enum: ['submitted', 'paid', 'rejected'],
    default: 'submitted'
  },
  submitted_at: {
    type: Date,
    default: Date.now
  }
}, {
  collection: 'bills',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Bill', BillSchema);
