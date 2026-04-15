import ClearSky from './weather_backgrounds/ClearSky.jpg';
import Cloudy from './weather_backgrounds/Cloudy.jpg';
import NightClear from './weather_backgrounds/NightClear.jpg';
import NightCloudy from './weather_backgrounds/NightCloudy.jpg';
import NightPartlyCloudy from './weather_backgrounds/NightPartlyCloudy.jpg';
import PartlyCloudy from './weather_backgrounds/PartlyCloudy.jpg';
import SunsetSunriseClearSky from './weather_backgrounds/SunsetSunriseClearSky.png';
import SunsetSunriseCloudy from './weather_backgrounds/SunsetSunriseCloudy.jpg';
import SunsetSunrisePartlyCloudy from './weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

export const WEATHER_SLOTS = [
    { key: 'clearDay', label: 'Clear Day' },
    { key: 'clearSunrise', label: 'Sunrise / Sunset (Clear)' },
    { key: 'clearNight', label: 'Clear Night' },
    { key: 'cloudyDay', label: 'Cloudy Day' },
    { key: 'cloudySunrise', label: 'Sunrise / Sunset (Cloudy)' },
    { key: 'cloudyNight', label: 'Cloudy Night' },
    { key: 'partlyCloudyDay', label: 'Partly Cloudy Day' },
    { key: 'partlyCloudySunrise', label: 'Partly Cloudy Sunrise / Sunset' },
    { key: 'partlyCloudyNight', label: 'Partly Cloudy Night' },
];

const WEATHER_IMAGES = {
    clearDay: ClearSky,
    clearSunrise: SunsetSunriseClearSky,
    clearNight: NightClear,
    cloudyDay: Cloudy,
    cloudySunrise: SunsetSunriseCloudy,
    cloudyNight: NightCloudy,
    partlyCloudyDay: PartlyCloudy,
    partlyCloudySunrise: SunsetSunrisePartlyCloudy,
    partlyCloudyNight: NightPartlyCloudy,
};

function resolveTimeSlot(dateValue = new Date()) {
    const hour = new Date(dateValue).getHours();
    if ((hour >= 6 && hour < 9) || (hour >= 18 && hour < 21)) {
        return 'sunrise';
    }
    if (hour >= 9 && hour < 18) {
        return 'day';
    }
    return 'night';
}

function resolveWeatherFamily(currentWeather) {
    const normalized = String(currentWeather || '').trim().toLowerCase();
    if (!normalized || normalized === 'unknown') {
        return null;
    }

    if (normalized.includes('partly cloudy')) {
        return 'partlyCloudy';
    }

    if (normalized.includes('clear')) {
        return 'clear';
    }

    if (
        normalized.includes('cloud')
        || normalized.includes('overcast')
        || normalized.includes('fog')
        || normalized.includes('drizzle')
        || normalized.includes('rain')
        || normalized.includes('snow')
        || normalized.includes('storm')
        || normalized.includes('hail')
    ) {
        return 'cloudy';
    }

    return null;
}

export function getWeatherSceneKey(currentWeather, dateValue = new Date()) {
    const family = resolveWeatherFamily(currentWeather);
    if (!family) {
        return null;
    }

    const timeSlot = resolveTimeSlot(dateValue);
    if (family === 'clear') {
        if (timeSlot === 'day') return 'clearDay';
        if (timeSlot === 'sunrise') return 'clearSunrise';
        return 'clearNight';
    }

    if (family === 'partlyCloudy') {
        if (timeSlot === 'day') return 'partlyCloudyDay';
        if (timeSlot === 'sunrise') return 'partlyCloudySunrise';
        return 'partlyCloudyNight';
    }

    if (timeSlot === 'day') return 'cloudyDay';
    if (timeSlot === 'sunrise') return 'cloudySunrise';
    return 'cloudyNight';
}

export function getWeatherBackgroundImage(currentWeather, dateValue = new Date()) {
    const sceneKey = getWeatherSceneKey(currentWeather, dateValue);
    return sceneKey ? WEATHER_IMAGES[sceneKey] || null : null;
}
