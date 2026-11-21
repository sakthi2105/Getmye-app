const mongoose = require('mongoose');

const RegisteredDeliveryPersonSchema = new mongoose.Schema({
  DP_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  mobile_number: {
    type: String,
    required: true,
    index: true
  },
  password: {
    type: String,
    default: '123456'
  },
  name: {
    type: String,
    required: true
  },
  email: {
    type: String,
    default: ''
  },
  address: {
    type: String,
    default: ''
  },
  profile_picture: {
    type: Buffer,
    default: null
  },
  aadhar_number: {
    type: String,
    default: ''
  },
  aadhar_proof_picture: {
    type: Buffer,
    default: null
  },
  pancard_number: {
    type: String,
    default: ''
  },
  pancard_proof_picture: {
    type: Buffer,
    default: null
  },
  verification_time_slot: {
    type: String,
    default: ''
  },
  know_your_partner_status: {
    type: String,
    enum: ['pending', 'completed', 'approved', 'rejected'],
    default: 'completed'
  },
  dp_status: {
    type: String,
    default: 'online'
  },
  bank_name: {
    type: String,
    default: ''
  },
  branch_name: {
    type: String,
    default: ''
  },
  bank_account_number: {
    type: String,
    default: ''
  },
  ifsc_code: {
    type: String,
    default: ''
  },
  micr_code: {
    type: String,
    default: ''
  },
  linked_number: {
    type: String,
    default: ''
  },
  dp_registered_time: {
    type: Date,
    default: Date.now
  },
  registered_time: {
    type: Date,
    default: Date.now
  },
  kyp_approved_time: {
    type: Date,
    default: null
  },
  aadhar_kyp: {
    type: String,
    default: null
  },
  pan_kyp: {
    type: String,
    default: null
  },
  profile_kyp: {
    type: String,
    default: null
  },
  reset_otp: {
    type: String,
    default: null
  },
  reset_otp_expires_at: {
    type: Date,
    default: null
  }
}, {
  collection: 'registered delivery person',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

const RegisteredDeliveryPerson = mongoose.models.RegisteredDeliveryPerson ||
  mongoose.model('RegisteredDeliveryPerson', RegisteredDeliveryPersonSchema, 'registered delivery person');

const RegisteredDeliveryPersonSnakeSchema = new mongoose.Schema(RegisteredDeliveryPersonSchema.obj, {
  collection: 'registered_delivery_person',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

const RegisteredDeliveryPersonSnake = mongoose.models.RegisteredDeliveryPersonSnake ||
  mongoose.model('RegisteredDeliveryPersonSnake', RegisteredDeliveryPersonSnakeSchema, 'registered_delivery_person');

module.exports = {
  RegisteredDeliveryPerson,
  RegisteredDeliveryPersonSnake
};
