const express = require('express');
const router = express.Router();
const Profile = require('../models/Profile');
const { getNextSequence } = require('../models/Counter');

function toBase64(val) {
  if (!val) return '';
  if (Buffer.isBuffer(val)) return val.toString('base64');
  if (val.buffer && Buffer.isBuffer(val.buffer)) return val.buffer.toString('base64');
  if (typeof val.toString === 'function') {
    const res = val.toString('base64');
    if (res && res !== '[object Object]') return res;
  }
  return Buffer.from(val).toString('base64');
}

function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// ✅ Dispatch SMS via Twilio to the physical phone owning the mobile number
async function sendSmsOtp(mobileNumber, otp) {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_PHONE_NUMBER;

  if (accountSid && authToken && fromNumber) {
    try {
      const client = require('twilio')(accountSid, authToken);
      const formattedTo = mobileNumber.startsWith('+') ? mobileNumber : `+91${mobileNumber}`;
      await client.messages.create({
        body: `Your GETMYE verification OTP is: ${otp}. Do not share this OTP with anyone.`,
        from: fromNumber,
        to: formattedTo
      });
      console.log(`✅ Twilio SMS sent to ${formattedTo}: OTP ${otp}`);
      return true;
    } catch (smsErr) {
      console.error('❌ Twilio SMS error:', smsErr.message);
    }
  } else {
    console.log(`ℹ️ [SMS Gateway] Target device +91${mobileNumber} OTP: ${otp}`);
  }
  return false;
}

// ✅ POST /api/profile — login or create user & send OTP to target mobile number
router.post('/', async (req, res) => {
  console.log('POST /api/profile body:', req.body);
  const { mobile_number } = req.body;

  if (!mobile_number) {
    return res.status(400).json({ message: 'Mobile number is required' });
  }

  try {
    let user = await Profile.findOne({ mobile_number });

    if (!user) {
      const userId = await getNextSequence('user_id', 'usr_', 3);

      try {
        user = await Profile.create({
          user_id: userId,
          mobile_number
        });
      } catch (err) {
        if (err.code === 11000) {
          user = await Profile.findOne({ mobile_number });
        } else {
          throw err;
        }
      }
    }

    const otp = generateOTP();
    user.login_otp = otp;
    user.login_otp_created_at = new Date();
    await user.save();
    console.log(`Generated OTP for ${mobile_number}: ${otp}`);

    // Dispatch SMS to the physical mobile holding that SIM
    await sendSmsOtp(mobile_number, otp);

    res.json({ message: 'OTP sent successfully', otp, user_id: user.user_id });
  } catch (err) {
    console.error('POST /api/profile error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// ✅ GET /api/profile/otp/:mobile_number — target device fetches its incoming OTP
router.get('/otp/:mobile_number', async (req, res) => {
  const { mobile_number } = req.params;
  try {
    const user = await Profile.findOne({ mobile_number });
    if (!user || !user.login_otp) {
      return res.status(404).json({ error: 'No active OTP found for this mobile number' });
    }
    res.json({
      success: true,
      mobile_number: user.mobile_number,
      otp: user.login_otp,
      created_at: user.login_otp_created_at
    });
  } catch (err) {
    console.error('Fetch OTP error:', err);
    res.status(500).json({ error: 'Failed to fetch OTP' });
  }
});

// ✅ POST /api/profile/verify-otp — verify login OTP on server
router.post('/verify-otp', async (req, res) => {
  const { mobile_number, otp } = req.body;
  if (!mobile_number || !otp) {
    return res.status(400).json({ error: 'mobile_number and otp are required' });
  }
  try {
    const user = await Profile.findOne({ mobile_number });
    if (!user) return res.status(404).json({ error: 'User not found' });
    if (user.login_otp === otp.toString().trim()) {
      res.json({ success: true, message: 'OTP verified successfully', user_id: user.user_id });
    } else {
      res.status(400).json({ error: 'Invalid OTP entered' });
    }
  } catch (err) {
    console.error('Verify OTP error:', err);
    res.status(500).json({ error: 'Failed to verify OTP' });
  }
});

// ✅ GET /api/profile/:mobile_number
router.get('/:mobile_number', async (req, res) => {
  const { mobile_number } = req.params;

  try {
    const user = await Profile.findOne({ mobile_number }).lean();

    if (user) {
      res.json({
        user_id: user.user_id,
        name: user.name ?? '',
        email: user.email ?? '',
        mobile_number: user.mobile_number ?? '',
        profile_picture: toBase64(user.profile_picture)
      });
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (err) {
    console.error('❌ Fetch profile error:', err);
    res.status(500).json({ message: 'Server error', error: err.message });
  }
});

// ✅ POST /api/profile/fetch
router.post('/fetch', async (req, res) => {
  const { user_id } = req.body;

  if (!user_id) {
    return res.status(400).json({ message: 'user_id is required' });
  }

  try {
    const user = await Profile.findOne({ user_id }).lean();

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    let profilePictureUrl = user.profile_picture
      ? `data:image/png;base64,${toBase64(user.profile_picture)}`
      : null;

    res.json({
      name: user.name,
      mobile_number: user.mobile_number,
      profile_picture_url: profilePictureUrl
    });
  } catch (err) {
    console.error('Error fetching profile:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// ✅ POST /api/profile/register — Customer new account creation (Mobile + Password)
router.post('/register', async (req, res) => {
  try {
    const { mobile_number, password, name, email } = req.body;
    if (!mobile_number || !password) {
      return res.status(400).json({ error: 'Mobile number and password are required' });
    }
    const cleanMobile = mobile_number.toString().trim();
    if (!/^[0-9]{10}$/.test(cleanMobile)) {
      return res.status(400).json({ error: 'Please enter a valid 10-digit mobile number' });
    }
    const existing = await Profile.findOne({ mobile_number: cleanMobile });
    if (existing) {
      return res.status(400).json({ error: 'This mobile number is already registered. Please login.' });
    }
    const userId = await getNextSequence('user_id', 'usr_', 3);
    const user = await Profile.create({
      user_id: userId,
      mobile_number: cleanMobile,
      password: password.toString().trim(),
      name: (name || '').trim(),
      email: (email || '').trim()
    });
    res.json({
      success: true,
      message: 'Account created successfully',
      user_id: user.user_id,
      mobile_number: user.mobile_number,
      name: user.name,
      email: user.email
    });
  } catch (err) {
    console.error('Customer register error:', err);
    res.status(500).json({ error: 'Failed to create account: ' + err.message });
  }
});

// ✅ POST /api/profile/login — Customer login with Mobile + Password (NO OTP)
router.post('/login', async (req, res) => {
  try {
    const { mobile_number, password } = req.body;
    if (!mobile_number || !password) {
      return res.status(400).json({ error: 'Mobile number and password are required' });
    }
    const cleanMobile = mobile_number.toString().trim();
    const user = await Profile.findOne({ mobile_number: cleanMobile });
    if (!user) {
      return res.status(404).json({ error: 'Account not found. Please create a new account.' });
    }
    if (user.password && user.password !== password.toString().trim()) {
      return res.status(401).json({ error: 'Incorrect password. Please try again.' });
    }
    if (!user.password) {
      // First time password setup for existing users
      user.password = password.toString().trim();
      await user.save();
    }
    res.json({
      success: true,
      message: 'Login successful',
      user_id: user.user_id,
      mobile_number: user.mobile_number,
      name: user.name || '',
      email: user.email || ''
    });
  } catch (err) {
    console.error('Customer login error:', err);
    res.status(500).json({ error: 'Failed to login: ' + err.message });
  }
});

module.exports = router;
