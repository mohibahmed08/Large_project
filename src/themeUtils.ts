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
    angle: 135,
    colors: ['#0f172a', '#2563eb', '#7dd3fc'],
}) {
    const rawColors = Array.isArray(gradient?.colors) ? gradient.colors : fallback.colors;
    const colors = rawColors
        .map((color) => normalizeHexColor(color, ''))
        .filter(Boolean);

    return {
        angle: Number.isFinite(Number(gradient?.angle)) ? Number(gradient.angle) : fallback.angle,
        colors: colors.length >= 2 ? colors.slice(0, 3) : [...fallback.colors],
    };
}

export function buildGradientCss(gradient, fallback = undefined) {
    const normalized = normalizeGradient(gradient, fallback);
    return `linear-gradient(${normalized.angle}deg, ${normalized.colors.join(', ')})`;
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
