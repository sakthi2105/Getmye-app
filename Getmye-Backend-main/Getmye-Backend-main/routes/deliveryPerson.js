const express = require('express');
const multer = require('multer');
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');

const router = express.Router();
const storage = multer.memoryStorage();
const upload = multer({ storage });

// POST /api/deliveryperson/add
router.post('/add', upload.fields([
  { name: 'personImage', maxCount: 1 },
  { name: 'aadhaarImage', maxCount: 1 },
  { name: 'pancardImage', maxCount: 1 }
]), async (req, res) => {
  try {
    const {
      mobile_number, name, email, address,
      aadhar_number, pancard_number, know_your_partner_status,
      dp_status, bank_name, branch_name, bank_account_number,
      ifsc_code, micr_code, linked_number, password
    } = req.body;

    if (!mobile_number) {
      return res.status(400).json({ message: 'Mobile number is required' });
    }

    const cleanMobile = mobile_number.toString().trim();
    const existing = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
    if (existing) {
      return res.status(400).json({ message: 'Mobile number is already registered as partner. Please log in.' });
    }

    const personImage = req.files?.personImage ? req.files.personImage[0].buffer : null;
    const aadhaarImage = req.files?.aadhaarImage ? req.files.aadhaarImage[0].buffer : null;
    const pancardImage = req.files?.pancardImage ? req.files.pancardImage[0].buffer : null;

    const dpId = await getNextSequence('dp_id', 'dp_', 3);

    await DeliveryPerson.create({
      DP_id: dpId,
      mobile_number: cleanMobile,
      password: (password || '123456').toString().trim(),
      name,
      email: email || '',
      address: address || '',
      profile_picture: personImage,
      aadhar_number: aadhar_number || '',
      aadhar_proof_picture: aadhaarImage,
      pancard_number: pancard_number || '',
      pancard_proof_picture: pancardImage,
      know_your_partner_status: know_your_partner_status || 'completed',
      dp_status: dp_status || 'online',
      bank_name: bank_name || '',
      branch_name: branch_name || '',
      bank_account_number: bank_account_number || '',
      ifsc_code: ifsc_code || '',
      micr_code: micr_code || '',
      linked_number: linked_number || '',
      dp_registered_time: new Date()
    });

    res.json({ message: '✅ Delivery person added successfully!', dp_id: dpId });
  } catch (error) {
    console.error('❌ Insert delivery person error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// ✅ POST /api/deliveryperson/register — Partner account creation requiring BOTH Mobile Number & Email ID
router.post('/register', async (req, res) => {
  try {
    const { mobile_number, email, password, name, address } = req.body;
    if (!mobile_number || !password || !email) {
      return res.status(400).json({ error: 'Mobile number, email ID, and password are all required' });
    }
    const cleanMobile = mobile_number.toString().trim();
    const cleanEmail = email.toString().trim().toLowerCase();

    if (!/^[0-9]{10}$/.test(cleanMobile)) {
      return res.status(400).json({ error: 'Please enter a valid 10-digit mobile number' });
    }
    if (!cleanEmail.includes('@') || !cleanEmail.includes('.')) {
      return res.status(400).json({ error: 'Please enter a valid email address' });
    }

    const existing = await DeliveryPerson.findOne({
      $or: [
        { mobile_number: cleanMobile },
        { email: cleanEmail }
      ]
    });
    if (existing) {
      const field = existing.mobile_number === cleanMobile ? 'Mobile number' : 'Email ID';
      return res.status(400).json({ error: `${field} is already registered as partner. Please log in.` });
    }

    const dpId = await getNextSequence('dp_id', 'dp_', 3);
    const partner = await DeliveryPerson.create({
      DP_id: dpId,
      mobile_number: cleanMobile,
      email: cleanEmail,
      password: password.toString().trim(),
      name: (name || 'Delivery Partner').trim(),
      address: (address || '').trim(),
      know_your_partner_status: 'completed',
      dp_status: 'online',
      dp_registered_time: new Date()
    });
    res.json({
      success: true,
      message: 'Delivery partner registered successfully',
      dp_id: partner.DP_id,
      name: partner.name,
      mobile_number: partner.mobile_number,
      email: partner.email,
      address: partner.address
    });
  } catch (err) {
    console.error('Partner register error:', err);
    res.status(500).json({ error: 'Failed to create partner account: ' + err.message });
  }
});

// ✅ POST /api/deliveryperson/login — Partner login with Mobile or Email + Password (NO OTP)
router.post('/login', async (req, res) => {
  try {
    const { mobile_number, email, identifier, password } = req.body;
    const cleanMobile = (mobile_number || '').toString().trim();
    const cleanEmail = (email || '').toString().trim().toLowerCase();
    const cleanId = (identifier || '').toString().trim();

    const input = cleanMobile || cleanEmail || cleanId;
    if (!input || !password) {
      return res.status(400).json({ error: 'Mobile number or email ID and password are required' });
    }

    const orList = [];
    if (cleanMobile) orList.push({ mobile_number: cleanMobile });
    if (cleanEmail) orList.push({ email: cleanEmail });
    if (cleanId) {
      orList.push({ mobile_number: cleanId });
      orList.push({ email: cleanId.toLowerCase() });
    }
    if (orList.length === 0) {
      orList.push({ mobile_number: input }, { email: input.toLowerCase() });
    }

    const partner = await DeliveryPerson.findOne({ $or: orList });
    if (!partner) {
      return res.status(404).json({ error: 'Delivery partner account not found. Please register.' });
    }
    if (partner.password && partner.password !== password.toString().trim()) {
      return res.status(401).json({ error: 'Incorrect password. Please try again.' });
    }
    if (!partner.password) {
      partner.password = password.toString().trim();
      await partner.save();
    }
    res.json({
      success: true,
      message: 'Login successful',
      dp_id: partner.DP_id,
      name: partner.name || 'Delivery Partner',
      mobile_number: partner.mobile_number,
      email: partner.email || '',
      address: partner.address || ''
    });
  } catch (err) {
    console.error('Partner login error:', err);
    res.status(500).json({ error: 'Failed to login: ' + err.message });
  }
});

// GET /api/deliveryperson/missing-kyp
router.get('/missing-kyp', async (req, res) => {
  try {
    const results = await DeliveryPerson.find({
      $or: [
        { aadhar_kyp: null },
        { aadhar_kyp: { $exists: false } },
        { pan_kyp: null },
        { pan_kyp: { $exists: false } },
        { profile_kyp: null },
        { profile_kyp: { $exists: false } }
      ]
    }).select('DP_id name email mobile_number dp_registered_time');

    res.json(results);
  } catch (err) {
    console.error('Database error in missing-kyp:', err);
    res.status(500).send('Server error');
  }
});

module.exports = router;
