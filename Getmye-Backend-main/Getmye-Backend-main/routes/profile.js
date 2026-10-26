const express = require('express');
const router = express.Router();
const Profile = require('../models/Profile');
const DeliveryPerson = require('../models/DeliveryPerson');
const { getNextSequence } = require('../models/Counter');

const dns = require('dns');
if (dns.setDefaultResultOrder) {
  dns.setDefaultResultOrder('ipv4first');
}

const nodemailer = require('nodemailer');

// Persistent high-performance pooled SMTP transporter (Forced IPv4 to prevent ENETUNREACH)
// Reliable Gmail SMTP transporter creator (no connection pooling to avoid dead-socket timeouts)
const emailUser = process.env.EMAIL_USER || 'getmye.official@gmail.com';
const emailPass = process.env.EMAIL_PASS || 'wyabgjacrprbdtgu';

function createTransporter() {
  if (!emailUser || !emailPass) return null;
  return nodemailer.createTransport({
    service: 'gmail',
    auth: { user: emailUser, pass: emailPass },
    tls: { rejectUnauthorized: false },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000
  });
}

// Fast email sending helper with automated fallback
async function sendEmailOtp(email, otp) {
  const mailTransporter = createTransporter();
  if (!mailTransporter) {
    console.log(`🔑 [EMAIL OTP GATEWAY] Target email: ${email} -> OTP: ${otp} (Set EMAIL_USER and EMAIL_PASS in .env for live SMTP delivery)`);
    return false;
  }

  const mailOptions = {
    from: `"Getmye" <${emailUser}>`,
    to: email,
    subject: `Your Getmye Password Reset OTP: ${otp}`,
    text: `Your Getmye verification OTP is: ${otp}. This code is valid for 10 minutes. If you did not request this, please ignore this email.`,
    html: `
      <div style="font-family: 'Segoe UI', Helvetica, Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 28px; background: #ffffff; border: 1px solid #e2e8f0; border-radius: 16px;">
        <div style="text-align: center; margin-bottom: 24px;">
          <h1 style="color: #10b981; font-size: 28px; margin: 0; font-weight: 800; letter-spacing: -0.5px;">GET<span style="color: #0f172a;">MYE</span></h1>
          <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Password Reset Verification</p>
        </div>
        <div style="padding: 20px; background: #f8fafc; border-radius: 12px; border: 1px solid #f1f5f9; text-align: center;">
          <p style="color: #334155; font-size: 14px; margin: 0 0 16px 0;">Use the 6-digit verification code below to reset your Getmye account password:</p>
          <div style="background: #ecfdf5; border: 2px dashed #10b981; border-radius: 10px; padding: 14px 28px; font-size: 32px; font-weight: 800; letter-spacing: 8px; color: #047857; display: inline-block; margin: 8px 0 14px 0;">
            ${otp}
          </div>
          <p style="color: #64748b; font-size: 12px; margin: 0;">⏱️ This OTP is valid for <strong>10 minutes</strong>.</p>
        </div>
        <div style="margin-top: 24px; padding-top: 18px; border-top: 1px solid #f1f5f9; text-align: center;">
          <p style="color: #94a3b8; font-size: 12px; margin: 0; line-height: 1.5;">
            If you did not request a password reset, please disregard this email. Your password will remain unchanged.<br/>
            &copy; ${new Date().getFullYear()} Getmye. All rights reserved.
          </p>
        </div>
      </div>
    `
  };

  try {
    const info = await mailTransporter.sendMail(mailOptions);
    console.log(`✅ [EMAIL OTP SENT] Fast dispatch to ${email} (Message ID: ${info.messageId})`);
    return true;
  } catch (err) {
    console.warn(`⚠️ [EMAIL OTP RETRY] Service dispatch notice (${err.message}). Retrying on Port 465 SSL...`);
    try {
      const fallbackTransporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: { user: emailUser, pass: emailPass },
        tls: { rejectUnauthorized: false },
        connectionTimeout: 10000,
        greetingTimeout: 10000,
        socketTimeout: 15000
      });
      const info = await fallbackTransporter.sendMail(mailOptions);
      console.log(`✅ [EMAIL OTP SENT] Fallback dispatch to ${email} (Message ID: ${info.messageId})`);
      return true;
    } catch (fallbackErr) {
      console.error(`⚠️ [EMAIL OTP ERROR] Nodemailer error:`, fallbackErr.message);
      return false;
    }
  }
}

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

