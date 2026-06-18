const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const { admin, db } = require("./shared");

function parseStock(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw === "number") return Math.floor(raw);
  const text = String(raw).trim();
  if (text === "") return null;
  const parsed = parseInt(text, 10);
  return isNaN(parsed) ? null : parsed;
}

function getProductStock(productData) {
  const manageStock = productData.manageStock !== false;
  if (!manageStock) return null;

  const rawStock =
    productData.stock ??
    productData.quantity ??
    productData.qty ??
    productData.inventory ??
    productData.stockCount;
  return parseStock(rawStock);
}

function getVariantStock(productData, variantId) {
  const manageStock = productData.manageStock !== false;
  if (!manageStock) return null;

  const variants = Array.isArray(productData.variants) ? productData.variants : [];
  const variant = variants.find(v => String(v.id || v.variantId || "").trim() === String(variantId).trim());
  if (!variant) return getProductStock(productData);

  const rawStock =
    variant.stock ??
    variant.quantity ??
    variant.qty ??
    variant.inventory ??
    variant.stockCount;
  const parsed = parseStock(rawStock);
  if (parsed !== null) return parsed;

  return getProductStock(productData);
}

function getStockForId(productData, variantId) {
  const cleanVariantId = String(variantId || "").trim();
  if (cleanVariantId) {
    return getVariantStock(productData, cleanVariantId);
  }
  return getProductStock(productData);
}

function checkBackInStock(beforeData, afterData, variantId) {
  const beforeManageStock = beforeData.manageStock !== false;
  const afterManageStock = afterData.manageStock !== false;

  const beforeStock = getStockForId(beforeData, variantId);
  const afterStock = getStockForId(afterData, variantId);

  // Out of stock if stock management is enabled and stock level is <= 0
  const beforeIsOutOfStock = beforeManageStock && beforeStock !== null && beforeStock <= 0;
  const afterIsOutOfStock = afterManageStock && afterStock !== null && afterStock <= 0;

  // Back in stock if it was out of stock before, and is not out of stock now
  return beforeIsOutOfStock && !afterIsOutOfStock;
}

exports.onBackInStockTrigger = onDocumentWritten("products/{productId}", async (event) => {
  const productId = String(event.params?.productId || "").trim();
  const beforeData = event.data?.before?.data() || null;
  const afterData = event.data?.after?.data() || null;

  // If the product was deleted, or newly created (where there is no "beforeData" to compare), or neither exists
  if (!beforeData || !afterData) {
    return;
  }

  try {
    // 1. Query all unnotified subscriptions for this product
    const subsSnap = await db
      .collection("backInStockSubscriptions")
      .where("productId", "==", productId)
      .where("notified", "==", false)
      .get();

    if (subsSnap.empty) {
      return;
    }

    logger.info(`[BackInStockTrigger] Found ${subsSnap.size} pending subscriptions for product ${productId}`);

    const batch = db.batch();
    const notificationsToSend = [];

    for (const doc of subsSnap.docs) {
      const sub = doc.data();
      const variantId = String(sub.variantId || "").trim();
      const fcmToken = String(sub.fcmToken || "").trim();

      if (!fcmToken) {
        batch.update(doc.ref, {
          notified: true,
          notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          error: "Missing FCM token",
        });
        continue;
      }

      // Check if this specific target (variant or simple product) has come back in stock
      const isReplenished = checkBackInStock(beforeData, afterData, variantId);

      if (isReplenished) {
        const productName = String(sub.productName || afterData.name || "Product").trim();
        const variantName = String(sub.variantName || "").trim();

        const title = "Back in Stock! 🎉";
        const message = variantName
          ? `Great news! ${productName} (${variantName}) is back in stock now.`
          : `Great news! ${productName} is back in stock now.`;

        notificationsToSend.push({
          subDocId: doc.id,
          subRef: doc.ref,
          token: fcmToken,
          title,
          body: message,
          data: {
            eventType: "back_in_stock",
            productId,
            variantId,
            title,
            message,
          },
        });
      }
    }

    if (notificationsToSend.length === 0) {
      if (batch.size > 0) {
        await batch.commit();
      }
      return;
    }

    logger.info(`[BackInStockTrigger] Sending ${notificationsToSend.length} back-in-stock notifications for product ${productId}`);

    // Send the notifications and update Firestore records
    await Promise.all(
      notificationsToSend.map(async (n) => {
        try {
          const messageId = await admin.messaging().send({
            token: n.token,
            notification: {
              title: n.title,
              body: n.body,
            },
            data: n.data,
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

          // Mark subscription as notified in the batch
          batch.update(n.subRef, {
            notified: true,
            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            messageId: messageId,
          });

          logger.info(`[BackInStockTrigger] Successfully sent push to sub ${n.subDocId}, messageId: ${messageId}`);
        } catch (err) {
          const errMsg = String(err?.message || err);
          logger.error(`[BackInStockTrigger] Failed to send push to sub ${n.subDocId}: ${errMsg}`);
          
          // Even if the push notification fails, mark it as notified to prevent repeating/looping
          batch.update(n.subRef, {
            notified: true,
            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            error: errMsg,
          });
        }
      })
    );

    // Commit all status updates in Firestore
    await batch.commit();
    logger.info(`[BackInStockTrigger] Completed processing for product ${productId}`);

  } catch (error) {
    logger.error(`[BackInStockTrigger] Error processing back-in-stock notifications for product ${productId}`, error);
  }
});
