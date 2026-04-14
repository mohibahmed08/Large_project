import { normalizeGradient, normalizeHexColor } from './themeUtils';

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

function buildFeaturedGallery(packId, extension, count = 9) {
    return Array.from({ length: count }, (_, index) => (
        `${PUBLIC_ASSET_BASE}/theme_featured/${packId}/${packId}-${String(index + 1).padStart(2, '0')}.${extension}`
    ));
}

function buildFeaturedCover(packId, extension) {
    return `${PUBLIC_ASSET_BASE}/theme_featured/${packId}/cover.${extension}`;
}

export const FEATURED_THEMES = [
    {
        id: 'default',
        name: 'Mountain',
        description: 'Alpine skies across shifting weather',
        preview: 'linear-gradient(135deg,#1e3a5f 0%,#3b82f6 100%)',
        btnColor: '#60a5fa',
        images: buildThemeSceneImages('default'),
        backgroundMode: 'perScene',
    },
    {
        id: 'aurora',
        name: 'Aurora',
        description: 'Electric twilight over high ridges',
        preview: 'linear-gradient(135deg,#0d0221 0%,#5a0d82 50%,#1a6b8a 100%)',
        btnColor: '#a855f7',
        images: buildThemeSceneImages('aurora'),
        backgroundMode: 'perScene',
    },
    {
        id: 'forest',
        name: 'Forest',
        description: 'Cedar silhouettes, mist, and rain',
        preview: 'linear-gradient(135deg,#0f2a0f 0%,#2d6a2d 50%,#1a3a1a 100%)',
        btnColor: '#22c55e',
        images: buildThemeSceneImages('forest'),
        backgroundMode: 'perScene',
    },
    {
        id: 'desert',
        name: 'Desert Dusk',
        description: 'Wind-cut dunes in changing light',
        preview: 'linear-gradient(135deg,#7c2d12 0%,#ea580c 50%,#fbbf24 100%)',
        btnColor: '#f97316',
        images: buildThemeSceneImages('desert'),
        backgroundMode: 'perScene',
    },
    {
        id: 'ocean',
        name: 'Ocean',
        description: 'Open water horizons and sea haze',
        preview: 'linear-gradient(135deg,#0c1a40 0%,#0e4d6e 50%,#0ea5e9 100%)',
        btnColor: '#06b6d4',
        images: buildThemeSceneImages('ocean'),
        backgroundMode: 'perScene',
    },
    {
        id: 'midnight',
        name: 'Midnight',
        description: 'Steel blue night air over dark peaks',
        preview: 'linear-gradient(135deg,#0a0a0a 0%,#1c1c2e 50%,#2d2d44 100%)',
        btnColor: '#94a3b8',
        images: buildThemeSceneImages('midnight'),
        backgroundMode: 'perScene',
    },
    {
        id: 'mountain-photo',
        name: 'Mountain Photos',
        description: 'Photo pack of high-country light and ridge lines',
        preview: `url(${buildFeaturedCover('mountain', 'png')})`,
        previewImage: buildFeaturedCover('mountain', 'png'),
        btnColor: '#67e8f9',
        images: {
            universal: `${PUBLIC_ASSET_BASE}/theme_featured/mountain/mountain-01.jpg`,
        },
        galleryImages: buildFeaturedGallery('mountain', 'jpg'),
        imageFit: 'cover',
        backgroundMode: 'universal',
    },
    {
        id: 'forest-photo',
        name: 'Forest Photos',
        description: 'Photo pack of canopy haze, greens, and rainfall',
        preview: `url(${buildFeaturedCover('forest', 'jpg')})`,
        previewImage: buildFeaturedCover('forest', 'jpg'),
        btnColor: '#4ade80',
        images: {
            universal: `${PUBLIC_ASSET_BASE}/theme_featured/forest/forest-01.jpg`,
        },
        galleryImages: buildFeaturedGallery('forest', 'jpg'),
        imageFit: 'cover',
        backgroundMode: 'universal',
    },
    {
        id: 'desert-photo',
        name: 'Desert Photos',
        description: 'Photo pack of sandstone, heat shimmer, and dusk',
        preview: `url(${buildFeaturedCover('desert', 'webp')})`,
        previewImage: buildFeaturedCover('desert', 'webp'),
        btnColor: '#f59e0b',
        images: {
            universal: `${PUBLIC_ASSET_BASE}/theme_featured/desert/desert-01.png`,
        },
        galleryImages: buildFeaturedGallery('desert', 'png'),
        imageFit: 'cover',
        backgroundMode: 'universal',
    },
    {
        id: 'beach-photo',
        name: 'Beach Photos',
        description: 'Photo pack of shoreline blues, surf, and horizon glow',
        preview: `url(${buildFeaturedCover('beach', 'jpg')})`,
        previewImage: buildFeaturedCover('beach', 'jpg'),
        btnColor: '#38bdf8',
        images: {
            universal: `${PUBLIC_ASSET_BASE}/theme_featured/beach/beach-01.jpg`,
        },
        galleryImages: buildFeaturedGallery('beach', 'jpg'),
        imageFit: 'cover',
        backgroundMode: 'universal',
    },
];

export const EMPTY_CUSTOM_THEME = {
    id: 'custom',
    name: 'New Pack',
    description: 'Build a gradient or image-based theme pack and save it.',
    preview: 'linear-gradient(135deg,#0f172a 0%,#2563eb 55%,#7dd3fc 100%)',
    btnColor: '#60a5fa',
    images: {},
    galleryImages: [],
    imageFit: 'cover',
    backgroundMode: 'gradient',
    gradient: {
        angle: 135,
        colors: ['#0f172a', '#2563eb', '#7dd3fc'],
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
        images,
        galleryImages,
        imageFit: draft.imageFit === 'contain' || draft.imageFit === 'center' ? draft.imageFit : 'cover',
        backgroundMode,
        gradient,
        source: draft.source || base.source || 'user',
        preview: draft.preview || base.preview,
        previewImage: draft.previewImage || base.previewImage || '',
    };
}
