const logger = require("firebase-functions/logger");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { admin, db } = require("./shared");

exports.onAbandonedCartScheduler = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "asia-south1",
    timeZone: "Asia/Kolkata",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const now = Date.now();
    // 12 minutes ago threshold
    const twelveMinutesAgo = new Date(now - 12 * 60 * 1000);
    // 24 hours ago safety window to prevent spamming extremely old stale data
    const twentyFourHoursAgo = new Date(now - 24 * 60 * 60 * 1000);

    try {
      const cartsSnap = await db
        .collection("carts")
        .where("itemsCount", ">", 0)
        .where("notified", "==", false)
        .limit(100)
        .get();

      if (cartsSnap.empty) {
        logger.info("[AbandonedCart] No active unnotified carts found.");
        return;
      }

      logger.info(`[AbandonedCart] Found ${cartsSnap.size} potentially abandoned carts to check.`);

      let notifiedCount = 0;

      for (const cartDoc of cartsSnap.docs) {
        const cartData = cartDoc.data();
        const lastActiveAt = cartData.lastActiveAt ? cartData.lastActiveAt.toDate() : null;

        if (!lastActiveAt) {
          continue;
        }

        // Check if lastActiveAt falls within the 12 minutes to 24 hours window
        if (lastActiveAt < twelveMinutesAgo && lastActiveAt > twentyFourHoursAgo) {
          const userId = cartDoc.id;

          // Fetch the user's FCM token from their profile document
          const userDoc = await db.collection("users").doc(userId).get();
          if (!userDoc.exists) {
            logger.warn(`[AbandonedCart] User profile ${userId} not found for cart.`);
            continue;
          }

          const userData = userDoc.data() || {};
          const fcmToken = String(userData.fcmToken || "").trim();

          if (!fcmToken) {
            logger.warn(`[AbandonedCart] User ${userId} has no active FCM token.`);
            // Mark notified: true to avoid scanning this again
            await cartDoc.ref.update({
              notified: true,
              notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
              error: "Missing FCM token",
            });
            continue;
          }

          const title = "Your cart is waiting! ✨";
          const message = "Your cart is waiting for you! We've saved your items so you can complete your order whenever you're ready.";

          try {
            const messageId = await admin.messaging().send({
              token: fcmToken,
              notification: {
                title,
                body: message,
              },
              data: {
                eventType: "abandoned_cart",
                title,
                message,
              },
              android: {
                priority: "high",
                notification: {
                  channelId: "high_importance_channel",
                },
              },
              apns: {
                headers: {
                  "apns-priority": "10",
                },
                payload: {
                  aps: {
                    sound: "default",
                  },
                },
              },
            });

            await cartDoc.ref.update({
              notified: true,
              notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
              messageId,
            });

            notifiedCount++;
            logger.info(`[AbandonedCart] Push sent to user ${userId}, messageId: ${messageId}`);
          } catch (sendError) {
            const errMsg = String(sendError?.message || sendError);
            logger.error(`[AbandonedCart] Failed to send push to user ${userId}: ${errMsg}`);
            
            // Mark notified: true to prevent retrying infinitely and spamming
            await cartDoc.ref.update({
              notified: true,
              notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
              error: errMsg,
            });
          }
        }
      }

      logger.info(`[AbandonedCart] Cycle complete. Sent ${notifiedCount} notifications.`);
    } catch (error) {
      logger.error("[AbandonedCart] Error running scheduler", error);
    }
  }
);
