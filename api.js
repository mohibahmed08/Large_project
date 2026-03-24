const nodemailer = require('nodemailer');
const crypto     = require('crypto');
const { ObjectId } = require('mongodb');

function createTransporter()
{
    return nodemailer.createTransport(
    {
        host:   process.env.SMTP_HOST,
        port:   Number(process.env.SMTP_PORT) || 587,
        secure: process.env.SMTP_SECURE === 'true',
        auth:
        {
            user: process.env.SMTP_USER,
            pass: process.env.SMTP_PASS,
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
                from:    `"Callendar" <${process.env.SMTP_USER}>`,
                to:      email,
                subject: 'Verify your Callendar account',
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
            const query = { user_id: new ObjectId(userId) };

            if(startDate || endDate)
            {
                query.dueDate = {};
                if(startDate) query.dueDate.$gte = new Date(startDate);
                if(endDate)   query.dueDate.$lte = new Date(endDate);
            }

            const results = await db.collection('tasks')
                .find(query)
                .sort({ dueDate: 1 })
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
            .sort({ dueDate: 1 })
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
        const { userId, jwtToken, taskId, title, description, dueDate, isCompleted } = req.body;

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
                if(dueDate     !== undefined) updates.dueDate     = new Date(dueDate);
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
                    dueDate:     dueDate ? new Date(dueDate) : null,
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
        const { userId, jwtToken, icsContent } = req.body;

        if(!validateJwtOrRespond(token, res, jwtToken))
        {
            return;
        }

        try
        {
            const ical = require('node-ical');
            const db = getDatabase(client);

            const parsed   = ical.sync.parseICS(icsContent);
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
                    dueDate:     new Date(entry.start),
                    isCompleted: false,
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

};

exports.verifyEmailTransporter = verifyEmailTransporter;
