const serverUrl = String(process.env.SERVER_URL || 'http://localhost:5000')
  .trim()
  .replace(/\/+$/, '');

const VERIFICATION_MASCOT = `${serverUrl}/api/email-assets/verification-mascot.png`;
const REMINDER_MASCOT = `${serverUrl}/api/email-assets/reminder-mascot.png`;
const RESET_PASSWORD_MASCOT = `${serverUrl}/api/email-assets/reset-password-mascot.png`;

function escapeHtml(value)
{
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function actionButton(href, label, backgroundColor)
{
  return `
    <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:24px auto 0;">
      <tr>
        <td align="center" bgcolor="${backgroundColor}" style="border-radius:12px;">
          <a href="${href}"
             style="display:inline-block;padding:15px 32px;color:#ffffff;font-size:16px;font-weight:700;line-height:1;text-decoration:none;border-radius:12px;background:${backgroundColor};">
            ${label}
          </a>
        </td>
      </tr>
    </table>
  `;
}

function linkFallback(href, color)
{
  return `
    <p style="margin:16px 0 0;font-size:12px;line-height:1.5;color:#94a3b8;text-align:center;">
      If the button does not work, open this link:<br>
      <a href="${href}" style="color:${color};text-decoration:underline;word-break:break-all;">${href}</a>
    </p>
  `;
}

function emailBase({ mascotUrl, mascotAlt, accentColor, title, preheader, content })
{
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="x-apple-disable-message-reformatting">
    <title>${escapeHtml(title)}</title>
  </head>
  <body style="margin:0;padding:0;background:#eef2f7;font-family:Arial,Helvetica,sans-serif;color:#0f172a;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">
      ${escapeHtml(preheader)}
    </div>
    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background:#eef2f7;">
      <tr>
        <td align="center" style="padding:24px 12px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;">
            <tr>
              <td align="center" style="padding:22px 24px;background:${accentColor};color:#ffffff;font-size:18px;font-weight:700;">
                Calendar++
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:24px 24px 8px;">
                <img src="${mascotUrl}"
                     alt="${escapeHtml(mascotAlt)}"
                     width="180"
                     style="display:block;width:180px;max-width:100%;height:auto;border:0;outline:none;text-decoration:none;">
              </td>
            </tr>
            <tr>
              <td style="padding:8px 28px 28px;">
                ${content}
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

function verificationEmailHtml(verifyLink)
{
  const content = `
    <h1 style="margin:0 0 12px;text-align:center;font-size:34px;line-height:1.15;color:#0f172a;">Almost there!</h1>
    <p style="margin:0;text-align:center;font-size:17px;line-height:1.6;color:#334155;">
      Welcome to <strong>Calendar++</strong>. Verify your email address to finish setting up your account.
    </p>
    ${actionButton(verifyLink, '&#9989; Verify My Email', '#4285f4')}
    <p style="margin:24px 0 0;text-align:center;font-size:13px;line-height:1.6;color:#64748b;">
      This link expires in <strong>24 hours</strong>. If you did not sign up, you can safely ignore this email.
    </p>
    ${linkFallback(verifyLink, '#4285f4')}
  `;

  return emailBase({
    mascotUrl: VERIFICATION_MASCOT,
    mascotAlt: 'Calendar++ mascot',
    accentColor: '#4285f4',
    title: 'Verify your Calendar++ email',
    preheader: 'Verify your email to finish setting up Calendar++.',
    content,
  });
}

function emailChangeEmailHtml(verifyLink)
{
  const content = `
    <h1 style="margin:0 0 12px;text-align:center;font-size:32px;line-height:1.15;color:#0f172a;">Confirm your new email</h1>
    <p style="margin:0;text-align:center;font-size:16px;line-height:1.6;color:#334155;">
      We received a request to change the email address on your <strong>Calendar++</strong> account.
    </p>
    ${actionButton(verifyLink, '&#9993; Confirm New Email', '#4285f4')}
    <p style="margin:24px 0 0;text-align:center;font-size:13px;line-height:1.6;color:#64748b;">
      If you did not request this change, you can ignore this message and keep using your current email.
    </p>
    ${linkFallback(verifyLink, '#4285f4')}
  `;

  return emailBase({
    mascotUrl: VERIFICATION_MASCOT,
    mascotAlt: 'Calendar++ mascot',
    accentColor: '#4285f4',
    title: 'Confirm your new Calendar++ email',
    preheader: 'Confirm the new email address for your Calendar++ account.',
    content,
  });
}

function reminderEmailHtml(task, startText, endText)
{
  const title = escapeHtml(task?.title || 'Upcoming task');
  const description = String(task?.description || '').trim();
  const location = String(task?.location || '').trim();
  const timeLine = endText
    ? `${escapeHtml(startText)} to ${escapeHtml(endText)}`
    : escapeHtml(startText);

  const content = `
    <h1 style="margin:0 0 12px;text-align:center;font-size:32px;line-height:1.15;color:#0f172a;">Upcoming reminder</h1>
    <p style="margin:0;text-align:center;font-size:17px;line-height:1.6;color:#334155;">
      <strong>${title}</strong>
    </p>
    <p style="margin:12px 0 0;text-align:center;font-size:15px;line-height:1.6;color:#475569;">
      ${timeLine}
    </p>
    ${location ? `<p style="margin:12px 0 0;text-align:center;font-size:14px;line-height:1.6;color:#64748b;">Location: ${escapeHtml(location)}</p>` : ''}
    ${description ? `<p style="margin:16px 0 0;text-align:center;font-size:14px;line-height:1.7;color:#475569;">${escapeHtml(description)}</p>` : ''}
  `;

  return emailBase({
    mascotUrl: REMINDER_MASCOT,
    mascotAlt: 'Calendar++ reminder mascot',
    accentColor: '#22c55e',
    title: `Reminder: ${title}`,
    preheader: `Reminder for ${title}`,
    content,
  });
}

function passwordResetEmailHtml({ openLink, webLink })
{
  const content = `
    <h1 style="margin:0 0 12px;text-align:center;font-size:32px;line-height:1.15;color:#0f172a;">Reset your password</h1>
    <p style="margin:0;text-align:center;font-size:16px;line-height:1.6;color:#334155;">
      Use the button below to choose a new password for your <strong>Calendar++</strong> account.
    </p>
    ${actionButton(openLink, '&#128273; Open Reset Screen', '#ef4444')}
    <p style="margin:18px 0 0;text-align:center;font-size:13px;line-height:1.6;color:#64748b;">
      On mobile, we&apos;ll try to open the Calendar++ app first. If that does not work, the reset page will open in your browser.
    </p>
    <p style="margin:24px 0 0;text-align:center;font-size:13px;line-height:1.6;color:#64748b;">
      If you did not request a password reset, you can safely ignore this email.
    </p>
    ${linkFallback(webLink, '#ef4444')}
  `;

  return emailBase({
    mascotUrl: RESET_PASSWORD_MASCOT,
    mascotAlt: 'Calendar++ password reset mascot',
    accentColor: '#ef4444',
    title: 'Reset your Calendar++ password',
    preheader: 'Reset your Calendar++ password.',
    content,
  });
}

module.exports = {
  verificationEmailHtml,
  emailChangeEmailHtml,
  reminderEmailHtml,
  passwordResetEmailHtml,
};
