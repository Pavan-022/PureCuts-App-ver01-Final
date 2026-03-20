const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();

const STEP = {
  START: "START",
  CATEGORY: "CATEGORY",
  QUANTITY: "QUANTITY",
  RESULT: "RESULT",
  HUMAN: "HUMAN",
};

const BOT_CONFIG_DOC = "bot_config/support_bot";

function normalize(value) {
  return String(value || "").trim().toLowerCase();
}

function asArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map((v) => String(v || "").trim()).filter(Boolean);
}

function optionMap(options) {
  const map = new Map();
  options.forEach((opt) => map.set(normalize(opt), opt));
  return map;
}

function nowTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function chatUserId(chatData, userMessageData) {
  const fromMessage = String(userMessageData.senderId || userMessageData.uid || "").trim();
  if (fromMessage) return fromMessage;
  return String(chatData.userId || chatData.uid || "").trim();
}

async function createBotMessage({ chatId, replyTo, text, options = [] }) {
  const ref = db.collection("chats").doc(chatId).collection("messages").doc();
  await ref.set({
    messageId: ref.id,
    chatId,
    sender: "bot",
    senderRole: "bot",
    senderId: "support-bot",
    text: String(text || "").trim(),
    message: String(text || "").trim(),
    options: asArray(options),
    replyTo: String(replyTo || "").trim(),
    seen: false,
    timestamp: admin.firestore.Timestamp.now(),
    serverTimestamp: nowTs(),
    createdAt: nowTs(),
  });
}

function defaultConfig() {
  return {
    enabled: true,
    steps: {
      START: {
        text: "Welcome to PureCuts Bulk Support 👋",
        options: ["Bulk Order Discount", "Product Availability", "Delivery Info"],
      },
      CATEGORY: {
        text: "Select product type:",
        options: ["Skincare", "Hair", "Equipment", "Mixed"],
      },
      QUANTITY: {
        text: "Select quantity range:",
        options: ["5-10", "10-25", "25-50", "50+"],
      },
    },
    discounts: {
      "5-10": "5%",
      "10-25": "8%",
      "25-50": "12%",
      "50+": "15%",
    },
  };
}

