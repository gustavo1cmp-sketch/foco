// Cloud Function: avisa o parceiro (push) quando o dono cria um pedido,
// e avisa o dono quando o parceiro decide.
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

async function tokenOf(uid) {
  const d = await admin.firestore().doc(`users/${uid}`).get();
  return d.exists ? d.data().fcmToken : null;
}

exports.notifyPartner = onDocumentCreated("pairs/{pairId}/requests/{reqId}", async (event) => {
  const pair = (await admin.firestore().doc(`pairs/${event.params.pairId}`).get()).data();
  const token = await tokenOf(pair.partnerUid);
  if (!token) return;
  const r = event.data.data();
  await admin.messaging().send({
    token,
    notification: {
      title: "Pedido de desbloqueio",
      body: r.reason ? r.reason : "Seu parceiro está pedindo uma liberação.",
    },
    data: { type: "unlock_request", requestId: event.params.reqId },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  });
});

exports.notifyOwner = onDocumentUpdated("pairs/{pairId}/requests/{reqId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  const token = await tokenOf(after.ownerUid);
  if (!token) return;
  await admin.messaging().send({
    token,
    notification: {
      title: after.status === "approved" ? "Liberado pelo parceiro" : "Pedido negado",
      body: after.status === "approved" ? "Você tem acesso temporário." : "Seu parceiro negou o pedido.",
    },
    data: { type: "unlock_decision", requestId: event.params.reqId },
  });
});