// ✅ POST /api/profile/register — Customer new account creation (Mobile + Password + Email)
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
    const cleanEmail = (email || '').toString().trim().toLowerCase();
    if (!cleanEmail || !cleanEmail.includes('@') || !cleanEmail.includes('.')) {
      return res.status(400).json({ error: 'A valid Email ID is mandatory to create an account' });
    }
    const existing = await Profile.findOne({ mobile_number: cleanMobile });
    if (existing) {
      return res.status(400).json({ error: 'This mobile number is already registered. Please login.' });
    }
    const existingEmail = await Profile.findOne({ email: cleanEmail });
    if (existingEmail) {
      return res.status(400).json({ error: 'This email ID is already registered with another account. Please use a different email.' });
    }
    const userId = await getNextSequence('user_id', 'usr_', 3);
    const user = await Profile.create({
      user_id: userId,
      mobile_number: cleanMobile,
      password: password.toString().trim(),
      name: (name || '').trim(),
      email: cleanEmail
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

function maskEmail(email) {
  if (!email || !email.includes('@')) return email || '';
  const [name, domain] = email.split('@');
  if (name.length <= 2) return `${name[0]}*@${domain}`;
  const start = name.slice(0, 2);
  const end = name.slice(-1);
  return `${start}****${end}@${domain}`;
}

// ✅ POST /api/profile/forgot-password/send-otp — Look up user by mobile number or email, and dispatch OTP to registered email
router.post('/forgot-password/send-otp', async (req, res) => {
  try {
    const { mobile_number, email, role } = req.body;
    let account = null;
    let foundRole = role || 'customer';

    if (mobile_number) {
      const cleanMobile = mobile_number.toString().trim().replace(/[^0-9]/g, '').slice(-10);
      if (!cleanMobile || cleanMobile.length !== 10) {
        return res.status(400).json({ error: 'Please enter a valid 10-digit registered mobile number' });
      }
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
        foundRole = 'partner';
      } else if (role === 'customer') {
        account = await Profile.findOne({ mobile_number: cleanMobile });
        foundRole = 'customer';
      } else {
        account = await Profile.findOne({ mobile_number: cleanMobile });
        if (!account) {
          account = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
          if (account) foundRole = 'partner';
        }
      }
      if (!account) {
        return res.status(404).json({ error: `No registered account found with mobile number ${cleanMobile}.` });
      }
    } else if (email) {
      const cleanEmail = email.toString().trim().toLowerCase();
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ email: cleanEmail });
        foundRole = 'partner';
      } else if (role === 'customer') {
        account = await Profile.findOne({ email: cleanEmail });
        foundRole = 'customer';
      } else {
        account = await Profile.findOne({ email: cleanEmail });
        if (!account) {
          account = await DeliveryPerson.findOne({ email: cleanEmail });
          if (account) foundRole = 'partner';
        }
      }
      if (!account) {
        return res.status(404).json({ error: `No registered account found with email ${cleanEmail}.` });
      }
    } else {
      return res.status(400).json({ error: 'Please enter your registered mobile number' });
    }

    let targetEmail = (account.email || '').toString().trim().toLowerCase();
    if (!targetEmail || !targetEmail.includes('@')) {
      if (email && email.toString().trim().includes('@')) {
        targetEmail = email.toString().trim().toLowerCase();
        account.email = targetEmail;
        await account.save();
      } else {
        return res.status(400).json({
          error: 'No email address is linked to this mobile number in database. Please enter your email ID to link and receive OTP.',
          needs_email: true,
          mobile_number: account.mobile_number
        });
      }
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    account.reset_otp = otp;
    account.reset_otp_expires_at = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes expiry
    await account.save();

    // Dispatch email to the user's registered email address
    const emailSent = await sendEmailOtp(targetEmail, otp);
    if (!emailSent) {
      console.warn(`⚠️ [EMAIL OTP WARNING] Email delivery could not complete for ${targetEmail}`);
    }

    res.json({
      success: true,
      message: `Password reset OTP has been sent to your registered email (${maskEmail(targetEmail)})`,
      otp, // included for testing convenience
      email: targetEmail,
      masked_email: maskEmail(targetEmail),
      mobile_number: account.mobile_number,
      role: foundRole,
      name: account.name || ''
    });
  } catch (err) {
    console.error('Forgot password send OTP error:', err);
    res.status(500).json({ error: 'Failed to send OTP: ' + err.message });
  }
});

