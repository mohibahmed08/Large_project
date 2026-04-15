// @ts-nocheck
import './App.css';
import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';

import Calendar from './Calendar';
import Login, { ResetPasswordPage } from './login';
import {
    buildGradientCss,
    getContrastTextColor,
    hexToRgbString,
    normalizeHexColor,
    resolveEffectiveBackground,
    toCssBackgroundImage,
} from './themeUtils';
import {
    ACCENT_SWATCHES,
    cloneThemePack,
    DEFAULT_THEME,
    EMPTY_CUSTOM_THEME,
    FEATURED_THEMES,
    inferThemeBackgroundMode,
    PRESET_THEMES,
    sanitizeThemePack,
} from './themeLibrary';
import {
    buildThemePackId,
    buildThemeShareTargets,
    clearSharedThemeValueFromLocation,
    extractSharedThemeValue,
    mergeThemePacks,
    PENDING_SHARED_THEME_STORAGE_KEY,
    readSharedThemeValueFromLocation,
} from './themeSharing';
import { WEATHER_SLOTS } from './weatherScenes';
import { requestWeatherLocation } from './weatherLocation.js';

import leftOpenIcon from './icons/panel-left-open.svg';
import leftCloseIcon from './icons/panel-left-close.svg';
import rightOpenIcon from './icons/panel-right-open.svg';
import rightCloseIcon from './icons/panel-right-close.svg';
import shareIcon from './icons/share-theme.svg';

const RAW_API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';
const API_ROOT = RAW_API_BASE.endsWith('/api') ? RAW_API_BASE : `${RAW_API_BASE}/api`;

function ShareArrowIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M14 5h5v5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M10 14 19 5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M19 13v4a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
    );
}

function CopyIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <rect x="9" y="9" width="10" height="10" rx="2" fill="none" stroke="currentColor" strokeWidth="1.8" />
            <path d="M7 15H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v1" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
    );
}

function CodeHashIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M9 4 7 20M17 4l-2 16M4 9h16M3 15h16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
    );
}

function MessagesIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M6 7h12M6 11h9M7 18l-3 2V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H7Z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
    );
}

function MailIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" strokeWidth="1.8" />
            <path d="m5 7 7 6 7-6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
    );
}

function FacebookIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M14 8h3V4h-3c-2.2 0-4 1.8-4 4v3H7v4h3v5h4v-5h3l1-4h-4V8Z" fill="currentColor" />
        </svg>
    );
}

function WhatsAppIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 4a8 8 0 0 0-6.9 12l-1.1 4 4.1-1A8 8 0 1 0 12 4Z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M9.7 9.5c.2-.4.4-.4.6-.4h.5c.1 0 .3.1.3.3l.8 1.9c.1.2 0 .4-.1.5l-.4.5c.7 1.3 1.8 2.3 3.1 3l.5-.4c.2-.1.4-.1.5-.1l1.9.8c.2.1.3.2.3.3v.5c0 .3-.1.5-.4.6-.4.2-1 .3-1.6.2-2-.4-5.1-3.3-5.6-5.4-.1-.6 0-1.2.2-1.7Z" fill="currentColor" />
        </svg>
    );
}

// ── Theme system ──────────────────────────────────────────────────────────────
const LEGACY_THEME_STORAGE_KEY = 'calpp_theme';
const THEME_STORAGE_KEY = 'calpp_theme';
const SAVED_THEME_PACKS_STORAGE_KEY = 'calpp_theme_packs';

const BUILT_IN_THEME_IDS = new Set([
    ...PRESET_THEMES.filter((theme) => theme.id !== 'custom').map((theme) => theme.id),
    ...FEATURED_THEMES.map((theme) => theme.id),
]);

function loadTheme() {
    try {
        const raw = localStorage.getItem(THEME_STORAGE_KEY) || localStorage.getItem(LEGACY_THEME_STORAGE_KEY);
        if (!raw) return null;
        return sanitizeThemePack(JSON.parse(raw), DEFAULT_THEME);
    } catch {
        return null;
    }
}

function loadSavedThemePacks() {
    try {
        const raw = localStorage.getItem(SAVED_THEME_PACKS_STORAGE_KEY);
        if (!raw) return [];
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed.map((pack) => sanitizeThemePack(pack, EMPTY_CUSTOM_THEME)) : [];
    } catch {
        return [];
    }
}

function persistTheme(theme) {
    try {
        localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
    } catch {
        // ignore quota errors
    }
}

function persistSavedThemePacks(packs) {
    try {
        localStorage.setItem(SAVED_THEME_PACKS_STORAGE_KEY, JSON.stringify(packs));
    } catch {
        // ignore quota errors
    }
}

function applyBtnColorOverride(color) {
    const resolvedColor = normalizeHexColor(color);
    document.documentElement.style.setProperty('--btn-color', resolvedColor);
    document.documentElement.style.setProperty('--btn-color-rgb', hexToRgbString(resolvedColor));
    document.documentElement.style.setProperty('--btn-text-color', getContrastTextColor(resolvedColor));
}

function resolveThemeButtonStyle(theme) {
    const baseColor = normalizeHexColor(theme?.btnColor || '#60a5fa');
    const btnTextColor = String(theme?.btnTextColor || '').trim()
        ? normalizeHexColor(theme.btnTextColor, getContrastTextColor(baseColor))
        : getContrastTextColor(baseColor);
    const gradientColors = Array.isArray(theme?.btnGradient?.colors)
        ? theme.btnGradient.colors.map((color) => normalizeHexColor(color, '')).filter(Boolean)
        : [];
    const hasGradient = gradientColors.length >= 2;
    const background = hasGradient
        ? `linear-gradient(${Number.isFinite(Number(theme?.btnGradient?.angle)) ? Number(theme.btnGradient.angle) : 135}deg, ${gradientColors.slice(0, 3).join(', ')})`
        : baseColor;

    return {
        '--btn-color': baseColor,
        '--btn-color-rgb': hexToRgbString(baseColor),
        '--btn-text-color': btnTextColor,
        background,
        color: btnTextColor,
    };
}

function inferThemePreview(theme) {
    return toCssBackgroundImage(resolveEffectiveBackground(theme, null)) || theme?.preview || buildGradientCss(theme?.gradient);
}

function inferImageFit(theme) {
    return theme?.imageFit === 'contain' ? 'contain' : theme?.imageFit === 'center' ? 'auto' : 'cover';
}

function getEditableGradientStops(gradient) {
    const stops = Array.isArray(gradient?.stops) ? gradient.stops : [];
    if (stops.length >= 1) {
        return stops
            .map((stop, index) => ({
                color: normalizeHexColor(stop?.color || '#60a5fa'),
                position: Math.max(0, Math.min(100, Math.round(Number(stop?.position ?? (index === 0 ? 0 : 100))))),
            }))
            .sort((first, second) => first.position - second.position);
    }

    const colors = Array.isArray(gradient?.colors) ? gradient.colors : ['#2563eb'];
    return colors.slice(0, 5).map((color, index, palette) => ({
        color: normalizeHexColor(color),
        position: palette.length === 1 ? 0 : Math.round((index / (palette.length - 1)) * 100),
    }));
}

function syncGradientStops(nextStops, currentGradient = {}) {
    const orderedStops = nextStops
        .map((stop) => ({
            color: normalizeHexColor(stop?.color || '#60a5fa'),
            position: Math.max(0, Math.min(100, Math.round(Number(stop?.position ?? 0)))),
        }))
        .sort((first, second) => first.position - second.position);

    return {
        ...currentGradient,
        type: String(currentGradient?.type || 'linear').trim().toLowerCase() === 'radial' ? 'radial' : 'linear',
        angle: Number.isFinite(Number(currentGradient?.angle)) ? Number(currentGradient.angle) : 135,
        colors: orderedStops.map((stop) => stop.color),
        stops: orderedStops,
    };
}

const DEFAULT_GRADIENT_POSITIONS = [0, 50, 100, 25, 75, 12, 37, 62, 87, 6, 18, 31, 43, 56, 68, 81, 93];

function nextGradientPosition(stops = []) {
    const taken = new Set(stops.map((stop) => Math.round(stop.position)));
    for (const candidate of DEFAULT_GRADIENT_POSITIONS) {
        if (!taken.has(candidate)) {
            return candidate;
        }
    }

    return Math.min(100, Math.max(0, (stops[stops.length - 1]?.position ?? 0) + 8));
}

function isEditableThemePack(theme) {
    if (!theme) {
        return false;
    }

    return theme.id === 'custom' || !BUILT_IN_THEME_IDS.has(theme.id);
}
// ─────────────────────────────────────────────────────────────────────────────

const REMINDER_OPTIONS = [
    { value: 0, label: 'At time of event' },
    { value: 5, label: '5 minutes before' },
    { value: 15, label: '15 minutes before' },
    { value: 30, label: '30 minutes before' },
    { value: 60, label: '1 hour before' },
    { value: 1440, label: '1 day before' },
];
const SUPPORTED_AVATAR_TYPES = new Set([
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/avif',
    'image/heic',
    'image/heif',
]);
const AVATAR_ACCEPT = 'image/png,image/jpeg,image/gif,image/webp,image/avif,image/heic,image/heif';
const MAX_AVATAR_FILE_BYTES = 2 * 1024 * 1024;
const AVATAR_FORMAT_LABEL = 'PNG, JPEG, GIF, WEBP, AVIF, HEIC, or HEIF';

export function decodeToken(token) {
    if (!token) {
        return null;
    }

    try {
        const payload = token.split('.')[1];
        const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
        return JSON.parse(window.atob(normalized));
    } catch {
        return null;
    }
}

function suggestionKey(suggestion) {
    return `${suggestion.title}|${suggestion.suggestedTime}|${suggestion.description}`;
}

export function dateWithSuggestedTime(base, suggestedTime) {
    const parts = suggestedTime.split(':');
    if (parts.length !== 2) {
        return new Date(base.getFullYear(), base.getMonth(), base.getDate(), 12, 0, 0, 0);
    }

    const hour = Number.parseInt(parts[0], 10);
    const minute = Number.parseInt(parts[1], 10);
    return new Date(
        base.getFullYear(),
        base.getMonth(),
        base.getDate(),
        Number.isNaN(hour) ? 12 : hour,
        Number.isNaN(minute) ? 0 : minute,
        0,
        0,
    );
}

export function extractJsonArray(text) {
    const fenceMatch = /```(?:json)?\s*([\s\S]*?)```/m.exec(text);
    const fenced = fenceMatch?.[1]?.trim();
    if (fenced && fenced.startsWith('[') && fenced.endsWith(']')) {
        return fenced;
    }

    const start = text.indexOf('[');
    const end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
        return text.slice(start, end + 1).trim();
    }

    return '';
}

export function normalizeSuggestions(rawSuggestions) {
    const items = Array.isArray(rawSuggestions) ? rawSuggestions : [];
    if (
        items.length === 1 &&
        items[0]?.title === 'Parse error' &&
        typeof items[0]?.description === 'string'
    ) {
        const cleaned = extractJsonArray(items[0].description);
        if (cleaned) {
            try {
                const decoded = JSON.parse(cleaned);
                return Array.isArray(decoded) ? decoded : [];
            } catch {
                return items;
            }
        }
    }

    return items;
}

export function displayAssistantStatus(status) {
    const trimmed = String(status || '').trim();
    if (!trimmed) {
        return '';
    }

    return (trimmed.endsWith('...') || /[.!?]$/.test(trimmed)) ? trimmed : `${trimmed}...`;
}

function waitForNextPaint() {
    return new Promise((resolve) => {
        const schedule =
            typeof window.requestAnimationFrame === 'function'
                ? window.requestAnimationFrame.bind(window)
                : (callback) => window.setTimeout(callback, 16);
        schedule(() => resolve());
    });
}

export function validateAvatarFile(file) {
    if (!file) {
        throw new Error('Choose an image file to upload.');
    }

    if (!SUPPORTED_AVATAR_TYPES.has(String(file.type || '').toLowerCase())) {
        throw new Error(`Profile picture must be ${AVATAR_FORMAT_LABEL}.`);
    }

    if (file.size > MAX_AVATAR_FILE_BYTES) {
        throw new Error('Profile picture must be 2 MB or smaller.');
    }
}

function readFileAsDataUrl(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            if (typeof reader.result === 'string' && reader.result) {
                resolve(reader.result);
                return;
            }

            reject(new Error('Could not read the selected image.'));
        };
        reader.onerror = () => reject(new Error('Could not read the selected image.'));
        reader.readAsDataURL(file);
    });
}

