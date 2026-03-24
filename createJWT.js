const jwt = require('jsonwebtoken');
require('dotenv').config();

function _createToken(firstName, lastName, userId)
{
    const user = { userId, firstName, lastName };
    return jwt.sign(user, process.env.ACCESS_TOKEN_SECRET, { expiresIn: '24h' });
}

exports.createToken = function(firstName, lastName, userId)
{
    try
    {
        return { accessToken: _createToken(firstName, lastName, userId) };
    }
    catch(error)
    {
        return { error: error.message };
    }
};

exports.isExpired = function(accessToken)
{
    try
    {
        jwt.verify(accessToken, process.env.ACCESS_TOKEN_SECRET);
        return false;
    }
    catch(error)
    {
        return true;
    }
};

exports.refresh = function(accessToken)
{
    try
    {
        const decodedToken = jwt.decode(accessToken, { complete: true });

        if(!decodedToken || !decodedToken.payload)
        {
            return { error: 'Invalid token payload' };
        }

        const { firstName, lastName, userId } = decodedToken.payload;
        return { accessToken: _createToken(firstName, lastName, userId) };
    }
    catch(error)
    {
        return { error: error.message };
    }
};