// ✅ POST /api/profile/forgot-password/verify-otp — Verify entered email OTP
router.post('/forgot-password/verify-otp', async (req, res) => {
  try {
    const { mobile_number, email, otp, role } = req.body;
    if (!otp) {
      return res.status(400).json({ error: 'OTP is required' });
    }
    const cleanOtp = otp.toString().trim();

    let account = null;
    if (mobile_number) {
      const cleanMobile = mobile_number.toString().trim().replace(/[^0-9]/g, '').slice(-10);
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
      } else if (role === 'customer') {
        account = await Profile.findOne({ mobile_number: cleanMobile });
      } else {
        account = await Profile.findOne({ mobile_number: cleanMobile }) || await DeliveryPerson.findOne({ mobile_number: cleanMobile });
      }
    } else if (email) {
      const cleanEmail = email.toString().trim().toLowerCase();
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ email: cleanEmail });
      } else if (role === 'customer') {
        account = await Profile.findOne({ email: cleanEmail });
      } else {
        account = await Profile.findOne({ email: cleanEmail }) || await DeliveryPerson.findOne({ email: cleanEmail });
      }
    }

    if (!account) {
      return res.status(404).json({ error: 'Account not found' });
    }

    if (!account.reset_otp || account.reset_otp !== cleanOtp) {
      return res.status(400).json({ error: 'Invalid OTP entered. Please check and try again.' });
    }

    if (account.reset_otp_expires_at && new Date() > new Date(account.reset_otp_expires_at)) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new OTP.' });
    }

    res.json({
      success: true,
      message: 'OTP verified successfully'
    });
  } catch (err) {
    console.error('Forgot password verify OTP error:', err);
    res.status(500).json({ error: 'Failed to verify OTP: ' + err.message });
  }
});

// ✅ POST /api/profile/forgot-password/reset-password — Set new password with OTP
router.post('/forgot-password/reset-password', async (req, res) => {
  try {
    const { mobile_number, email, otp, new_password, role } = req.body;
    if (!otp || !new_password) {
      return res.status(400).json({ error: 'OTP and new password are required' });
    }
    const cleanOtp = otp.toString().trim();
    const cleanPass = new_password.toString().trim();

    if (cleanPass.length < 4) {
      return res.status(400).json({ error: 'Password must be at least 4 characters long' });
    }

    let account = null;
    let foundRole = role || 'customer';

    if (mobile_number) {
      const cleanMobile = mobile_number.toString().trim().replace(/[^0-9]/g, '').slice(-10);
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
        foundRole = 'partner';
      } else if (role === 'customer') {
        account = await Profile.findOne({ mobile_number: cleanMobile });
        foundRole = 'customer';
      } else {
        account = await Profile.findOne({ mobile_number: cleanMobile });
        if (!account) {
          account = await DeliveryPerson.findOne({ mobile_number: cleanMobile });
          if (account) foundRole = 'partner';
        }
      }
    } else if (email) {
      const cleanEmail = email.toString().trim().toLowerCase();
      if (role === 'partner') {
        account = await DeliveryPerson.findOne({ email: cleanEmail });
        foundRole = 'partner';
      } else if (role === 'customer') {
        account = await Profile.findOne({ email: cleanEmail });
        foundRole = 'customer';
      } else {
        account = await Profile.findOne({ email: cleanEmail });
        if (!account) {
          account = await DeliveryPerson.findOne({ email: cleanEmail });
          if (account) foundRole = 'partner';
        }
      }
    }

    if (!account) {
      return res.status(404).json({ error: 'Account not found' });
    }

    if (!account.reset_otp || account.reset_otp !== cleanOtp) {
      return res.status(400).json({ error: 'Invalid or expired OTP. Cannot reset password.' });
    }

    if (account.reset_otp_expires_at && new Date() > new Date(account.reset_otp_expires_at)) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new OTP.' });
    }

    account.password = cleanPass;
    account.reset_otp = null;
    account.reset_otp_expires_at = null;
    await account.save();

    console.log(`✅ [PASSWORD RESET SUCCESS] Mobile: ${account.mobile_number}, Email: ${account.email}, Role: ${foundRole}`);

    res.json({
      success: true,
      message: 'Password has been reset successfully! You can now log in with your new password.',
      role: foundRole,
      mobile_number: account.mobile_number,
      email: account.email
    });
  } catch (err) {
    console.error('Forgot password reset error:', err);
    res.status(500).json({ error: 'Failed to reset password: ' + err.message });
  }
});

module.exports = router;
