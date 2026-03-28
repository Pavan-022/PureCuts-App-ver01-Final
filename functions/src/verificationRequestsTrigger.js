const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");

const TELEGRAM_BOT_TOKEN = defineSecret("TELEGRAM_BOT_TOKEN");
const TELEGRAM_ADMIN_CHAT_IDS = defineSecret("TELEGRAM_ADMIN_CHAT_IDS");

function firstNonEmpty(...values) {
  for (const value of values) {
    const resolved = String(value ?? "").trim();
    if (resolved) return resolved;
  }
  return "";
}

function normalizeChatIds(rawValue) {
  const unique = new Set();

  String(rawValue || "")
    .split(/[\n,;]+/)
    .map((part) => part.trim())
    .filter(Boolean)
    .forEach((id) => unique.add(id));

  return Array.from(unique);
}

function buildMessage({ requestId, userId, gstNumber, udyamNumber }) {
  return [
    "🚀 New User Verification Request",
    "",
    `Request ID: ${requestId || "Unknown"}`,
    `User ID: ${userId || "Not Provided"}`,
    `GST Number: ${gstNumber || "Not Provided"}`,
    `Udyam Number: ${udyamNumber || "Not Provided"}`,
    "",
    "Review this request in the admin dashboard.",
  ].join("\n");
}

exports.onVerificationRequestCreated = onDocumentCreated(
  {
    document: "verificationRequests/{requestId}",
    secrets: [TELEGRAM_BOT_TOKEN, TELEGRAM_ADMIN_CHAT_IDS],
  },
  async (event) => {
    const requestId = String(event.params?.requestId || "").trim();
    const data = event.data?.data() || {};

    const userId = firstNonEmpty(
      data.userId,
      data.uid,
      data.customerId,
      data.createdBy,
      data.user && (data.user.id || data.user.uid)
    );

    const gstNumber = firstNonEmpty(
      data.gstNumber,
      data.gst,
      data.gstin,
      data.gstNo,
      data.gst_number
    );

    const udyamNumber = firstNonEmpty(
      data.udyamNumber,
      data.udyam,
      data.udyamNo,
      data.udyam_number,
      data.msmeNumber
    );

    let token = "";
    let rawChatIds = "";

    try {
      token = String(TELEGRAM_BOT_TOKEN.value() || "").trim();
    } catch (_) {
      // Secret might be unavailable in local/dev contexts.
    }

    try {
      rawChatIds = String(TELEGRAM_ADMIN_CHAT_IDS.value() || "").trim();
    } catch (_) {
      // Secret might be unavailable in local/dev contexts.
    }

    if (!token) {
      token = String(process.env.TELEGRAM_BOT_TOKEN || "").trim();
    }

    if (!rawChatIds) {
      rawChatIds = String(process.env.TELEGRAM_ADMIN_CHAT_IDS || "").trim();
    }

    const chatIds = normalizeChatIds(rawChatIds);

    if (!token) {
      logger.error(
        "[VerificationTelegram] Missing TELEGRAM_BOT_TOKEN (secret/env)",
        {
          requestId,
        }
      );
      return;
    }

    if (chatIds.length === 0) {
      logger.error(
        "[VerificationTelegram] No valid TELEGRAM_ADMIN_CHAT_IDS (secret/env)",
        {
          requestId,
        }
      );
      return;
    }

    const url = `https://api.telegram.org/bot${token}/sendMessage`;
    const message = buildMessage({ requestId, userId, gstNumber, udyamNumber });

    const results = await Promise.allSettled(
      chatIds.map((chatId) =>
        axios.post(url, {
          chat_id: chatId,
          text: message,
          disable_notification: false,
        })
      )
    );

    let delivered = 0;
    let failed = 0;

    results.forEach((result, index) => {
      const chatId = chatIds[index];
      if (result.status === "fulfilled") {
        delivered += 1;
        return;
      }

      failed += 1;
      logger.error("[VerificationTelegram] Failed to send message", {
        requestId,
        chatId,
        error: String(result.reason?.message || result.reason),
      });
    });

    logger.info("[VerificationTelegram] Notification dispatch complete", {
      requestId,
      delivered,
      failed,
      recipients: chatIds.length,
      hasGst: Boolean(gstNumber),
      hasUdyam: Boolean(udyamNumber),
      hasUserId: Boolean(userId),
    });
  }
);
