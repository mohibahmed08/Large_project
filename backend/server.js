const express    = require('express');
const bodyParser = require('body-parser');
const cors       = require('cors');
const fs         = require('fs');
const path       = require('path');

require('dotenv').config({ path: path.resolve(__dirname, '.env') });

// MongoDB connection
const { MongoClient } = require('mongodb');
const client = new MongoClient(process.env.MONGODB_URI);
client.connect();

const app = express();
const appleAssociationPath = path.resolve(__dirname, 'apple-app-site-association');
const appleAssociationBody = fs.existsSync(appleAssociationPath)
    ? fs.readFileSync(appleAssociationPath, 'utf8')
    : JSON.stringify({
        applinks: {
            details: [
                {
                    appIDs: ['5QT26Z28QX.com.jonathan.calendar'],
                    components: [
                        {
                            '/': '/*',
                            comment: 'Open Calendar++ web links in the iOS app when installed.',
                        },
                    ],
                },
            ],
        },
    });

app.use(cors());
app.use(bodyParser.json({ limit: '24mb' }));

app.use((req, res, next) =>
{
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader(
        'Access-Control-Allow-Headers',
        'Origin, X-Requested-With, Content-Type, Accept, Authorization'
    );
    res.setHeader(
        'Access-Control-Allow-Methods',
        'GET, POST, PATCH, DELETE, OPTIONS'
    );
    next();
});

function sendAppleAssociation(req, res)
{
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.status(200).send(appleAssociationBody);
}

app.get('/apple-app-site-association', sendAppleAssociation);
app.get('/.well-known/apple-app-site-association', sendAppleAssociation);

// API routing
const api = require('./api.js');
api.setApp(app, client);
api.verifyEmailTransporter();
api.startReminderLoop(client);

app.use((err, req, res, next) =>
{
    if(err?.type === 'entity.too.large')
    {
        res.status(413).json({
            error: 'Upload too large. Try a smaller image.',
        });
        return;
    }

    if(err instanceof SyntaxError && err.status === 400 && 'body' in err)
    {
        res.status(400).json({
            error: 'Invalid JSON request body.',
        });
        return;
    }

    next(err);
});

// Starting the server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