exports.onSupportMessageCreated = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { chatId, messageId } = event.params;
    const messageData = snap.data() || {};

    // 1) Ignore if sender != user
    const sender = normalize(messageData.sender || messageData.senderRole);
    if (sender !== "user") return;

    // 9) Idempotency lock per user message
    const lockRef = db.doc(`chats/${chatId}/botLocks/${messageId}`);
    try {
      await lockRef.create({
        createdAt: nowTs(),
        status: "processing",
      });
    } catch (_) {
      logger.info("Duplicate bot trigger skipped", { chatId, messageId });
      return;
    }

    const chatRef = db.doc(`chats/${chatId}`);
    const configRef = db.doc(BOT_CONFIG_DOC);

    try {
      // 2) Fetch chat
      // 3) Fetch config
      const [chatSnap, configSnap] = await Promise.all([chatRef.get(), configRef.get()]);

      const chat = chatSnap.exists ? (chatSnap.data() || {}) : {};
      const flow = chat.supportFlow || {};
      const cfg = configSnap.exists ? (configSnap.data() || {}) : defaultConfig();

      // 4) If disabled, return
      if (cfg.enabled === false) {
        await lockRef.set({ status: "skipped_disabled", finishedAt: nowTs() }, { merge: true });
        return;
      }

      const currentStep = String(flow.step || STEP.START).trim().toUpperCase();

      // 5) If HUMAN, return
      if (currentStep === STEP.HUMAN) {
        await lockRef.set({ status: "skipped_human", finishedAt: nowTs() }, { merge: true });
        return;
      }

      const startCfg = cfg.steps?.START || {};
      const categoryCfg = cfg.steps?.CATEGORY || {};
      const quantityCfg = cfg.steps?.QUANTITY || {};
      const discounts = cfg.discounts || {};

      const startOptions = asArray(startCfg.options);
      const categoryOptions = asArray(categoryCfg.options);
      const quantityOptions = asArray(quantityCfg.options);
      const resultOptions = ["Talk to Sales", "Place Order", "Start Over"];

      const startMap = optionMap(startOptions);
      const categoryMap = optionMap(categoryOptions);
      const quantityMap = optionMap(quantityOptions);

      const inputRaw = String(messageData.text || messageData.message || "").trim();
      const input = normalize(inputRaw);

      const looksLikeStart = ["hi", "hii", "hello", "hey", "start", "start over", "restart"].includes(input);

      // 6) State machine
      if (currentStep === STEP.START) {
        await chatRef.set({
          supportFlow: {
            step: STEP.CATEGORY,
            selectedCategory: "",
            selectedQuantity: "",
            isCompleted: false,
          },
          updatedAt: nowTs(),
        }, { merge: true });

        await createBotMessage({
          chatId,
          replyTo: messageId,
          text: startCfg.text || "Welcome to PureCuts Bulk Support 👋",
          options: startOptions,
        });
      } else if (currentStep === STEP.CATEGORY) {
        if (looksLikeStart) {
          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: startCfg.text || "Welcome to PureCuts Bulk Support 👋",
            options: startOptions,
          });
          await lockRef.set({ status: "completed", finishedAt: nowTs() }, { merge: true });
          return;
        }

        const topLevelChoice = startMap.get(input);
        if (topLevelChoice) {
          if (normalize(topLevelChoice) === normalize("bulk order discount")) {
            await createBotMessage({
              chatId,
              replyTo: messageId,
              text: categoryCfg.text || "Select product type:",
              options: categoryOptions,
            });
          } else if (normalize(topLevelChoice) === normalize("product availability")) {
            await chatRef.set({
              supportFlow: {
                ...flow,
                step: STEP.RESULT,
                selectedCategory: "Product Availability",
                selectedQuantity: "",
                isCompleted: false,
              },
              updatedAt: nowTs(),
            }, { merge: true });

            await createBotMessage({
              chatId,
              replyTo: messageId,
              text: "Please share category or product names. We’ll confirm stock with priority handling.",
              options: ["Talk to Sales", "Start Over"],
            });
          } else if (normalize(topLevelChoice) === normalize("delivery info")) {
            await chatRef.set({
              supportFlow: {
                ...flow,
                step: STEP.RESULT,
                selectedCategory: "Delivery Info",
                selectedQuantity: "",
                isCompleted: false,
              },
              updatedAt: nowTs(),
            }, { merge: true });

            await createBotMessage({
              chatId,
              replyTo: messageId,
              text: "Bulk orders usually ship within 2-5 business days based on location and stock.",
              options: ["Talk to Sales", "Start Over"],
            });
          }
        } else {
          const selectedCategory = categoryMap.get(input);
          if (!selectedCategory) {
            await createBotMessage({
              chatId,
              replyTo: messageId,
              text: "Please choose one of the available options.",
              options: [...startOptions, ...categoryOptions],
            });
          } else {
            await chatRef.set({
              supportFlow: {
                ...flow,
                step: STEP.QUANTITY,
                selectedCategory,
                selectedQuantity: "",
                isCompleted: false,
              },
              updatedAt: nowTs(),
            }, { merge: true });

            await createBotMessage({
              chatId,
              replyTo: messageId,
              text: quantityCfg.text || "Select quantity range:",
              options: quantityOptions,
            });
          }
        }
      } else if (currentStep === STEP.QUANTITY) {
        const selectedQty = quantityMap.get(input);

        if (!selectedQty) {
          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: "Please select a valid quantity range.",
            options: quantityOptions,
          });
        } else {
          const discount = String(discounts[selectedQty] || "0%").trim();
          const selectedCategory = String(flow.selectedCategory || "").trim();

          await chatRef.set({
            supportFlow: {
              ...flow,
              step: STEP.RESULT,
              selectedCategory,
              selectedQuantity: selectedQty,
              isCompleted: true,
            },
            updatedAt: nowTs(),
          }, { merge: true });

          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: `You are eligible for ${discount} discount for ${selectedQty} quantity range.`,
            options: resultOptions,
          });

          await db.collection("bulkLeads").add({
            chatId,
            userId: chatUserId(chat, messageData),
            category: selectedCategory,
            quantity: selectedQty,
            discount,
            timestamp: nowTs(),
          });
        }
      } else if (currentStep === STEP.RESULT) {
        if (input === normalize("talk to sales")) {
          // 7) Human takeover
          await chatRef.set({
            supportFlow: {
              ...flow,
              step: STEP.HUMAN,
              isCompleted: true,
            },
            updatedAt: nowTs(),
          }, { merge: true });

          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: "Perfect. A sales specialist will connect with you shortly.",
            options: [],
          });
        } else if (input === normalize("place order")) {
          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: "Great! Please continue with your order and share details if you need help.",
            options: ["Start Over"],
          });
        } else if (input === normalize("start over") || input === normalize("restart")) {
          await chatRef.set({
            supportFlow: {
              step: STEP.START,
              selectedCategory: "",
              selectedQuantity: "",
              isCompleted: false,
            },
            updatedAt: nowTs(),
          }, { merge: true });

          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: startCfg.text || "Welcome to PureCuts Bulk Support 👋",
            options: startOptions,
          });
        } else {
          await createBotMessage({
            chatId,
            replyTo: messageId,
            text: "Please choose one of the available actions.",
            options: resultOptions,
          });
        }
      }

      // keep chat message preview aligned
      await chatRef.set({
        lastMessage: String(inputRaw || "").trim(),
        lastMessageBy: String(messageData.senderId || "").trim() || "user",
        lastServerTimestamp: nowTs(),
        updatedAt: nowTs(),
      }, { merge: true });

      await lockRef.set({ status: "completed", finishedAt: nowTs() }, { merge: true });
    } catch (error) {
      logger.error("Support bot processing failed", {
        chatId,
        messageId,
        error: String(error?.message || error),
      });
      await lockRef.set(
        {
          status: "failed",
          error: String(error?.message || error),
          finishedAt: nowTs(),
        },
        { merge: true },
      );
      throw error;
    }
  },
);
