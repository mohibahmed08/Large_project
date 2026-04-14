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

export function resolveEffectiveBackground(theme, weatherBackground) {
    const fallbackImage = weatherBackground?.image || null;
    if (!theme || theme.id === 'default') {
        return fallbackImage;
    }

    const images = theme.images || {};
    if (images.universal) {
        return images.universal;
    }

    const sceneKey = weatherBackground?.sceneKey || '';
    if (sceneKey && images[sceneKey]) {
        return images[sceneKey];
    }

    return fallbackImage;
}
