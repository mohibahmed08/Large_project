import {
  DEFAULT_WEATHER_LOCATION,
  requestWeatherLocation,
} from '../weatherLocation.js';
import { vi } from 'vitest';

const originalGeolocation = window.navigator.geolocation;
const originalPermissions = window.navigator.permissions;

function setNavigatorProperty(name: string, value: unknown) {
  Object.defineProperty(window.navigator, name, {
    configurable: true,
    writable: true,
    value,
  });
}

describe('requestWeatherLocation', () => {
  afterEach(() => {
    setNavigatorProperty('geolocation', originalGeolocation);
    setNavigatorProperty('permissions', originalPermissions);
  });

  test('returns the fallback location when geolocation is unavailable', async () => {
    setNavigatorProperty('geolocation', undefined);
    setNavigatorProperty('permissions', undefined);

    await expect(requestWeatherLocation()).resolves.toEqual({
      ...DEFAULT_WEATHER_LOCATION,
      isFallback: true,
    });
  });

  test('returns the fallback location when permission is denied', async () => {
    const getCurrentPosition = vi.fn();

    setNavigatorProperty('permissions', {
      query: vi.fn().mockResolvedValue({ state: 'denied' }),
    });
    setNavigatorProperty('geolocation', { getCurrentPosition });

    await expect(requestWeatherLocation()).resolves.toEqual({
      ...DEFAULT_WEATHER_LOCATION,
      isFallback: true,
    });
    expect(getCurrentPosition).not.toHaveBeenCalled();
  });

  test('returns the current coordinates when geolocation succeeds', async () => {
    setNavigatorProperty('permissions', {
      query: vi.fn().mockResolvedValue({ state: 'granted' }),
    });
    setNavigatorProperty('geolocation', {
      getCurrentPosition: vi.fn((onSuccess) =>
        onSuccess({
          coords: {
            latitude: 28.60,
            longitude: -81.20,
          },
        }),
      ),
    });

    await expect(requestWeatherLocation()).resolves.toEqual({
      latitude: 28.60,
      longitude: -81.20,
      label: 'Current location',
      isFallback: false,
    });
  });
});
