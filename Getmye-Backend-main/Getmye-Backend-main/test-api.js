const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');

const BASE_URL = 'http://127.0.0.1:5000';

async function runTests() {
  console.log(' Starting End-to-End MongoDB Migration Verification Tests...\n');
  let testUserMobile = '9876543210';
  let userId = '';
  let addressId = '';
  let dpId = '';

  try {
    // 1. Health check
    console.log('1️⃣ Testing GET /api/health...');
    const health = await axios.get(`${BASE_URL}/api/health`);
    console.log('   Response:', health.data);
    if (health.data.status !== 'OK') throw new Error('Health check failed');
    console.log('   Health check passed.\n');

    // 2. Profile creation (POST /api/profile)
    console.log('2️⃣ Testing POST /api/profile (New user login/signup)...');
    const profileRes1 = await axios.post(`${BASE_URL}/api/profile`, { mobile_number: testUserMobile });
    console.log('   Response:', profileRes1.data);
    userId = profileRes1.data.user_id;
    if (!userId || !profileRes1.data.otp) throw new Error('Invalid response from /api/profile');
    console.log(`   User created with ID: ${userId}, OTP: ${profileRes1.data.otp}\n`);

    // 3. Profile duplicate/existing login
    console.log('3️⃣ Testing POST /api/profile with existing mobile...');
    const profileRes2 = await axios.post(`${BASE_URL}/api/profile`, { mobile_number: testUserMobile });
    if (profileRes2.data.user_id !== userId) throw new Error('User ID mismatch on repeat login');
    console.log(`   Existing user recognized correctly: ${profileRes2.data.user_id}\n`);

    // 4. Fetch profile by mobile (GET /api/profile/:mobile_number)
    console.log('4️⃣ Testing GET /api/profile/:mobile_number...');
    const getProfileRes = await axios.get(`${BASE_URL}/api/profile/${testUserMobile}`);
    console.log('   Response:', getProfileRes.data);
    if (getProfileRes.data.user_id !== userId) throw new Error('user_id mismatch in get profile');
    console.log('   Profile retrieved successfully.\n');

    // 5. Update profile (PUT /api/editp/update)
    console.log('5️⃣ Testing PUT /api/editp/update (multipart with profile picture)...');
    const form = new FormData();
    form.append('name', 'John Doe');
    form.append('email', 'johndoe@example.com');
    form.append('mobile_number', testUserMobile);
    form.append('profile_picture', Buffer.from('mock_image_bytes_here'), { filename: 'avatar.png' });

    const updateProfileRes = await axios.put(`${BASE_URL}/api/editp/update`, form, {
      headers: form.getHeaders()
    });
    console.log('   Response:', updateProfileRes.data);
    console.log('   Profile updated successfully.\n');

    // 6. Verify updated profile
    console.log('6️⃣ Verifying updated profile fields and base64 picture...');
    const updatedProfile = await axios.get(`${BASE_URL}/api/profile/${testUserMobile}`);
    console.log('   Name:', updatedProfile.data.name, '| Email:', updatedProfile.data.email);
    console.log('   Profile picture base64 prefix:', updatedProfile.data.profile_picture.substring(0, 30));
    if (updatedProfile.data.name !== 'John Doe') throw new Error('Name was not updated');
    if (!updatedProfile.data.profile_picture) throw new Error('Profile picture was not saved');
    console.log('   Profile verification passed.\n');

    // 7. GET /api/pro/:user_id
    console.log('7️⃣ Testing GET /api/pro/:user_id...');
    const proRes = await axios.get(`${BASE_URL}/api/pro/${userId}`);
    console.log('   Response:', proRes.data);
    if (proRes.data.name !== 'John Doe') throw new Error('pro/:user_id returned wrong name');
    console.log('   pro route passed.\n');

    // 8. Address Add (POST /api/address/add)
    console.log('8️⃣ Testing POST /api/address/add...');
    const addAddressRes = await axios.post(`${BASE_URL}/api/address/add`, {
      user_id: userId,
      line1: '123 Tech Street',
      line2: 'Apartment 4B',
      city: 'Bangalore',
      district: 'Bangalore Urban',
      state: 'Karnataka',
      country: 'India',
      pincode: '560001'
    });
    console.log('   Response:', addAddressRes.data);
    addressId = addAddressRes.data.added.add_id;
    if (!addressId) throw new Error('add_id not generated');
    console.log(`   Address added with ID: ${addressId}\n`);

    // 9. Address List (GET /api/address/list)
    console.log('9️⃣ Testing GET /api/address/list...');
    const listAddressRes = await axios.get(`${BASE_URL}/api/address/list?user_id=${userId}`);
    console.log(`   Found ${listAddressRes.data.addresses.length} address(es)`);
    if (listAddressRes.data.addresses.length === 0) throw new Error('No addresses returned');
    console.log('   Address list passed.\n');

    // 10. Address Update (PUT /api/address/update)
    console.log('🔟 Testing PUT /api/address/update...');
    const updateAddressRes = await axios.put(`${BASE_URL}/api/address/update`, {
      add_id: addressId,
      user_id: userId,
      line1: '456 Updated Tech Park',
      line2: 'Suite 100',
      city: 'Bangalore',
      district: 'Bangalore Urban',
      state: 'Karnataka',
      country: 'India',
      pincode: '560002'
    });
    console.log('   Response:', updateAddressRes.data);
    if (updateAddressRes.data.updated.line1 !== '456 Updated Tech Park') throw new Error('Address not updated');
    console.log('   Address update passed.\n');

    // 11. Delivery Person Add (POST /api/deliveryperson/add)
    console.log('1️⃣1️⃣ Testing POST /api/deliveryperson/add (Partner Registration with KYC docs)...');
    const dpForm = new FormData();
    dpForm.append('name', 'Ravi Kumar');
    dpForm.append('mobile_number', '9988776655');
    dpForm.append('email', 'ravi.dp@example.com');
    dpForm.append('address', '789 Rider Colony');
    dpForm.append('aadhar_number', '123456789012');
    dpForm.append('pancard_number', 'ABCDE1234F');
    dpForm.append('bank_name', 'HDFC Bank');
    dpForm.append('branch_name', 'Indiranagar');
    dpForm.append('bank_account_number', '50100012345678');
    dpForm.append('ifsc_code', 'HDFC0001234');
    dpForm.append('micr_code', '560240002');
    dpForm.append('linked_number', '9988776655');
    dpForm.append('personImage', Buffer.from('mock_person_photo'), { filename: 'selfie.jpg' });
    dpForm.append('aadhaarImage', Buffer.from('mock_aadhaar_card'), { filename: 'aadhaar.jpg' });
    dpForm.append('pancardImage', Buffer.from('mock_pancard_doc'), { filename: 'pan.jpg' });

    const dpAddRes = await axios.post(`${BASE_URL}/api/deliveryperson/add`, dpForm, {
      headers: dpForm.getHeaders()
    });
    console.log('   Response:', dpAddRes.data);
    console.log('   Delivery Person registered successfully.\n');

    // 12. Pending KYC list for Admin (GET /api/getPendingKYC/pendingkyc)
    console.log('1️⃣2️⃣ Testing GET /api/getPendingKYC/pendingkyc (Admin verification queue)...');
    const pendingListRes = await axios.get(`${BASE_URL}/api/getPendingKYC/pendingkyc`);
    console.log(`   Pending partners count: ${pendingListRes.data.length}`);
    const foundDp = pendingListRes.data.find(dp => dp.mobile_number === '9988776655');
    if (!foundDp) throw new Error('Registered delivery partner not found in pending list');
    dpId = foundDp.DP_id;
    console.log(`   Found partner DP_id: ${dpId}, Name: ${foundDp.name}\n`);

    // 13. Admin Video Call Page details (GET /api/getPendingKYC/:dp_id)
    console.log('1️⃣3️⃣ Testing GET /api/getPendingKYC/:dp_id (Admin detailed review)...');
    const dpDetailRes = await axios.get(`${BASE_URL}/api/getPendingKYC/${dpId}`);
    const dpData = Array.isArray(dpDetailRes.data) ? dpDetailRes.data[0] : dpDetailRes.data;
    console.log('   Partner Name:', dpData.name);
    console.log('   Aadhaar Doc base64 prefix:', dpData.aadhar_proof_picture.substring(0, 30));
    console.log('   PAN Doc base64 prefix:', dpData.pancard_proof_picture.substring(0, 30));
    if (!dpData.aadhar_proof_picture || !dpData.pancard_proof_picture) {
      throw new Error('KYC proof documents missing in response');
    }
    console.log('   KYC details verified successfully.\n');

    // 14. Admin Approve Partner (POST /api/getPendingKYC/updateKYCStatus)
    console.log('1️⃣4️⃣ Testing POST /api/getPendingKYC/updateKYCStatus (Admin approval)...');
    const approveRes = await axios.post(`${BASE_URL}/api/getPendingKYC/updateKYCStatus`, {
      dpId,
      status: 'approved'
    });
    console.log('   Response:', approveRes.data);

    const pendingAfter = await axios.get(`${BASE_URL}/api/getPendingKYC/pendingkyc`);
    const stillPending = pendingAfter.data.some(dp => dp.DP_id === dpId);
    if (stillPending) throw new Error('Approved partner should not be in pending list');
    console.log('   Approval verified: partner correctly removed from pending queue.\n');

    // 15. Address Delete (DELETE /api/address/delete/:add_id)
    console.log('1️⃣5️⃣ Testing DELETE /api/address/delete/:add_id...');
    const deleteAddressRes = await axios.delete(`${BASE_URL}/api/address/delete/${addressId}`);
    console.log('   Response:', deleteAddressRes.data);
    const listAfterDelete = await axios.get(`${BASE_URL}/api/address/list?user_id=${userId}`);
    if (listAfterDelete.data.addresses.some(a => a.add_id === addressId)) {
      throw new Error('Address was not deleted');
    }
    console.log('   Address deletion verified.\n');

    console.log('=====================================================');
    console.log(' ALL 15 VERIFICATION TESTS PASSED SUCCESSFULLY! ');
    console.log(' MongoDB Migration is 100% functional and verified! ');
    console.log('=====================================================');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Test failed with error:', error.response?.data || error.message);
    process.exit(1);
  }
}

runTests();
