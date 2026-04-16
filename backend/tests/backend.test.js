const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

process.env.ACCESS_TOKEN_SECRET = 'test-access-secret';
process.env.OPENAI_MODEL = 'gpt-5.4';
process.env.OPENAI_FALLBACK_MODEL = 'gpt-4.1-mini';
process.env.OPENAI_REASONING_EFFORT = 'medium';
process.env.CLIENT_ORIGIN = 'https://calendarplusplus.xyz';

const tokenUtils = require('../createJWT.js');
const { __testables } = require('../api.js');

const tests = [
  {
    name: 'createToken signs a JWT with the expected payload',
    run() {
      const result = tokenUtils.createToken('Alex', 'Rivera', 'user-42');
      const decoded = jwt.verify(
        result.accessToken,
        process.env.ACCESS_TOKEN_SECRET,
      );

      assert.equal(decoded.userId, 'user-42');
      assert.equal(decoded.firstName, 'Alex');
      assert.equal(decoded.lastName, 'Rivera');
    },
  },
  {
    name: 'isExpired returns false for a valid token and true for a bad token',
    run() {
      const token = tokenUtils.createToken(
        'Alex',
        'Rivera',
        'user-42',
      ).accessToken;

      assert.equal(tokenUtils.isExpired(token), false);
      assert.equal(tokenUtils.isExpired('bad-token'), true);
    },
  },
  {
    name: 'refresh returns a new access token with the original user data',
    run() {
      const token = tokenUtils.createToken(
        'Alex',
        'Rivera',
        'user-42',
      ).accessToken;
      const refreshed = tokenUtils.refresh(token);
      const decoded = jwt.verify(
        refreshed.accessToken,
        process.env.ACCESS_TOKEN_SECRET,
      );

      assert.equal(decoded.userId, 'user-42');
      assert.equal(decoded.firstName, 'Alex');
      assert.equal(decoded.lastName, 'Rivera');
    },
  },
  {
    name: 'normalizeAvatarDataUrl normalizes case and strips whitespace',
    run() {
      const normalized = __testables.normalizeAvatarDataUrl(
        ' data:IMAGE/PNG;base64,aGV sbG8= ',
      );

      assert.equal(normalized, 'data:image/png;base64,aGVsbG8=');
    },
  },
  {
    name: 'normalizeAvatarDataUrl rejects unsupported mime types',
    run() {
        assert.throws(
          () =>
          __testables.normalizeAvatarDataUrl(
            'data:image/svg+xml;base64,aGVsbG8=',
          ),
        /Profile picture must be PNG, JPEG, GIF, WEBP, AVIF, HEIC, HEIF, BMP, or TIFF\./,
      );
    },
  },
  {
    name: 'normalizeCustomThemePack keeps supported fields and enforces defaults',
    run() {
      const normalized = __testables.normalizeCustomThemePack({
        name: 'My Theme',
        btnColor: '#ABCDEF',
        images: {
          clearDay: 'clear.png',
        },
        gradient: {
          angle: 90,
          colors: ['#123456', '#654321'],
        },
      });

      assert.equal(normalized.name, 'My Theme');
      assert.equal(normalized.btnColor, '#abcdef');
      assert.equal(normalized.images.clearDay, 'clear.png');
      assert.equal(normalized.backgroundMode, 'gradient');
      assert.deepEqual(normalized.gradient.colors, ['#123456', '#654321']);
    },
  },
  {
    name: 'normalizeCustomThemePack preserves mobile custom image and none background modes',
    run() {
      const customImageTheme = __testables.normalizeCustomThemePack({
        name: 'Photo Theme',
        backgroundMode: 'customImage',
        images: {
          universal: 'https://example.com/photo.jpg',
        },
        gradient: {
          angle: 180,
          colors: ['#08111f', '#10203a', '#163761'],
        },
      });

      const noImageTheme = __testables.normalizeCustomThemePack({
        name: 'No Image Theme',
        backgroundMode: 'none',
        gradient: {
          angle: 180,
          colors: ['#08111f', '#10203a', '#163761'],
        },
      });

      assert.equal(customImageTheme.backgroundMode, 'customImage');
      assert.equal(customImageTheme.images.universal, 'https://example.com/photo.jpg');
      assert.equal(noImageTheme.backgroundMode, 'none');
    },
  },
  {
    name: 'theme share helpers parse links, validate slugs, and build share URLs',
    run() {
      assert.equal(
        __testables.extractThemeShareLookupKey('https://calendarplusplus.xyz/?theme=mountain_theme'),
        'mountain_theme',
      );
      assert.equal(
        __testables.normalizeThemeShareSlug('Mountain_Theme'),
        'mountain_theme',
      );
      assert.equal(
        __testables.buildSharedThemeUrls({
          shareSlug: 'mountain_theme',
          shareCode: 'A1B2C3',
        }).shareUrl,
        'https://calendarplusplus.xyz/?theme=mountain_theme',
      );

      assert.deepEqual(
        __testables.buildThemeLookupQuery('abc123'),
        {
          $or: [
            { shareSlug: 'abc123' },
            { shareCode: 'ABC123' },
          ],
        },
      );
    },
  },
  {
    name: 'extractResponseText flattens message output text fragments',
    run() {
      const result = __testables.extractResponseText({
        output: [
          {
            type: 'message',
            content: [
              { type: 'output_text', text: 'Line one' },
              { type: 'ignored', text: 'skip me' },
              { type: 'output_text', text: 'Line two' },
            ],
          },
        ],
      });

      assert.equal(result, 'Line one\nLine two');
    },
  },
  {
    name: 'buildOpenAIRequestVariants keeps unique model and reasoning combinations',
    run() {
      const variants = __testables.buildOpenAIRequestVariants();

      assert.deepEqual(variants, [
        { model: 'gpt-5.4', reasoningEffort: 'medium' },
        { model: 'gpt-5.4', reasoningEffort: '' },
        { model: 'gpt-4.1-mini', reasoningEffort: '' },
      ]);
    },
  },
  {
    name: 'buildOpenAIRequestBody adds instructions, reasoning, and web search tools',
    run() {
      const requestBody = __testables.buildOpenAIRequestBody('Hello', {
        instructions: 'Be concise',
        useWebSearch: true,
        tools: [{ type: 'function', name: 'lookup_calendar' }],
        stream: true,
        model: 'gpt-5.4',
        reasoningEffort: 'high',
      });

      assert.deepEqual(requestBody, {
        model: 'gpt-5.4',
        input: 'Hello',
        stream: true,
        instructions: 'Be concise',
        reasoning: { effort: 'high' },
        tools: [
          { type: 'function', name: 'lookup_calendar' },
          { type: 'web_search' },
        ],
        tool_choice: 'auto',
      });
    },
  },
  {
    name: 'retry helpers classify retryable statuses and network errors',
    run() {
      assert.equal(__testables.isRetryableOpenAIStatus(429), true);
      assert.equal(__testables.isRetryableOpenAIStatus(404), false);
      assert.equal(
        __testables.isRetryableOpenAINetworkError(new Error('socket hang up')),
        true,
      );
      assert.equal(
        __testables.isRetryableOpenAINetworkError(
          new Error('validation failed'),
        ),
        false,
      );
    },
  },
];

let failed = 0;

for (const testCase of tests) {
  try {
    testCase.run();
    console.log(`PASS ${testCase.name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL ${testCase.name}`);
    console.error(error);
  }
}

if (failed > 0) {
  console.error(`\n${failed} backend test(s) failed.`);
  process.exit(1);
}

console.log(`\n${tests.length} backend tests passed.`);
