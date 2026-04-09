const crypto     = require('crypto');
const https      = require('https');
const path       = require('path');
const fs         = require('fs');
const jwt        = require('jsonwebtoken');
const { ObjectId } = require('mongodb');
const { DateTime, FixedOffsetZone, IANAZone } = require('luxon');
const { verificationEmailHtml, emailChangeEmailHtml, reminderEmailHtml, passwordResetEmailHtml } = require('./emailTemplates');

// Make an HTTPS request and resolve
function httpsRequest(options, body)
{
    return new Promise((resolve, reject) =>
    {
        const req = https.request(options, (res) =>
        {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end',  ()      =>
            {
                try   { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch { resolve({ status: res.statusCode, body: data }); }
            });
        });
        req.on('error', reject);
        if(body) req.write(body);
        req.end();
    });
}

function httpsTextRequest(url)
{
    return new Promise((resolve, reject) =>
    {
        https.get(url, (res) =>
        {
            let data = '';

            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () =>
            {
                if(res.statusCode !== 200)
                {
                    reject(new Error(`Unable to fetch ICS URL (status ${res.statusCode})`));
                    return;
                }

                resolve(data);
            });
        }).on('error', reject);
    });
}

// Fetch current weather from Open-Meteo (for ChatGPT stuff)
async function fetchWeather(latitude, longitude)
{
    const path = `/v1/forecast?latitude=${latitude}&longitude=${longitude}` +
                 `&current=temperature_2m,weather_code,wind_speed_10m` +
                 `&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=1`;

    const result = await httpsRequest({ hostname: 'api.open-meteo.com', path, method: 'GET' });
    if(result.status !== 200) return null;

    const c = result.body.current;
    const WMO_DESCRIPTIONS = {
        0:'Clear sky', 1:'Mainly clear', 2:'Partly cloudy', 3:'Overcast',
        45:'Foggy', 48:'Icy fog', 51:'Light drizzle', 53:'Drizzle', 55:'Heavy drizzle',
        61:'Slight rain', 63:'Rain', 65:'Heavy rain', 71:'Slight snow', 73:'Snow',
        75:'Heavy snow', 80:'Slight showers', 81:'Showers', 82:'Heavy showers',
        95:'Thunderstorm', 96:'Thunderstorm with hail', 99:'Thunderstorm with heavy hail',
    };
    return {
        temperatureF:  c.temperature_2m,
        windSpeedMph:  c.wind_speed_10m,
        description:   WMO_DESCRIPTIONS[c.weather_code] ?? `Code ${c.weather_code}`,
    };
}

function extractResponseText(responseBody)
{
    const outputs = Array.isArray(responseBody?.output) ? responseBody.output : [];
    const textParts = [];

    for(const item of outputs)
    {
        if(item?.type !== 'message' || !Array.isArray(item.content))
        {
            continue;
        }

        for(const content of item.content)
        {
            if(content?.type === 'output_text' && typeof content.text === 'string')
            {
                textParts.push(content.text);
            }
        }
    }

    return textParts.join('\n').trim();
}

async function createOpenAIResponse(apiKey, input, options = {})
{
    const {
        model = process.env.OPENAI_MODEL || 'gpt-4.1-mini',
        instructions = '',
        useWebSearch = false,
        tools = [],
    } = options;

    const requestBody = {
        model,
        input,
    };

    if(instructions)
    {
        requestBody.instructions = instructions;
    }

    if(useWebSearch)
    {
        requestBody.tools = [...tools, { type: 'web_search' }];
        requestBody.tool_choice = 'auto';
    }
    else if(tools.length > 0)
    {
        requestBody.tools = tools;
        requestBody.tool_choice = 'auto';
    }

    const bodyStr = JSON.stringify(requestBody);
    const result  = await httpsRequest(
    {
        hostname: 'api.openai.com',
        path:     '/v1/responses',
        method:   'POST',
        headers:
        {
            'Content-Type':   'application/json',
            'Authorization':  `Bearer ${apiKey}`,
            'Content-Length': Buffer.byteLength(bodyStr),
        },
    }, bodyStr);

    if(result.status !== 200)
    {
        throw new Error(`OpenAI error ${result.status}: ${JSON.stringify(result.body)}`);
    }

    return result.body;
}

// OpenAI Responses API call with optional web search.
async function callOpenAI(apiKey, input, options = {})
{
    const responseBody = await createOpenAIResponse(apiKey, input, options);

    const outputText = extractResponseText(responseBody);
    if(outputText)
    {
        return outputText;
    }

    throw new Error(`OpenAI response did not include output text: ${JSON.stringify(responseBody)}`);
}

async function streamOpenAI(apiKey, input, options = {}, handlers = {})
{
    const {
        model = process.env.OPENAI_MODEL || 'gpt-4.1-mini',
        instructions = '',
        useWebSearch = false,
    } = options;

    const requestBody = {
        model,
        input,
        stream: true,
    };

    if(instructions)
    {
        requestBody.instructions = instructions;
    }

    if(useWebSearch)
    {
        requestBody.tools = [{ type: 'web_search' }];
        requestBody.tool_choice = 'auto';
    }

    const bodyStr = JSON.stringify(requestBody);

    await new Promise((resolve, reject) =>
    {
        const req = https.request(
        {
            hostname: 'api.openai.com',
            path:     '/v1/responses',
            method:   'POST',
            headers:
            {
                'Content-Type':   'application/json',
                'Authorization':  `Bearer ${apiKey}`,
                'Content-Length': Buffer.byteLength(bodyStr),
            },
        }, (res) =>
        {
            if(res.statusCode !== 200)
            {
                let errorBody = '';
                res.on('data', (chunk) => { errorBody += chunk; });
                res.on('end', () =>
                {
                    reject(new Error(`OpenAI error ${res.statusCode}: ${errorBody}`));
                });
                return;
            }

            let buffer = '';
            let currentEvent = '';

            const processBlock = (block) =>
            {
                const lines = block.split('\n');
                let data = '';

                for(const rawLine of lines)
                {
                    const line = rawLine.trimEnd();
                    if(!line) continue;

                    if(line.startsWith('event:'))
                    {
                        currentEvent = line.slice(6).trim();
                    }
                    else if(line.startsWith('data:'))
                    {
                        data += line.slice(5).trim();
                    }
                }

                if(!data || data === '[DONE]')
                {
                    return;
                }

                let payload;
                try
                {
                    payload = JSON.parse(data);
                }
                catch
                {
                    return;
                }

                const eventType = currentEvent || payload.type || '';
                if(eventType === 'response.output_text.delta' && typeof payload.delta === 'string')
                {
                    handlers.onDelta?.(payload.delta);
                }
                else if(eventType === 'response.completed')
                {
                    handlers.onDone?.(payload);
                }
                else if(eventType === 'response.error')
                {
                    handlers.onError?.(payload);
                }
            };

            res.setEncoding('utf8');
            res.on('data', (chunk) =>
            {
                buffer += chunk;

                let separatorIndex = buffer.indexOf('\n\n');
                while(separatorIndex >= 0)
                {
                    const block = buffer.slice(0, separatorIndex);
                    buffer = buffer.slice(separatorIndex + 2);
                    processBlock(block);
                    currentEvent = '';
                    separatorIndex = buffer.indexOf('\n\n');
                }
            });

            res.on('end', () =>
            {
                if(buffer.trim().length > 0)
                {
                    processBlock(buffer);
                }
                resolve();
            });

            res.on('error', reject);
        });

        req.on('error', reject);
        req.write(bodyStr);
        req.end();
    });
}