async function readResponseJson(response, fallbackError) {
    const text = await response.text();
    if (!text) {
        return {};
    }

    const trimmed = text.trimStart();
    if (trimmed.startsWith('<!DOCTYPE html') || trimmed.startsWith('<html')) {
        throw new Error(fallbackError);
    }

    try {
        return JSON.parse(text);
    } catch {
        throw new Error(fallbackError);
    }
}

async function uploadImageDataUrl(session, imageDataUrl, purpose, fileName) {
    const response = await fetch(`${API_ROOT}/uploadimage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            userId: session.userId,
            jwtToken: session.jwtToken,
            imageDataUrl,
            purpose,
            fileName,
        }),
    });

    const data = await readResponseJson(response, 'Image upload failed.');
    if (!response.ok) {
        throw new Error(data.error || 'Image upload failed.');
    }

    return data;
}

async function uploadThemeImageFile(file, session, purpose, fileName) {
    const dataUrl = await readFileAsDataUrl(file);
    const result = await uploadImageDataUrl(session, dataUrl, purpose, fileName);
    return result.imageUrl;
}

function normalizeAssistantMarkdown(text) {
    return String(text || '')
        .replace(/\r\n?/g, '\n')
        .replace(/\]\s*\n\s*\(/g, '](')
        .replace(/^\s{0,3}#{1,6}\s+/gm, '');
}

function renderInlineMarkdown(text) {
    const source = normalizeAssistantMarkdown(text);
    const nodes = [];
    const pattern = /(\*\*[^*]+\*\*|__[^_]+__|(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)|`[^`\n]+`|\[[^\]]+\]\s*\((https?:\/\/[^\s)]+)\)|https?:\/\/[^\s<]+)/g;
    let lastIndex = 0;
    let match;

    while ((match = pattern.exec(source)) !== null) {
        if (match.index > lastIndex) {
            nodes.push(<span key={`text-${lastIndex}`}>{source.slice(lastIndex, match.index)}</span>);
        }

        const token = match[0];
        if (
            ((token.startsWith('**') && token.endsWith('**')) ||
             (token.startsWith('__') && token.endsWith('__'))) &&
            token.length > 4
        ) {
            nodes.push(<strong key={`bold-${match.index}`}>{token.slice(2, -2)}</strong>);
        } else if (
            ((token.startsWith('*') && token.endsWith('*')) ||
             (token.startsWith('_') && token.endsWith('_'))) &&
            token.length > 2
        ) {
            nodes.push(<em key={`italic-${match.index}`}>{token.slice(1, -1)}</em>);
        } else if (token.startsWith('`') && token.endsWith('`') && token.length > 2) {
            nodes.push(<code key={`code-${match.index}`} className="ai-inline-code">{token.slice(1, -1)}</code>);
        } else {
            const linkMatch = /^\[([^\]]+)\]\s*\((https?:\/\/[^\s)]+)\)$/.exec(token);
            if (linkMatch) {
                nodes.push(
                    <a
                        key={`link-${match.index}`}
                        href={linkMatch[2]}
                        target="_blank"
                        rel="noreferrer"
                    >
                        {linkMatch[1]}
                    </a>
                );
            } else if (/^https?:\/\/[^\s<]+$/.test(token)) {
                nodes.push(
                    <a
                        key={`url-${match.index}`}
                        href={token}
                        target="_blank"
                        rel="noreferrer"
                    >
                        {token}
                    </a>
                );
            } else {
                nodes.push(<span key={`token-${match.index}`}>{token}</span>);
            }
        }

        lastIndex = match.index + token.length;
    }

    if (lastIndex < source.length) {
        nodes.push(<span key={`text-${lastIndex}`}>{source.slice(lastIndex)}</span>);
    }

    return nodes.length ? nodes : source;
}

function renderAssistantMessage(text) {
    const normalizedText = normalizeAssistantMarkdown(text);
    const lines = normalizedText.split('\n');
    const blocks = [];
    let listItems = [];

    const flushList = () => {
        if (!listItems.length) {
            return;
        }

        blocks.push(
            <ul key={`list-${blocks.length}`} className="ai-message-list">
                {listItems.map((item, index) => (
                    <li key={`item-${index}`}>{renderInlineMarkdown(item)}</li>
                ))}
            </ul>
        );
        listItems = [];
    };

    lines.forEach((line, index) => {
        const trimmed = line.trim();
        const listMatch = /^([-*]|\d+\.)\s+(.*)$/.exec(trimmed);

        if (!trimmed) {
            flushList();
            return;
        }

        if (listMatch) {
            listItems.push(listMatch[2]);
            return;
        }

        flushList();
        blocks.push(
            <div key={`line-${index}`} className="ai-message-line">
                {renderInlineMarkdown(trimmed)}
            </div>
        );
    });

    flushList();

    return blocks.length > 0 ? blocks : normalizedText;
}

function SparklesIcon() {
    return (
        <svg viewBox="0 0 24 24" className="ai-inline-icon" aria-hidden="true">
            <path d="M12 3 13.8 8.2 19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8Z" fill="currentColor" />
            <path d="M18.5 3 19.2 5 21 5.8 19.2 6.5 18.5 8.5 17.8 6.5 16 5.8 17.8 5Z" fill="currentColor" />
        </svg>
    );
}

function SendIcon() {
    return (
        <svg viewBox="0 0 24 24" className="ai-inline-icon" aria-hidden="true">
            <path d="M3 20 21 12 3 4l3.8 7.2L15 12l-8.2.8Z" fill="currentColor" />
        </svg>
    );
}

function LocationIcon() {
    return (
        <svg viewBox="0 0 24 24" className="ai-inline-icon" aria-hidden="true">
            <path d="M11 2h2v3h-2Z" fill="currentColor" />
            <path d="M11 19h2v3h-2Z" fill="currentColor" />
            <path d="M2 11h3v2H2Z" fill="currentColor" />
            <path d="M19 11h3v2h-3Z" fill="currentColor" />
            <path d="M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10Zm0 2.2a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6Z" fill="currentColor" />
        </svg>
    );
}

