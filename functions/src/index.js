const { onSupportMessageCreated } = require("./supportBot");
const { setAdminClaims, listAdminsFromAuth } = require("./adminClaims");

exports.onSupportMessageCreated = onSupportMessageCreated;
exports.setAdminClaims = setAdminClaims;
exports.listAdminsFromAuth = listAdminsFromAuth;
