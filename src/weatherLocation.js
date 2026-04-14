export const DEFAULT_WEATHER_LOCATION = Object.freeze({
    latitude: 28.6024,
    longitude: -81.2001,
    label: 'UCF, Orlando, Florida',
});

export async function requestWeatherLocation() {
    const fallbackLocation = {
        ...DEFAULT_WEATHER_LOCATION,
        isFallback: true,
    };

    if (!window.navigator.geolocation) {
        return fallbackLocation;
    }

    if (window.navigator.permissions?.query) {
        try {
            const permission = await window.navigator.permissions.query({ name: 'geolocation' });
            if (permission.state === 'denied') {
                return fallbackLocation;
            }
        } catch {
            // Continue and let the geolocation request decide.
        }
    }

    return new Promise((resolve) => {
        window.navigator.geolocation.getCurrentPosition(
            ({ coords }) => resolve({
                latitude: coords.latitude,
                longitude: coords.longitude,
                label: 'Current location',
                isFallback: false,
            }),
            () => resolve(fallbackLocation),
            {
                enableHighAccuracy: false,
                timeout: 10000,
                maximumAge: 300000,
            },
        );
    });
}
