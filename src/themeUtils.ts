export function normalizeHexColor(color, fallback = '#60a5fa') {
    const normalized = String(color || '').trim();
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
        return normalized.toLowerCase();
    }

    return fallback;
}

export function hexToRgbString(color, fallback = '#60a5fa') {
    const normalized = normalizeHexColor(color, fallback).slice(1);
    const red = Number.parseInt(normalized.slice(0, 2), 16);
    const green = Number.parseInt(normalized.slice(2, 4), 16);
    const blue = Number.parseInt(normalized.slice(4, 6), 16);
    return `${red}, ${green}, ${blue}`;
}

function relativeChannel(channel) {
    const normalized = channel / 255;
    return normalized <= 0.03928
        ? normalized / 12.92
        : ((normalized + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance(color) {
    const normalized = normalizeHexColor(color).slice(1);
    const red = Number.parseInt(normalized.slice(0, 2), 16);
    const green = Number.parseInt(normalized.slice(2, 4), 16);
    const blue = Number.parseInt(normalized.slice(4, 6), 16);

    return (0.2126 * relativeChannel(red))
        + (0.7152 * relativeChannel(green))
        + (0.0722 * relativeChannel(blue));
}

function contrastRatio(first, second) {
    const [lighter, darker] = [relativeLuminance(first), relativeLuminance(second)].sort((a, b) => b - a);
    return (lighter + 0.05) / (darker + 0.05);
}

export function getContrastTextColor(color, light = '#f8fafc', dark = '#0f172a') {
    const normalized = normalizeHexColor(color);
    return contrastRatio(normalized, light) >= contrastRatio(normalized, dark) ? light : dark;
}

export function normalizeGradient(gradient, fallback = {
    type: 'linear',
    angle: 135,
    colors: ['#2563eb'],
}) {
    const rawColors = Array.isArray(gradient?.colors) ? gradient.colors : fallback.colors;
    const colors = rawColors
        .map((color) => normalizeHexColor(color, ''))
        .filter(Boolean);
    const rawStops = Array.isArray(gradient?.stops) ? gradient.stops : [];
    const fallbackStops = colors.length >= 1
        ? colors.slice(0, 5).map((color, index, palette) => ({
            color,
            position: palette.length === 1 ? 0 : Math.round((index / (palette.length - 1)) * 100),
        }))
        : [
            { color: fallback.colors[0] || '#2563eb', position: 0 },
        ];
    const stops = rawStops
        .map((stop, index) => ({
            color: normalizeHexColor(stop?.color || colors[index] || fallback.colors[index] || fallback.colors[0]),
            position: Math.max(0, Math.min(100, Math.round(Number(stop?.position ?? (index * 50))))),
        }))
        .filter((stop) => stop.color)
        .sort((first, second) => first.position - second.position);
    const normalizedStops = stops.length >= 1 ? stops.slice(0, 8) : fallbackStops;

    return {
        type: String(gradient?.type || fallback.type || 'linear').trim().toLowerCase() === 'radial' ? 'radial' : 'linear',
        angle: Number.isFinite(Number(gradient?.angle)) ? Number(gradient.angle) : fallback.angle,
        colors: normalizedStops.map((stop) => stop.color),
        stops: normalizedStops,
    };
}

export function buildGradientCss(gradient, fallback = undefined) {
    const normalized = normalizeGradient(gradient, fallback);
    const renderStops = normalized.stops.length === 1
        ? [
            normalized.stops[0],
            { ...normalized.stops[0], position: 100 },
        ]
        : normalized.stops;
    const stopList = renderStops
        .map((stop) => `${stop.color} ${stop.position}%`)
        .join(', ');

    if (normalized.type === 'radial') {
        return `radial-gradient(circle at center, ${stopList})`;
    }

    return `linear-gradient(${normalized.angle}deg, ${stopList})`;
}

export function toCssBackgroundImage(value) {
    if (!value) {
        return null;
    }

    if (/gradient\(/i.test(value) || /^url\(/i.test(value)) {
        return value;
    }

    return `url(${value})`;
}

function resolvePackGalleryImage(theme) {
    if (theme?.images?.universal) {
        return theme.images.universal;
    }

    if (theme?.selectedGalleryImage) {
        return theme.selectedGalleryImage;
    }

    if (Array.isArray(theme?.galleryImages) && theme.galleryImages.length > 0) {
        return theme.galleryImages[0];
    }

    return null;
}

export function resolveEffectiveBackground(theme, weatherBackground) {
    const fallbackImage = weatherBackground?.image || null;
    if (!theme) {
        return fallbackImage;
    }

    const images = theme.images || {};
    if (theme.backgroundMode === 'gradient' && theme.gradient?.colors?.length >= 2) {
        return buildGradientCss(theme.gradient);
    }

    const galleryImage = resolvePackGalleryImage(theme);
    if (theme.backgroundMode !== 'perScene' && galleryImage) {
        return galleryImage;
    }

    if (images.universal) {
        return images.universal;
    }

    const sceneKey = weatherBackground?.sceneKey || '';
    if (sceneKey && images[sceneKey]) {
        return images[sceneKey];
    }

    if (galleryImage) {
        return galleryImage;
    }

    if (theme.preview) {
        return theme.preview;
    }

    return fallbackImage;
}
