# purecuts

PureCuts Flutter + Firebase project.

## Telegram admin alerts for verification requests

This project includes a Firebase Functions v2 trigger that sends Telegram alerts when a new document is created at:

- `verificationRequests/{requestId}`

### 1) Create Telegram bot and get chat IDs

1. In Telegram, open **@BotFather**.
2. Run `/newbot` and copy your bot token.
3. Send any message to your new bot from each admin account/group.
4. Open:
	- `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
5. Copy each `chat.id` you want notified.

### 2) Configure Firebase Functions secrets

From `c:\Users\manep\purecuts\functions` configure:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ADMIN_CHAT_IDS` (comma-separated, e.g. `12345,67890`)

### 3) Deploy functions

Deploy Cloud Functions after setting secrets.

### 4) What gets sent

For each new verification request, admins receive:

- Request ID
- User ID
- GST Number
- Udyam Number

### 5) Local placeholder config

Root `.env` includes placeholders for local development only:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ADMIN_CHAT_IDS`

In local/emulator mode, the function can fall back to these environment values when secrets are not injected.
Production should use Firebase Functions secrets.

Do not store real production secrets in `.env`.
