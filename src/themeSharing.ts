export const SHARED_THEME_QUERY_PARAM = 'theme';
export const PENDING_SHARED_THEME_STORAGE_KEY = 'calpp_pending_shared_theme';

function toThemeIdentity(theme) {
    if (theme?.sharedThemeId) {
        return `shared:${theme.sharedThemeId}`;
    }

    return `local:${String(theme?.id || '')}`;
}

export function mergeThemePacks(...collections) {
    const merged = new Map();

    collections
        .flat()
        .filter(Boolean)
        .forEach((theme) => {
            merged.set(toThemeIdentity(theme), theme);
        });

    return Array.from(merged.values());
}

export function extractSharedThemeValue(value) {
    const trimmed = String(value || '').trim();
    if (!trimmed) {
        return '';
    }

    try {
        const parsed = new URL(trimmed);
        return parsed.searchParams.get(SHARED_THEME_QUERY_PARAM)?.trim() || '';
    } catch {
        return trimmed;
    }
}

export function readSharedThemeValueFromLocation(locationLike = window.location) {
    const params = new URLSearchParams(locationLike.search || '');
    return extractSharedThemeValue(params.get(SHARED_THEME_QUERY_PARAM) || '');
}

export function clearSharedThemeValueFromLocation() {
    const url = new URL(window.location.href);
    if (!url.searchParams.has(SHARED_THEME_QUERY_PARAM)) {
        return;
    }

    url.searchParams.delete(SHARED_THEME_QUERY_PARAM);
    const nextSearch = url.searchParams.toString();
    const nextUrl = `${url.pathname}${nextSearch ? `?${nextSearch}` : ''}${url.hash || ''}`;
    window.history.replaceState({}, '', nextUrl);
}

export function buildThemePackId(name) {
    const slug = String(name || 'theme-pack')
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/(^-|-$)/g, '')
        .slice(0, 36) || 'theme-pack';

    return `user-${slug}-${Date.now()}`;
}

export function buildThemeShareTargets(theme) {
    const shareUrl = String(theme?.shareUrl || '').trim();
    const shareCode = String(theme?.shareCode || '').trim();
    const themeName = String(theme?.name || 'Theme Pack').trim() || 'Theme Pack';
    const summary = `${themeName}${shareCode ? ` (${shareCode})` : ''}`;
    const shareText = `Check out this Calendar++ theme: ${summary}${shareUrl ? ` ${shareUrl}` : ''}`.trim();
    const encodedUrl = encodeURIComponent(shareUrl);
    const encodedText = encodeURIComponent(shareText);
    const encodedSubject = encodeURIComponent(`Calendar++ theme: ${themeName}`);

    return {
        shareText,
        email: `mailto:?subject=${encodedSubject}&body=${encodedText}`,
        sms: `sms:?&body=${encodedText}`,
        facebook: `https://www.facebook.com/sharer/sharer.php?u=${encodedUrl}`,
        whatsapp: `https://wa.me/?text=${encodedText}`,
    };
}
