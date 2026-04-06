const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();

async function upsertPaymentRecord({
  txnid,
  userId,
  amount,
  status,
  hashVerified,
  payuStatus,
  mihpayid,
  mode,
  responseHashPrefix,
}) {
  const ref = db.collection("payments").doc(txnid);

  await ref.set(
    {
      txnid,
      userId: String(userId || "").trim(),
      amount,
      status,
      hashVerified,
      payuStatus,
      mihpayid,
      mode,
      responseHashPrefix,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...(status === "success"
        ? { successAt: admin.firestore.FieldValue.serverTimestamp() }
        : { failureAt: admin.firestore.FieldValue.serverTimestamp() }),
    },
    { merge: true }
  );

  return ref.id;
}

module.exports = {
  upsertPaymentRecord,
};