function App() {
    const initialSelectedDate = new Date();
    initialSelectedDate.setHours(0, 0, 0, 0);
    const [isAuthenticated, setIsAuthenticated] = useState(Boolean(localStorage.getItem('jwtToken')));
    const [leftOpen, setLeftOpen] = useState(true);
    const [rightOpen, setRightOpen] = useState(true);
    const [background, setBackground] = useState({ image: null, sceneKey: null });
    const [aiInput, setAiInput] = useState('');
    const [suggestionPreferences, setSuggestionPreferences] = useState('');
    const [aiLoading, setAiLoading] = useState(false);
    const [suggestions, setSuggestions] = useState([]);
    const [savedSuggestionKeys, setSavedSuggestionKeys] = useState([]);
    const [aiMode, setAiMode] = useState('chat');
    const [location, setLocation] = useState(null);
    const [isLocating, setIsLocating] = useState(false);
    const [locationNotice, setLocationNotice] = useState('Trying to use your current location for nearby suggestions.');
    const [messages, setMessages] = useState([
        { role: 'assistant', text: 'Ask about your day or grab event suggestions.' },
    ]);
    const [calendarRefreshKey, setCalendarRefreshKey] = useState(0);
    const [calendarModalIntent, setCalendarModalIntent] = useState(null);
    const [selectedDate, setSelectedDate] = useState(initialSelectedDate);
    const [searchOpen, setSearchOpen] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
    const [searchMeta, setSearchMeta] = useState({
        active: false,
        loading: false,
        count: 0,
        error: '',
    });
    const [accountModalOpen, setAccountModalOpen] = useState(false);
    const [accountTab, setAccountTab] = useState('account');
    // Theme state — loaded from localStorage on mount
    const [activeTheme, setActiveTheme] = useState(() => {
        const saved = loadTheme();
        return saved || DEFAULT_THEME;
    });
    const [savedThemePacks, setSavedThemePacks] = useState(() => loadSavedThemePacks());
    // Scratch state for the theme editor (before Apply is clicked)
    const [themeDraft, setThemeDraft] = useState(null);
    const [customBgMode, setCustomBgMode] = useState('gradient'); // 'gradient' | 'universal' | 'perScene'
    const [selectedGradientStopIndex, setSelectedGradientStopIndex] = useState(0);
    const [gradientEditorOpen, setGradientEditorOpen] = useState(false);
    const [themeImportValue, setThemeImportValue] = useState('');
    const [themeShareState, setThemeShareState] = useState({
        open: false,
        loading: false,
        theme: null,
        customLinkId: '',
        activeTab: 'share',
    });
    const [accountSettings, setAccountSettings] = useState(null);
    const [accountDraft, setAccountDraft] = useState({
        firstName: '',
        lastName: '',
        email: '',
        pendingEmail: '',
        calendarFeedUrl: '',
        calendarFeedWebcalUrl: '',
        reminderDefaults: {
            reminderEnabled: false,
            reminderMinutesBefore: 30,
        },
    });
    const [emailDraft, setEmailDraft] = useState('');
    const [accountLoading, setAccountLoading] = useState(false);
    const [accountSaving, setAccountSaving] = useState(false);
    const [accountFeedback, setAccountFeedback] = useState('');
    const [emailFeedback, setEmailFeedback] = useState('');
    const [avatarUrl, setAvatarUrl] = useState(null);
    const [pendingAvatarUrl, setPendingAvatarUrl] = useState(null);
    const searchInputRef = useRef(null);
    const locationRequestRef = useRef(null);
    const themeImportInputRef = useRef(null);
    const sharedThemeImportInFlight = useRef(false);

    const currentDate = new Date();
    const verticalDateString = selectedDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const fullDateString = selectedDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
    const todayDate = new Date();
    todayDate.setHours(0, 0, 0, 0);
    const isSelectedToday = selectedDate.getTime() === todayDate.getTime();
    const trimmedSearchQuery = searchQuery.trim();
    const themeShareTargets = themeShareState.theme ? buildThemeShareTargets(themeShareState.theme) : null;
    const themeSharePreview = themeShareState.theme
        ? (inferThemePreview(themeShareState.theme) || themeShareState.theme.preview || 'none')
        : 'none';
    const customThemeCard = sanitizeThemePack({
        ...EMPTY_CUSTOM_THEME,
        ...(isEditableThemePack(themeDraft) ? themeDraft : {}),
        id: 'custom',
        name: 'Custom Photo Pack',
        description: 'Create and tune your own photo or gradient-based weather pack.',
        source: 'draft',
    }, EMPTY_CUSTOM_THEME);
    const featuredWeatherThemes = [DEFAULT_THEME, ...FEATURED_THEMES, customThemeCard];
    const draftPreviewBackground = themeDraft ? (inferThemePreview(themeDraft) || themeDraft.preview || 'none') : 'none';
    const draftGradientStops = getEditableGradientStops(themeDraft?.gradient);
    const activeGradientStopIndex = Math.min(selectedGradientStopIndex, Math.max(0, draftGradientStops.length - 1));
    const activeGradientStop = draftGradientStops[activeGradientStopIndex] || draftGradientStops[0] || { color: '#60a5fa', position: 50 };
    const shareModalActions = [
        { key: 'native', label: 'Share', icon: ShareArrowIcon, onClick: async () => shareThemeThroughSystem(themeShareState.theme), disabled: !themeShareState.theme?.shareUrl || typeof navigator.share !== 'function' },
        { key: 'copy-link', label: 'Copy Link', icon: CopyIcon, onClick: () => copyThemeShareValue(themeShareState.theme?.shareUrl, 'Share link'), disabled: !themeShareState.theme?.shareUrl },
        { key: 'copy-code', label: 'Copy Code', icon: CodeHashIcon, onClick: () => copyThemeShareValue(themeShareState.theme?.shareCode, 'Theme code'), disabled: !themeShareState.theme?.shareCode },
        { key: 'sms', label: 'Messages', icon: MessagesIcon, onClick: () => openThemeShareTarget(themeShareTargets?.sms), disabled: !themeShareState.theme?.shareUrl },
        { key: 'email', label: 'Email', icon: MailIcon, onClick: () => openThemeShareTarget(themeShareTargets?.email), disabled: !themeShareState.theme?.shareUrl },
        { key: 'facebook', label: 'Facebook', icon: FacebookIcon, onClick: () => openThemeShareTarget(themeShareTargets?.facebook), disabled: !themeShareState.theme?.shareUrl },
        { key: 'whatsapp', label: 'WhatsApp', icon: WhatsAppIcon, onClick: () => openThemeShareTarget(themeShareTargets?.whatsapp), disabled: !themeShareState.theme?.shareUrl },
    ].filter((item) => item.key !== 'native' || typeof navigator.share === 'function');

    const logout = () => {
        localStorage.removeItem('jwtToken');
        localStorage.removeItem('accessToken');
        setAvatarUrl(null);
        setPendingAvatarUrl(null);
        locationRequestRef.current = null;
        setLocation(null);
        setLocationNotice('Trying to use your current location for nearby suggestions.');
        setSearchQuery('');
        setSearchOpen(false);
        setIsAuthenticated(false);
    };

    const getSession = () => {
        const jwtToken = localStorage.getItem('jwtToken') || '';
        const decoded = decodeToken(jwtToken);
        if (!jwtToken || !decoded?.userId) {
            logout();
            return null;
        }

        return {
            userId: decoded.userId,
            jwtToken,
            firstName: decoded.firstName || '',
            lastName: decoded.lastName || '',
        };
    };

    const updateToken = (nextToken) => {
        if (nextToken) {
            localStorage.setItem('jwtToken', nextToken);
        }
    };

    const loadAccountSettings = async (sessionOverride = null) => {
        const session = sessionOverride || getSession();
        if (!session) {
            return;
        }

        setAccountLoading(true);
        try {
            const response = await fetch(`${API_ROOT}/getaccountsettings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not load account settings.');
            }

            updateToken(data.jwtToken);
            const nextSettings = data.settings || {
                firstName: session.firstName || '',
                lastName: session.lastName || '',
                email: '',
                pendingEmail: '',
                avatarUrl: '',
                calendarFeedUrl: '',
                calendarFeedWebcalUrl: '',
                customThemes: [],
                reminderDefaults: {
                    reminderEnabled: false,
                    reminderMinutesBefore: 30,
                },
            };
            setAccountSettings(nextSettings);
            setAccountDraft(nextSettings);
            setAvatarUrl(nextSettings.avatarUrl || null);
            setEmailDraft('');
            setPendingAvatarUrl(null);
            setSavedThemePacks((prev) => {
                const merged = mergeThemePacks(prev, nextSettings.customThemes || []);
                persistSavedThemePacks(merged);
                return merged;
            });
        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountLoading(false);
        }
    };

    useEffect(() => {
        const sharedThemeValue = readSharedThemeValueFromLocation();
        if (!sharedThemeValue) {
            return;
        }

        localStorage.setItem(PENDING_SHARED_THEME_STORAGE_KEY, sharedThemeValue);
        clearSharedThemeValueFromLocation();
    }, []);

    useEffect(() => {
        if (isAuthenticated) {
            const session = getSession();
            if (session) {
                loadAccountSettings(session);
            }
        } else {
            setAccountSettings(null);
            setAvatarUrl(null);
            setPendingAvatarUrl(null);
        }
    }, [isAuthenticated]);

    useEffect(() => {
        if (!isAuthenticated) {
            return;
        }

        ensureLocation();
    }, [isAuthenticated]);

    useEffect(() => {
        if (!isAuthenticated || sharedThemeImportInFlight.current) {
            return;
        }

        const pendingSharedTheme = localStorage.getItem(PENDING_SHARED_THEME_STORAGE_KEY) || '';
        if (!pendingSharedTheme) {
            return;
        }

        sharedThemeImportInFlight.current = true;
        importSharedTheme(pendingSharedTheme, { openDashboard: true })
            .catch((error) => {
                localStorage.removeItem(PENDING_SHARED_THEME_STORAGE_KEY);
                setAccountFeedback(error.message);
            })
            .finally(() => {
                sharedThemeImportInFlight.current = false;
            });
    }, [isAuthenticated]);

    // Apply btn-color override whenever theme changes
    useEffect(() => {
        applyBtnColorOverride(activeTheme?.btnColor || '#60a5fa');
    }, [activeTheme]);

    useEffect(() => {
        if (!searchOpen) {
            return;
        }

        window.requestAnimationFrame(() => {
            searchInputRef.current?.focus();
        });
    }, [searchOpen]);

    const refreshCalendar = () => {
        setCalendarRefreshKey((prev) => prev + 1);
    };

    const openSearch = () => {
        setSearchOpen(true);
    };

    const clearSearch = () => {
        setSearchQuery('');
        setSearchMeta({
            active: false,
            loading: false,
            count: 0,
            error: '',
        });
        searchInputRef.current?.focus();
    };

    const openAccountModal = (tab = 'account') => {
        setAccountTab(tab);
        setAccountFeedback('');
        setEmailFeedback('');
        setAccountModalOpen(true);
        if (accountSettings) {
            setAccountDraft(accountSettings);
        } else {
            loadAccountSettings();
        }
        if (tab === 'themes') {
            const nextDraft = sanitizeThemePack(cloneThemePack(activeTheme), EMPTY_CUSTOM_THEME);
            setThemeDraft(nextDraft);
            setCustomBgMode(inferThemeBackgroundMode(nextDraft));
        }
    };

    const syncThemeDraft = (nextTheme) => {
        const nextDraft = sanitizeThemePack(nextTheme, EMPTY_CUSTOM_THEME);
        setThemeDraft(nextDraft);
        setCustomBgMode(inferThemeBackgroundMode(nextDraft));
        setSelectedGradientStopIndex(0);
        return nextDraft;
    };

    const themePackMatches = (first, second) => {
        if (!first || !second) {
            return false;
        }

        if (first.sharedThemeId || second.sharedThemeId) {
            return String(first.sharedThemeId || '') === String(second.sharedThemeId || '');
        }

        return String(first.id || '') === String(second.id || '');
    };

    const upsertSavedThemePack = (nextTheme) => {
        const normalized = sanitizeThemePack(nextTheme, EMPTY_CUSTOM_THEME);
        setSavedThemePacks((prev) => {
            const nextPacks = mergeThemePacks(prev, [normalized]);
            persistSavedThemePacks(nextPacks);
            return nextPacks;
        });
        setAccountSettings((prev) => (
            prev
                ? { ...prev, customThemes: mergeThemePacks(prev.customThemes || [], [normalized]) }
                : prev
        ));
        return normalized;
    };

    const replaceSavedThemePack = (previousTheme, nextTheme) => {
        const normalized = sanitizeThemePack(nextTheme, EMPTY_CUSTOM_THEME);
        setSavedThemePacks((prev) => {
            const filtered = prev.filter((pack) => (
                !themePackMatches(pack, previousTheme) && !themePackMatches(pack, normalized)
            ));
            const nextPacks = mergeThemePacks(filtered, [normalized]);
            persistSavedThemePacks(nextPacks);
            return nextPacks;
        });
        setAccountSettings((prev) => (
            prev
                ? {
                    ...prev,
                    customThemes: mergeThemePacks(
                        (prev.customThemes || []).filter((pack) => !themePackMatches(pack, previousTheme)),
                        [normalized],
                    ),
                }
                : prev
        ));
        return normalized;
    };

    const uploadThemeAssets = async (nextTheme, session) => {
        const uploaded = { ...nextTheme, images: { ...(nextTheme.images || {}) } };

        const uploadDataUrl = async (purpose, fileName, dataUrl) => {
            const result = await uploadImageDataUrl(session, dataUrl, purpose, fileName);
            return result.imageUrl;
        };

        const universal = String(uploaded.images?.universal || '').trim();
        if (universal.startsWith('data:')) {
            uploaded.images.universal = await uploadDataUrl(
                'theme-images',
                `${uploaded.id || 'theme'}-universal.png`,
                universal,
            );
        }

        if (Array.isArray(uploaded.galleryImages)) {
            const nextGallery = [];
            for (let index = 0; index < uploaded.galleryImages.length; index += 1) {
                const value = String(uploaded.galleryImages[index] || '').trim();
                if (!value) {
                    continue;
                }
                if (value.startsWith('data:')) {
                    nextGallery.push(await uploadDataUrl(
                        'theme-gallery',
                        `${uploaded.id || 'theme'}-gallery-${index + 1}.png`,
                        value,
                    ));
                } else {
                    nextGallery.push(value);
                }
            }
            uploaded.galleryImages = nextGallery;
        }

        const previewImage = String(uploaded.previewImage || '').trim();
        if (previewImage.startsWith('data:')) {
            uploaded.previewImage = await uploadDataUrl(
                'theme-previews',
                `${uploaded.id || 'theme'}-preview.png`,
                previewImage,
            );
        }

        return uploaded;
    };

    const syncThemePackToServer = async (nextTheme, options = {}) => {
        const session = getSession();
        if (!session) {
            throw new Error('Please log in again to sync this theme.');
        }

        const response = await fetch(`${API_ROOT}/upsertcustomtheme`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
                theme: nextTheme,
                ...(options.shareSlug ? { shareSlug: options.shareSlug } : {}),
            }),
        });

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Could not sync that theme.');
        }

        updateToken(data.jwtToken);
        return replaceSavedThemePack(nextTheme, data.theme);
    };

    const applyImportedTheme = (nextTheme, feedbackText = '') => {
        const importedTheme = upsertSavedThemePack(nextTheme);
        syncThemeDraft(importedTheme);
        setActiveTheme(importedTheme);
        persistTheme(importedTheme);
        if (feedbackText) {
            setAccountFeedback(feedbackText);
        }
        return importedTheme;
    };

    const importSharedTheme = async (shareValue, options = {}) => {
        const resolvedShareValue = extractSharedThemeValue(shareValue);
        if (!resolvedShareValue) {
            throw new Error('Paste a theme code or share link first.');
        }

        const session = getSession();
        if (!session) {
            localStorage.setItem(PENDING_SHARED_THEME_STORAGE_KEY, resolvedShareValue);
            throw new Error('Log in to import that theme.');
        }

        const response = await fetch(`${API_ROOT}/importsharedtheme`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
                shareValue: resolvedShareValue,
            }),
        });

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Could not import that theme.');
        }

        updateToken(data.jwtToken);
        const importedTheme = applyImportedTheme(
            sanitizeThemePack(data.theme, EMPTY_CUSTOM_THEME),
            `Imported "${data.theme?.name || 'theme'}" and applied it.`,
        );

        localStorage.removeItem(PENDING_SHARED_THEME_STORAGE_KEY);
        setThemeImportValue('');

        if (options.openDashboard) {
            setAccountTab('themes');
            setAccountModalOpen(true);
        }

        return importedTheme;
    };

    const openThemeShareDialog = (theme) => {
        if (!theme) {
            return;
        }

        setThemeShareState({
            open: true,
            loading: false,
            theme,
            customLinkId: theme.shareSlug || '',
            activeTab: 'share',
        });
    };

    const closeThemeShareDialog = () => {
        setThemeShareState({
            open: false,
            loading: false,
            theme: null,
            customLinkId: '',
            activeTab: 'share',
        });
    };

    const saveSharedThemeDetails = async () => {
        if (!themeShareState.theme) {
            return;
        }

        setThemeShareState((prev) => ({ ...prev, loading: true }));
        try {
            const session = getSession();
            if (!session) {
                throw new Error('Please log in again to sync this theme.');
            }
            const nextTheme = await uploadThemeAssets(themeShareState.theme, session);
            const syncedTheme = await syncThemePackToServer(nextTheme, {
                shareSlug: themeShareState.customLinkId,
            });

            if (themePackMatches(themeDraft, themeShareState.theme)) {
                syncThemeDraft(syncedTheme);
            }
            if (themePackMatches(activeTheme, themeShareState.theme)) {
                setActiveTheme(syncedTheme);
                persistTheme(syncedTheme);
            }

            setThemeShareState({
                open: true,
                loading: false,
                theme: syncedTheme,
                customLinkId: syncedTheme.shareSlug || '',
                activeTab: 'share',
            });
            setAccountFeedback(`Share ready for "${syncedTheme.name}".`);
        } catch (error) {
            setThemeShareState((prev) => ({ ...prev, loading: false }));
            setAccountFeedback(error.message);
        }
    };

    const openThemeLinkEditor = () => {
        setThemeShareState((prev) => ({ ...prev, activeTab: 'edit' }));
    };

    const closeThemeLinkEditor = () => {
        setThemeShareState((prev) => ({ ...prev, activeTab: 'share' }));
    };

    const saveThemePackDraft = async () => {
        if (!themeDraft) {
            return;
        }

        const baseId = savedThemePacks.some((pack) => themePackMatches(pack, themeDraft))
            ? themeDraft.id
            : buildThemePackId(themeDraft.name);
        const savedPack = upsertSavedThemePack({
            ...themeDraft,
            id: baseId,
            source: 'user',
        });
        syncThemeDraft(savedPack);
        setAccountFeedback(`Saved "${savedPack.name}" to your theme packs.`);

        try {
            const session = getSession();
            if (!session) {
                throw new Error('Please log in again to sync this theme.');
            }
            const syncedPack = await uploadThemeAssets(savedPack, session);
            const syncedTheme = await syncThemePackToServer(syncedPack);
            syncThemeDraft(syncedTheme);
            if (themePackMatches(activeTheme, savedPack)) {
                setActiveTheme(syncedTheme);
                persistTheme(syncedTheme);
            }
            setAccountFeedback(`Saved "${syncedTheme.name}" to your theme packs.`);
        } catch (error) {
            setAccountFeedback(`Saved "${savedPack.name}" locally. ${error.message}`);
        }
    };

    const updateThemeGradient = (mutator) => {
        setThemeDraft((prev) => {
            const nextStops = mutator(getEditableGradientStops(prev?.gradient));
            return {
                ...prev,
                backgroundMode: 'gradient',
                gradient: syncGradientStops(nextStops, prev?.gradient),
            };
        });
    };

    const addGradientStop = () => {
        updateThemeGradient((stops) => {
            const baseStops = stops.length >= 1 ? stops : getEditableGradientStops(EMPTY_CUSTOM_THEME.gradient);
            const selected = baseStops[Math.min(selectedGradientStopIndex, baseStops.length - 1)] || baseStops[0];
            const position = nextGradientPosition(baseStops);
            const nextStops = [...baseStops, { color: selected.color, position }];
            return nextStops;
        });
        setSelectedGradientStopIndex((prev) => Math.min(prev + 1, 8));
    };

    const removeGradientStop = () => {
        updateThemeGradient((stops) => {
            if (stops.length <= 1) {
                return stops;
            }
            return stops.filter((_, index) => index !== activeGradientStopIndex);
        });
        setSelectedGradientStopIndex((prev) => Math.max(0, prev - 1));
    };

    const updateGradientStopColor = (color) => {
        updateThemeGradient((stops) => stops.map((stop, index) => (
            index === activeGradientStopIndex ? { ...stop, color } : stop
        )));
    };

    const updateGradientStopPosition = (position) => {
        updateThemeGradient((stops) => stops.map((stop, index) => (
            index === activeGradientStopIndex ? { ...stop, position } : stop
        )));
    };

    const gradientEditorModal = gradientEditorOpen && themeDraft && typeof document !== 'undefined'
        ? createPortal(
            <div className="theme-overlay-backdrop" onClick={() => setGradientEditorOpen(false)}>
                <div className="theme-gradient-modal" onClick={(event) => event.stopPropagation()}>
                    <div className="theme-gradient-modal-header">
                        <div>
                            <div className="account-modal-kicker">Gradient Background</div>
                            <h3>Custom Gradient</h3>
                        </div>
                        <button type="button" className="account-close-btn" onClick={() => setGradientEditorOpen(false)}>
                            Close
                        </button>
                    </div>
                    <div className="theme-gradient-editor theme-gradient-editor-modal">
                        <div className="theme-gradient-editor-top">
                            <label className="account-field">
                                <span>Type</span>
                                <select
                                    value={themeDraft.gradient?.type || 'linear'}
                                    onChange={(event) => setThemeDraft((prev) => ({
                                        ...prev,
                                        backgroundMode: 'gradient',
                                        gradient: {
                                            ...(prev.gradient || EMPTY_CUSTOM_THEME.gradient),
                                            type: event.target.value,
                                        },
                                    }))}
                                >
                                    <option value="linear">Linear</option>
                                    <option value="radial">Radial</option>
                                </select>
                            </label>
                            <label className="account-field">
                                <span>Angle</span>
                                <select
                                    value={Number(themeDraft.gradient?.angle ?? EMPTY_CUSTOM_THEME.gradient.angle)}
                                    onChange={(event) => setThemeDraft((prev) => ({
                                        ...prev,
                                        backgroundMode: 'gradient',
                                        gradient: {
                                            ...(prev.gradient || EMPTY_CUSTOM_THEME.gradient),
                                            angle: Number(event.target.value),
                                        },
                                    }))}
                                    disabled={themeDraft.gradient?.type === 'radial'}
                                >
                                    {[0, 45, 90, 135, 180, 225, 270, 315].map((angle) => (
                                        <option key={angle} value={angle}>{`${angle} deg`}</option>
                                    ))}
                                </select>
                            </label>
                            <div className="theme-gradient-preview-card">
                                <span className="theme-gradient-preview-label">Preview</span>
                                <div className="theme-gradient-preview-swatch" style={{ backgroundImage: buildGradientCss(themeDraft.gradient) }} />
                            </div>
                        </div>
                        <div className="theme-gradient-editor-controls">
                            <div className="theme-gradient-editor-header">
                                <span className="theme-gradient-editor-title">Gradient Stops</span>
                            </div>
                            <div className="theme-gradient-stop-toolbar">
                                <div className="theme-gradient-stop-actions">
                                    <button type="button" className="account-secondary-btn" onClick={addGradientStop}>
                                        Add
                                    </button>
                                    <button type="button" className="account-secondary-btn" onClick={removeGradientStop} disabled={draftGradientStops.length <= 1}>
                                        Remove
                                    </button>
                                </div>
                                <div className="theme-gradient-stop-swatch">
                                    <input
                                        type="color"
                                        className="theme-color-input theme-gradient-color-input"
                                        value={activeGradientStop.color}
                                        onChange={(event) => updateGradientStopColor(event.target.value)}
                                    />
                                </div>
                            </div>
                            <div className="theme-gradient-stop-editor">
                                <label className="account-check-row theme-gradient-rotate-row">
                                    <input type="checkbox" checked readOnly />
                                    <span>Rotate with shape</span>
                                </label>
                                <label className="account-field">
                                    <span>Selected color</span>
                                    <input
                                        type="text"
                                        className="theme-color-text"
                                        value={activeGradientStop.color}
                                        maxLength={7}
                                        onChange={(event) => {
                                            const value = event.target.value;
                                            if (/^#[0-9a-fA-F]{0,6}$/.test(value)) {
                                                updateGradientStopColor(value);
                                            }
                                        }}
                                    />
                                </label>
                            </div>
                            <div className="theme-gradient-rail-shell">
                                <div className="theme-gradient-rail" style={{ backgroundImage: buildGradientCss(themeDraft.gradient) }}>
                                    {draftGradientStops.map((stop, index) => (
                                        <button
                                            key={`${stop.color}-${stop.position}-${index}`}
                                            type="button"
                                            className={`theme-gradient-stop-handle${index === activeGradientStopIndex ? ' active' : ''}`}
                                            style={{ left: `${stop.position}%`, background: stop.color }}
                                            onClick={() => setSelectedGradientStopIndex(index)}
                                            aria-label={`Select gradient stop ${index + 1}`}
                                        />
                                    ))}
                                </div>
                            </div>
                            <input
                                className="theme-gradient-position-range"
                                type="range"
                                min="0"
                                max="100"
                                value={activeGradientStop.position}
                                onChange={(event) => updateGradientStopPosition(Number(event.target.value))}
                            />
                        </div>
                        <div className="theme-gradient-modal-actions">
                            <button type="button" className="account-secondary-btn" onClick={() => setGradientEditorOpen(false)}>
                                Cancel
                            </button>
                            <button type="button" className="account-primary-btn" onClick={() => setGradientEditorOpen(false)}>
                                OK
                            </button>
                        </div>
                    </div>
                </div>
            </div>,
            document.body,
        )
        : null;

    const themeShareModal = themeShareState.open && themeShareState.theme && typeof document !== 'undefined'
        ? createPortal(
            <div className="theme-overlay-backdrop" onClick={closeThemeShareDialog}>
                <div className="theme-share-floating-modal" onClick={(event) => event.stopPropagation()}>
                    <div className="theme-share-modal-header theme-share-floating-header">
                        <div>
                            <div className="account-modal-kicker">Share Theme</div>
                            <h3>{themeShareState.theme.name}</h3>
                            <p>{themeShareState.theme.creatorLabel || `Theme created by ${themeShareState.theme.authorName || 'you'}`}</p>
                        </div>
                        <button type="button" className="account-close-btn" onClick={closeThemeShareDialog}>
                            Done
                        </button>
                    </div>

                    <div className="theme-share-tabs" role="tablist" aria-label="Theme share tabs">
                        <button
                            type="button"
                            className={`theme-share-tab${themeShareState.activeTab === 'share' ? ' active' : ''}`}
                            onClick={closeThemeLinkEditor}
                        >
                            Share
                        </button>
                        <button
                            type="button"
                            className={`theme-share-tab${themeShareState.activeTab === 'edit' ? ' active' : ''}`}
                            onClick={openThemeLinkEditor}
                            disabled={themeShareState.theme.sharedThemeId && themeShareState.theme.isOwnedTheme !== true}
                        >
                            Edit Link
                        </button>
                    </div>

                    <div className="theme-share-modal-body theme-share-compact-body">
                        {themeShareState.activeTab === 'share' ? (
                            <>
                                <div className="theme-share-preview-panel theme-share-preview-panel-compact" style={{ backgroundImage: themeSharePreview }}>
                                    <div className="theme-share-preview-overlay">
                                        <span className="theme-share-preview-chip">{themeShareState.theme.authorLabel || 'By you'}</span>
                                        <button
                                            type="button"
                                            className="theme-preview-btn"
                                            style={resolveThemeButtonStyle(themeShareState.theme)}
                                        >
                                            Preview Theme
                                        </button>
                                    </div>
                                </div>

                                {themeShareState.theme.sharedThemeId && themeShareState.theme.isOwnedTheme !== true && (
                                    <p className="theme-share-note">This imported theme keeps the original creator name. You can share the existing link or code, but only the owner can edit the custom link.</p>
                                )}

                                <div className="theme-share-action-grid compact">
                                    <button
                                        type="button"
                                        className="theme-share-action primary"
                                        onClick={saveSharedThemeDetails}
                                        disabled={themeShareState.loading}
                                    >
                                        <span className="theme-share-action-icon">+</span>
                                        <span>{themeShareState.loading ? 'Saving...' : themeShareState.theme.shareCode ? 'Refresh Share' : 'Create Share'}</span>
                                    </button>
                                    {shareModalActions.map((action) => {
                                        const Icon = action.icon;
                                        return (
                                            <button
                                                key={action.key}
                                                type="button"
                                                className="theme-share-action"
                                                onClick={action.onClick}
                                                disabled={action.disabled}
                                            >
                                                <span className="theme-share-action-icon">
                                                    <Icon />
                                                </span>
                                                <span>{action.label}</span>
                                            </button>
                                        );
                                    })}
                                </div>

                                <div className="theme-share-value-stack compact">
                                    <label className="theme-share-value-card">
                                        <span>Share link</span>
                                        <input value={themeShareState.theme.shareUrl || ''} readOnly />
                                    </label>
                                    <label className="theme-share-value-card">
                                        <span>Theme code</span>
                                        <input value={themeShareState.theme.shareCode || ''} readOnly />
                                    </label>
                                </div>
                            </>
                        ) : (
                            <div className="theme-share-edit-stack">
                                <div className="theme-share-edit-card">
                                    <div>
                                        <strong>Custom link ID</strong>
                                        <p>Use a short, memorable link ID or a six-digit code.</p>
                                    </div>
                                    <label className="account-field">
                                        <span>Custom link ID</span>
                                        <input
                                            value={themeShareState.customLinkId}
                                            onChange={(event) => setThemeShareState((prev) => ({ ...prev, customLinkId: event.target.value }))}
                                            placeholder="mountain-theme"
                                            disabled={themeShareState.loading || (themeShareState.theme.sharedThemeId && themeShareState.theme.isOwnedTheme !== true)}
                                        />
                                    </label>
                                </div>
                                <div className="theme-share-footer theme-share-footer-compact">
                                    <div>
                                        <strong>Share export</strong>
                                        <p>Export the current pack or save a custom share link from here.</p>
                                    </div>
                                    <div className="theme-share-footer-actions">
                                        <button
                                            type="button"
                                            className="account-secondary-btn"
                                            onClick={() => exportThemePackDraft(themeShareState.theme)}
                                            disabled={!themeShareState.theme}
                                        >
                                            Export file
                                        </button>
                                        <button type="button" className="account-primary-btn" onClick={saveSharedThemeDetails} disabled={themeShareState.loading}>
                                            {themeShareState.loading ? 'Saving...' : 'Save link ID'}
                                        </button>
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                </div>
            </div>,
            document.body,
        )
        : null;

    const exportThemePackDraft = (theme = themeDraft) => {
        if (!theme) {
            return;
        }

        const pack = sanitizeThemePack({
            ...theme,
            source: 'shared',
        }, EMPTY_CUSTOM_THEME);
        const blob = new Blob([JSON.stringify(pack, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `${pack.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || 'theme-pack'}.calpp-theme.json`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);
    };

    const importThemePackFile = async (file) => {
        if (!file) {
            return;
        }

        try {
            const text = await file.text();
            const parsed = JSON.parse(text);
            const importedPack = sanitizeThemePack({
                ...parsed,
                id: buildThemePackId(parsed?.name || 'imported-pack'),
                source: 'user',
            }, EMPTY_CUSTOM_THEME);
            applyImportedTheme(importedPack, `Imported "${importedPack.name}" and applied it.`);
        } catch {
            setAccountFeedback('Could not import that theme pack.');
        }
    };

    const deleteThemePack = async (packToDelete) => {
        if (!packToDelete) {
            return;
        }

        const session = getSession();
        if (packToDelete.sharedThemeId && session) {
            try {
                const response = await fetch(`${API_ROOT}/deletecustomtheme`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        userId: session.userId,
                        jwtToken: session.jwtToken,
                        sharedThemeId: packToDelete.sharedThemeId,
                    }),
                });

                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.error || 'Could not remove that theme.');
                }

                updateToken(data.jwtToken);
            } catch (error) {
                setAccountFeedback(error.message);
                return;
            }
        }

        setSavedThemePacks((prev) => {
            const nextPacks = prev.filter((pack) => !themePackMatches(pack, packToDelete));
            persistSavedThemePacks(nextPacks);
            return nextPacks;
        });
        setAccountSettings((prev) => (
            prev
                ? {
                    ...prev,
                    customThemes: (prev.customThemes || []).filter((pack) => !themePackMatches(pack, packToDelete)),
                }
                : prev
        ));

        if (themePackMatches(themeDraft, packToDelete)) {
            syncThemeDraft(EMPTY_CUSTOM_THEME);
        }
        if (themePackMatches(activeTheme, packToDelete)) {
            setActiveTheme(DEFAULT_THEME);
            persistTheme(DEFAULT_THEME);
        }
        if (themePackMatches(themeShareState.theme, packToDelete)) {
            closeThemeShareDialog();
        }

        setAccountFeedback('Saved theme pack removed.');
    };

    const copyThemeShareValue = async (value, label) => {
        if (!value) {
            setAccountFeedback(`${label} is not ready yet.`);
            return;
        }

        try {
            await navigator.clipboard.writeText(value);
            setAccountFeedback(`${label} copied.`);
        } catch {
            setAccountFeedback(value);
        }
    };

    const openThemeShareTarget = (targetUrl) => {
        if (!targetUrl) {
            return;
        }

        if (targetUrl.startsWith('mailto:') || targetUrl.startsWith('sms:')) {
            window.location.href = targetUrl;
            return;
        }

        window.open(targetUrl, '_blank', 'noopener,noreferrer');
    };

    const shareThemeThroughSystem = async (theme) => {
        if (!theme?.shareUrl || typeof navigator.share !== 'function') {
            return;
        }

        const targets = buildThemeShareTargets(theme);
        await navigator.share({
            title: `Calendar++ theme: ${theme.name}`,
            text: targets.shareText,
            url: theme.shareUrl,
        });
    };

    const openCalendarModal = (kind) => {
        setCalendarModalIntent({
            kind,
            date: new Date().toISOString(),
            key: Date.now(),
        });
    };

    const saveAccountSettings = async () => {
        const session = getSession();
        if (!session) {
            return;
        }

        setAccountSaving(true);
        setAccountFeedback('');
        try {
            let avatarUrlValue = null;
            if (pendingAvatarUrl !== null) {
                if (pendingAvatarUrl === 'REMOVED') {
                    avatarUrlValue = '';
                } else {
                    const avatarUpload = await uploadImageDataUrl(
                        session,
                        pendingAvatarUrl,
                        'avatars',
                        'avatar.png',
                    );
                    avatarUrlValue = avatarUpload.imageUrl;
                }
            }
            const requestBody = {
                userId: session.userId,
                jwtToken: session.jwtToken,
                firstName: accountDraft.firstName,
                lastName: accountDraft.lastName,
                reminderEnabled: accountDraft.reminderDefaults?.reminderEnabled === true,
                reminderMinutesBefore: Number(accountDraft.reminderDefaults?.reminderMinutesBefore || 30),
                ...(pendingAvatarUrl !== null ? { avatarUrl: avatarUrlValue } : {}),
            };
            const response = await fetch(`${API_ROOT}/saveaccountsettings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(requestBody),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not save settings.');
            }

            updateToken(data.jwtToken);
            const nextSettings = data.settings || accountDraft;
            setAccountSettings(nextSettings);
            setAccountDraft(nextSettings);
            setAvatarUrl(nextSettings.avatarUrl || null);
            setPendingAvatarUrl(null);
            setAccountFeedback('Settings saved.');
        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountSaving(false);
        }
    };

    const requestEmailChange = async () => {
        const session = getSession();
        if (!session || !emailDraft.trim()) {
            return;
        }

        setAccountSaving(true);
        setEmailFeedback('');
        try {
            const response = await fetch(`${API_ROOT}/requestemailchange`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    nextEmail: emailDraft.trim(),
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not start email change.');
            }

            updateToken(data.jwtToken);
            setEmailFeedback('Verification sent to the new email address.');
            await loadAccountSettings();
            setEmailDraft('');
        } catch (error) {
            setEmailFeedback(error.message);
        } finally {
            setAccountSaving(false);
        }
    };

    const exportCalendar = async () => {
        const session = getSession();
        if (!session) {
            return;
        }

        try {
            const response = await fetch(`${API_ROOT}/exportcalendar`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not export calendar.');
            }

            updateToken(data.jwtToken);
            const blob = new Blob([data.ics || ''], { type: 'text/calendar;charset=utf-8' });
            const downloadUrl = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = downloadUrl;
            link.download = data.filename || 'calendar-plus-plus.ics';
            document.body.appendChild(link);
            link.click();
            link.remove();
            URL.revokeObjectURL(downloadUrl);
            setAccountFeedback('Calendar exported.');
        } catch (error) {
            setAccountFeedback(error.message);
        }
    };

    const copyCalendarFeed = async (useWebcal = false) => {
        const nextLink = useWebcal
            ? accountSettings?.calendarFeedWebcalUrl
            : accountSettings?.calendarFeedUrl;

        if (!nextLink) {
            setAccountFeedback('Calendar feed link is not ready yet.');
            return;
        }

        try {
            await navigator.clipboard.writeText(nextLink);
            setAccountFeedback(useWebcal ? 'Subscription link copied.' : 'Feed URL copied.');
        } catch {
            setAccountFeedback(nextLink);
        }
    };

    const regenerateCalendarFeed = async () => {
        const session = getSession();
        if (!session) {
            return;
        }

        setAccountSaving(true);
        setAccountFeedback('');
        try {
            const response = await fetch(`${API_ROOT}/regeneratecalendarfeed`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not regenerate calendar feed.');
            }

            updateToken(data.jwtToken);
            setAccountSettings(data.settings);
            setAccountDraft(data.settings);
            setAccountFeedback('Subscription link regenerated. Old links no longer work.');
        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountSaving(false);
        }
    };

    const ensureLocation = async () => {
        if (location && !location.isFallback) {
            return location;
        }

        if (locationRequestRef.current) {
            return locationRequestRef.current;
        }

        const locationRequest = (async () => {
            setIsLocating(true);
            setLocationNotice('Checking location...');

            try {
                const coords = await requestWeatherLocation();

                if (!coords.isFallback) {
                    setLocation(coords);
                    setLocationNotice('Nearby suggestions are using your current location.');
                    return coords;
                }

                setLocationNotice('Location is blocked, set to UCF');
                return coords;
            } finally {
                locationRequestRef.current = null;
                setIsLocating(false);
            }
        })();

        locationRequestRef.current = locationRequest;
        return locationRequest;
    };

    const loadSuggestions = async () => {
        const session = getSession();
        if (!session) return;

        setAiLoading(true);
        setAiMode('suggestions');
        try {
            const localNow = new Date();
            const coords = await ensureLocation();
            const response = await fetch(`${API_ROOT}/suggestevents`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    date: localNow.toISOString(),
                    localNow: localNow.toISOString(),
                    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                    utcOffsetMinutes: -localNow.getTimezoneOffset(),
                    preferences: suggestionPreferences.trim(),
                    latitude: coords?.latitude,
                    longitude: coords?.longitude,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not load suggestions.');
            }

            updateToken(data.jwtToken);
            setSuggestions(normalizeSuggestions(data.suggestions));
        } catch (error) {
            setMessages((prev) => [...prev, { role: 'assistant', text: error.message }]);
        } finally {
            setAiLoading(false);
        }
    };

    const updateStreamingAssistantMessage = (updater) => {
        setMessages((prev) => {
            const updated = [...prev];
            const lastIndex = updated.length - 1;
            const previous = updated[lastIndex];
            const seed = previous?.role === 'assistant'
                ? previous
                : { role: 'assistant', text: '', status: '' };
            const nextMessage = updater(seed);

            if (previous?.role === 'assistant') {
                updated[lastIndex] = nextMessage;
                return updated;
            }

            return [...updated, nextMessage];
        });
    };

    const sendChat = async () => {
        const trimmed = aiInput.trim();
        const session = getSession();
        if (!trimmed || !session || aiLoading) return;

        const nextMessages = [...messages, { role: 'user', text: trimmed }];
        setAiMode('chat');
        setMessages([...nextMessages, { role: 'assistant', text: '', status: 'Thinking' }]);
        setAiInput('');
        setAiLoading(true);

        try {
            const localNow = new Date();
            const coords = await ensureLocation();
            const response = await fetch(`${API_ROOT}/chatstream`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    messages: nextMessages.map((message) => ({
                        role: message.role,
                        content: message.text,
                    })),
                    localNow: localNow.toISOString(),
                    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                    utcOffsetMinutes: -localNow.getTimezoneOffset(),
                    latitude: coords?.latitude,
                    longitude: coords?.longitude,
                }),
            });

            if (!response.ok) {
                const data = await response.json();
                throw new Error(data.error || 'Chat failed.');
            }

            if (!response.body) {
                throw new Error('Streaming is not available.');
            }

            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';

            while (true) {
                const { done, value } = await reader.read();
                if (done) {
                    break;
                }

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';

                for (const line of lines) {
                    const trimmedLine = line.trim();
                    if (!trimmedLine) {
                        continue;
                    }

                    let payload;
                    try {
                        payload = JSON.parse(trimmedLine);
                    } catch {
                        continue;
                    }

                    if (payload.type === 'delta' && payload.delta) {
                        updateStreamingAssistantMessage((previous) => ({
                            ...previous,
                            text: `${previous.text}${payload.delta}`,
                            status: '',
                        }));
                    } else if (payload.type === 'status' && payload.status) {
                        updateStreamingAssistantMessage((previous) => ({
                            ...previous,
                            status: payload.status,
                        }));
                        await waitForNextPaint();
                    } else if (payload.type === 'done') {
                        updateToken(payload.jwtToken);
                        updateStreamingAssistantMessage((previous) => ({
                            ...previous,
                            status: '',
                        }));
                        if (payload.calendarChanged) {
                            refreshCalendar();
                        }
                    } else if (payload.type === 'error') {
                        throw new Error(payload.error || 'Streaming failed.');
                    }
                }
            }

            const finalLine = buffer.trim();
            if (finalLine) {
                let payload;
                try {
                    payload = JSON.parse(finalLine);
                } catch {
                    payload = null;
                }

                if (payload?.type === 'done') {
                    updateToken(payload.jwtToken);
                } else if (payload?.type === 'error') {
                    throw new Error(payload.error || 'Streaming failed.');
                }
            }
        } catch (error) {
            setMessages((prev) => {
                const updated = [...prev];
                const lastIndex = updated.length - 1;
                const previous = updated[lastIndex];
                if (previous?.role === 'assistant' && previous.text === '') {
                    updated[lastIndex] = { role: 'assistant', text: error.message };
                    return updated;
                }

                return [...updated, { role: 'assistant', text: error.message }];
            });
        } finally {
            setAiLoading(false);
        }
    };

    const saveSuggestion = async (suggestion) => {
        const session = getSession();
        const key = suggestionKey(suggestion);
        if (!session || savedSuggestionKeys.includes(key) || aiLoading) {
            return;
        }

        setAiLoading(true);
        try {
            const startDate = dateWithSuggestedTime(currentDate, suggestion.suggestedTime || '');
            const endDate = new Date(startDate.getTime() + 60 * 60 * 1000);
            const response = await fetch(`${API_ROOT}/savecalendar`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    title: suggestion.title,
                    description: suggestion.description,
                    dueDate: startDate.toISOString(),
                    endDate: endDate.toISOString(),
                    source: 'manual',
                    isCompleted: false,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not save suggestion.');
            }

            updateToken(data.jwtToken);
            setSavedSuggestionKeys((prev) => [...prev, key]);
            refreshCalendar();
        } catch (error) {
            setMessages((prev) => [...prev, { role: 'assistant', text: error.message }]);
            setAiMode('chat');
        } finally {
            setAiLoading(false);
        }
    };

    const currentSession = isAuthenticated ? getSession() : null;
    const profileFirstName = accountSettings?.firstName || currentSession?.firstName || 'John';
    const profileLastName = accountSettings?.lastName || currentSession?.lastName || 'Doe';
    const profileInitials = `${profileFirstName.charAt(0)}${profileLastName.charAt(0)}`.toUpperCase();

    // Compute the effective background: theme override takes precedence over weather
    const effectiveBackground = toCssBackgroundImage(resolveEffectiveBackground(activeTheme, background));

    // Render the password reset screen directly when the reset route is active.
    const isResetRoute = window.location.pathname === '/resetpassword' &&
                         new URLSearchParams(window.location.search).has('token');
    if (isResetRoute) {
        return <ResetPasswordPage />;
    }

    return (
        <>
            {isAuthenticated && currentSession ? (
                <>
                    <div
                        className="main-layout"
                        style={{
                            '--bg-img': effectiveBackground || 'none',
                            backgroundSize: inferImageFit(activeTheme),
                        }}
                    >
                        <div className={`sidebar left-sidebar ${leftOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn right-align" onClick={() => setLeftOpen(!leftOpen)}>
                            <img src={leftOpen ? leftCloseIcon : leftOpenIcon} alt="Toggle Left" />
                        </button>

                        {leftOpen ? (
                            <div className="sidebar-content">
                                <div style={{ marginBottom: '20px' }}>
                                    <h2 style={{ margin: '0 0 5px 0' }}>{isSelectedToday ? 'Today' : 'Plan'}</h2>
                                    <p style={{ margin: 0, color: 'var(--btn-color)', fontWeight: 'bold' }}>{fullDateString}</p>
                                </div>

                                <nav style={{ display: 'flex', flexDirection: 'column', gap: '5px' }}>
                                    <button className="nav-item" onClick={() => openCalendarModal('plan')}><span className="nav-icon">Plan</span></button>
                                    <button className="nav-item" onClick={() => openCalendarModal('event')}><span className="nav-icon">Event</span></button>
                                    <button className="nav-item" onClick={() => openCalendarModal('task')}><span className="nav-icon">Task</span></button>
                                    <hr style={{ border: '0', borderTop: '1px solid #2c2c3e', margin: '10px 0' }} />
                                    <button className="nav-item" onClick={() => openCalendarModal('import')}><span className="nav-icon">Import</span></button>
                                    <button className="nav-item" onClick={() => openAccountModal('settings')}><span className="nav-icon">Settings</span></button>
                                </nav>

                                <button
                                    type="button"
                                    className="profile-summary-button"
                                    onClick={() => openAccountModal('account')}
                                >
                                    <div className="profile-summary-avatar">
                                        {profileInitials}
                                    </div>
                                    <div className="profile-summary-copy">
                                        <span className="profile-summary-name">{`${profileFirstName} ${profileLastName}`}</span>
                                        <span className="profile-summary-email">{accountSettings?.email || ''}</span>
                                    </div>
                                </button>
                                <div className="logout-container">
                                    <button onClick={logout} className="logout-btn">
                                        Logout
                                    </button>
                                </div>
                            </div>
                        ) : (
                            <div className="vertical-date">
                                {verticalDateString}
                            </div>
                        )}
                    </div>

                    <div className="center-content">
                        <div className="calendar-wrapper">
                            <Calendar
                                singleMonth={false}
                                setBackground={setBackground}
                                session={currentSession}
                                apiRoot={API_ROOT}
                                onSessionRefresh={updateToken}
                                refreshKey={calendarRefreshKey}
                                modalIntent={calendarModalIntent}
                                reminderDefaults={accountSettings?.reminderDefaults}
                                onSelectedDateChange={setSelectedDate}
                                searchQuery={searchQuery}
                                setSearchQuery={setSearchQuery}
                                onSearchMetaChange={setSearchMeta}
                            />
                        </div>
                    </div>

                    <div className={`sidebar right-sidebar ${rightOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn left-align" onClick={() => setRightOpen(!rightOpen)}>
                            <img src={rightOpen ? rightCloseIcon : rightOpenIcon} alt="Toggle Right" />
                        </button>
                        {rightOpen && (
                            <div className="sidebar-content ai-panel">
                                <div className="ai-panel-header">
                                    <h2>AI Assistant</h2>
                                </div>
                                <div className="ai-hero-card">
                                    <h3>Schedule ideas with context</h3>
                                    <div className="ai-location-row">
                                        <span className="ai-location-text">{locationNotice}</span>
                                        <button
                                            className="ai-icon-btn"
                                            type="button"
                                            onClick={ensureLocation}
                                            disabled={isLocating}
                                            aria-label="Refresh location"
                                        >
                                            {isLocating ? '...' : <LocationIcon />}
                                        </button>
                                    </div>
                                    <textarea
                                        className="ai-input ai-preferences"
                                        placeholder="Suggestion preferences"
                                        value={suggestionPreferences}
                                        onChange={(event) => setSuggestionPreferences(event.target.value)}
                                    />
                                    <button
                                        className="ai-send-btn ai-suggest-btn"
                                        onClick={loadSuggestions}
                                        disabled={aiLoading}
                                    >
                                        <SparklesIcon />
                                        {aiLoading && aiMode === 'suggestions'
                                            ? 'Loading...'
                                            : `Suggest events for ${currentDate.getMonth() + 1}/${currentDate.getDate()}/${currentDate.getFullYear()}`}
                                    </button>
                                </div>

                                {aiMode === 'suggestions' ? (
                                    <>
                                        <div className="ai-main-shell suggestions-mode">
                                            <div className="ai-section ai-suggestions active">
                                                <div className="ai-section-header">
                                                    <h3>Suggestions</h3>
                                                    <span>{suggestions.length} ready</span>
                                                </div>
                                                <div className="ai-suggestion-list">
                                                    {suggestions.length > 0 ? (
                                                        suggestions.map((suggestion, index) => {
                                                            const key = suggestionKey(suggestion);
                                                            const isSaved = savedSuggestionKeys.includes(key);

                                                            return (
                                                                <div
                                                                    key={`${key}-${index}`}
                                                                    className="ai-suggestion-card"
                                                                >
                                                                    <div className="ai-suggestion-copy">
                                                                        <div className="ai-suggestion-time">
                                                                            {suggestion.suggestedTime || 'No time'}
                                                                        </div>
                                                                        <div className="ai-suggestion-title">{suggestion.title}</div>
                                                                        <div className="ai-suggestion-description">{suggestion.description}</div>
                                                                    </div>
                                                                    <button
                                                                        type="button"
                                                                        className={`ai-add-btn ${isSaved ? 'saved' : ''}`}
                                                                        onClick={() => saveSuggestion(suggestion)}
                                                                        disabled={isSaved || aiLoading}
                                                                        aria-label={isSaved ? 'Already added' : 'Add to calendar'}
                                                                    >
                                                                        {isSaved ? '\u2713' : '+'}
                                                                    </button>
                                                                </div>
                                                            );
                                                        })
                                                    ) : (
                                                        <div className="ai-empty-state">
                                                            Use the button above and I&apos;ll fill this panel with ideas for today.
                                                        </div>
                                                    )}
                                                </div>
                                            </div>
                                        </div>

                                        <div className="ai-composer">
                                            <textarea
                                                className="ai-input ai-message-input"
                                                placeholder="Message the assistant..."
                                                value={aiInput}
                                                onChange={(event) => setAiInput(event.target.value)}
                                                onKeyDown={(event) => {
                                                    if (event.key === 'Enter' && !event.shiftKey) {
                                                        event.preventDefault();
                                                        sendChat();
                                                    }
                                                }}
                                            />
                                            <button className="ai-send-btn ai-composer-send" onClick={sendChat} disabled={aiLoading}>
                                                {aiLoading && aiMode === 'chat' ? '...' : <SendIcon />}
                                            </button>
                                        </div>
                                    </>
                                ) : (
                                    <div className="ai-chat-shell">
                                        <div className="ai-main-shell chat-mode">
                                            <div className="ai-section ai-chat active">
                                                <div className="ai-chat-feed">
                                                    {messages.map((message, index) => (
                                                        <div
                                                            key={`${message.role}-${index}`}
                                                            className={`ai-message ${message.role === 'user' ? 'user' : 'assistant'}${message.role === 'assistant' && !message.text && message.status ? ' status-loading' : ''}`}
                                                        >
                                                            {message.role === 'assistant'
                                                                ? (
                                                                    message.text
                                                                        ? renderAssistantMessage(message.text)
                                                                        : message.status
                                                                            ? <span className="ai-status-text">{displayAssistantStatus(message.status)}</span>
                                                                            : ''
                                                                )
                                                                : message.text}
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>
                                        </div>

                                        <div className="ai-composer ai-composer-inline">
                                            <textarea
                                                className="ai-input ai-message-input"
                                                placeholder="Message the assistant..."
                                                value={aiInput}
                                                onChange={(event) => setAiInput(event.target.value)}
                                                onKeyDown={(event) => {
                                                    if (event.key === 'Enter' && !event.shiftKey) {
                                                        event.preventDefault();
                                                        sendChat();
                                                    }
                                                }}
                                            />
                                            <button className="ai-send-btn ai-composer-send" onClick={sendChat} disabled={aiLoading}>
                                                {aiLoading && aiMode === 'chat' ? '...' : <SendIcon />}
                                            </button>
                                        </div>
                                    </div>
                                )}
                            </div>
                        )}
                        </div>
                    </div>
                    {accountModalOpen && (
                        <div className="account-modal-overlay" onClick={() => setAccountModalOpen(false)}>
                            <div className="account-modal" onClick={(event) => event.stopPropagation()}>
                            <div className="account-modal-header">
                                <div>
                                    <div className="account-modal-kicker">Account</div>
                                    <h2>Account & Settings</h2>
                                </div>
                                <button type="button" className="account-close-btn" onClick={() => setAccountModalOpen(false)}>
                                    Close
                                </button>
                            </div>

                            <div className="account-modal-tabs">
                                <button
                                    type="button"
                                    className={`account-tab-btn ${accountTab === 'account' ? 'active' : ''}`}
                                    onClick={() => setAccountTab('account')}
                                >
                                    Account
                                </button>
                                <button
                                    type="button"
                                    className={`account-tab-btn ${accountTab === 'settings' ? 'active' : ''}`}
                                    onClick={() => setAccountTab('settings')}
                                >
                                    Settings
                                </button>
                                <button
                                    type="button"
                                    className={`account-tab-btn ${accountTab === 'themes' ? 'active' : ''}`}
                                    onClick={() => {
                                        setAccountTab('themes');
                                        syncThemeDraft(cloneThemePack(activeTheme));
                                    }}
                                >
                                    Themes
                                </button>
                            </div>

                            <div className="account-modal-body">
                                <div className="account-hero">
                                    <div className="account-avatar-shell">
                                        {pendingAvatarUrl !== null && pendingAvatarUrl !== 'REMOVED' ? (
                                            <img src={pendingAvatarUrl} alt="Profile" className="account-avatar account-avatar-img" />
                                        ) : (pendingAvatarUrl !== 'REMOVED' && avatarUrl) ? (
                                            <img src={avatarUrl} alt="Profile" className="account-avatar account-avatar-img" />
                                        ) : (
                                            <div className="account-avatar">{profileInitials}</div>
                                        )}
                                        <label className="account-avatar-btn" style={{ cursor: 'pointer' }}>
                                            Upload picture
                                            <input
                                                type="file"
                                                accept={AVATAR_ACCEPT}
                                                style={{ display: 'none' }}
                                                onChange={async (event) => {
                                                    const file = event.target.files?.[0];
                                                    event.target.value = '';
                                                    if (!file) return;

                                                    try {
                                                        setAccountFeedback('');
                                                        validateAvatarFile(file);
                                                        const nextAvatarUrl = await readFileAsDataUrl(file);
                                                        setPendingAvatarUrl(nextAvatarUrl);
                                                    } catch (error) {
                                                        setAccountFeedback(error.message);
                                                    }
                                                }}
                                            />
                                        </label>
                                        {(avatarUrl || pendingAvatarUrl) && pendingAvatarUrl !== 'REMOVED' && (
                                            <button type="button" className="account-avatar-remove-btn" onClick={() => { setPendingAvatarUrl('REMOVED'); }}>
                                                Remove picture
                                            </button>
                                        )}
                                    </div>
                                    <div className="account-hero-copy">
                                        <h3>{`${profileFirstName} ${profileLastName}`}</h3>
                                        <p>{accountSettings?.email || 'Loading email...'}</p>
                                        {accountSettings?.pendingEmail && (
                                            <div className="account-pending-badge">
                                                Pending email: {accountSettings.pendingEmail}
                                            </div>
                                        )}
                                    </div>
                                </div>

                                {accountLoading ? (
                                    <div className="account-feedback-panel">Loading account details...</div>
                                ) : (
                                    <>
                                        {accountTab === 'account' ? (
                                            <div className="account-section-stack">
                                                <div className="account-section-card">
                                                    <h3>Profile</h3>
                                                    <div className="account-field-row">
                                                        <label className="account-field">
                                                            <span>First name</span>
                                                            <input
                                                                value={accountDraft.firstName || ''}
                                                                onChange={(event) => setAccountDraft((prev) => ({ ...prev, firstName: event.target.value }))}
                                                            />
                                                        </label>
                                                        <label className="account-field">
                                                            <span>Last name</span>
                                                            <input
                                                                value={accountDraft.lastName || ''}
                                                                onChange={(event) => setAccountDraft((prev) => ({ ...prev, lastName: event.target.value }))}
                                                            />
                                                        </label>
                                                    </div>
                                                </div>

                                                <div className="account-section-card">
                                                    <h3>Email</h3>
                                                    <label className="account-field">
                                                        <span>Current email</span>
                                                        <input value={accountSettings?.email || ''} disabled />
                                                    </label>
                                                    <label className="account-field">
                                                        <span>New email</span>
                                                        <input
                                                            value={emailDraft}
                                                            onChange={(event) => setEmailDraft(event.target.value)}
                                                            placeholder="name@example.com"
                                                        />
                                                    </label>
                                                    <div className="account-inline-actions">
                                                        <button type="button" className="account-primary-btn" onClick={requestEmailChange} disabled={accountSaving || !emailDraft.trim()}>
                                                            {accountSaving ? 'Sending...' : 'Verify new email'}
                                                        </button>
                                                    </div>
                                                    {emailFeedback && <div className="account-feedback-panel">{emailFeedback}</div>}
                                                </div>
                                            </div>
                                        ) : accountTab === 'themes' ? (
                                            /* ── THEMES TAB ─────────────────────────────────────────── */
                                            <div className="account-section-stack">
                                                <div className="account-section-card">
                                                    <div className="theme-library-header">
                                                        <div>
                                                            <h3>Featured Weather Photo Themes</h3>
                                                            <p className="account-section-copy">Photo-based theme packs for weather-aware backgrounds.</p>
                                                        </div>
                                                    </div>
                                                    <div className="featured-theme-grid">
                                                        {featuredWeatherThemes.map((theme) => {
                                                            const isSelected = themeDraft?.id === theme.id;
                                                            const previewBackground = inferThemePreview(theme) || theme.preview;
                                                            return (
                                                                <button
                                                                    key={theme.id}
                                                                    type="button"
                                                                    className={`featured-theme-card${isSelected ? ' selected' : ''}`}
                                                                    onClick={() => syncThemeDraft(theme)}
                                                                >
                                                                    <div
                                                                        className="featured-theme-media"
                                                                        style={{ backgroundImage: previewBackground }}
                                                                    >
                                                                        <span className="featured-theme-chip">
                                                                            {theme.id === 'default' ? 'Default' : theme.id === 'custom' ? 'Custom' : 'Featured'}
                                                                        </span>
                                                                    </div>
                                                                    <div className="featured-theme-copy">
                                                                        <span className="featured-theme-name">{theme.name}</span>
                                                                        <span className="featured-theme-desc">{theme.description}</span>
                                                                    </div>
                                                                </button>
                                                            );
                                                        })}
                                                    </div>
                                                </div>

                                                <div className="account-section-card">
                                                    <div className="theme-library-header">
                                                        <div>
                                                            <h3>Your Saved & Shared Themes</h3>
                                                            <p className="account-section-copy">Save your own packs, import shared themes, and manage them from this library.</p>
                                                        </div>
                                                        <div className="theme-library-actions">
                                                            <button
                                                                type="button"
                                                                className="account-secondary-btn"
                                                                onClick={() => themeImportInputRef.current?.click()}
                                                            >
                                                                Import from File
                                                            </button>
                                                            <button
                                                                type="button"
                                                                className="theme-icon-btn"
                                                                onClick={() => openThemeShareDialog(themeDraft)}
                                                                disabled={!themeDraft}
                                                                title="Share theme"
                                                                aria-label="Share theme"
                                                            >
                                                                <img src={shareIcon} alt="" />
                                                            </button>
                                                            <input
                                                                ref={themeImportInputRef}
                                                                type="file"
                                                                accept=".json,.calpp-theme.json,application/json"
                                                                style={{ display: 'none' }}
                                                                onChange={async (event) => {
                                                                    const file = event.target.files?.[0];
                                                                    event.target.value = '';
                                                                    await importThemePackFile(file);
                                                                }}
                                                            />
                                                        </div>
                                                    </div>

                                                    <div className="theme-import-row">
                                                        <label className="account-field theme-import-field">
                                                            <span>Import a shared theme</span>
                                                            <input
                                                                value={themeImportValue}
                                                                onChange={(event) => setThemeImportValue(event.target.value)}
                                                                placeholder="Paste a share link or 6-digit code"
                                                            />
                                                        </label>
                                                        <div className="account-inline-actions">
                                                            <button
                                                                type="button"
                                                                className="account-primary-btn"
                                                                onClick={async () => {
                                                                    try {
                                                                        await importSharedTheme(themeImportValue);
                                                                    } catch (error) {
                                                                        setAccountFeedback(error.message);
                                                                    }
                                                                }}
                                                                disabled={!themeImportValue.trim()}
                                                            >
                                                                Import & Apply
                                                            </button>
                                                        </div>
                                                    </div>

                                                    {savedThemePacks.length > 0 ? (
                                                        <div className="saved-theme-grid">
                                                            {savedThemePacks.map((pack) => {
                                                                const isSelected = themePackMatches(themeDraft, pack);
                                                                const previewBackground = inferThemePreview(pack) || pack.preview;
                                                                return (
                                                                    <div
                                                                        key={pack.sharedThemeId || pack.id}
                                                                        className={`saved-theme-card${isSelected ? ' selected' : ''}`}
                                                                        onClick={() => syncThemeDraft(pack)}
                                                                        onKeyDown={(event) => {
                                                                            if (event.key === 'Enter' || event.key === ' ') {
                                                                                event.preventDefault();
                                                                                syncThemeDraft(pack);
                                                                            }
                                                                        }}
                                                                        role="button"
                                                                        tabIndex={0}
                                                                    >
                                                                        <div
                                                                            className="saved-theme-swatch"
                                                                            style={{ background: previewBackground }}
                                                                        />
                                                                        <div className="saved-theme-copy">
                                                                            <span className="saved-theme-name">{pack.name}</span>
                                                                            <span className="saved-theme-meta">{pack.authorLabel || 'By you'}</span>
                                                                            <span className="saved-theme-desc">{pack.description || 'Custom theme pack'}</span>
                                                                        </div>
                                                                        <div className="saved-theme-actions">
                                                                            <button
                                                                                type="button"
                                                                                className="theme-icon-btn"
                                                                                title="Share theme"
                                                                                aria-label={`Share ${pack.name}`}
                                                                                onClick={(event) => {
                                                                                    event.stopPropagation();
                                                                                    openThemeShareDialog(pack);
                                                                                }}
                                                                            >
                                                                                <img src={shareIcon} alt="" />
                                                                            </button>
                                                                            <button
                                                                                type="button"
                                                                                className="account-secondary-btn"
                                                                                onClick={(event) => {
                                                                                    event.stopPropagation();
                                                                                    deleteThemePack(pack);
                                                                                }}
                                                                            >
                                                                                Delete
                                                                            </button>
                                                                        </div>
                                                                    </div>
                                                                );
                                                            })}
                                                        </div>
                                                    ) : (
                                                        <p className="theme-empty-state">No saved or imported themes yet.</p>
                                                    )}
                                                </div>

                                                {isEditableThemePack(themeDraft) && (
                                                    <div className="account-section-card">
                                                        <div className="theme-preview-card">
                                                            <div className="theme-library-header">
                                                                <div>
                                                                    <h3>Preview</h3>
                                                                    <p className="account-section-copy">Live preview of the current pack while you edit it.</p>
                                                                </div>
                                                                <div className="theme-library-actions">
                                                                    <button
                                                                        type="button"
                                                                        className="account-primary-btn"
                                                                        onClick={saveThemePackDraft}
                                                                        disabled={!themeDraft}
                                                                    >
                                                                        Save Pack
                                                                    </button>
                                                                </div>
                                                            </div>
                                                            <div
                                                                className="theme-preview-strip"
                                                                style={{ backgroundImage: draftPreviewBackground }}
                                                            >
                                                                <div className="theme-preview-overlay">
                                                                    <button
                                                                        type="button"
                                                                        className="theme-preview-btn"
                                                                        style={resolveThemeButtonStyle(themeDraft)}
                                                                    >
                                                                        Button Preview
                                                                    </button>
                                                                    <span className="theme-preview-label">{themeDraft?.name || 'Custom Photo Pack'}</span>
                                                                </div>
                                                            </div>
                                                        </div>
                                                    </div>
                                                )}

                                                {isEditableThemePack(themeDraft) && (
                                                    <div className="account-section-card">
                                                        <h3>Customize</h3>

                                                        {/* Button color picker */}
                                                        <div className="theme-custom-row">
                                                            <label className="theme-color-label">
                                                                <span>Button color</span>
                                                                <div className="theme-color-row">
                                                                    <input
                                                                        type="color"
                                                                        className="theme-color-input"
                                                                        value={themeDraft.btnColor || '#60a5fa'}
                                                                        onChange={(e) => setThemeDraft((prev) => ({ ...prev, btnColor: e.target.value, btnGradient: undefined }))}
                                                                    />
                                                                    <input
                                                                        type="text"
                                                                        className="theme-color-text"
                                                                        value={themeDraft.btnColor || '#60a5fa'}
                                                                        maxLength={7}
                                                                        onChange={(e) => {
                                                                            const v = e.target.value;
                                                                            if (/^#[0-9a-fA-F]{0,6}$/.test(v)) {
                                                                                setThemeDraft((prev) => ({ ...prev, btnColor: v, btnGradient: undefined }));
                                                                            }
                                                                        }}
                                                                    />
                                                                </div>
                                                            </label>
                                                        </div>

                                                        <div className="theme-custom-row">
                                                            <label className="theme-color-label">
                                                                <span>Button text color</span>
                                                                <div className="theme-color-row">
                                                                    <input
                                                                        type="color"
                                                                        className="theme-color-input"
                                                                        value={themeDraft.btnTextColor || getContrastTextColor(themeDraft.btnColor || '#60a5fa')}
                                                                        onChange={(e) => setThemeDraft((prev) => ({ ...prev, btnTextColor: e.target.value }))}
                                                                    />
                                                                    <input
                                                                        type="text"
                                                                        className="theme-color-text"
                                                                        value={themeDraft.btnTextColor || getContrastTextColor(themeDraft.btnColor || '#60a5fa')}
                                                                        maxLength={7}
                                                                        onChange={(e) => {
                                                                            const v = e.target.value;
                                                                            if (/^#[0-9a-fA-F]{0,6}$/.test(v)) {
                                                                                setThemeDraft((prev) => ({ ...prev, btnTextColor: v }));
                                                                            }
                                                                        }}
                                                                    />
                                                                </div>
                                                            </label>
                                                        </div>

                                                        <div className="theme-custom-row">
                                                            <label className="theme-color-label">
                                                                <span>Button gradient</span>
                                                                <div className="theme-color-row">
                                                                    {[0, 1, 2].map((index) => (
                                                                        <input
                                                                            key={index}
                                                                            type="color"
                                                                            className="theme-color-input"
                                                                            value={themeDraft.btnGradient?.colors?.[index] || themeDraft.btnColor || ACCENT_SWATCHES[index] || '#60a5fa'}
                                                                            onChange={(event) => setThemeDraft((prev) => {
                                                                                const nextColors = [...(prev.btnGradient?.colors || [prev.btnColor || '#60a5fa', '#2563eb', '#7dd3fc'])];
                                                                                nextColors[index] = event.target.value;
                                                                                return {
                                                                                    ...prev,
                                                                                    btnGradient: {
                                                                                        angle: Number.isFinite(Number(prev.btnGradient?.angle)) ? Number(prev.btnGradient.angle) : 135,
                                                                                        colors: nextColors.slice(0, 3),
                                                                                    },
                                                                                };
                                                                            })}
                                                                        />
                                                                    ))}
                                                                </div>
                                                            </label>
                                                            <label className="account-field" style={{ marginTop: 8 }}>
                                                                <span>Gradient angle</span>
                                                                <input
                                                                    type="range"
                                                                    min="0"
                                                                    max="360"
                                                                    value={Number(themeDraft.btnGradient?.angle ?? 135)}
                                                                    onChange={(event) => setThemeDraft((prev) => ({
                                                                        ...prev,
                                                                        btnGradient: {
                                                                            angle: Number(event.target.value),
                                                                            colors: [...(prev.btnGradient?.colors || [prev.btnColor || '#60a5fa', '#2563eb', '#7dd3fc'])].slice(0, 3),
                                                                        },
                                                                    }))}
                                                                />
                                                            </label>
                                                        </div>

                                                        {/* Background image mode toggle */}
                                                        <div className="theme-bg-mode-row">
                                                            <button
                                                                type="button"
                                                                className={`account-tab-btn${customBgMode === 'gradient' ? ' active' : ''}`}
                                                                style={{ fontSize: '12px', padding: '6px 14px' }}
                                                                onClick={() => {
                                                                    setCustomBgMode('gradient');
                                                                    setThemeDraft((prev) => ({
                                                                        ...prev,
                                                                        backgroundMode: 'gradient',
                                                                    }));
                                                                }}
                                                            >
                                                                Gradient Background
                                                            </button>
                                                            <button
                                                                type="button"
                                                                className={`account-tab-btn${customBgMode === 'universal' ? ' active' : ''}`}
                                                                style={{ fontSize: '12px', padding: '6px 14px' }}
                                                                onClick={() => {
                                                                    setCustomBgMode('universal');
                                                                    setThemeDraft((prev) => ({
                                                                        ...prev,
                                                                        backgroundMode: 'universal',
                                                                    }));
                                                                }}
                                                            >
                                                                Single background
                                                            </button>
                                                            <button
                                                                type="button"
                                                                className={`account-tab-btn${customBgMode === 'perScene' ? ' active' : ''}`}
                                                                style={{ fontSize: '12px', padding: '6px 14px' }}
                                                                onClick={() => {
                                                                    setCustomBgMode('perScene');
                                                                    setThemeDraft((prev) => ({
                                                                        ...prev,
                                                                        backgroundMode: 'perScene',
                                                                    }));
                                                                }}
                                                            >
                                                                Per-weather scenes
                                                            </button>
                                                        </div>

                                                        {customBgMode === 'gradient' ? (
                                                            <div className="theme-gradient-summary-card">
                                                                <div
                                                                    className="theme-gradient-summary-preview"
                                                                    style={{ backgroundImage: buildGradientCss(themeDraft.gradient) }}
                                                                />
                                                                <div className="theme-gradient-summary-copy">
                                                                    <strong>Custom Gradient</strong>
                                                                    <span>{`${themeDraft.gradient?.type || 'linear'} / ${draftGradientStops.length} stop${draftGradientStops.length === 1 ? '' : 's'}`}</span>
                                                                </div>
                                                                <button
                                                                    type="button"
                                                                    className="account-primary-btn"
                                                                    onClick={() => setGradientEditorOpen(true)}
                                                                >
                                                                    Edit Gradient
                                                                </button>
                                                            </div>
                                                        ) : customBgMode === 'universal' ? (
                                                            <div className="theme-bg-upload-row">
                                                                <label className="theme-bg-upload-label">
                                                                    <div className="theme-bg-thumb" style={{
                                                                        backgroundImage: themeDraft.images?.universal ? `url(${themeDraft.images.universal})` : 'none',
                                                                    }}>
                                                                        {!themeDraft.images?.universal && <span className="theme-bg-placeholder">No image</span>}
                                                                    </div>
                                                                    <div className="theme-bg-info">
                                                                        <span className="theme-bg-title">Background image</span>
                                                                        <span className="theme-bg-hint">Used for all weather conditions</span>
                                                                        <span className="theme-bg-hint">PNG or JPEG, &lt; 4 MB</span>
                                                                    </div>
                                                                    <input
                                                                        type="file"
                                                                        accept="image/png,image/jpeg,image/webp"
                                                                        style={{ display: 'none' }}
                                                                    onChange={async (e) => {
                                                                            const file = e.target.files?.[0];
                                                                            e.target.value = '';
                                                                            if (!file) return;
                                                                            if (file.size > 4 * 1024 * 1024) { setAccountFeedback('Background image must be under 4 MB.'); return; }
                                                                            try {
                                                                                const session = getSession();
                                                                                if (!session) {
                                                                                    throw new Error('Please log in again to upload this image.');
                                                                                }
                                                                                const url = await uploadThemeImageFile(file, session, 'theme-images', `${themeDraft?.id || 'theme'}-universal.${file.name.split('.').pop() || 'png'}`);
                                                                                setThemeDraft((prev) => ({ ...prev, images: { ...prev.images, universal: url } }));
                                                                            } catch (error) {
                                                                                setAccountFeedback(error.message);
                                                                            }
                                                                        }}
                                                                    />
                                                                    <button
                                                                        type="button"
                                                                        className="account-secondary-btn"
                                                                        style={{ pointerEvents: 'none' }}
                                                                    >
                                                                        Choose image
                                                                    </button>
                                                                </label>
                                                                {themeDraft.images?.universal && (
                                                                    <button
                                                                        type="button"
                                                                        className="account-secondary-btn"
                                                                        onClick={() => setThemeDraft((prev) => ({ ...prev, images: {} }))}
                                                                    >
                                                                        Remove image
                                                                    </button>
                                                                )}
                                                                {/* Image fit selector */}
                                                                {themeDraft.images?.universal && (
                                                                    <label className="account-field" style={{ marginTop: 8 }}>
                                                                        <span>Image fit</span>
                                                                        <select
                                                                            value={themeDraft.imageFit || 'cover'}
                                                                            onChange={(e) => setThemeDraft((prev) => ({ ...prev, imageFit: e.target.value }))}
                                                                        >
                                                                            <option value="cover">Cover (fill &amp; crop)</option>
                                                                            <option value="contain">Contain (show full image)</option>
                                                                            <option value="center">Center (no scaling)</option>
                                                                        </select>
                                                                    </label>
                                                                )}
                                                            </div>
                                                        ) : (
                                                            <div className="theme-scene-grid">
                                                                {WEATHER_SLOTS.map(({ key, label }) => {
                                                                    const img = themeDraft.images?.[key];
                                                                    return (
                                                                        <label key={key} className="theme-scene-cell">
                                                                            <div className="theme-scene-thumb" style={{
                                                                                backgroundImage: img ? `url(${img})` : 'none',
                                                                            }}>
                                                                                {!img && <span className="theme-bg-placeholder">+</span>}
                                                                            </div>
                                                                            <span className="theme-scene-label">{label}</span>
                                                                            <input
                                                                                type="file"
                                                                                accept="image/png,image/jpeg,image/webp"
                                                                                style={{ display: 'none' }}
                                                                                onChange={async (e) => {
                                                                                    const file = e.target.files?.[0];
                                                                                    e.target.value = '';
                                                                                    if (!file) return;
                                                                                    if (file.size > 4 * 1024 * 1024) { setAccountFeedback('Image must be under 4 MB.'); return; }
                                                                                    try {
                                                                                        const session = getSession();
                                                                                        if (!session) {
                                                                                            throw new Error('Please log in again to upload this image.');
                                                                                        }
                                                                                        const ext = file.name.split('.').pop() || 'png';
                                                                                        const url = await uploadThemeImageFile(file, session, 'theme-gallery', `${themeDraft?.id || 'theme'}-${key}.${ext}`);
                                                                                        setThemeDraft((prev) => ({ ...prev, images: { ...prev.images, [key]: url } }));
                                                                                    } catch (error) {
                                                                                        setAccountFeedback(error.message);
                                                                                    }
                                                                                }}
                                                                            />
                                                                        </label>
                                                                    );
                                                                })}
                                                            </div>
                                                        )}
                                                    </div>
                                                )}

                                            </div>
                                        ) : (
                                            <div className="account-section-stack">
                                                <div className="account-section-card">
                                                    <h3>Reminder defaults</h3>
                                                    <label className="account-check-row">
                                                        <input
                                                            type="checkbox"
                                                            checked={accountDraft.reminderDefaults?.reminderEnabled === true}
                                                            onChange={(event) => setAccountDraft((prev) => ({
                                                                ...prev,
                                                                reminderDefaults: {
                                                                    ...prev.reminderDefaults,
                                                                    reminderEnabled: event.target.checked,
                                                                },
                                                            }))}
                                                        />
                                                        <span>Enable reminders by default for new items</span>
                                                    </label>
                                                    <label className="account-field">
                                                        <span>Default reminder timing</span>
                                                        <select
                                                            value={Number(accountDraft.reminderDefaults?.reminderMinutesBefore || 30)}
                                                            disabled={accountDraft.reminderDefaults?.reminderEnabled !== true}
                                                            onChange={(event) => setAccountDraft((prev) => ({
                                                                ...prev,
                                                                reminderDefaults: {
                                                                    ...prev.reminderDefaults,
                                                                    reminderMinutesBefore: Number(event.target.value),
                                                                },
                                                            }))}
                                                        >
                                                            {REMINDER_OPTIONS.map((option) => (
                                                                <option key={option.value} value={option.value}>{option.label}</option>
                                                            ))}
                                                        </select>
                                                    </label>
                                                </div>

                                                <div className="account-section-card">
                                                    <h3>Calendar data</h3>
                                                    <p className="account-section-copy">
                                                        Import and connected calendar tools stay in the calendar import modal. You can also export your current calendar as an iCal file here.
                                                    </p>
                                                    <label className="account-field">
                                                        <span>Subscription feed URL</span>
                                                        <input value={accountSettings?.calendarFeedUrl || ''} readOnly />
                                                    </label>
                                                    <div className="account-inline-actions account-inline-actions-wrap">
                                                        <button type="button" className="account-secondary-btn" onClick={() => copyCalendarFeed(false)}>
                                                            Copy feed URL
                                                        </button>
                                                        <button type="button" className="account-secondary-btn" onClick={() => copyCalendarFeed(true)}>
                                                            Copy webcal link
                                                        </button>
                                                        <button type="button" className="account-secondary-btn" onClick={regenerateCalendarFeed} disabled={accountSaving}>
                                                            Regenerate link
                                                        </button>
                                                    </div>
                                                    <div className="account-inline-actions">
                                                        <button type="button" className="account-primary-btn" onClick={exportCalendar}>
                                                            Export iCal
                                                        </button>
                                                    </div>
                                                </div>
                                            </div>
                                        )}

                                        {accountFeedback && <div className="account-feedback-panel">{accountFeedback}</div>}
                                    </>
                                )}
                            </div>

                            <div className="account-modal-actions">
                                <button type="button" className="account-secondary-btn" onClick={() => setAccountModalOpen(false)}>
                                    Close
                                </button>
                                {accountTab === 'themes' ? (
                                    <>
                                        <button
                                            type="button"
                                            className="account-secondary-btn"
                                            onClick={() => {
                                                const reset = DEFAULT_THEME;
                                                setActiveTheme(reset);
                                                setThemeDraft(reset);
                                                persistTheme(reset);
                                            }}
                                        >
                                            Reset to default
                                        </button>
                                        <button
                                            type="button"
                                            className="account-primary-btn"
                                            disabled={!themeDraft}
                                            onClick={() => {
                                                if (!themeDraft) return;
                                                setActiveTheme(themeDraft);
                                                persistTheme(themeDraft);
                                                setAccountFeedback('Theme applied.');
                                            }}
                                        >
                                            Apply theme
                                        </button>
                                    </>
                                ) : (
                                    <button type="button" className="account-primary-btn" onClick={saveAccountSettings} disabled={accountSaving || accountLoading}>
                                        {accountSaving ? 'Saving...' : 'Save changes'}
                                    </button>
                                )}
                            </div>
                            </div>
                        </div>
                    )}
                    {gradientEditorModal}
                    {themeShareModal}
                </>
            ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
            )}
        </>
    );
}

export default App;




