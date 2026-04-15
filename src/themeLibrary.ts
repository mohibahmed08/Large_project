import { normalizeGradient, normalizeHexColor } from './themeUtils';
import clearDayPhoto from './weather_backgrounds/ClearSky.jpg';
import cloudyDayPhoto from './weather_backgrounds/Cloudy.jpg';
import clearNightPhoto from './weather_backgrounds/NightClear.jpg';
import cloudyNightPhoto from './weather_backgrounds/NightCloudy.jpg';
import partlyCloudyNightPhoto from './weather_backgrounds/NightPartlyCloudy.jpg';
import partlyCloudyDayPhoto from './weather_backgrounds/PartlyCloudy.jpg';
import sunriseClearPhoto from './weather_backgrounds/SunsetSunriseClearSky.png';
import sunriseCloudyPhoto from './weather_backgrounds/SunsetSunriseCloudy.jpg';
import sunrisePartlyCloudyPhoto from './weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

const PUBLIC_ASSET_BASE = process.env.PUBLIC_URL || '';

function buildThemeSceneImages(themeId) {
    return {
        clearDay: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/clearDay.png`,
        clearSunrise: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/clearSunrise.png`,
        clearNight: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/clearNight.png`,
        cloudyDay: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/cloudyDay.png`,
        cloudySunrise: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/cloudySunrise.png`,
        cloudyNight: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/cloudyNight.png`,
        partlyCloudyDay: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/partlyCloudyDay.png`,
        partlyCloudySunrise: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/partlyCloudySunrise.png`,
        partlyCloudyNight: `${PUBLIC_ASSET_BASE}/theme_packages/${themeId}/partlyCloudyNight.png`,
    };
}

function buildWeatherPhotoSceneImages() {
    return {
        clearDay: clearDayPhoto,
        clearSunrise: sunriseClearPhoto,
        clearNight: clearNightPhoto,
        cloudyDay: cloudyDayPhoto,
        cloudySunrise: sunriseCloudyPhoto,
        cloudyNight: cloudyNightPhoto,
        partlyCloudyDay: partlyCloudyDayPhoto,
        partlyCloudySunrise: sunrisePartlyCloudyPhoto,
        partlyCloudyNight: partlyCloudyNightPhoto,
    };
}

function buildFeaturedAsset(packId, assetName, extension) {
    return `${PUBLIC_ASSET_BASE}/theme_featured/${packId}/${assetName}.${extension}`;
}

function buildFeaturedSceneImages(packId, extension) {
    return {
        clearDay: buildFeaturedAsset(packId, 'ClearDay', extension),
        clearSunrise: buildFeaturedAsset(packId, 'ClearSunset', extension),
        clearNight: buildFeaturedAsset(packId, 'ClearNight', extension),
        cloudyDay: buildFeaturedAsset(packId, 'CloudyDay', extension),
        cloudySunrise: buildFeaturedAsset(packId, 'CloudySunset', extension),
        cloudyNight: buildFeaturedAsset(packId, 'CloudyNight', extension),
        partlyCloudyDay: buildFeaturedAsset(packId, 'PartlyCloudyDay', extension),
        partlyCloudySunrise: buildFeaturedAsset(packId, 'PartlyCloudySunset', extension),
        partlyCloudyNight: buildFeaturedAsset(packId, 'PartlyCloudyNight', extension),
    };
}

function buildFeaturedGallery(packId, extension) {
    return [
        buildFeaturedAsset(packId, 'ClearDay', extension),
        buildFeaturedAsset(packId, 'PartlyCloudyDay', extension),
        buildFeaturedAsset(packId, 'CloudyDay', extension),
        buildFeaturedAsset(packId, 'ClearSunset', extension),
        buildFeaturedAsset(packId, 'PartlyCloudySunset', extension),
        buildFeaturedAsset(packId, 'CloudySunset', extension),
        buildFeaturedAsset(packId, 'ClearNight', extension),
        buildFeaturedAsset(packId, 'PartlyCloudyNight', extension),
        buildFeaturedAsset(packId, 'CloudyNight', extension),
    ];
}

