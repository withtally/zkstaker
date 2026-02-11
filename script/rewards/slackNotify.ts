const LEVEL_EMOJI = {
  info: ":white_check_mark:",
  warning: ":warning:",
  error: ":rotating_light:",
} as const;

/**
 * Posts a message to Slack via incoming webhook.
 * Silently no-ops if SLACK_WEBHOOK_URL is not set.
 * Never throws — logs a warning to console on failure.
 */
export async function notifySlack(
  message: string,
  level: "info" | "warning" | "error" = "info"
): Promise<void> {
  const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
  if (!SLACK_WEBHOOK_URL) return;

  const prefix = LEVEL_EMOJI[level];
  const payload = {
    text: `${prefix} *[zkStaker]* ${message}`,
  };

  try {
    const response = await fetch(SLACK_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      console.warn(`[Slack] Warning: webhook returned ${response.status}`);
    }
  } catch (err: any) {
    console.warn(`[Slack] Warning: failed to send notification: ${err.message}`);
  }
}
