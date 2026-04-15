import {
  dateWithSuggestedTime,
  decodeToken,
  displayAssistantStatus,
  normalizeSuggestions,
  validateAvatarFile,
} from '../App';
import {
  getContrastTextColor,
  resolveEffectiveBackground,
} from '../themeUtils';
import { getWeatherSceneKey } from '../weatherScenes';

function createJwtPayload(payload: Record<string, unknown>) {
  const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');

  return `header.${encodedPayload}.signature`;
}

describe('frontend app helpers', () => {
  test('decodeToken returns the parsed JWT payload', () => {
    const token = createJwtPayload({
      userId: 'user-123',
      firstName: 'Casey',
      lastName: 'Ng',
    });

    expect(decodeToken(token)).toEqual({
      userId: 'user-123',
      firstName: 'Casey',
      lastName: 'Ng',
    });
  });

  test('decodeToken returns null for malformed values', () => {
    expect(decodeToken('not-a-jwt')).toBeNull();
  });

  test('dateWithSuggestedTime falls back to noon when the time is invalid', () => {
    const date = new Date(2026, 3, 14, 0, 0, 0, 0);
    const result = dateWithSuggestedTime(date, 'bad-value');

    expect(result.getHours()).toBe(12);
    expect(result.getMinutes()).toBe(0);
  });

  test('normalizeSuggestions recovers JSON arrays wrapped in a parse error', () => {
    const normalized = normalizeSuggestions([
      {
        title: 'Parse error',
        description:
          '```json\n[{"title":"Focus block","suggestedTime":"09:30","description":"Deep work"}]\n```',
      },
    ]);

    expect(normalized).toEqual([
      {
        title: 'Focus block',
        suggestedTime: '09:30',
        description: 'Deep work',
      },
    ]);
  });

  test('displayAssistantStatus appends an ellipsis only when needed', () => {
    expect(displayAssistantStatus('Working')).toBe('Working...');
    expect(displayAssistantStatus('Done.')).toBe('Done.');
    expect(displayAssistantStatus('')).toBe('');
  });

  test('validateAvatarFile accepts supported image uploads and rejects invalid ones', () => {
    const validFile = new File(['avatar'], 'avatar.png', { type: 'image/png' });
    expect(() => validateAvatarFile(validFile)).not.toThrow();

    const invalidType = new File(['avatar'], 'avatar.txt', { type: 'text/plain' });
    expect(() => validateAvatarFile(invalidType)).toThrow(
      'Profile picture must be PNG, JPEG, GIF, WEBP, AVIF, HEIC, HEIF, BMP, or TIFF.',
    );

    const largeFile = { type: 'image/png', size: (2 * 1024 * 1024) + 1 };
    expect(() => validateAvatarFile(largeFile)).toThrow(
      'Profile picture must be 2 MB or smaller.',
    );
  });

  test('resolveEffectiveBackground prefers a matching custom weather scene and falls back to weather', () => {
    const theme = {
      id: 'custom',
      images: {
        clearDay: 'custom-clear-day.png',
      },
    };

    expect(resolveEffectiveBackground(theme, {
      image: 'default-clear-day.jpg',
      sceneKey: 'clearDay',
    })).toBe('custom-clear-day.png');

    expect(resolveEffectiveBackground(theme, {
      image: 'default-cloudy-day.jpg',
      sceneKey: 'cloudyDay',
    })).toBe('default-cloudy-day.jpg');
  });

  test('getWeatherSceneKey buckets unsupported weather labels into the cloudy suite', () => {
    const midday = new Date(2026, 3, 14, 12, 0, 0, 0);
    const evening = new Date(2026, 3, 14, 19, 0, 0, 0);

    expect(getWeatherSceneKey('Rainy', midday)).toBe('cloudyDay');
    expect(getWeatherSceneKey('Thunderstorm with hail', evening)).toBe('cloudySunrise');
    expect(getWeatherSceneKey('Partly cloudy', evening)).toBe('partlyCloudySunrise');
  });

  test('getContrastTextColor switches button text based on accent contrast', () => {
    expect(getContrastTextColor('#facc15')).toBe('#0f172a');
    expect(getContrastTextColor('#1d4ed8')).toBe('#f8fafc');
  });
});