function buildFeaturedTheme({
    id,
    packId,
    name,
    description,
    btnColor,
    coverExtension,
    sceneExtension,
}) {
    const coverImage = buildFeaturedAsset(packId, 'cover', coverExtension);
    return {
        id,
        packId,
        name,
        description,
        preview: `url(${coverImage})`,
        previewImage: coverImage,
        btnColor,
        images: buildFeaturedSceneImages(packId, sceneExtension),
        galleryImages: [coverImage, ...buildFeaturedGallery(packId, sceneExtension)],
        imageFit: 'cover',
        backgroundMode: 'perScene',
        source: 'featured',
    };
}

export const PRESET_THEMES = [
    {
        id: 'default',
        name: 'Weather Photo Pack',
        description: 'The original weather-reactive photo pack',
        preview: `url(${clearDayPhoto})`,
        previewImage: clearDayPhoto,
        btnColor: '#60a5fa',
        images: buildWeatherPhotoSceneImages(),
        galleryImages: [
            clearDayPhoto,
            cloudyDayPhoto,
            partlyCloudyDayPhoto,
            sunriseClearPhoto,
            sunriseCloudyPhoto,
            sunrisePartlyCloudyPhoto,
            clearNightPhoto,
            cloudyNightPhoto,
            partlyCloudyNightPhoto,
        ],
        imageFit: 'cover',
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'aurora',
        name: 'Aurora',
        description: 'Electric twilight over high ridges',
        preview: 'linear-gradient(135deg,#0d0221 0%,#5a0d82 50%,#1a6b8a 100%)',
        btnColor: '#a855f7',
        images: buildThemeSceneImages('aurora'),
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'forest',
        name: 'Forest',
        description: 'Cedar silhouettes, mist, and rain',
        preview: 'linear-gradient(135deg,#0f2a0f 0%,#2d6a2d 50%,#1a3a1a 100%)',
        btnColor: '#22c55e',
        images: buildThemeSceneImages('forest'),
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'desert',
        name: 'Desert Dusk',
        description: 'Wind-cut dunes in changing light',
        preview: 'linear-gradient(135deg,#7c2d12 0%,#ea580c 50%,#fbbf24 100%)',
        btnColor: '#f97316',
        images: buildThemeSceneImages('desert'),
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'ocean',
        name: 'Ocean',
        description: 'Open water horizons and sea haze',
        preview: 'linear-gradient(135deg,#0c1a40 0%,#0e4d6e 50%,#0ea5e9 100%)',
        btnColor: '#06b6d4',
        images: buildThemeSceneImages('ocean'),
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'midnight',
        name: 'Midnight',
        description: 'Steel blue night air over dark peaks',
        preview: 'linear-gradient(135deg,#0a0a0a 0%,#1c1c2e 50%,#2d2d44 100%)',
        btnColor: '#94a3b8',
        images: buildThemeSceneImages('midnight'),
        backgroundMode: 'perScene',
        source: 'preset',
    },
    {
        id: 'custom',
        name: 'Custom Weather Pack',
        description: 'Your own colors & images',
        preview: 'linear-gradient(135deg,#374151 0%,#6b7280 100%)',
        btnColor: '#60a5fa',
        images: {},
        backgroundMode: 'gradient',
        source: 'draft',
    },
];

