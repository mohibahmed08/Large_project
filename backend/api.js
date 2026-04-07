const nodemailer = require('nodemailer');
const crypto     = require('crypto');
const https      = require('https');
const { ObjectId } = require('mongodb');

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

// OpenAI Chat Completions Call
async function callOpenAI(apiKey, messages, model = 'gpt-4o-mini')
{
    const bodyStr = JSON.stringify({ model, messages, temperature: 0.7 });
    const result  = await httpsRequest(
    {
        hostname: 'api.openai.com',
        path:     '/v1/chat/completions',
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
    return result.body.choices[0].message.content;
}

function createTransporter()
{
    return nodemailer.createTransport(
    {
        service: 'gmail',
        auth:
        {
            user: 'calendarplusplusapp@gmail.com',
            pass: process.env.Gmail_APP_PASS || process.env.GMAIL_APP_PASS,
        },
    });
}

const emailTransporter = createTransporter();

function verifyEmailTransporter()
{
    emailTransporter.verify((error) =>
    {
        if(error)
        {
            console.error('SMTP verification failed:', error.message);
            return;
        }

        console.log('SMTP server is ready to take messages');
    });
}

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

function refreshJwtToken(tokenUtils, accessToken)
{
    const refreshedToken = tokenUtils.refresh(accessToken);
    return refreshedToken.error ? '' : refreshedToken.accessToken;
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

function buildTaskFromIcsEntry(userId, subscriptionId, entry)
{
    return {
        user_id:        new ObjectId(userId),
        title:          entry.summary     || '(No title)',
        description:    entry.description || '',
        location:       entry.location    || '',
        startDate:      new Date(entry.start),
        endDate:        entry.end ? new Date(entry.end) : null,
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

        const task = buildTaskFromIcsEntry(userId, subscription._id, entry);
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

    await db.collection('calendar_subscriptions').updateOne(
        { _id: new ObjectId(subscription._id) },
        {
            $set:
            {
                url: parsedUrl.toString(),
                name: calendarName || subscription.name || '',
                lastSyncedAt: now,
                lastSyncError: '',
            },
        }
    );

    return {
        insertedCount,
        updatedCount,
        deletedCount: deleteResult.deletedCount || 0,
        skipped: false,
    };
}

async function syncStoredCalendarSubscriptions(db, userId)
{
    const subscriptions = await db.collection('calendar_subscriptions')
        .find({ user_id: new ObjectId(userId) })
        .toArray();

    for(const subscription of subscriptions)
    {
        try
        {
            await syncCalendarSubscription(db, userId, subscription);
        }
        catch(error)
        {
            await db.collection('calendar_subscriptions').updateOne(
                { _id: new ObjectId(subscription._id) },
                {
                    $set:
                    {
                        lastSyncError: error.message,
                        lastSyncedAt: new Date(),
                    },
                }
            );
        }
    }
}

function buildStartDateRangeFilter(startDate, endDate)
{
    if(!startDate && !endDate)
    {
        return null;
    }

    const range = {};
    if(startDate) range.$gte = new Date(startDate);
    if(endDate)   range.$lte = new Date(endDate);

    return { startDate: range };
}

function getTaskStartDate(task)
{
    return task.startDate || null;
}

exports.setApp = function(app, client)
{
    const token = require('./createJWT.js');

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
            await emailTransporter.sendMail(
            {
                from:    `"${process.env.SMTP_FROM_NAME || 'Calendar'}" <calendarplusplusapp@gmail.com>`,
                to:      email,
                subject: 'Verify your Calendar account',
                html:    `<h2>Welcome!</h2>
                          <p>Click below to verify your email. Link expires in 24 hours.</p>
                          <a href="${verifyLink}">Verify Email</a>`,
            });

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


    app.post('/api/loadcalendar', async (req, res) =>
    {
        const { userId, jwtToken, startDate, endDate } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);
            await syncStoredCalendarSubscriptions(db, userId);
            const query = { user_id: new ObjectId(userId) };
            const dateRangeFilter = buildStartDateRangeFilter(startDate, endDate);

            if(dateRangeFilter)
            {
                query.startDate = dateRangeFilter.startDate;
            }

            const results = await db.collection('tasks')
                .find(query)
                .sort({ startDate: 1 })
                .toArray();

            res.status(200).json({
                tasks: results,
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
                ]
            })
            .sort({ startDate: 1 })
            .toArray();

            res.status(200).json({
                results,
                error: '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ results: [], error: error.toString(), jwtToken: '' });
        }
    });


    app.post('/api/savecalendar', async (req, res) =>
    {
        const { userId, jwtToken, taskId, title, description, startDate, isCompleted } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const db = getDatabase(client);

            if(taskId)
            {
                const updates = {};
                if(title       !== undefined) updates.title       = title;
                if(description !== undefined) updates.description = description;
                if(startDate !== undefined)
                {
                    updates.startDate = startDate ? new Date(startDate) : null;
                }
                if(isCompleted !== undefined) updates.isCompleted = isCompleted;

                await db.collection('tasks').updateOne(
                    { _id: new ObjectId(taskId), user_id: new ObjectId(userId) },
                    { $set: updates }
                );
            }
            else
            {
                const newTask = {
                    user_id:     new ObjectId(userId),
                    title:       title || '',
                    description: description || '',
                    startDate:   startDate ? new Date(startDate) : null,
                    isCompleted: isCompleted || false,
                };

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
        const { userId, jwtToken, icsContent, icsUrl } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const ical = require('node-ical');
            const db = getDatabase(client);
            let calendarContent = String(icsContent || '').trim();
            const trimmedUrl = String(icsUrl || '').trim();

            if(!calendarContent && trimmedUrl)
            {
                const parsedUrl = normalizeHttpsUrl(trimmedUrl);
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

            if(trimmedUrl)
            {
                const normalizedUrl = normalizeHttpsUrl(trimmedUrl).toString();
                const existingSubscription = await db.collection('calendar_subscriptions').findOne(
                {
                    user_id: new ObjectId(userId),
                    url: normalizedUrl,
                });

                let subscription = existingSubscription;

                if(!subscription)
                {
                    const insertResult = await db.collection('calendar_subscriptions').insertOne(
                    {
                        user_id: new ObjectId(userId),
                        url: normalizedUrl,
                        name: '',
                        lastSyncedAt: null,
                        lastSyncError: '',
                        createdAt: new Date(),
                    });

                    subscription = {
                        _id: insertResult.insertedId,
                        user_id: new ObjectId(userId),
                        url: normalizedUrl,
                        name: '',
                        lastSyncedAt: null,
                    };
                }

                const syncResult = await syncCalendarSubscription(db, userId, subscription, { force: true });
                res.status(200).json({
                    count: syncResult.insertedCount + syncResult.updatedCount,
                    error: '',
                    jwtToken: refreshJwtToken(token, jwtToken),
                });
                return;
            }

            const parsed   = ical.sync.parseICS(calendarContent);
            const toInsert = [];

            for(const key of Object.keys(parsed))
            {
                const entry = parsed[key];
                if(entry.type !== 'VEVENT') continue;
                if(!entry.summary || !entry.start) continue;

                toInsert.push(
                {
                    user_id:     new ObjectId(userId),
                    title:       entry.summary     || '(No title)',
                    description: entry.description || '',
                    location:    entry.location    || '',
                    startDate:   new Date(entry.start),
                    endDate:     entry.end ? new Date(entry.end) : null,
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


    // Suggest events with ChatGPT Chat Completions API
    app.post('/api/suggestevents', async (req, res) =>
    {
        const { userId, jwtToken, date, latitude, longitude, preferences } = req.body;

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
            const targetDate  = date ? new Date(date) : new Date();
            const dayStart    = new Date(targetDate); dayStart.setHours(0, 0, 0, 0);
            const dayEnd      = new Date(targetDate); dayEnd.setHours(23, 59, 59, 999);

            // Fetch the current tasks for the target day
            const tasks = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                startDate: { $gte: dayStart, $lte: dayEnd },
            })
            .sort({ startDate: 1 })
            .toArray();

            const taskSummary = tasks.length
                ? tasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' at ' + getTaskStartDate(t).toLocaleTimeString() : ''}${t.location ? ' (' + t.location + ')' : ''}`)
                      .join('\n')
                : 'No tasks scheduled for this day.';

            // Get user preferences by getting recent task history
            const recent = await db.collection('tasks').find(
            {
                user_id:     new ObjectId(userId),
                isCompleted: true,
            })
            .sort({ startDate: -1 })
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

            // Build system prompt and completion prompt
            const systemPrompt =
                `You are a helpful personal assistant that suggests calendar events for a user's day.
                 Respond ONLY with a valid JSON array of objects.
                 Each object must have: "title" (string), "description" (string), "suggestedTime" (HH:MM 24-hour).
                 Suggest 3-5 events. Do not include any explanation or text outside the JSON array.`;

            const userPrompt =
                `Today is ${targetDate.toDateString()}.

Current weather: ${weatherSummary}

Existing tasks for today:
${taskSummary}

Recent activity (interests): ${recentSummary}

${preferences ? `Additional caller preferences: ${preferences}` : ''}

Suggest practical, realistic calendar events that complement the existing tasks and fit the weather and preferences.`;

            // Call OpenAI chat completion
            const rawResponse = await callOpenAI(apiKey,
            [
                { role: 'system', content: systemPrompt },
                { role: 'user',   content: userPrompt   },
            ]);

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
        const { userId, jwtToken, messages, latitude, longitude } = req.body;

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
            const now  = new Date();
            const dayStart = new Date(now); dayStart.setHours(0, 0, 0, 0);
            const dayEnd   = new Date(now); dayEnd.setHours(23, 59, 59, 999);

            // Current tasks for today
            const todayTasks = await db.collection('tasks').find(
            {
                user_id: new ObjectId(userId),
                startDate: { $gte: dayStart, $lte: dayEnd },
            })
            .sort({ startDate: 1 })
            .toArray();

            const todaySummary = todayTasks.length
                ? todayTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' at ' + getTaskStartDate(t).toLocaleTimeString() : ''}`)
                            .join('\n')
                : 'No tasks today.';

            // Current tasks for this week (where isCompleted: false)
            const weekEnd = new Date(now);
            weekEnd.setDate(weekEnd.getDate() + 7);
            weekEnd.setHours(23, 59, 59, 999);

            const weekTasks = await db.collection('tasks').find({
                user_id: new ObjectId(userId),
                isCompleted: false,
                startDate: { $gt: dayEnd, $lte: weekEnd },
            })
            .sort({ startDate: 1 })
            .toArray();

            const comingWeek = weekTasks.length
                ? weekTasks.map(t => `- ${t.title}${getTaskStartDate(t) ? ' on ' + new Date(getTaskStartDate(t)).toLocaleString() : ''}`).join('\n')
                : 'No upcoming tasks this week.';

            // Get user preferences by getting recent task history
            const recent = await db.collection('tasks').find(
            {
                user_id:     new ObjectId(userId),
                isCompleted: true,
            })
            .sort({ startDate: -1 })
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

            // Build system prompt and user prompt
            const systemPrompt =
                `You are a knowledgeable personal calendar assistant.
                 You have access to the user's current schedule and preferences.

Today is ${now.toDateString()}.
${weatherLine}

Today's schedule:
${todaySummary}

Coming week schedule:
${comingWeek}

Recently completed tasks (interests): ${recentTitles}

Help the user manage their schedule, suggest events, answer questions about their day, and offer practical advice. Be concise but conversational and relatable.`;

            // Call OpenAI chat completions
            const openAIMessages = [
                { role: 'system', content: systemPrompt },
                ...messages,
            ];

            const reply = await callOpenAI(apiKey, openAIMessages);

            res.status(200).json({
                reply,
                error:    '',
                jwtToken: refreshJwtToken(token, jwtToken),
            });
        }
        catch(error)
        {
            res.status(500).json({ reply: '', error: error.toString(), jwtToken: '' });
        }
    });

};

exports.verifyEmailTransporter = verifyEmailTransporter;