async function sendWithResend(to, subject, html)
{
    const resendApiKey = process.env.RESEND_API_KEY;
    if(!resendApiKey)
    {
        throw new Error('RESEND_API_KEY is not configured');
    }

    const fromEmail = process.env.SMTP_FROM_EMAIL || 'onboarding@resend.dev';
    const fromName = process.env.SMTP_FROM_NAME || 'Calendar';
    const bodyStr = JSON.stringify({
        from: `"${fromName}" <${fromEmail}>`,
        to: [to],
        subject,
        html,
    });

    const result = await httpsRequest(
    {
        hostname: 'api.resend.com',
        path: '/emails',
        method: 'POST',
        headers:
        {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${resendApiKey}`,
            'Content-Length': Buffer.byteLength(bodyStr),
        },
    }, bodyStr);

    if(result.status < 200 || result.status >= 300)
    {
        throw new Error(`Resend error ${result.status}: ${JSON.stringify(result.body)}`);
    }

}

// ─── Send FCM push notification via Firebase Admin REST API ─────────────────
function pushDebug(message, details)
{
    const prefix = '[PushDebug]';
    if(details === undefined)
    {
        console.log(`${prefix} ${message}`);
        return;
    }

    console.log(`${prefix} ${message}`, details);
}

let firebaseMessagingInstance = null;

function getFirebaseMessaging()
{
    if(firebaseMessagingInstance)
    {
        return firebaseMessagingInstance;
    }

    let admin;
    try
    {
        admin = require('firebase-admin');
    }
    catch(error)
    {
        pushDebug('Skipping push send because firebase-admin is not installed.', {
            error: error.message,
        });
        return null;
    }

    if(admin.apps.length === 0)
    {
        const explicitServiceAccountPath = String(process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '').trim();

        try
        {
            if(explicitServiceAccountPath)
            {
                const resolvedPath = path.isAbsolute(explicitServiceAccountPath)
                    ? explicitServiceAccountPath
                    : path.resolve(__dirname, explicitServiceAccountPath);
                const serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
                admin.initializeApp({
                    credential: admin.credential.cert(serviceAccount),
                });
                pushDebug('Initialized Firebase Admin with FIREBASE_SERVICE_ACCOUNT_PATH.', {
                    path: resolvedPath,
                });
            }
            else
            {
                admin.initializeApp({
                    credential: admin.credential.applicationDefault(),
                });
                pushDebug('Initialized Firebase Admin with application default credentials.');
            }
        }
        catch(error)
        {
            pushDebug('Skipping push send because Firebase Admin credentials could not be initialized.', {
                error: error.message,
                hasExplicitPath: Boolean(explicitServiceAccountPath),
            });
            return null;
        }
    }

    firebaseMessagingInstance = admin.messaging();
    return firebaseMessagingInstance;
}

async function sendFcmPush(deviceToken, title, body, data = {})
{
    if(!deviceToken)
    {
        pushDebug('Skipping push send because device token is missing.');
        return;
    }

    const messaging = getFirebaseMessaging();
    if(!messaging)
    {
        return;
    }

    try
    {
        pushDebug('Sending FCM push.', {
            tokenPreview: `${String(deviceToken).slice(0, 12)}...`,
            title,
            hasBody: Boolean(body),
            dataKeys: Object.keys(data || {}),
        });

        const normalizedData = Object.fromEntries(
            Object.entries(data || {}).map(([key, value]) => [key, String(value)])
        );

        const result = await messaging.send({
            token: deviceToken,
            notification: { title, body },
            data: normalizedData,
            android: {
                priority: 'high',
                notification: {
                    sound: 'default',
                    channelId: 'calendar_reminders',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                    },
                },
            },
        });
        pushDebug('FCM push response received.', {
            messageId: result,
        });
    }
    catch(err)
    {
        pushDebug('FCM push request failed.', { error: err.message });
        console.error('[FCM] push error:', err.message);
    }
}


function verifyEmailTransporter()
{
    if(process.env.RESEND_API_KEY)
    {
        console.log('Resend API key detected; email delivery will use Resend');
        return;
    }

    console.error('Email delivery is disabled: RESEND_API_KEY is missing');
}

let reminderIntervalHandle = null;

function getDatabase(client)
{
    return client.db('largeProject');
}

function hashPassword(password)
{
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(password, salt, 64).toString('hex');
    return `${salt}:${hash}`;
}

function verifyPassword(password, storedPassword)
{
    const [salt, storedHash] = String(storedPassword || '').split(':');

    if(!salt || !storedHash)
    {
        return false;
    }

    const derivedHash = crypto.scryptSync(password, salt, 64);
    const savedHashBuffer = Buffer.from(storedHash, 'hex');

    if(savedHashBuffer.length !== derivedHash.length)
    {
        return false;
    }

    return crypto.timingSafeEqual(savedHashBuffer, derivedHash);
}

function validateJwtOrRespond(tokenUtils, response, accessToken)
{
    try
    {
        if(tokenUtils.isExpired(accessToken))
        {
            response.status(401).json({ error: 'The JWT is no longer valid', jwtToken: '' });
            return false;
        }
    }
    catch(error)
    {
        response.status(401).json({ error: error.message, jwtToken: '' });
        return false;
    }

    return true;
}

function validateBearerJwtOrRespond(req, response)
{
    const authorizationHeader = String(req.headers.authorization || '').trim();

    if(!authorizationHeader.toLowerCase().startsWith('bearer '))
    {
        response.status(401).json({ error: 'Missing bearer token' });
        return null;
    }

    const accessToken = authorizationHeader.slice(7).trim();
    if(!accessToken)
    {
        response.status(401).json({ error: 'Missing bearer token' });
        return null;
    }

    try
    {
        const verifiedJwt = jwt.verify(accessToken, process.env.ACCESS_TOKEN_SECRET);
        return {
            accessToken,
            userId: verifiedJwt.userId,
        };
    }
    catch(error)
    {
        response.status(401).json({ error: error.message });
        return null;
    }
}

function refreshJwtToken(tokenUtils, accessToken)
{
    const refreshedToken = tokenUtils.refresh(accessToken);
    return refreshedToken.error ? '' : refreshedToken.accessToken;
}

function generateCalendarFeedToken()
{
    return crypto.randomBytes(32).toString('hex');
}

function buildCalendarFeedUrls(user)
{
    const feedToken = String(user?.calendarFeedToken || '').trim();
    if(!feedToken)
    {
        return {
            calendarFeedUrl: '',
            calendarFeedWebcalUrl: '',
        };
    }

    const serverUrl = String(process.env.SERVER_URL || 'http://localhost:5000').trim().replace(/\/+$/, '');
    const calendarFeedUrl = `${serverUrl}/api/calendarfeed/${feedToken}`;
    const calendarFeedWebcalUrl = calendarFeedUrl.replace(/^https?/, 'webcal');

    return {
        calendarFeedUrl,
        calendarFeedWebcalUrl,
    };
}

function trimTrailingSlash(value)
{
    return String(value || '').trim().replace(/\/+$/, '');
}

function buildResetLinks(resetToken)
{
    const encodedToken = encodeURIComponent(resetToken);
    const serverUrl    = trimTrailingSlash(process.env.SERVER_URL || 'http://localhost:5000');
    const clientOrigin = trimTrailingSlash(process.env.CLIENT_ORIGIN || 'http://localhost:3000');
    const mobileBase   = String(process.env.MOBILE_RESET_URL_BASE || 'calendarplusplus://reset-password').trim();
    const separator    = mobileBase.includes('?') ? '&' : '?';

    return {
        appLink:  `${mobileBase}${separator}token=${encodedToken}`,
        webLink:  `${clientOrigin}/resetpassword?token=${encodedToken}`,
        openLink: `${serverUrl}/api/open-resetpassword?token=${encodedToken}`,
    };
}

function renderOpenResetPage({ appLink, webLink })
{
    return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Open Calendar++</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: linear-gradient(180deg, #111827, #020617);
        color: #f8fafc;
        font-family: Arial, Helvetica, sans-serif;
        padding: 24px;
      }
      .panel {
        max-width: 420px;
        width: 100%;
        padding: 28px;
        border-radius: 24px;
        background: rgba(15, 23, 42, 0.86);
        border: 1px solid rgba(148, 163, 184, 0.18);
        box-shadow: 0 18px 45px rgba(0, 0, 0, 0.32);
        text-align: center;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 30px;
      }
      p {
        margin: 0;
        line-height: 1.6;
        color: #cbd5e1;
      }
      .button {
        display: inline-block;
        margin-top: 22px;
        padding: 14px 22px;
        border-radius: 14px;
        background: #ef4444;
        color: #fff;
        font-weight: 700;
        text-decoration: none;
      }
      .link {
        display: inline-block;
        margin-top: 14px;
        color: #93c5fd;
        word-break: break-all;
      }
    </style>
  </head>
  <body>
    <div class="panel">
      <h1>Opening Calendar++</h1>
      <p>If the app is installed, your reset link will open there first. If not, we&apos;ll send you to the browser fallback in a moment.</p>
      <a class="button" href="${appLink}">Open in app</a>
      <div>
        <a class="link" href="${webLink}">Use browser instead</a>
      </div>
    </div>
    <script>
      const appLink = ${JSON.stringify(appLink)};
      const webLink = ${JSON.stringify(webLink)};
      window.location.replace(appLink);
      window.setTimeout(() => {
        window.location.replace(webLink);
      }, 1400);
    </script>
  </body>
</html>`;
}

function buildSettingsPayload(user)
{
    const reminderDefaults = normalizeReminderSettings(user?.reminderDefaults || {}, {
        reminderEnabled: false,
        reminderMinutesBefore: 30,
        reminderDelivery: 'email',
    });
    const feedUrls = buildCalendarFeedUrls(user);

    return {
        firstName: String(user?.firstName || ''),
        lastName: String(user?.lastName || ''),
        email: String(user?.email || ''),
        pendingEmail: String(user?.pendingEmail || ''),
        reminderDefaults,
        ...feedUrls,
    };
}

const CALENDAR_SYNC_INTERVAL_MS = 15 * 60 * 1000;

function normalizeHttpsUrl(urlText)
{
    const trimmedUrl = String(urlText || '').trim();
    if(!trimmedUrl)
    {
        return null;
    }

    let parsedUrl;
    try
    {
        parsedUrl = new URL(trimmedUrl);
    }
    catch
    {
        throw new Error('icsUrl must be a valid URL');
    }

    if(parsedUrl.protocol !== 'https:')
    {
        throw new Error('icsUrl must use HTTPS');
    }

    return parsedUrl;
}

function getCalendarDisplayName(parsedCalendar)
{
    for(const entry of Object.values(parsedCalendar || {}))
    {
        if(entry?.type === 'VCALENDAR' && entry['x-wr-calname'])
        {
            return String(entry['x-wr-calname']).trim();
        }
    }

    return '';
}

function buildExternalEventId(subscriptionId, entry)
{
    const baseId = entry.uid
        ? String(entry.uid).trim()
        : `${entry.summary || ''}|${entry.start ? new Date(entry.start).toISOString() : ''}`;

    const recurrenceId = entry.recurrenceid
        ? new Date(entry.recurrenceid).toISOString()
        : '';

    return `${String(subscriptionId)}:${baseId}:${recurrenceId}`;
}

function isExactMidnight(date)
{
    if(!(date instanceof Date) || !Number.isFinite(date.getTime()))
    {
        return false;
    }

    return date.getUTCHours() === 0 &&
           date.getUTCMinutes() === 0 &&
           date.getUTCSeconds() === 0 &&
           date.getUTCMilliseconds() === 0;
}

function isDateOnlyIcsEntry(entry)
{
    if(!entry)
    {
        return false;
    }

    if(String(entry.datetype || '').toLowerCase() === 'date')
    {
        return true;
    }

    if(entry.start?.dateOnly === true || entry.end?.dateOnly === true)
    {
        return true;
    }

    const startValueType = String(entry.start?.params?.VALUE || entry.start?.params?.value || '').toUpperCase();
    const endValueType = String(entry.end?.params?.VALUE || entry.end?.params?.value || '').toUpperCase();
    return startValueType === 'DATE' || endValueType === 'DATE';
}

function endOfDayInZoneFromIcsDate(value, options = {})
{
    const zone = normalizeTimeZone(options.timeZone) || 'America/New_York';
    const baseDate = value instanceof Date ? value : new Date(value);

    if(!Number.isFinite(baseDate.getTime()))
    {
        return null;
    }

    return DateTime.fromObject(
    {
        year: baseDate.getUTCFullYear(),
        month: baseDate.getUTCMonth() + 1,
        day: baseDate.getUTCDate(),
        hour: 23,
        minute: 59,
        second: 0,
        millisecond: 0,
    }, { zone }).toUTC().toJSDate();
}

function isLegacyDateOnlyImportedTask(dueDate, endDate, options = {})
{
    if(!(dueDate instanceof Date) || !Number.isFinite(dueDate.getTime()))
    {
        return false;
    }

    const zone = normalizeTimeZone(options.timeZone) || 'America/New_York';
    const dueDateInZone = DateTime.fromJSDate(dueDate, { zone });

    if(dueDateInZone.hour !== 0 || dueDateInZone.minute !== 0 || dueDateInZone.second !== 0)
    {
        return false;
    }

    if(!endDate)
    {
        return true;
    }

    if(!(endDate instanceof Date) || !Number.isFinite(endDate.getTime()))
    {
        return false;
    }

    const endDateInZone = DateTime.fromJSDate(endDate, { zone });
    return endDateInZone.diff(dueDateInZone, 'hours').hours === 24;
}

function buildIcsTaskSignature(entry, options = {})
{
    let dueDate = entry?.start ? new Date(entry.start) : null;
    let endDate = entry?.end ? new Date(entry.end) : dueDate;

    const shouldUseDefaultDueTime =
        dueDate &&
        (
            isDateOnlyIcsEntry(entry) ||
            (!entry?.end && isExactMidnight(dueDate))
        );

    if(shouldUseDefaultDueTime)
    {
        dueDate = endOfDayInZoneFromIcsDate(dueDate, options);
        endDate = dueDate;
    }

    return {
        title: entry?.summary || '(No title)',
        description: entry?.description || '',
        location: entry?.location || '',
        dueDate,
        endDate,
    };
}

function escapeIcsText(value)
{
    return String(value || '')
        .replace(/\\/g, '\\\\')
        .replace(/\r?\n/g, '\\n')
        .replace(/,/g, '\\,')
        .replace(/;/g, '\\;');
}

function formatIcsUtcDate(dateValue)
{
    const date = dateValue instanceof Date ? dateValue : new Date(dateValue);
    if(!Number.isFinite(date.getTime()))
    {
        return '';
    }

    return DateTime.fromJSDate(date, { zone: 'utc' }).toFormat("yyyyMMdd'T'HHmmss'Z'");
}

function buildCalendarExport(tasks = [])
{
    const lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Calendar++//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
    ];

    for(const task of tasks)
    {
        if(!task?.dueDate)
        {
            continue;
        }

        const dtStart = formatIcsUtcDate(task.dueDate);
        const dtEnd = formatIcsUtcDate(task.endDate || task.dueDate);
        if(!dtStart || !dtEnd)
        {
            continue;
        }

        lines.push(
            'BEGIN:VEVENT',
            `UID:${String(task._id || crypto.randomUUID())}@calendarplusplus.xyz`,
            `DTSTAMP:${formatIcsUtcDate(new Date())}`,
            `DTSTART:${dtStart}`,
            `DTEND:${dtEnd}`,
            `SUMMARY:${escapeIcsText(task.title || '(No title)')}`,
            `DESCRIPTION:${escapeIcsText(task.description || '')}`,
            `LOCATION:${escapeIcsText(task.location || '')}`,
            `STATUS:${task.isCompleted === true ? 'COMPLETED' : 'CONFIRMED'}`,
            `CATEGORIES:${escapeIcsText(String(task.source || 'manual').toUpperCase())}`,
            'END:VEVENT'
        );
    }

    lines.push('END:VCALENDAR');
    return `${lines.join('\r\n')}\r\n`;
}

function normalizeLegacyIcsTaskForResponse(task, options = {})
{
    if(task?.source !== 'ical' || !task?.dueDate)
    {
        return task;
    }

    const dueDate = task.dueDate instanceof Date ? task.dueDate : new Date(task.dueDate);
    const endDate = task?.endDate ? (task.endDate instanceof Date ? task.endDate : new Date(task.endDate)) : null;
    const shouldUseDefaultDueTime =
        isLegacyDateOnlyImportedTask(dueDate, endDate, options) ||
        (
            isExactMidnight(dueDate) &&
            (!endDate || endDate.getTime() === dueDate.getTime())
        );

    if(!shouldUseDefaultDueTime)
    {
        return task;
    }

    const normalizedDueDate = endOfDayInZoneFromIcsDate(dueDate, options);
    if(!normalizedDueDate)
    {
        return task;
    }

    return {
        ...task,
        dueDate: normalizedDueDate,
        endDate: normalizedDueDate,
    };
}

function buildTaskFromIcsEntry(userId, subscriptionId, entry, options = {})
{
    const signature = buildIcsTaskSignature(entry, options);

    return {
        user_id:        new ObjectId(userId),
        title:          signature.title,
        description:    signature.description,
        location:       signature.location,
        dueDate:        signature.dueDate,
        endDate:        signature.endDate,
        isCompleted:    false,
        source:         'ical',
        subscriptionId: new ObjectId(subscriptionId),
        externalEventId: buildExternalEventId(subscriptionId, entry),
        externalUid:    entry.uid ? String(entry.uid) : '',
        lastSyncedAt:   new Date(),
    };
}

async function syncCalendarSubscription(db, userId, subscription, options = {})
{
    const parsedUrl = normalizeHttpsUrl(subscription.url);
    const shouldForce = options.force === true;
    const now = new Date();

    if(!shouldForce && subscription.lastSyncedAt)
    {
        const lastSyncedAt = new Date(subscription.lastSyncedAt);
        if(Number.isFinite(lastSyncedAt.getTime()) &&
           now.getTime() - lastSyncedAt.getTime() < CALENDAR_SYNC_INTERVAL_MS)
        {
            return { insertedCount: 0, updatedCount: 0, deletedCount: 0, skipped: true };
        }
    }

    const ical = require('node-ical');
    const calendarContent = await httpsTextRequest(parsedUrl);
    const parsedCalendar = ical.sync.parseICS(calendarContent);
    const activeExternalIds = [];
    let insertedCount = 0;
    let updatedCount = 0;

    for(const entry of Object.values(parsedCalendar))
    {
        if(entry?.type !== 'VEVENT') continue;
        if(!entry.summary || !entry.start) continue;

        const task = buildTaskFromIcsEntry(userId, subscription._id, entry, options);
        activeExternalIds.push(task.externalEventId);

        const updateResult = await db.collection('tasks').updateOne(
            {
                user_id: new ObjectId(userId),
                subscriptionId: new ObjectId(subscription._id),
                externalEventId: task.externalEventId,
            },
            { $set: task },
            { upsert: true }
        );

        if(updateResult.upsertedCount > 0) insertedCount += 1;
        else if(updateResult.modifiedCount > 0) updatedCount += 1;
    }

    const deleteFilter = {
        user_id: new ObjectId(userId),
        subscriptionId: new ObjectId(subscription._id),
        source: 'ical',
    };

    if(activeExternalIds.length > 0)
    {
        deleteFilter.externalEventId = { $nin: activeExternalIds };
    }

    const deleteResult = await db.collection('tasks').deleteMany(deleteFilter);
    const calendarName = getCalendarDisplayName(parsedCalendar);

    await updateUserCalendarSubscription(db, userId, subscription._id, {
        url: parsedUrl.toString(),
        name: calendarName || subscription.name || '',
        lastSyncedAt: now,
        lastSyncError: '',
    });

    return {
        insertedCount,
        updatedCount,
        deletedCount: deleteResult.deletedCount || 0,
        skipped: false,
    };
}

async function syncStoredCalendarSubscriptions(db, userId, options = {})
{
    const subscriptions = await getUserCalendarSubscriptions(db, userId);

    for(const subscription of subscriptions)
    {
        try
        {
            await syncCalendarSubscription(db, userId, subscription, options);
        }
        catch(error)
        {
            await updateUserCalendarSubscription(db, userId, subscription._id, {
                lastSyncError: error.message,
                lastSyncedAt: new Date(),
            });
        }
    }
}

function normalizeTimeZone(timeZone)
{
    const text = String(timeZone || '').trim();
    if(!text)
    {
        return '';
    }

    return IANAZone.isValidZone(text) ? text : '';
}

async function persistUserTimeContext(db, userId, timeZone, utcOffsetMinutes)
{
    const updates = {};
    const normalizedTimeZone = normalizeTimeZone(timeZone);
    const numericOffset = Number(utcOffsetMinutes);

    if(normalizedTimeZone)
    {
        updates.timeZone = normalizedTimeZone;
    }

    if(Number.isFinite(numericOffset))
    {
        updates.utcOffsetMinutes = Math.round(numericOffset);
    }

    if(Object.keys(updates).length === 0)
    {
        return;
    }

    await db.collection('users').updateOne(
        { _id: new ObjectId(userId) },
        { $set: updates }
    );
}

function resolveUserZone(options = {})
{
    const zone = normalizeTimeZone(options.timeZone);
    if(zone)
    {
        return zone;
    }

    if(Number.isFinite(options.utcOffsetMinutes))
    {
        return FixedOffsetZone.instance(Number(options.utcOffsetMinutes));
    }

    return 'utc';
}

function toUserDateTime(value, options = {})
{
    if(!(value instanceof Date) || !Number.isFinite(value.getTime()))
    {
        return null;
    }

    return DateTime.fromJSDate(value, { zone: resolveUserZone(options) });
}

function getDayRangeInUserZone(value, options = {})
{
    const dateTime = toUserDateTime(value, options);
    if(!dateTime || !dateTime.isValid)
    {
        return {
            start: null,
            end: null,
        };
    }

    return {
        start: dateTime.startOf('day').toUTC().toJSDate(),
        end: dateTime.endOf('day').toUTC().toJSDate(),
    };
}

function formatDateTimeForUser(value, options = {}, format = DateTime.DATETIME_MED)
{
    const dateTime = toUserDateTime(value, options);
    return dateTime && dateTime.isValid ? dateTime.toLocaleString(format) : '';
}

function formatTimeForUser(value, options = {})
{
    return formatDateTimeForUser(value, options, DateTime.TIME_SIMPLE);
}

function formatDateForUser(value, options = {})
{
    return formatDateTimeForUser(value, options, DateTime.DATE_FULL);
}

function formatLocalTimeContext(value, options = {})
{
    const dateTime = toUserDateTime(value, options);
    if(!dateTime || !dateTime.isValid)
    {
        return '';
    }

    return `${dateTime.toFormat("cccc, LLLL d, yyyy 'at' h:mm a")} (${dateTime.offsetNameShort}, UTC${dateTime.toFormat('ZZ')})`;
}

function parseDateTimeInUserZone(value, options = {})
{
    const { timeZone, utcOffsetMinutes } = options;

    if(value === undefined || value === null || value === '')
    {
        return null;
    }

    if(value instanceof Date)
    {
        return new Date(value);
    }

    const text = String(value).trim();
    if(!text)
    {
        return null;
    }

    if(hasExplicitTimezone(text))
    {
        const explicit = DateTime.fromISO(text, { setZone: true });
        return explicit.isValid ? explicit.toUTC().toJSDate() : new Date(text);
    }

    const zone = normalizeTimeZone(timeZone);
    if(zone)
    {
        const zoned = DateTime.fromISO(text, { zone, setZone: true });
        if(zoned.isValid)
        {
            return zoned.toUTC().toJSDate();
        }
    }

    const match = text.match(
        /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(\.\d{1,3})?)?)?$/
    );

    if(match && Number.isFinite(utcOffsetMinutes))
    {
        const [
            ,
            yearText,
            monthText,
            dayText,
            hourText = '00',
            minuteText = '00',
            secondText = '00',
            fractionText = '',
        ] = match;

        const milliseconds = fractionText
            ? Number(fractionText.slice(1).padEnd(3, '0'))
            : 0;
        const utcMillis = Date.UTC(
            Number(yearText),
            Number(monthText) - 1,
            Number(dayText),
            Number(hourText),
            Number(minuteText),
            Number(secondText),
            milliseconds
        ) - (Number(utcOffsetMinutes) * 60 * 1000);

        return new Date(utcMillis);
    }

    return new Date(text);
}