export const FEATURED_THEMES = [
    buildFeaturedTheme({
        id: 'mountain-featured',
        packId: 'mountain',
        name: 'Mountain Photo Pack',
        description: 'The real featured mountain set from theme_featured',
        btnColor: '#67e8f9',
        coverExtension: 'png',
        sceneExtension: 'jpg',
    }),
    buildFeaturedTheme({
        id: 'forest-featured',
        packId: 'forest',
        name: 'Forest Photo Pack',
        description: 'Weather-based forest photography with mist and canopy glow',
        btnColor: '#4ade80',
        coverExtension: 'jpg',
        sceneExtension: 'jpg',
    }),
    buildFeaturedTheme({
        id: 'desert-featured',
        packId: 'desert',
        name: 'Desert Photo Pack',
        description: 'Weather-based desert skies, sandstone, and dusk light',
        btnColor: '#f59e0b',
        coverExtension: 'webp',
        sceneExtension: 'png',
    }),
    buildFeaturedTheme({
        id: 'beach-featured',
        packId: 'beach',
        name: 'Beach Photo Pack',
        description: 'Weather-based shoreline scenes with surf, haze, and horizon glow',
        btnColor: '#38bdf8',
        coverExtension: 'jpg',
        sceneExtension: 'jpg',
    }),
];

export const DEFAULT_THEME = PRESET_THEMES[0];

export const EMPTY_CUSTOM_THEME = {
    id: 'custom',
    name: 'New Pack',
    description: 'Build a gradient or image-based theme pack and save it.',
    preview: 'linear-gradient(135deg,#2563eb 0%,#2563eb 100%)',
    btnColor: '#60a5fa',
    btnTextColor: '',
    btnGradient: null,
    images: {},
    galleryImages: [],
    imageFit: 'cover',
    backgroundMode: 'gradient',
    gradient: {
        type: 'linear',
        angle: 135,
        colors: ['#2563eb'],
        stops: [
            { color: '#2563eb', position: 0 },
        ],
    },
    source: 'draft',
};

export const ACCENT_SWATCHES = [
    '#60a5fa',
    '#38bdf8',
    '#22c55e',
    '#f59e0b',
    '#f97316',
    '#f43f5e',
    '#a855f7',
    '#94a3b8',
    '#f8fafc',
];

export function cloneThemePack(theme) {
    return JSON.parse(JSON.stringify(theme || EMPTY_CUSTOM_THEME));
}

export function inferThemeBackgroundMode(theme) {
    if (theme?.backgroundMode) {
        return theme.backgroundMode;
    }

    if (theme?.gradient?.colors?.length >= 2) {
        return 'gradient';
    }

    if (theme?.images?.universal || theme?.galleryImages?.length) {
        return 'universal';
    }

    return 'perScene';
}

export function sanitizeThemePack(input, fallback = EMPTY_CUSTOM_THEME) {
    const base = cloneThemePack(fallback);
    const draft = {
        ...base,
        ...(input || {}),
    };
    const images = {
        ...(base.images || {}),
        ...(draft.images || {}),
    };
    const galleryImages = Array.isArray(draft.galleryImages)
        ? draft.galleryImages.filter(Boolean)
        : [];
    const gradient = normalizeGradient(draft.gradient || base.gradient);
    const backgroundMode = inferThemeBackgroundMode({
        ...draft,
        images,
        galleryImages,
        gradient,
    });

    return {
        ...draft,
        id: String(draft.id || base.id || `user-theme-${Date.now()}`),
        name: String(draft.name || base.name || 'Untitled Pack').trim() || 'Untitled Pack',
        description: String(draft.description || base.description || '').trim(),
        btnColor: normalizeHexColor(draft.btnColor || base.btnColor || '#60a5fa'),
        btnTextColor: String(draft.btnTextColor || base.btnTextColor || '').trim(),
        btnGradient: draft.btnGradient && Array.isArray(draft.btnGradient.colors)
            ? {
                angle: Number.isFinite(Number(draft.btnGradient.angle)) ? Number(draft.btnGradient.angle) : 135,
                colors: draft.btnGradient.colors.slice(0, 3),
            }
            : (base.btnGradient || null),
        images,
        galleryImages,
        imageFit: draft.imageFit === 'contain' || draft.imageFit === 'center' ? draft.imageFit : 'cover',
        backgroundMode,
        gradient,
        source: draft.source || base.source || 'user',
        preview: draft.preview || base.preview,
        previewImage: draft.previewImage || base.previewImage || '',
        packId: draft.packId || base.packId || '',
    };
}
