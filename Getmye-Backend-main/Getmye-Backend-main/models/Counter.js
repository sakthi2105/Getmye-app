const mongoose = require('mongoose');

const CounterSchema = new mongoose.Schema({
  _id: { type: String, required: true },
  seq: { type: Number, default: 0 }
});

const Counter = mongoose.model('Counter', CounterSchema);

async function getNextSequence(sequenceName, prefix = '', padLength = 3) {
  const counter = await Counter.findByIdAndUpdate(
    sequenceName,
    { $inc: { seq: 1 } },
    { returnDocument: 'after', upsert: true }
  );
  return `${prefix}${String(counter.seq).padStart(padLength, '0')}`;
}

module.exports = { Counter, getNextSequence };
