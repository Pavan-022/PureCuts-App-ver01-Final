const { onSupportMessageCreated } = require("./supportBot");
const { setAdminClaims, listAdminsFromAuth } = require("./adminClaims");
const { sendNotification } = require("./notifications/notificationService");
const { registerFcmToken } = require("./notifications/tokenService");
const { onOrderPlacedNotification } = require("./notifications/orderPlacedTrigger");

exports.onSupportMessageCreated = onSupportMessageCreated;
exports.setAdminClaims = setAdminClaims;
exports.listAdminsFromAuth = listAdminsFromAuth;
exports.sendNotification = sendNotification;
exports.registerFcmToken = registerFcmToken;
exports.onOrderPlacedNotification = onOrderPlacedNotification;
