const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const invalidTokenCodes = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

exports.sendRanchNotification = onDocumentCreated(
  {
    document: "ranches/{ranchId}/notifications/{notificationId}",
    region: "asia-northeast1",
    maxInstances: 10,
  },
  async (event) => {
    const notification = event.data?.data();
    if (!notification) return;

    const ranchId = event.params.ranchId;
    const targetName = String(notification.targetUser || "")
      .trim()
      .toLocaleLowerCase();
    const senderUid = String(notification.createdByUid || "");
    const tokenSnapshot = await getFirestore()
      .collection("ranches")
      .doc(ranchId)
      .collection("push_tokens")
      .where("active", "==", true)
      .get();

    const recipients = tokenSnapshot.docs.filter((document) => {
      const data = document.data();
      if (!data.token || data.uid === senderUid) return false;
      if (!targetName) return true;
      return String(data.userName || "").trim().toLocaleLowerCase() === targetName;
    });

    const uniqueRecipients = [];
    const seenTokens = new Set();
    for (const recipient of recipients) {
      const token = String(recipient.data().token);
      if (!seenTokens.has(token)) {
        seenTokens.add(token);
        uniqueRecipients.push({token, ref: recipient.ref});
      }
    }
    if (!uniqueRecipients.length) {
      logger.info("No eligible push recipients", {ranchId, targetName});
      return;
    }

    const title = String(notification.title || "VIMO Ranch update").slice(0, 120);
    const body = String(notification.message || "Open VIMO to view the update")
      .slice(0, 500);
    const staleRefs = [];

    for (let offset = 0; offset < uniqueRecipients.length; offset += 500) {
      const chunk = uniqueRecipients.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map((recipient) => recipient.token),
        notification: {title, body},
        data: {
          ranchId,
          notificationId: event.params.notificationId,
          type: String(notification.type || "info"),
          sourceId: String(notification.sourceId || ""),
        },
        android: {
          priority: "high",
          notification: {sound: "default"},
        },
        apns: {
          payload: {aps: {sound: "default"}},
        },
      });

      response.responses.forEach((result, index) => {
        if (!result.success && invalidTokenCodes.has(result.error?.code)) {
          staleRefs.push(chunk[index].ref);
        }
      });
      logger.info("Ranch push sent", {
        ranchId,
        success: response.successCount,
        failed: response.failureCount,
      });
    }

    if (staleRefs.length) {
      const cleanup = getFirestore().batch();
      staleRefs.forEach((ref) => cleanup.delete(ref));
      await cleanup.commit();
    }
  },
);