function buildDueDateRangeFilter(startDate, endDate, options = {})
{
    if(!startDate && !endDate)
    {
        return null;
    }

    const range = {};
    if(startDate) range.$gte = parseDateTimeInUserZone(startDate, options);
    if(endDate)   range.$lte = parseDateTimeInUserZone(endDate, options);

    return { dueDate: range };
}

function hasExplicitTimezone(value)
{
    return /(?:Z|[+-]\d{2}:\d{2})$/i.test(String(value || '').trim());
}

function parseDateTimeWithOffset(value, utcOffsetMinutes, timeZone)
{
    return parseDateTimeInUserZone(value, { utcOffsetMinutes, timeZone });
}

function normalizeTaskColor(value)
{
    const color = String(value || '').trim();
    if(!color) return '';
    if(/^#[0-9a-fA-F]{6}$/.test(color) || /^#[0-9a-fA-F]{8}$/.test(color))
    {
        return color.toUpperCase();
    }

    return '';
}

function normalizeTaskGroup(value, fallback = '')
{
    const group = String(value || fallback || '').trim();
    return group.slice(0, 60);
}

function weekDayNumberToCode(dayNumber)
{
    return ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'][dayNumber] || '';
}

function normalizeRecurrenceDays(days)
{
    const values = Array.isArray(days) ? days : [];
    const normalized = values
        .map((day) => String(day || '').trim().toUpperCase())
        .filter((day) => ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'].includes(day));

    return [...new Set(normalized)];
}

function buildRecurringTaskDocuments(userId, args, options = {})
{
    const utcOffsetMinutes = options.utcOffsetMinutes;
    const timeZone = options.timeZone;
    const startDate = parseDateTimeWithOffset(args.startDate || args.dueDate, utcOffsetMinutes, timeZone);
    if(!startDate || Number.isNaN(startDate.getTime()))
    {
        throw new Error('create_recurring_calendar_tasks requires a valid startDate');
    }

    const parsedEndDate = args.endDate
        ? parseDateTimeWithOffset(args.endDate, utcOffsetMinutes, timeZone)
        : null;
    const endDate = parsedEndDate && !Number.isNaN(parsedEndDate.getTime()) ? parsedEndDate : startDate;
    const durationMs = Math.max(0, endDate.getTime() - startDate.getTime());
    const recurrenceDays = normalizeRecurrenceDays(args.daysOfWeek);

    if(recurrenceDays.length === 0)
    {
        throw new Error('create_recurring_calendar_tasks requires at least one valid day in daysOfWeek');
    }

    const untilDate = parseDateTimeWithOffset(args.untilDate, utcOffsetMinutes, timeZone);
    if(!untilDate || Number.isNaN(untilDate.getTime()))
    {
        throw new Error('create_recurring_calendar_tasks requires a valid untilDate');
    }

    const intervalWeeks = Math.max(1, Math.min(Number(args.intervalWeeks) || 1, 8));
    const maxOccurrences = Math.max(1, Math.min(Number(args.maxOccurrences) || 120, 240));
    const startWeekAnchor = new Date(startDate);
    startWeekAnchor.setHours(0, 0, 0, 0);
    startWeekAnchor.setDate(startWeekAnchor.getDate() - startWeekAnchor.getDay());

    const documents = [];
    for(let cursor = new Date(startDate); cursor <= untilDate; cursor.setDate(cursor.getDate() + 1))
    {
        const weekdayCode = weekDayNumberToCode(cursor.getDay());
        if(!recurrenceDays.includes(weekdayCode))
        {
            continue;
        }

        const cursorWeekAnchor = new Date(cursor);
        cursorWeekAnchor.setHours(0, 0, 0, 0);
        cursorWeekAnchor.setDate(cursorWeekAnchor.getDate() - cursorWeekAnchor.getDay());
        const weekDiff = Math.floor((cursorWeekAnchor.getTime() - startWeekAnchor.getTime()) / (7 * 24 * 60 * 60 * 1000));
        if(weekDiff < 0 || weekDiff % intervalWeeks !== 0)
        {
            continue;
        }

        const dueDate = new Date(
            cursor.getFullYear(),
            cursor.getMonth(),
            cursor.getDate(),
            startDate.getHours(),
            startDate.getMinutes(),
            startDate.getSeconds(),
            startDate.getMilliseconds()
        );

        if(dueDate < startDate || dueDate > untilDate)
        {
            continue;
        }

        const document = {
            user_id: new ObjectId(userId),
            title: String(args.title || '').trim(),
            description: String(args.description || '').trim(),
            location: String(args.location || '').trim(),
            dueDate,
            endDate: new Date(dueDate.getTime() + durationMs),
            isCompleted: false,
            source: 'manual',
            color: normalizeTaskColor(args.color),
            group: normalizeTaskGroup(args.group),
        };
        Object.assign(document, buildReminderFields(document, {
            reminderEnabled: args.reminderEnabled,
            reminderMinutesBefore: args.reminderMinutesBefore,
            reminderDelivery: args.reminderDelivery,
        }));
        documents.push(document);

        if(documents.length >= maxOccurrences)
        {
            break;
        }
    }

    if(!String(args.title || '').trim())
    {
        throw new Error('create_recurring_calendar_tasks requires a title');
    }

    if(documents.length === 0)
    {
        throw new Error('No recurring tasks matched the provided schedule.');
    }

    return documents;
}

function shouldUseAssistantWebSearch(messages = [])
{
    const combinedText = messages
        .map((message) => typeof message?.content === 'string' ? message.content : '')
        .join(' ')
        .toLowerCase();

    if(!combinedText)
    {
        return false;
    }

    return [
        'nearby',
        'closest',
        'open now',
        'hours',
        'weather',
        'restaurant',
        'store',
        'venue',
        'today',
        'tonight',
        'current',
        'latest',
        'news',
        'this week',
        'this weekend',
        'tomorrow',
        'recommend',
        'recommendation',
        'best',
        'available',
        'happening',
        'event',
        'traffic',
        'temperature',
        'forecast',
        'campus',
        'local',
    ].some((phrase) => combinedText.includes(phrase));
}

function getTaskStartDate(task)
{
    return task.dueDate || task.startDate || null;
}

function normalizeReminderSettings(input = {}, fallback = {})
{
    const enabledInput = input.reminderEnabled;
    const minutesInput = input.reminderMinutesBefore;
    const deliveryInput = String(input.reminderDelivery || '').trim().toLowerCase();
    const fallbackDelivery = String(fallback.reminderDelivery || 'email').trim().toLowerCase();
    const baseEnabled = fallback.reminderEnabled === true;
    const enabled = enabledInput === undefined
        ? baseEnabled
        : enabledInput === true;
    const fallbackMinutes = Number.isFinite(Number(fallback.reminderMinutesBefore))
        ? Math.max(0, Math.round(Number(fallback.reminderMinutesBefore)))
        : 30;
    const parsedMinutes = minutesInput === undefined || minutesInput === null || minutesInput === ''
        ? fallbackMinutes
        : Math.max(0, Math.round(Number(minutesInput)));
    const reminderDelivery = ['email', 'push', 'both'].includes(deliveryInput)
        ? deliveryInput
        : ['email', 'push', 'both'].includes(fallbackDelivery)
            ? fallbackDelivery
            : 'email';

    return {
        reminderEnabled: enabled,
        reminderMinutesBefore: enabled ? parsedMinutes : 0,
        reminderDelivery,
    };
}

function buildReminderFields(taskLike, reminderInput = {}, fallback = {})
{
    const startDate = getTaskStartDate(taskLike);
    const normalized = normalizeReminderSettings(reminderInput, fallback);
    const reminderAt = normalized.reminderEnabled && startDate
        ? new Date(startDate.getTime() - (normalized.reminderMinutesBefore * 60 * 1000))
        : null;

    return {
        reminderEnabled: normalized.reminderEnabled,
        reminderMinutesBefore: normalized.reminderMinutesBefore,
        reminderDelivery: normalized.reminderDelivery,
        reminderAt,
        reminderSentAt: null,
    };
}

async function sendTaskReminderEmail(user, task)
{
    if(!task?.dueDate)
    {
        return false;
    }

    const startDate = getTaskStartDate(task);
    const endDate = task.endDate ? new Date(task.endDate) : null;
    const timeOptions = {
        timeZone: user?.timeZone,
        utcOffsetMinutes: user?.utcOffsetMinutes,
    };
    const startText = startDate ? formatDateTimeForUser(startDate, timeOptions) : 'an upcoming time';
    const endText = endDate ? formatDateTimeForUser(endDate, timeOptions) : '';
    const locationLine = task.location ? `<p>Location: ${task.location}</p>` : '';
    const descriptionLine = task.description ? `<p>${task.description}</p>` : '';
    const delivery = normalizeReminderSettings(task, {
        reminderEnabled: true,
        reminderMinutesBefore: Number(task?.reminderMinutesBefore || 30),
        reminderDelivery: 'email',
    }).reminderDelivery;
    const shouldSendEmail = delivery === 'email' || delivery === 'both';
    const shouldSendPush = delivery === 'push' || delivery === 'both';
    pushDebug('Preparing reminder delivery.', {
        taskId: String(task?._id || ''),
        title: task?.title || '',
        delivery,
        shouldSendEmail,
        shouldSendPush,
        hasDeviceToken: Boolean(user?.deviceToken),
        devicePlatform: user?.devicePlatform || '',
        userTimeZone: user?.timeZone || '',
        utcOffsetMinutes: user?.utcOffsetMinutes,
        reminderAt: task?.reminderAt ? new Date(task.reminderAt).toISOString() : null,
        dueDate: task?.dueDate ? new Date(task.dueDate).toISOString() : null,
    });

    if(shouldSendEmail && user?.email)
    {
        await sendWithResend(
        user.email,
        `⏰ Reminder: ${task.title || 'Upcoming task'}`,
        reminderEmailHtml(task, startText, endText)
        );
    }

    if(shouldSendPush && user.deviceToken)
    {
        const pushTitle = `⏰ ${task.title || 'Upcoming task'}`;
        const pushBody  = startText + (endText ? ` → ${endText}` : '');
        pushDebug('Attempting push reminder send.', {
            taskId: String(task?._id || ''),
            tokenPreview: `${String(user.deviceToken).slice(0, 12)}...`,
            pushTitle,
            pushBody,
        });
        await sendFcmPush(user.deviceToken, pushTitle, pushBody, {
            taskId: String(task._id || ''),
            type:   'reminder',
        });
    }

    if(shouldSendPush && !user.deviceToken)
    {
        pushDebug('Push reminder skipped because user has no device token.', {
            taskId: String(task?._id || ''),
            userId: String(user?._id || ''),
        });
    }

    return true;
}

async function sendPendingTaskReminders(client)
{
    if(!process.env.RESEND_API_KEY)
    {
        return;
    }

    const db = getDatabase(client);
    const now = new Date();
    const tasks = await db.collection('tasks').find({
        reminderEnabled: true,
        reminderSentAt: null,
        isCompleted: { $ne: true },
        dueDate: { $ne: null },
        reminderAt: { $lte: now },
    })
    .sort({ reminderAt: 1 })
    .limit(50)
    .toArray();

    for(const task of tasks)
    {
        try
        {
            const user = await db.collection('users').findOne(
                { _id: task.user_id },
                {
                    projection: {
                        email: 1,
                        isVerified: 1,
                        deviceToken: 1,
                        devicePlatform: 1,
                        timeZone: 1,
                        utcOffsetMinutes: 1,
                    },
                }
            );

            if(!user?.email || user.isVerified === false)
            {
                await db.collection('tasks').updateOne(
                    { _id: task._id, reminderSentAt: null },
                    { $set: { reminderSentAt: now } }
                );
                continue;
            }

            const sent = await sendTaskReminderEmail(user, task);
            if(sent)
            {
                await db.collection('tasks').updateOne(
                    { _id: task._id, reminderSentAt: null },
                    { $set: { reminderSentAt: new Date() } }
                );
            }
        }
        catch(error)
        {
            console.error(`Failed to send reminder for task ${task._id}:`, error);
        }
    }
}

function startReminderLoop(client)
{
    if(reminderIntervalHandle)
    {
        return;
    }

    const tick = () =>
    {
        sendPendingTaskReminders(client).catch((error) =>
        {
            console.error('Reminder loop failed:', error);
        });
    };

    // Fire once immediately to catch any overdue reminders on startup, then
    // align subsequent ticks to the top of each wall-clock minute so that a
    // reminder set for e.g. 14:30 is sent within a second of 14:30 rather
    // than up to 60 s late due to interval drift.
    tick();

    const msUntilNextMinute = () =>
    {
        const now = Date.now();
        return 60_000 - (now % 60_000);
    };

    // setTimeout to the next minute boundary, then keep a steady 60-second interval.
    setTimeout(() =>
    {
        tick();
        reminderIntervalHandle = setInterval(tick, 60 * 1000);
    }, msUntilNextMinute());
}

function safeObjectId(value, fieldName = 'id')
{
    try
    {
        return new ObjectId(String(value));
    }
    catch
    {
        throw new Error(`${fieldName} must be a valid ObjectId`);
    }
}

function escapeRegexLiteral(text)
{
    return String(text || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function resolveAssistantTaskReference(db, userId, taskReference)
{
    const trimmedReference = String(taskReference || '').trim();
    if(!trimmedReference)
    {
        throw new Error('taskId is required');
    }

    const userObjectId = new ObjectId(userId);

    if(ObjectId.isValid(trimmedReference))
    {
        const byId = await db.collection('tasks').findOne({
            _id: new ObjectId(trimmedReference),
            user_id: userObjectId,
        });
        if(byId)
        {
            return byId;
        }
    }

    const exactTitleRegex = new RegExp(`^${escapeRegexLiteral(trimmedReference)}$`, 'i');
    const matches = await db.collection('tasks')
        .find({
            user_id: userObjectId,
            $or: [
                { title: exactTitleRegex },
                { externalEventId: trimmedReference },
                { externalUid: trimmedReference },
            ],
        })
        .sort({ dueDate: 1 })
        .limit(3)
        .toArray();

    if(matches.length === 1)
    {
        return matches[0];
    }

    if(matches.length > 1)
    {
        throw new Error('Multiple tasks matched that reference. Search first or mention the title plus a date/group so I can pick the right one.');
    }

    const broadRegex = new RegExp(escapeRegexLiteral(trimmedReference), 'i');
    const broadMatches = await db.collection('tasks')
        .find({
            user_id: userObjectId,
            $or: [
                { title: broadRegex },
                { description: broadRegex },
                { location: broadRegex },
                { group: broadRegex },
            ],
        })
        .sort({ dueDate: 1 })
        .limit(5)
        .toArray();

    if(broadMatches.length === 1)
    {
        return broadMatches[0];
    }

    if(broadMatches.length > 1)
    {
        throw new Error('Multiple tasks matched that reference. Search first or mention the title plus a date/group so I can pick the right one.');
    }

    throw new Error('Task not found. Search first or mention the exact title plus a date/group so I can identify it.');
}

async function getUserCalendarSubscriptions(db, userId)
{
    const user = await db.collection('users').findOne(
        { _id: new ObjectId(userId) },
        { projection: { calendarSubscriptions: 1 } }
    );

    if(Array.isArray(user?.calendarSubscriptions))
    {
        return user.calendarSubscriptions.map((subscription) => ({
            _id: subscription._id instanceof ObjectId
                ? subscription._id
                : new ObjectId(String(subscription._id)),
            url: String(subscription.url || '').trim(),
            name: String(subscription.name || '').trim(),
            lastSyncedAt: subscription.lastSyncedAt ? new Date(subscription.lastSyncedAt) : null,
            lastSyncError: String(subscription.lastSyncError || ''),
        }));
    }

    return [];
}

async function upsertUserCalendarSubscription(db, userId, subscription)
{
    const subscriptions = await getUserCalendarSubscriptions(db, userId);
    const normalizedUrl = String(subscription.url || '').trim();
    const existing = subscriptions.find(item => item.url === normalizedUrl);

    if(existing)
    {
        const updates = {};
        if(subscription.name !== undefined) updates.name = String(subscription.name || '').trim();
        if(subscription.lastSyncedAt !== undefined) updates.lastSyncedAt = subscription.lastSyncedAt;
        if(subscription.lastSyncError !== undefined) updates.lastSyncError = String(subscription.lastSyncError || '');

        if(Object.keys(updates).length > 0)
        {
            await updateUserCalendarSubscription(db, userId, existing._id, updates);
            return { ...existing, ...updates };
        }

        return existing;
    }

    const created = {
        _id: new ObjectId(),
        url: normalizedUrl,
        name: String(subscription.name || '').trim(),
        lastSyncedAt: subscription.lastSyncedAt ?? null,
        lastSyncError: String(subscription.lastSyncError || ''),
    };

    await db.collection('users').updateOne(
        { _id: new ObjectId(userId) },
        { $push: { calendarSubscriptions: created } }
    );

    return created;
}

async function updateUserCalendarSubscription(db, userId, subscriptionId, updates)
{
    const normalizedId = subscriptionId instanceof ObjectId
        ? subscriptionId
        : new ObjectId(String(subscriptionId));
    const setUpdates = {};

    for(const [key, value] of Object.entries(updates))
    {
        setUpdates[`calendarSubscriptions.$.${key}`] = value;
    }

    if(Object.keys(setUpdates).length === 0)
    {
        return;
    }

    await db.collection('users').updateOne(
        {
            _id: new ObjectId(userId),
            'calendarSubscriptions._id': normalizedId,
        },
        { $set: setUpdates }
    );
}

async function removeUserCalendarSubscription(db, userId, subscriptionId)
{
    const normalizedId = subscriptionId instanceof ObjectId
        ? subscriptionId
        : new ObjectId(String(subscriptionId));

    const result = await db.collection('users').updateOne(
        { _id: new ObjectId(userId) },
        { $pull: { calendarSubscriptions: { _id: normalizedId } } }
    );

    return result.modifiedCount > 0;
}

function normalizeTaskForTool(task)
{
    if(!task) return null;

    return {
        id: String(task._id),
        title: task.title || '',
        description: task.description || '',
        location: task.location || '',
        dueDate: getTaskStartDate(task)?.toISOString() || null,
        endDate: task.endDate ? new Date(task.endDate).toISOString() : null,
        isCompleted: task.isCompleted === true,
        source: task.source || 'manual',
        color: normalizeTaskColor(task.color),
        group: normalizeTaskGroup(task.group, task.source || 'manual'),
        reminderEnabled: task.reminderEnabled === true,
        reminderMinutesBefore: Number.isFinite(Number(task.reminderMinutesBefore))
            ? Number(task.reminderMinutesBefore)
            : 0,
        reminderDelivery: String(task.reminderDelivery || 'email'),
        reminderAt: task.reminderAt ? new Date(task.reminderAt).toISOString() : null,
    };
}

function buildCalendarAssistantTools()
{
    return [
        {
            type: 'function',
            name: 'search_calendar_tasks',
            description: 'Find calendar tasks for the current user before editing or referencing them.',
            parameters: {
                type: 'object',
                properties: {
                    query: { type: 'string', description: 'Title, description, or location text to search for.' },
                    startDate: { type: 'string', description: 'Optional ISO datetime lower bound.' },
                    endDate: { type: 'string', description: 'Optional ISO datetime upper bound.' },
                    limit: { type: 'number', description: 'Maximum number of tasks to return.' },
                    offset: { type: 'number', description: 'Number of matches to skip for pagination.' },
                },
                required: [],
                additionalProperties: false,
            },
        },
        {
            type: 'function',
            name: 'list_calendar_tasks_in_range',
            description: 'List calendar tasks in a date range, useful for future planning questions.',
            parameters: {
                type: 'object',
                properties: {
                    startDate: { type: 'string', description: 'ISO datetime lower bound.' },
                    endDate: { type: 'string', description: 'ISO datetime upper bound.' },
                    limit: { type: 'number', description: 'Maximum number of tasks to return.' },
                    offset: { type: 'number', description: 'Number of matches to skip for pagination.' },
                },
                required: ['startDate', 'endDate'],
                additionalProperties: false,
            },
        },
        {
            type: 'function',
            name: 'create_calendar_task',
            description: 'Create a new calendar task or event for the current user.',
            parameters: {
                type: 'object',
                properties: {
                    title: { type: 'string' },
                    description: { type: 'string' },
                    location: { type: 'string' },
                    dueDate: { type: 'string', description: 'ISO datetime for the event start.' },
                    endDate: { type: 'string', description: 'Optional ISO datetime for the event end.' },
                    color: { type: 'string', description: 'Optional hex color such as #60A5FA.' },
                    group: { type: 'string', description: 'Optional user-facing group label such as School or Work.' },
                    reminderEnabled: { type: 'boolean', description: 'Whether to send an email reminder.' },
                    reminderMinutesBefore: { type: 'number', description: 'Minutes before the task to send the reminder email.' },
                },
                required: ['title', 'dueDate'],
                additionalProperties: false,
            },
        },
        {
            type: 'function',
            name: 'update_calendar_task',
            description: 'Update an existing calendar task or event for the current user. Prefer an exact id from tool results, but a unique title or other unique reference can also work.',
            parameters: {
                type: 'object',
                properties: {
                    taskId: { type: 'string', description: 'Prefer the exact task id from tool results, but a unique title or reference can also work. If uncertain, search first.' },
                    title: { type: 'string' },
                    description: { type: 'string' },
                    location: { type: 'string' },
                    dueDate: { type: 'string', description: 'Optional ISO datetime for the new start.' },
                    endDate: { type: 'string', description: 'Optional ISO datetime for the new end.' },
                    color: { type: 'string', description: 'Optional hex color such as #60A5FA.' },
                    group: { type: 'string', description: 'Optional user-facing group label such as School or Work.' },
                    isCompleted: { type: 'boolean' },
                    reminderEnabled: { type: 'boolean', description: 'Whether email reminders are enabled.' },
                    reminderMinutesBefore: { type: 'number', description: 'Minutes before the task to send the reminder email.' },
                },
                required: ['taskId'],
                additionalProperties: false,
            },
        },
        {
            type: 'function',
            name: 'create_recurring_calendar_tasks',
            description: 'Create a recurring series of calendar tasks for the current user, such as every Monday and Wednesday until a given date.',
            parameters: {
                type: 'object',
                properties: {
                    title: { type: 'string' },
                    description: { type: 'string' },
                    location: { type: 'string' },
                    startDate: { type: 'string', description: 'ISO datetime for the first event start time.' },
                    endDate: { type: 'string', description: 'Optional ISO datetime for the first event end time.' },
                    daysOfWeek: {
                        type: 'array',
                        description: 'Recurring weekday codes using SU, MO, TU, WE, TH, FR, SA.',
                        items: { type: 'string' },
                    },
                    untilDate: { type: 'string', description: 'ISO datetime cutoff for the final allowed occurrence.' },
                    intervalWeeks: { type: 'number', description: 'Optional number of weeks between repeats. Defaults to 1.' },
                    maxOccurrences: { type: 'number', description: 'Optional safety cap on created events. Defaults to 120.' },
                    color: { type: 'string', description: 'Optional hex color such as #60A5FA.' },
                    group: { type: 'string', description: 'Optional user-facing group label such as School or Work.' },
                    reminderEnabled: { type: 'boolean', description: 'Whether to send an email reminder.' },
                    reminderMinutesBefore: { type: 'number', description: 'Minutes before each task to send the reminder email.' },
                },
                required: ['title', 'startDate', 'daysOfWeek', 'untilDate'],
                additionalProperties: false,
            },
        },
        {
            type: 'function',
            name: 'delete_calendar_task',
            description: 'Delete an existing calendar task or event for the current user. Prefer an exact id from tool results, but a unique title or other unique reference can also work.',
            parameters: {
                type: 'object',
                properties: {
                    taskId: { type: 'string', description: 'Prefer the exact task id from tool results, but a unique title or reference can also work. If uncertain, search first.' },
                },
                required: ['taskId'],
                additionalProperties: false,
            },
        },
    ];
}

async function executeCalendarAssistantTool(db, userId, toolCall, options = {})
{
    const toolName = toolCall.name;
    const args = JSON.parse(toolCall.arguments || '{}');
    const utcOffsetMinutes = options.utcOffsetMinutes;
    const timeZone = options.timeZone;

    if(toolName === 'search_calendar_tasks')
    {
        const query = { user_id: new ObjectId(userId) };
        const trimmedQuery = String(args.query || '').trim();

        if(trimmedQuery)
        {
            query.$or = [
                { title: { $regex: trimmedQuery, $options: 'i' } },
                { description: { $regex: trimmedQuery, $options: 'i' } },
                { location: { $regex: trimmedQuery, $options: 'i' } },
                { group: { $regex: trimmedQuery, $options: 'i' } },
            ];
        }

        if(args.startDate || args.endDate)
        {
            query.dueDate = {};
            if(args.startDate) query.dueDate.$gte = parseDateTimeWithOffset(args.startDate, utcOffsetMinutes, timeZone);
            if(args.endDate) query.dueDate.$lte = parseDateTimeWithOffset(args.endDate, utcOffsetMinutes, timeZone);
        }

        const limit = Math.max(1, Math.min(Number(args.limit) || 20, 100));
        const offset = Math.max(0, Number(args.offset) || 0);
        const tasks = await db.collection('tasks')
            .find(query)
            .sort({ dueDate: 1 })
            .skip(offset)
            .limit(limit)
            .toArray();
        const total = await db.collection('tasks').countDocuments(query);

        return {
            total,
            found: tasks.length,
            offset,
            hasMore: offset + tasks.length < total,
            tasks: tasks.map(normalizeTaskForTool),
        };
    }

    if(toolName === 'list_calendar_tasks_in_range')
    {
        const startDate = parseDateTimeWithOffset(args.startDate, utcOffsetMinutes, timeZone);
        const endDate = parseDateTimeWithOffset(args.endDate, utcOffsetMinutes, timeZone);
        if(!startDate || Number.isNaN(startDate.getTime()) || !endDate || Number.isNaN(endDate.getTime()))
        {
            throw new Error('list_calendar_tasks_in_range requires valid startDate and endDate');
        }

        const limit = Math.max(1, Math.min(Number(args.limit) || 25, 100));
        const offset = Math.max(0, Number(args.offset) || 0);
        const query = {
            user_id: new ObjectId(userId),
            dueDate: { $gte: startDate, $lte: endDate },
        };
        const tasks = await db.collection('tasks')
            .find(query)
            .sort({ dueDate: 1 })
            .skip(offset)
            .limit(limit)
            .toArray();
        const total = await db.collection('tasks').countDocuments(query);

        return {
            total,
            found: tasks.length,
            offset,
            hasMore: offset + tasks.length < total,
            tasks: tasks.map(normalizeTaskForTool),
        };
    }

    if(toolName === 'create_calendar_task')
    {
        const dueDate = parseDateTimeWithOffset(args.dueDate, utcOffsetMinutes, timeZone);
        if(!dueDate || Number.isNaN(dueDate.getTime()))
        {
            throw new Error('create_calendar_task requires a valid dueDate');
        }

        const endDate = args.endDate
            ? parseDateTimeWithOffset(args.endDate, utcOffsetMinutes, timeZone)
            : dueDate;
        const document = {
            user_id: new ObjectId(userId),
            title: String(args.title || '').trim(),
            description: String(args.description || '').trim(),
            location: String(args.location || '').trim(),
            dueDate,
            endDate: Number.isNaN(endDate.getTime()) ? dueDate : endDate,
            isCompleted: false,
            source: 'manual',
            color: normalizeTaskColor(args.color),
            group: normalizeTaskGroup(args.group),
        };
        Object.assign(document, buildReminderFields(document, {
            reminderEnabled: args.reminderEnabled,
            reminderMinutesBefore: args.reminderMinutesBefore,
        }));

        if(!document.title)
        {
            throw new Error('create_calendar_task requires a title');
        }

        const result = await db.collection('tasks').insertOne(document);
        return {
            created: true,
            task: normalizeTaskForTool({ ...document, _id: result.insertedId }),
        };
    }

    if(toolName === 'update_calendar_task')
    {
        const existing = await resolveAssistantTaskReference(db, userId, args.taskId);
        const taskId = existing._id;


        const updates = {};
        if(args.title !== undefined) updates.title = String(args.title || '').trim();
        if(args.description !== undefined) updates.description = String(args.description || '').trim();
        if(args.location !== undefined) updates.location = String(args.location || '').trim();
        if(args.color !== undefined) updates.color = normalizeTaskColor(args.color);
        if(args.group !== undefined) updates.group = normalizeTaskGroup(args.group);
        if(args.dueDate !== undefined)
        {
            const dueDate = parseDateTimeWithOffset(args.dueDate, utcOffsetMinutes, timeZone);
            if(Number.isNaN(dueDate.getTime())) throw new Error('dueDate must be a valid ISO datetime');
            updates.dueDate = dueDate;
        }
        if(args.endDate !== undefined)
        {
            const endDate = parseDateTimeWithOffset(args.endDate, utcOffsetMinutes, timeZone);
            if(Number.isNaN(endDate.getTime())) throw new Error('endDate must be a valid ISO datetime');
            updates.endDate = endDate;
        }
        if(args.isCompleted !== undefined) updates.isCompleted = args.isCompleted === true;
        if(
            args.dueDate !== undefined ||
            args.endDate !== undefined ||
            args.reminderEnabled !== undefined ||
            args.reminderMinutesBefore !== undefined ||
            args.reminderDelivery !== undefined
        )
        {
            const mergedTask = {
                ...existing,
                ...updates,
            };
            Object.assign(updates, buildReminderFields(mergedTask, {
                reminderEnabled: args.reminderEnabled,
                reminderMinutesBefore: args.reminderMinutesBefore,
                reminderDelivery: args.reminderDelivery,
            }, existing));
        }

        if(Object.keys(updates).length === 0)
        {
            return {
                updated: false,
                task: normalizeTaskForTool(existing),
            };
        }

        await db.collection('tasks').updateOne(
            { _id: taskId, user_id: new ObjectId(userId) },
            { $set: updates }
        );

        const updatedTask = await db.collection('tasks').findOne({
            _id: taskId,
            user_id: new ObjectId(userId),
        });

        return {
            updated: true,
            task: normalizeTaskForTool(updatedTask),
        };
    }

    if(toolName === 'create_recurring_calendar_tasks')
    {
        const documents = buildRecurringTaskDocuments(userId, args, {
            utcOffsetMinutes,
            timeZone,
        });

        const insertResult = await db.collection('tasks').insertMany(documents, { ordered: true });
        const insertedIds = Object.values(insertResult.insertedIds || {});
        const createdTasks = documents.map((document, index) => normalizeTaskForTool({
            ...document,
            _id: insertedIds[index],
        }));

        return {
            created: true,
            count: createdTasks.length,
            tasks: createdTasks,
        };
    }

    if(toolName === 'delete_calendar_task')
    {
        const existing = await resolveAssistantTaskReference(db, userId, args.taskId);
        const taskId = existing._id;

        await db.collection('tasks').deleteOne({
            _id: taskId,
            user_id: new ObjectId(userId),
        });

        return {
            deleted: true,
            task: normalizeTaskForTool(existing),
        };
    }

    throw new Error(`Unsupported tool: ${toolName}`);
}

async function runCalendarAssistant(apiKey, db, userId, messages, context)
{
    const tools = buildCalendarAssistantTools();
    let input = [...context.prefixMessages, ...messages];
    let calendarChanged = false;
    const seenToolCalls = new Set();
    const useWebSearch = shouldUseAssistantWebSearch(messages);

    for(let iteration = 0; iteration < 6; iteration += 1)
    {
        const response = await createOpenAIResponse(
            apiKey,
            input,
            {
                instructions: context.systemPrompt,
                useWebSearch,
                tools,
            }
        );

        const functionCalls = Array.isArray(response.output)
            ? response.output.filter(item => item?.type === 'function_call')
            : [];

        if(functionCalls.length === 0)
        {
            return {
                reply: extractResponseText(response),
                calendarChanged,
            };
        }

        const repeatedCalls = functionCalls.filter((toolCall) =>
        {
            const signature = `${toolCall.name}:${toolCall.arguments || ''}`;
            if(seenToolCalls.has(signature))
            {
                return true;
            }

            seenToolCalls.add(signature);
            return false;
        });

        if(repeatedCalls.length === functionCalls.length)
        {
            const reply = await callOpenAI(
                apiKey,
                input,
                {
                    instructions: `${context.systemPrompt}

Use the existing tool results already in the conversation and answer the user directly now.
Do not call more tools unless the user asks for a new action.`,
                    useWebSearch,
                }
            );

            return {
                reply,
                calendarChanged,
            };
        }

        input = [...input, ...response.output];

        for(const toolCall of functionCalls)
        {
            let output;
            try
            {
                output = await executeCalendarAssistantTool(
                    db,
                    userId,
                    toolCall,
                    {
                        utcOffsetMinutes: context.utcOffsetMinutes,
                        timeZone: context.timeZone,
                    }
                );
                if(
                    (
                        toolCall.name === 'create_calendar_task' ||
                        toolCall.name === 'create_recurring_calendar_tasks' ||
                        toolCall.name === 'update_calendar_task' ||
                        toolCall.name === 'delete_calendar_task'
                    ) &&
                    !output?.error
                )
                {
                    calendarChanged = true;
                }
            }
            catch(error)
            {
                output = {
                    error: String(error?.message || error || 'Tool call failed'),
                    ok: false,
                };
            }
            input.push({
                type: 'function_call_output',
                call_id: toolCall.call_id,
                output: JSON.stringify(output),
            });
        }

        input.push({
            role: 'system',
            content: 'Use the tool results above to answer the user directly. If a tool returned an error, recover gracefully: either use web search, ask a brief clarification question, or explain that you could not identify the exact calendar item. Do not repeat the same tool call with the same arguments.',
        });
    }

    const reply = await callOpenAI(
        apiKey,
        input,
        {
            instructions: `${context.systemPrompt}

Answer the user directly using the tool results already gathered.
Do not call any more tools in this response.`,
            useWebSearch,
        }
    );

    return {
        reply,
        calendarChanged,
    };
}

exports.setApp = function(app, client)
{
    const token = require('./createJWT.js');
    const emailAssets = Object.freeze({
        'verification-mascot.png': path.resolve(__dirname, '..', 'VerificationMascot.png'),
        'reminder-mascot.png': path.resolve(__dirname, '..', 'ReminderMascot.png'),
        'reset-password-mascot.png': path.resolve(__dirname, '..', 'ResetPassword.png'),
    });

    app.get('/api/email-assets/:assetName', (req, res) =>
    {
        const assetPath = emailAssets[req.params.assetName];
        if(!assetPath)
        {
            res.sendStatus(404);
            return;
        }

        res.setHeader('Cache-Control', 'no-store, max-age=0');
        res.type('png');
        res.sendFile(assetPath, (error) =>
        {
            if(error && !res.headersSent)
            {
                res.sendStatus(404);
            }
        });
    });

    app.post('/api/login', async (req, res) =>
    {
        const { login, password } = req.body;

        try
        {
            const db = getDatabase(client);
            const user = await db.collection('users').findOne({ email: login });

            if(!user || !verifyPassword(password, user.password))
            {
                res.status(401).json({ error: 'Login/Password incorrect' });
                return;
            }

            if(!user.isVerified)
            {
                res.status(403).json({ error: 'Please verify your email before logging in' });
                return;
            }

            const tokenResult = token.createToken(user.firstName, user.lastName, user._id);
            res.status(200).json(tokenResult);
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });


    app.post('/api/signup', async (req, res) =>
    {
        const { firstName, lastName, email, password } = req.body;

        try
        {
            const db = getDatabase(client);
            const existingUser = await db.collection('users').findOne({ email });

            if(existingUser)
            {
                res.status(409).json({ error: 'An account with that email already exists' });
                return;
            }

            const verifyToken        = crypto.randomBytes(32).toString('hex');
            const verifyTokenExpires = new Date(Date.now() + 24 * 60 * 60 * 1000);

            const newUser = {
                firstName,
                lastName,
                email,
                password: hashPassword(password),
                isVerified: false,
                verifyToken,
                verifyTokenExpires,
            };

            await db.collection('users').insertOne(newUser);

            const verifyLink = `${process.env.SERVER_URL}/api/verifyemail?token=${verifyToken}`;
            await sendWithResend(
                email,
                'Verify your Calendar++ email ✅',
                verificationEmailHtml(verifyLink)
            );

            res.status(201).json({ error: '' });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });


    app.get('/api/verifyemail', async (req, res) =>
    {
        const { token: verifyToken } = req.query;

        if(!verifyToken)
        {
            res.status(400).json({ error: 'Verification token is missing' });
            return;
        }

        try
        {
            const db   = getDatabase(client);
            const user = await db.collection('users').findOne(
            {
                verifyToken,
                verifyTokenExpires: { $gt: new Date() },
            });

            if(!user)
            {
                res.status(400).json({ error: 'Invalid or expired verification link' });
                return;
            }

            await db.collection('users').updateOne(
                { _id: user._id },
                {
                    $set:   { isVerified: true },
                    $unset: { verifyToken: '', verifyTokenExpires: '' },
                }
            );

            res.redirect(`${process.env.CLIENT_ORIGIN || 'http://localhost:3000'}?verified=1`);
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });

    // ─── Forgot Password ────────────────────────────────────────────────────────
    app.get('/api/open-resetpassword', async (req, res) =>
    {
        const token = String(req.query.token || '').trim();
        if(!token)
        {
            res.status(400).send('Reset token is missing.');
            return;
        }

        const links = buildResetLinks(token);
        res.type('html').send(renderOpenResetPage(links));
    });

    app.post('/api/forgotpassword', async (req, res) =>
    {
        const { email } = req.body;
        if(!email)
        {
            res.status(400).json({ error: 'Email is required' });
            return;
        }

        try
        {
            const db   = getDatabase(client);
            const user = await db.collection('users').findOne({ email: email.toLowerCase().trim() });

            // Always return 200 to avoid user enumeration attacks
            if(!user)
            {
                res.status(200).json({ error: '' });
                return;
            }

            const resetToken        = crypto.randomBytes(32).toString('hex');
            const resetTokenExpires = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

            await db.collection('users').updateOne(
                { _id: user._id },
                { $set: { resetToken, resetTokenExpires } }
            );

            const resetLinks = buildResetLinks(resetToken);
            await sendWithResend(
                user.email,
                '&#128273; Reset your Calendar++ password',
                passwordResetEmailHtml(resetLinks)
            );

            res.status(200).json({ error: '' });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });

    // ─── Reset Password ──────────────────────────────────────────────────────────
    app.post('/api/resetpassword', async (req, res) =>
    {
        const { token, newPassword } = req.body;
        if(!token || !newPassword)
        {
            res.status(400).json({ error: 'Token and new password are required' });
            return;
        }

        if(newPassword.length < 6)
        {
            res.status(400).json({ error: 'Password must be at least 6 characters' });
            return;
        }

        try
        {
            const db   = getDatabase(client);
            const user = await db.collection('users').findOne(
            {
                resetToken: token,
                resetTokenExpires: { $gt: new Date() },
            });

            if(!user)
            {
                res.status(400).json({ error: 'Invalid or expired reset link' });
                return;
            }

            await db.collection('users').updateOne(
                { _id: user._id },
                {
                    $set:   { password: hashPassword(newPassword) },
                    $unset: { resetToken: '', resetTokenExpires: '' },
                }
            );

            res.status(200).json({ error: '' });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });

    // ─── Register Device Token (for push notifications) ─────────────────────
    app.post('/api/registerdevicetoken', async (req, res) =>
    {
        const auth = validateBearerJwtOrRespond(req, res);
        if(!auth) return;
        const { userId } = auth;

        const { deviceToken, platform } = req.body;
        pushDebug('registerdevicetoken hit.', {
            userId: String(userId || ''),
            platform: platform || '',
            hasToken: Boolean(deviceToken),
            tokenPreview: deviceToken ? `${String(deviceToken).slice(0, 12)}...` : '',
        });
        if(!deviceToken)
        {
            res.status(400).json({ error: 'deviceToken is required' });
            return;
        }

        try
        {
            const db = getDatabase(client);
            pushDebug('Persisting device token to users collection.', {
                userId: String(userId || ''),
                platform: platform || 'ios',
            });
            await db.collection('users').updateOne(
                { _id: new ObjectId(userId) },
                { $set: { deviceToken, devicePlatform: platform || 'ios' } }
            );
            pushDebug('Device token persisted successfully.', {
                userId: String(userId || ''),
                platform: platform || 'ios',
            });
            res.status(200).json({ error: '' });
        }
        catch(error)
        {
            pushDebug('registerdevicetoken failed.', {
                userId: String(userId || ''),
                error: error.message,
            });
            res.status(500).json({ error: error.toString() });
        }
    });

    app.delete('/api/registerdevicetoken', async (req, res) =>
    {
        const auth = validateBearerJwtOrRespond(req, res);
        if(!auth) return;
        const { userId } = auth;

        try
        {
            const db = getDatabase(client);
            await db.collection('users').updateOne(
                { _id: new ObjectId(userId) },
                { $unset: { deviceToken: '', devicePlatform: '' } }
            );
            res.status(200).json({ error: '' });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString() });
        }
    });

        app.get('/api/verifyemailchange', async (req, res) =>
    {
        const { token: emailChangeToken } = req.query;

        if(!emailChangeToken)
        {
            res.status(400).send('Missing email change token');
            return;
        }

        try
        {
            const db = getDatabase(client);
            const user = await db.collection('users').findOne({
                emailChangeToken,
                emailChangeTokenExpires: { $gt: new Date() },
            });

            if(!user || !user.pendingEmail)
            {
                res.status(400).send('Invalid or expired email change link');
                return;
            }

            const existingUser = await db.collection('users').findOne({
                email: user.pendingEmail,
                _id: { $ne: user._id },
            });

            if(existingUser)
            {
                res.status(409).send('That email is already in use');
                return;
            }

            await db.collection('users').updateOne(
                { _id: user._id },
                {
                    $set: { email: user.pendingEmail, isVerified: true },
                    $unset: {
                        pendingEmail: '',
                        emailChangeToken: '',
                        emailChangeTokenExpires: '',
                    },
                }
            );

            res.redirect(`${process.env.CLIENT_ORIGIN || 'http://localhost:3000'}?emailChanged=1`);
        }
        catch(error)
        {
            res.status(500).send(error.toString());
        }
    });

    app.get('/api/calendarfeed/:feedToken', async (req, res) =>
    {
        const feedToken = String(req.params.feedToken || '').trim();

        if(!feedToken)
        {
            res.status(400).send('Missing calendar feed token');
            return;
        }

        try
        {
            const db = getDatabase(client);
            const user = await db.collection('users').findOne(
                { calendarFeedToken: feedToken },
                { projection: { _id: 1 } }
            );

            if(!user)
            {
                res.status(404).send('Calendar feed not found');
                return;
            }

            const tasks = await db.collection('tasks')
                .find({ user_id: user._id })
                .sort({ dueDate: 1 })
                .toArray();

            res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
            res.setHeader('Content-Disposition', 'inline; filename="calendar-plus-plus.ics"');
            res.status(200).send(buildCalendarExport(tasks));
        }
        catch(error)
        {
            res.status(500).send(error.toString());
        }
    });

    app.post('/api/getaccountsettings', async (req, res) =>
    {
        const { userId, jwtToken } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            await db.collection('users').updateOne(
                {
                    _id: new ObjectId(userId),
                    $or: [
                        { calendarFeedToken: { $exists: false } },
                        { calendarFeedToken: '' },
                    ],
                },
                {
                    $set: { calendarFeedToken: generateCalendarFeedToken() },
                }
            );
            const user = await db.collection('users').findOne(
                { _id: new ObjectId(userId) },
                {
                    projection: {
                        firstName: 1,
                        lastName: 1,
                        email: 1,
                        pendingEmail: 1,
                        reminderDefaults: 1,
                        calendarFeedToken: 1,
                    },
                }
            );

            if(!user)
            {
                res.status(404).json({ settings: null, error: 'User not found', jwtToken: '' });
                return;
            }

            res.status(200).json({
                settings: buildSettingsPayload(user),
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ settings: null, error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/saveaccountsettings', async (req, res) =>
    {
        const {
            userId,
            jwtToken,
            firstName,
            lastName,
            reminderEnabled,
            reminderMinutesBefore,
            reminderDelivery,
        } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const updates = {
                firstName: String(firstName || '').trim(),
                lastName: String(lastName || '').trim(),
                reminderDefaults: normalizeReminderSettings({
                    reminderEnabled,
                    reminderMinutesBefore,
                    reminderDelivery,
                }, {
                    reminderEnabled: false,
                    reminderMinutesBefore: 30,
                    reminderDelivery: 'email',
                }),
            };

            await db.collection('users').updateOne(
                { _id: new ObjectId(userId) },
                { $set: updates }
            );

            const refreshedUser = await db.collection('users').findOne(
                { _id: new ObjectId(userId) },
                {
                    projection: {
                        firstName: 1,
                        lastName: 1,
                        email: 1,
                        pendingEmail: 1,
                        reminderDefaults: 1,
                        calendarFeedToken: 1,
                    },
                }
            );

            const refreshedToken = token.createToken(
                refreshedUser?.firstName || '',
                refreshedUser?.lastName || '',
                userId
            );

            res.status(200).json({
                settings: buildSettingsPayload(refreshedUser),
                error: '',
                jwtToken: refreshedToken.error ? '' : refreshedToken.accessToken,
            });
        }
        catch(error)
        {
            res.status(500).json({ settings: null, error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/regeneratecalendarfeed', async (req, res) =>
    {
        const { userId, jwtToken } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const nextFeedToken = generateCalendarFeedToken();

            await db.collection('users').updateOne(
                { _id: new ObjectId(userId) },
                { $set: { calendarFeedToken: nextFeedToken } }
            );

            const user = await db.collection('users').findOne(
                { _id: new ObjectId(userId) },
                {
                    projection: {
                        firstName: 1,
                        lastName: 1,
                        email: 1,
                        pendingEmail: 1,
                        reminderDefaults: 1,
                        calendarFeedToken: 1,
                    },
                }
            );

            res.status(200).json({
                settings: buildSettingsPayload(user),
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ settings: null, error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/requestemailchange', async (req, res) =>
    {
        const { userId, jwtToken, nextEmail } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        const normalizedEmail = String(nextEmail || '').trim().toLowerCase();
        if(!normalizedEmail)
        {
            res.status(400).json({ error: 'New email is required', jwtToken: '' });
            return;
        }

        try
        {
            const db = getDatabase(client);
            const user = await db.collection('users').findOne({ _id: new ObjectId(userId) });

            if(!user)
            {
                res.status(404).json({ error: 'User not found', jwtToken: '' });
                return;
            }

            if(String(user.email || '').toLowerCase() === normalizedEmail)
            {
                res.status(400).json({ error: 'That is already your current email', jwtToken: '' });
                return;
            }

            const existingUser = await db.collection('users').findOne({
                email: normalizedEmail,
                _id: { $ne: new ObjectId(userId) },
            });

            if(existingUser)
            {
                res.status(409).json({ error: 'An account with that email already exists', jwtToken: '' });
                return;
            }

            const emailChangeToken = crypto.randomBytes(32).toString('hex');
            const emailChangeTokenExpires = new Date(Date.now() + 24 * 60 * 60 * 1000);
            const verifyLink = `${process.env.SERVER_URL}/api/verifyemailchange?token=${emailChangeToken}`;

            await db.collection('users').updateOne(
                { _id: new ObjectId(userId) },
                {
                    $set: {
                        pendingEmail: normalizedEmail,
                        emailChangeToken,
                        emailChangeTokenExpires,
                    },
                }
            );

            await sendWithResend(
                normalizedEmail,
                'Confirm your new Calendar++ email 📬',
                emailChangeEmailHtml(verifyLink)
            );

            res.status(200).json({
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/loadcalendar', async (req, res) =>
    {
        const { userId, jwtToken, startDate, endDate, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            await persistUserTimeContext(db, userId, timeZone, utcOffsetMinutes);
            await syncStoredCalendarSubscriptions(db, userId, { timeZone, utcOffsetMinutes });
            const query = { user_id: new ObjectId(userId) };
            const dateRangeFilter = buildDueDateRangeFilter(startDate, endDate, { timeZone, utcOffsetMinutes });

            if(dateRangeFilter)
            {
                query.dueDate = dateRangeFilter.dueDate;
            }

            const results = await db.collection('tasks')
                .find(query)
                .sort({ dueDate: 1 })
                .toArray();

            res.status(200).json({
                tasks: results.map((task) => normalizeLegacyIcsTaskForResponse(task, {
                    timeZone,
                    utcOffsetMinutes,
                })),
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ tasks: [], error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/searchcalendar', async (req, res) =>
    {
        const { userId, jwtToken, search } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const trimmedSearch = search.trim();

            const results = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                $or:
                [
                    { title:       { $regex: trimmedSearch + '.*', $options: 'i' } },
                    { description: { $regex: trimmedSearch + '.*', $options: 'i' } },
                    { location:    { $regex: trimmedSearch + '.*', $options: 'i' } },
                    { group:       { $regex: trimmedSearch + '.*', $options: 'i' } },
                ]
            })
            .sort({ dueDate: 1 })
            .toArray();

            res.status(200).json({
                results: results.map((task) => normalizeLegacyIcsTaskForResponse(task)),
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ results: [], error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/exportcalendar', async (req, res) =>
    {
        const { userId, jwtToken } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const tasks = await db.collection('tasks')
                .find({ user_id: new ObjectId(userId) })
                .sort({ dueDate: 1 })
                .toArray();

            res.status(200).json({
                ics: buildCalendarExport(tasks),
                filename: 'calendar-plus-plus.ics',
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ ics: '', filename: '', error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/savecalendar', async (req, res) =>
    {
        const {
            userId,
            jwtToken,
            taskId,
            title,
            description,
            dueDate,
            startDate,
            endDate,
            location,
            source,
            color,
            group,
            isCompleted,
            reminderEnabled,
            reminderMinutesBefore,
            reminderDelivery,
            timeZone,
            utcOffsetMinutes,
        } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            await persistUserTimeContext(db, userId, timeZone, utcOffsetMinutes);

            if(taskId)
            {
                const existingTask = await db.collection('tasks').findOne({
                    _id: new ObjectId(taskId),
                    user_id: new ObjectId(userId),
                });

                if(!existingTask)
                {
                    res.status(404).json({ error: 'Task not found', jwtToken: '' });
                    return;
                }

                const updates = {};
                const nextDueDate = dueDate !== undefined ? dueDate : startDate;
                if(title       !== undefined) updates.title       = title;
                if(description !== undefined) updates.description = description;
                if(nextDueDate !== undefined)
                {
                    updates.dueDate = nextDueDate
                        ? parseDateTimeInUserZone(nextDueDate, { timeZone, utcOffsetMinutes })
                        : null;
                }
                if(endDate     !== undefined) updates.endDate     = endDate
                    ? parseDateTimeInUserZone(endDate, { timeZone, utcOffsetMinutes })
                    : null;
                if(location    !== undefined) updates.location    = location;
                if(source      !== undefined) updates.source      = source;
                if(color       !== undefined) updates.color       = normalizeTaskColor(color);
                if(group       !== undefined) updates.group       = normalizeTaskGroup(group);
                if(isCompleted !== undefined) updates.isCompleted = isCompleted;
                if(
                    nextDueDate !== undefined ||
                    endDate !== undefined ||
                    reminderEnabled !== undefined ||
                    reminderMinutesBefore !== undefined ||
                    reminderDelivery !== undefined
                )
                {
                    const mergedTask = {
                        ...existingTask,
                        ...updates,
                    };
                    Object.assign(updates, buildReminderFields(mergedTask, {
                        reminderEnabled,
                        reminderMinutesBefore,
                        reminderDelivery,
                    }, existingTask));
                }

                await db.collection('tasks').updateOne(
                    { _id: new ObjectId(taskId), user_id: new ObjectId(userId) },
                    { $set: updates }
                );
            }
            else
            {
                const nextDueDate = dueDate !== undefined ? dueDate : startDate;
                const nextEndDate = endDate !== undefined
                    ? (endDate ? parseDateTimeInUserZone(endDate, { timeZone, utcOffsetMinutes }) : null)
                    : (nextDueDate ? parseDateTimeInUserZone(nextDueDate, { timeZone, utcOffsetMinutes }) : null);
                const newTask = {
                    user_id:     new ObjectId(userId),
                    title:       title || '',
                    description: description || '',
                    location:    location || '',
                    dueDate:     nextDueDate ? parseDateTimeInUserZone(nextDueDate, { timeZone, utcOffsetMinutes }) : null,
                    endDate:     nextEndDate,
                    isCompleted: isCompleted || false,
                    source:      source || 'manual',
                    color:       normalizeTaskColor(color),
                    group:       normalizeTaskGroup(group),
                };
                Object.assign(newTask, buildReminderFields(newTask, {
                    reminderEnabled,
                    reminderMinutesBefore,
                    reminderDelivery,
                }));

                await db.collection('tasks').insertOne(newTask);
            }

            res.status(200).json({ error: '', jwtToken: refreshJwtToken(token, jwtToken) });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/readcalendar', async (req, res) =>
    {
        const { userId, jwtToken, icsContent, icsUrl, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const ical = require('node-ical');
            const db = getDatabase(client);
            await persistUserTimeContext(db, userId, timeZone, utcOffsetMinutes);
            let calendarContent = String(icsContent || '').trim();
            const trimmedUrl = String(icsUrl || '').trim();
            let parsedUrl = null;

            if(!calendarContent && trimmedUrl)
            {
                parsedUrl = normalizeHttpsUrl(trimmedUrl);
                calendarContent = await httpsTextRequest(parsedUrl);
            }

            if(!calendarContent)
            {
                res.status(400).json({
                    count: 0,
                    error: 'Either icsContent or icsUrl is required',
                    jwtToken: '',
                });
                return;
            }

            const parsed   = ical.sync.parseICS(calendarContent);

            if(parsedUrl)
            {
                const normalizedUrl = parsedUrl.toString();
                const calendarName = getCalendarDisplayName(parsed);
                const subscription = await upsertUserCalendarSubscription(db, userId, {
                    url: normalizedUrl,
                    name: calendarName || '',
                    lastSyncedAt: null,
                    lastSyncError: '',
                });

                await syncCalendarSubscription(db, userId, subscription, {
                    force: true,
                    timeZone,
                    utcOffsetMinutes,
                });

                const duplicateFilters = [];
                for(const key of Object.keys(parsed))
                {
                    const entry = parsed[key];
                    if(entry.type !== 'VEVENT') continue;
                    if(!entry.summary || !entry.start) continue;

                    const signature = buildIcsTaskSignature(entry, { timeZone, utcOffsetMinutes });
                    duplicateFilters.push({
                        user_id: new ObjectId(userId),
                        source: 'ical',
                        subscriptionId: { $exists: false },
                        title: signature.title,
                        description: signature.description,
                        location: signature.location,
                        dueDate: signature.dueDate,
                        endDate: signature.endDate,
                    });
                }

                if(duplicateFilters.length > 0)
                {
                    await db.collection('tasks').deleteMany({
                        $or: duplicateFilters,
                    });
                }

                const count = await db.collection('tasks').countDocuments({
                    user_id: new ObjectId(userId),
                    subscriptionId: new ObjectId(subscription._id),
                    source: 'ical',
                });

                res.status(200).json({
                    count,
                    error: '',
                    jwtToken: refreshJwtToken(token, jwtToken),
                });
                return;
            }

            const toInsert = [];

            for(const key of Object.keys(parsed))
            {
                const entry = parsed[key];
                if(entry.type !== 'VEVENT') continue;
                if(!entry.summary || !entry.start) continue;

                const signature = buildIcsTaskSignature(entry, { timeZone, utcOffsetMinutes });
                toInsert.push(
                {
                    user_id:     new ObjectId(userId),
                    title:       signature.title,
                    description: signature.description,
                    location:    signature.location,
                    dueDate:     signature.dueDate,
                    endDate:     signature.endDate,
                    isCompleted: false,
                    source:      'ical',
                });
            }

            if(toInsert.length > 0)
            {
                const result = await db.collection('tasks').insertMany(toInsert);
                res.status(200).json({
                    count: result.insertedCount,
                    error: '',
                    jwtToken: refreshJwtToken(token, jwtToken),
                });
                return;
            }

            res.status(200).json({ count: 0, error: '', jwtToken: refreshJwtToken(token, jwtToken) });
        }
        catch(error)
        {
            res.status(500).json({ count: 0, error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/listcalendarsubscriptions', async (req, res) =>
    {
        const { userId, jwtToken } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const subscriptions = await getUserCalendarSubscriptions(db, userId);
            res.status(200).json({
                subscriptions: subscriptions.map((subscription) => ({
                    _id: String(subscription._id),
                    url: subscription.url,
                    name: subscription.name,
                    lastSyncedAt: subscription.lastSyncedAt ? subscription.lastSyncedAt.toISOString() : null,
                    lastSyncError: subscription.lastSyncError,
                })),
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ subscriptions: [], error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/deletecalendarsubscription', async (req, res) =>
    {
        const { userId, jwtToken, subscriptionId } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        if(!subscriptionId)
        {
            res.status(400).json({ error: 'subscriptionId is required', jwtToken: '' });
            return;
        }

        try
        {
            const db = getDatabase(client);
            const normalizedId = new ObjectId(String(subscriptionId));
            await db.collection('tasks').deleteMany({
                user_id: new ObjectId(userId),
                subscriptionId: normalizedId,
            });
            await removeUserCalendarSubscription(db, userId, normalizedId);

            res.status(200).json({ error: '', jwtToken: refreshJwtToken(token, jwtToken) });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString(), jwtToken: '' });
        }
    });

    app.post('/api/synccalendarsubscription', async (req, res) =>
    {
        const { userId, jwtToken, subscriptionId, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        if(!subscriptionId)
        {
            res.status(400).json({ error: 'subscriptionId is required', jwtToken: '' });
            return;
        }

        try
        {
            const db = getDatabase(client);
            const subscriptions = await getUserCalendarSubscriptions(db, userId);
            const subscription = subscriptions.find((item) => String(item._id) === String(subscriptionId));

            if(!subscription)
            {
                res.status(404).json({ error: 'Subscription not found', jwtToken: '' });
                return;
            }

            await syncCalendarSubscription(db, userId, subscription, {
                force: true,
                timeZone,
                utcOffsetMinutes,
            });
            const refreshed = await getUserCalendarSubscriptions(db, userId);
            const updated = refreshed.find((item) => String(item._id) === String(subscriptionId));

            res.status(200).json({
                subscription: updated ? {
                    _id: String(updated._id),
                    url: updated.url,
                    name: updated.name,
                    lastSyncedAt: updated.lastSyncedAt ? updated.lastSyncedAt.toISOString() : null,
                    lastSyncError: updated.lastSyncError,
                } : null,
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ subscription: null, error: error.toString(), jwtToken: '' });
        }
    });


    // Suggest events with ChatGPT Chat Completions API
    app.post('/api/suggestevents', async (req, res) =>
    {
        const { userId, jwtToken, date, latitude, longitude, preferences, localNow, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        const apiKey = process.env.OPENAI_API_KEY;
        if(!apiKey)
        {
            res.status(500).json({ suggestions: [], error: 'OPENAI API key is not configured', jwtToken: '' });
            return;
        }

        try
        {
            const db          = getDatabase(client);
            const timeOptions = { timeZone, utcOffsetMinutes };
            const targetDate  = date ? parseDateTimeWithOffset(date, utcOffsetMinutes, timeZone) : new Date();
            const localNowDate = localNow ? parseDateTimeWithOffset(localNow, utcOffsetMinutes, timeZone) : new Date();
            const { start: dayStart, end: dayEnd } = getDayRangeInUserZone(targetDate, timeOptions);

            // Fetch the current tasks for the target day
            const tasks = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                dueDate: { $gte: dayStart, $lte: dayEnd },
            })
            .sort({ dueDate: 1 })
            .toArray();

            const taskSummary = tasks.length
                ? tasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' at ' + formatTimeForUser(getTaskStartDate(t), timeOptions) : ''}${t.location ? ' (' + t.location + ')' : ''}`)
                      .join('\n')
                : 'No tasks scheduled for this day.';

            // Get user preferences by getting recent task history
            const recent = await db.collection('tasks').find(
            {
                user_id:     new ObjectId(userId),
                isCompleted: true,
            })
            .sort({ dueDate: -1 })
            .limit(30)
            .toArray();

            const recentSummary = recent.length
                ? [...new Set(recent.map(t => t.title))].slice(0, 15).join(', ')
                : 'No recent task history available.';

            // Optionally fetch weather
            let weatherSummary = 'Weather data not available (no coordinates provided).';
            if(latitude != null && longitude != null)
            {
                const w = await fetchWeather(latitude, longitude);
                if(w) weatherSummary = `${w.description}, ${w.temperatureF}°F, wind ${w.windSpeedMph} mph`;
            }

            const localTimeSummary = [
                `Local time: ${formatLocalTimeContext(localNowDate, timeOptions)}.`,
                timeZone ? `Timezone: ${timeZone}.` : '',
                utcOffsetMinutes !== undefined ? `UTC offset minutes: ${utcOffsetMinutes}.` : '',
            ].filter(Boolean).join(' ');

            // Build system prompt and completion prompt
            const systemPrompt =
                `You are a helpful personal assistant that suggests calendar events for a user's day.
                 You may use live web search when current or local information would improve your answer.
                 Respond ONLY with a valid JSON array of objects.
                 Each object must have: "title" (string), "description" (string), "suggestedTime" (HH:MM 24-hour local time).
                 Suggest 3-5 events. Do not include any explanation or text outside the JSON array.`;

            const locationContext = latitude != null && longitude != null
                ? `Approximate user coordinates: latitude ${latitude}, longitude ${longitude}.`
                : 'No exact coordinates were provided.';

            const userPrompt =
                `Today is ${formatDateForUser(targetDate, timeOptions)}.

${localTimeSummary}

Current weather: ${weatherSummary}

${locationContext}

Existing tasks for today:
${taskSummary}

Recent activity (interests): ${recentSummary}

${preferences ? `Additional caller preferences: ${preferences}` : ''}

Suggest practical, realistic calendar events that complement the existing tasks and fit the weather and preferences.`;

            const rawResponse = await callOpenAI(
                apiKey,
                [{ role: 'user', content: userPrompt }],
                {
                    instructions: systemPrompt,
                    useWebSearch: true,
                }
            );

            let suggestions;
            try   { suggestions = JSON.parse(rawResponse); }
            catch { suggestions = [{ title: 'Parse error', description: rawResponse, suggestedTime: '' }]; }

            res.status(200).json({
                suggestions,
                error:    '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ suggestions: [], error: error.toString(), jwtToken: '' });
        }
    });


    // Chat with ChatGPT Chat Completions
    app.post('/api/chat', async (req, res) =>
    {
        const { userId, jwtToken, messages, latitude, longitude, localNow, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken)) return;

        const apiKey = process.env.OPENAI_API_KEY;
        if(!apiKey)
        {
            res.status(500).json({ reply: '', error: 'OPENAI API key is not configured', jwtToken: '' });
            return;
        }

        if(!Array.isArray(messages) || messages.length === 0)
        {
            res.status(400).json({ reply: '', error: 'messages array is required', jwtToken: '' });
            return;
        }

        try
        {
            const db   = getDatabase(client);
            const timeOptions = { timeZone, utcOffsetMinutes };
            const now  = localNow ? parseDateTimeWithOffset(localNow, utcOffsetMinutes, timeZone) : new Date();
            const { start: dayStart, end: dayEnd } = getDayRangeInUserZone(now, timeOptions);

            // Current tasks for today
            const todayTasks = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                dueDate: { $gte: dayStart, $lte: dayEnd },
            })
            .sort({ dueDate: 1 })
            .toArray();

            const todaySummary = todayTasks.length
                ? todayTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' at ' + formatTimeForUser(getTaskStartDate(t), timeOptions) : ''}`)
                            .join('\n')
                : 'No tasks today.';

            // Current tasks for this week (where isCompleted: false)
            const weekEnd = toUserDateTime(now, timeOptions).plus({ days: 7 }).endOf('day').toUTC().toJSDate();

            const weekTasks = await db.collection('tasks').find({
                user_id: new ObjectId(userId),
                isCompleted: false,
                dueDate: { $gt: dayEnd, $lte: weekEnd },
            })
            .sort({ dueDate: 1 })
            .toArray();

            const comingWeek = weekTasks.length
                ? weekTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' on ' + formatDateTimeForUser(getTaskStartDate(t), timeOptions) : ''}`).join('\n')
                : 'No upcoming tasks this week.';

            // Get user preferences by getting recent task history
            const recent = await db.collection('tasks').find(
            {
                user_id:     new ObjectId(userId),
                isCompleted: true,
            })
            .sort({ dueDate: -1 })
            .limit(30)
            .toArray();

            const recentTitles = recent.length
                ? [...new Set(recent.map(t => t.title))].slice(0, 15).join(', ')
                : 'None';

            // Get the weather
            let weatherLine = 'Weather: not available.';
            if(latitude != null && longitude != null)
            {
                const w = await fetchWeather(latitude, longitude);
                if(w) weatherLine = `Current weather: ${w.description}, ${w.temperatureF}°F, wind ${w.windSpeedMph} mph.`;
            }

            const localTimeLine = [
                `Local time: ${formatLocalTimeContext(now, timeOptions)}.`,
                timeZone ? `Timezone: ${timeZone}.` : '',
                utcOffsetMinutes !== undefined ? `UTC offset minutes: ${utcOffsetMinutes}.` : '',
            ].filter(Boolean).join(' ');

            // Build system prompt and user prompt
            const systemPrompt =
                `You are a knowledgeable personal calendar assistant.
                 You have access to the user's current schedule and preferences.
                 You should proactively use live web search when the user asks about current, nearby, local, recommended, or otherwise time-sensitive things.
                 Do not claim you lack real-time access if web search would help; use it instead.
                 Questions about store, restaurant, venue, or campus building hours are not calendar-edit requests. Use web search for those unless the user clearly refers to one of their scheduled items.
                 When the user asks to create, edit, move, reschedule, complete, or delete calendar tasks, use the available calendar tools.
                 When the user asks for repeating tasks like "every Monday and Wednesday until June", use the recurring calendar tool instead of many one-off creates.
                 Think carefully before editing or deleting. If the exact task id is not already known from tool results, search or list first. You may use an exact id, or a unique title/reference if it clearly identifies a single task. Do not invent task ids.
                 You can also enable email reminders when the user asks for a reminder before a task.
                 Respect task color or grouping requests when the user mentions them.
                 Treat times mentioned by the user as local to the user unless they say otherwise.
                 When calling calendar tools, provide ISO datetimes. If you only know a local wall-clock time, include the user's local offset if possible.
                 The schedule shown in this prompt is only a summary. If the user asks about future events or anything beyond the visible summary, use the calendar tools to search broader ranges before answering.
                 Your final reply should sound conversational, warm, and natural rather than robotic. Keep it concise, but talk like a helpful person.

Today is ${formatDateForUser(now, timeOptions)}.
${localTimeLine}
${weatherLine}

Today's schedule:
${todaySummary}

Coming week schedule:
${comingWeek}

Recently completed tasks (interests): ${recentTitles}

Help the user manage their schedule, suggest events, answer questions about their day, and offer practical advice. Be concise, conversational, and relatable.`;

            const locationContext = latitude != null && longitude != null
                ? `Approximate user coordinates: latitude ${latitude}, longitude ${longitude}.`
                : 'No exact coordinates were provided.';

            const assistantResult = await runCalendarAssistant(
                apiKey,
                db,
                userId,
                messages,
                {
                    systemPrompt,
                    prefixMessages: [{ role: 'user', content: locationContext }],
                    utcOffsetMinutes,
                    timeZone,
                }
            );

            res.status(200).json({
                reply: assistantResult.reply,
                calendarChanged: assistantResult.calendarChanged,
                error:    '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ reply: '', error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/deletecalendar', async (req, res) =>
    {
        const { userId, jwtToken, taskId } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            const result = await db.collection('tasks').deleteOne({
                _id: new ObjectId(taskId),
                user_id: new ObjectId(userId),
            });

            if(result.deletedCount === 0)
            {
                res.status(404).json({ error: 'Task not found', jwtToken: '' });
                return;
            }

            res.status(200).json({ error: '', jwtToken: refreshJwtToken(token, jwtToken) });
        }
        catch(error)
        {
            res.status(500).json({ error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/chatstream', async (req, res) =>
    {
        const { userId, jwtToken, messages, latitude, longitude, localNow, timeZone, utcOffsetMinutes } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken)) return;

        const apiKey = process.env.OPENAI_API_KEY;
        if(!apiKey)
        {
            res.status(500).json({ error: 'OPENAI API key is not configured', jwtToken: '' });
            return;
        }

        if(!Array.isArray(messages) || messages.length === 0)
        {
            res.status(400).json({ error: 'messages array is required', jwtToken: '' });
            return;
        }

        try
        {
            const db   = getDatabase(client);
            const timeOptions = { timeZone, utcOffsetMinutes };
            const now  = localNow ? parseDateTimeWithOffset(localNow, utcOffsetMinutes, timeZone) : new Date();
            const { start: dayStart, end: dayEnd } = getDayRangeInUserZone(now, timeOptions);

            const todayTasks = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                dueDate: { $gte: dayStart, $lte: dayEnd },
            })
            .sort({ dueDate: 1 })
            .toArray();

            const todaySummary = todayTasks.length
                ? todayTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' at ' + formatTimeForUser(getTaskStartDate(t), timeOptions) : ''}`).join('\n')
                : 'No tasks today.';

            const weekEnd = toUserDateTime(now, timeOptions).plus({ days: 7 }).endOf('day').toUTC().toJSDate();

            const weekTasks = await db.collection('tasks').find({
                user_id: new ObjectId(userId),
                isCompleted: false,
                dueDate: { $gt: dayEnd, $lte: weekEnd },
            })
            .sort({ dueDate: 1 })
            .toArray();

            const comingWeek = weekTasks.length
                ? weekTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' on ' + formatDateTimeForUser(getTaskStartDate(t), timeOptions) : ''}`).join('\n')
                : 'No upcoming tasks this week.';

            const recent = await db.collection('tasks').find(
            {
                user_id:     new ObjectId(userId),
                isCompleted: true,
            })
            .sort({ dueDate: -1 })
            .limit(30)
            .toArray();

            const recentTitles = recent.length
                ? [...new Set(recent.map(t => t.title))].slice(0, 15).join(', ')
                : 'None';

            let weatherLine = 'Weather: not available.';
            if(latitude != null && longitude != null)
            {
                const w = await fetchWeather(latitude, longitude);
                if(w) weatherLine = `Current weather: ${w.description}, ${w.temperatureF}Â°F, wind ${w.windSpeedMph} mph.`;
            }

            const localTimeLine = [
                `Local time: ${formatLocalTimeContext(now, timeOptions)}.`,
                timeZone ? `Timezone: ${timeZone}.` : '',
                utcOffsetMinutes !== undefined ? `UTC offset minutes: ${utcOffsetMinutes}.` : '',
            ].filter(Boolean).join(' ');

            const systemPrompt =
                `You are a knowledgeable personal calendar assistant.
                 You have access to the user's current schedule and preferences.
                 You should proactively use live web search when the user asks about current, nearby, local, recommended, or otherwise time-sensitive things.
                 Do not claim you lack real-time access if web search would help; use it instead.
                 Questions about store, restaurant, venue, or campus building hours are not calendar-edit requests. Use web search for those unless the user clearly refers to one of their scheduled items.
                 When the user asks to create, edit, move, reschedule, complete, or delete calendar tasks, use the available calendar tools.
                 When the user asks for repeating tasks like "every Monday and Wednesday until June", use the recurring calendar tool instead of many one-off creates.
                 Think carefully before editing or deleting. If the exact task id is not already known from tool results, search or list first. You may use an exact id, or a unique title/reference if it clearly identifies a single task. Do not invent task ids.
                 You can also enable email reminders when the user asks for a reminder before a task.
                 Respect task color or grouping requests when the user mentions them.
                 Treat times mentioned by the user as local to the user unless they say otherwise.
                 When calling calendar tools, provide ISO datetimes. If you only know a local wall-clock time, include the user's local offset if possible.
                 The schedule shown in this prompt is only a summary. If the user asks about future events or anything beyond the visible summary, use the calendar tools to search broader ranges before answering.
                 Your final reply should sound conversational, warm, and natural rather than robotic. Keep it concise, but talk like a helpful person.

Today is ${formatDateForUser(now, timeOptions)}.
${localTimeLine}
${weatherLine}

Today's schedule:
${todaySummary}

Coming week schedule:
${comingWeek}

Recently completed tasks (interests): ${recentTitles}

Help the user manage their schedule, suggest events, answer questions about their day, and offer practical advice. Be concise, conversational, and relatable.`;

            const locationContext = latitude != null && longitude != null
                ? `Approximate user coordinates: latitude ${latitude}, longitude ${longitude}.`
                : 'No exact coordinates were provided.';

            res.status(200);
            res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
            res.setHeader('Cache-Control', 'no-cache, no-transform');
            res.setHeader('Connection', 'keep-alive');
            res.flushHeaders?.();

            const writeEvent = (payload) =>
            {
                res.write(`${JSON.stringify(payload)}\n`);
            };

            const assistantResult = await runCalendarAssistant(
                apiKey,
                db,
                userId,
                messages,
                {
                    systemPrompt,
                    prefixMessages: [{ role: 'user', content: locationContext }],
                    utcOffsetMinutes,
                    timeZone,
                }
            );

            const chunks = assistantResult.reply.match(/.{1,28}(\s|$)|.{1,28}/g) || [assistantResult.reply];
            for(const chunk of chunks)
            {
                writeEvent({ type: 'delta', delta: chunk });
            }

            writeEvent({
                type: 'done',
                jwtToken: refreshJwtToken(token, jwtToken),
                calendarChanged: assistantResult.calendarChanged,
            });

            res.end();
        }
        catch(error)
        {
            if(!res.headersSent)
            {
                res.status(500).json({ error: error.toString(), jwtToken: '' });
                return;
            }

            res.write(`${JSON.stringify({ type: 'error', error: error.toString() })}\n`);
            res.end();
        }
    });

};

exports.verifyEmailTransporter = verifyEmailTransporter;
exports.startReminderLoop = startReminderLoop;
