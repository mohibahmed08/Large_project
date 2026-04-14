// @ts-nocheck
import './App.css';
import { useEffect, useRef, useState } from 'react';

import Calendar from './Calendar';
import Login, { ResetPasswordPage } from './login';
import {
    getContrastTextColor,
    hexToRgbString,
    normalizeHexColor,
    resolveEffectiveBackground,
} from './themeUtils';
import { WEATHER_SLOTS } from './weatherScenes';
import { requestWeatherLocation } from './weatherLocation.js';

import leftOpenIcon from './icons/panel-left-open.svg';
import leftCloseIcon from './icons/panel-left-close.svg';
import rightOpenIcon from './icons/panel-right-open.svg';
import rightCloseIcon from './icons/panel-right-close.svg';

const RAW_API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';
const API_ROOT = RAW_API_BASE.endsWith('/api') ? RAW_API_BASE : `${RAW_API_BASE}/api`;

// ── Theme system ──────────────────────────────────────────────────────────────
const THEME_STORAGE_KEY = 'calpp_theme';

const PRESET_THEMES = [
    {
        id: 'default',
        name: 'Default',
        description: 'Dynamic weather backgrounds',
        preview: 'linear-gradient(135deg,#1e3a5f 0%,#3b82f6 100%)',
        btnColor: '#60a5fa',
        images: null,
    },
    {
        id: 'aurora',
        name: 'Aurora',
        description: 'Deep purples & cool blues',
        preview: 'linear-gradient(135deg,#0d0221 0%,#5a0d82 50%,#1a6b8a 100%)',
        btnColor: '#a855f7',
        images: { universal: 'https://images.unsplash.com/photo-1531366936337-7c912a4589a7?w=1920&q=80&auto=format&fit=crop' },
    },
    {
        id: 'forest',
        name: 'Forest',
        description: 'Lush greens & earthy tones',
        preview: 'linear-gradient(135deg,#0f2a0f 0%,#2d6a2d 50%,#1a3a1a 100%)',
        btnColor: '#22c55e',
        images: { universal: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=1920&q=80&auto=format&fit=crop' },
    },
    {
        id: 'desert',
        name: 'Desert Dusk',
        description: 'Warm oranges & sandy hues',
        preview: 'linear-gradient(135deg,#7c2d12 0%,#ea580c 50%,#fbbf24 100%)',
        btnColor: '#f97316',
        images: { universal: 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?w=1920&q=80&auto=format&fit=crop' },
    },
    {
        id: 'ocean',
        name: 'Ocean',
        description: 'Deep sea blues & teals',
        preview: 'linear-gradient(135deg,#0c1a40 0%,#0e4d6e 50%,#0ea5e9 100%)',
        btnColor: '#06b6d4',
        images: { universal: 'https://images.unsplash.com/photo-1505118380757-91f5f5632de0?w=1920&q=80&auto=format&fit=crop' },
    },
    {
        id: 'midnight',
        name: 'Midnight',
        description: 'Deep blacks & silver accents',
        preview: 'linear-gradient(135deg,#0a0a0a 0%,#1c1c2e 50%,#2d2d44 100%)',
        btnColor: '#94a3b8',
        images: { universal: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=1920&q=80&auto=format&fit=crop' },
    },
    {
        id: 'custom',
        name: 'Custom',
        description: 'Your own colors & images',
        preview: 'linear-gradient(135deg,#374151 0%,#6b7280 100%)',
        btnColor: '#60a5fa',
        images: {},
    },
];

function loadTheme() {
    try {
        const raw = localStorage.getItem(THEME_STORAGE_KEY);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch {
        return null;
    }
}

function persistTheme(theme) {
    try {
        localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
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
        return saved || PRESET_THEMES[0];
    });
    // Scratch state for the theme editor (before Apply is clicked)
    const [themeDraft, setThemeDraft] = useState(null);
    const [customBgMode, setCustomBgMode] = useState('universal'); // 'universal' | 'perScene'
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

    const currentDate = new Date();
    const verticalDateString = selectedDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const fullDateString = selectedDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
    const todayDate = new Date();
    todayDate.setHours(0, 0, 0, 0);
    const isSelectedToday = selectedDate.getTime() === todayDate.getTime();
    const trimmedSearchQuery = searchQuery.trim();

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
        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountLoading(false);
        }
    };

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
            const requestBody = {
                userId: session.userId,
                jwtToken: session.jwtToken,
                firstName: accountDraft.firstName,
                lastName: accountDraft.lastName,
                reminderEnabled: accountDraft.reminderDefaults?.reminderEnabled === true,
                reminderMinutesBefore: Number(accountDraft.reminderDefaults?.reminderMinutesBefore || 30),
                ...(pendingAvatarUrl !== null
                    ? { avatarDataUrl: pendingAvatarUrl === 'REMOVED' ? '' : pendingAvatarUrl }
                    : {}),
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
    const effectiveBackground = resolveEffectiveBackground(activeTheme, background);

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
                            '--bg-img': effectiveBackground ? `url(${effectiveBackground})` : 'none',
                            backgroundSize: activeTheme?.imageFit === 'contain' ? 'contain' : activeTheme?.imageFit === 'center' ? 'auto' : 'cover',
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
                                    <button className={`nav-item${searchOpen || trimmedSearchQuery ? ' active' : ''}`} onClick={openSearch}><span className="nav-icon">Search</span></button>
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
                        {(searchOpen || trimmedSearchQuery) && (
                            <div className="calendar-search-shell">
                                <div className="calendar-search-card">
                                    <div className="calendar-search-copy">
                                        <span className="calendar-search-kicker">Search</span>
                                        <span className="calendar-search-status">
                                            {searchMeta.error
                                                ? searchMeta.error
                                                : searchMeta.loading
                                                    ? 'Searching...'
                                                    : trimmedSearchQuery
                                                        ? `${searchMeta.count} match${searchMeta.count === 1 ? '' : 'es'}`
                                                        : 'Search your calendar.'}
                                        </span>
                                    </div>
                                    <div className="calendar-search-input-shell">
                                        <input
                                            ref={searchInputRef}
                                            type="search"
                                            className="calendar-search-input"
                                            value={searchQuery}
                                            onChange={(event) => setSearchQuery(event.target.value)}
                                            placeholder="Search"
                                        />
                                        {(trimmedSearchQuery || searchMeta.active) && (
                                            <button
                                                type="button"
                                                className="calendar-search-clear-btn"
                                                onClick={clearSearch}
                                            >
                                                Clear
                                            </button>
                                        )}
                                    </div>
                                </div>
                            </div>
                        )}
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
                                        // Initialise draft from active theme when opening
                                        setThemeDraft(JSON.parse(JSON.stringify(activeTheme)));
                                        setCustomBgMode(
                                            activeTheme?.images?.universal !== undefined ? 'universal' : 'perScene'
                                        );
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
                                                    <h3>Choose a theme</h3>
                                                    <p className="account-section-copy">Select a preset or build your own. Changes apply instantly — click Apply to keep them.</p>
                                                    <div className="theme-preset-grid">
                                                        {PRESET_THEMES.map((preset) => {
                                                            const isSelected = themeDraft?.id === preset.id;
                                                            return (
                                                                <button
                                                                    key={preset.id}
                                                                    type="button"
                                                                    className={`theme-preset-card${isSelected ? ' selected' : ''}`}
                                                                    onClick={() => {
                                                                        const base = preset.id === 'custom'
                                                                            ? { ...preset, btnColor: themeDraft?.id === 'custom' ? themeDraft.btnColor : preset.btnColor, images: themeDraft?.id === 'custom' ? themeDraft.images : {} }
                                                                            : { ...preset };
                                                                        setThemeDraft(base);
                                                                        if (preset.id !== 'custom') {
                                                                            setCustomBgMode('universal');
                                                                        }
                                                                    }}
                                                                >
                                                                    <div className="theme-swatch" style={{ background: preset.preview }} />
                                                                    <span className="theme-preset-name">{preset.name}</span>
                                                                    <span className="theme-preset-desc">{preset.description}</span>
                                                                </button>
                                                            );
                                                        })}
                                                    </div>
                                                </div>

                                                {/* Custom theme editor — shown only when Custom is selected */}
                                                {themeDraft?.id === 'custom' && (
                                                    <div className="account-section-card">
                                                        <h3>Customize</h3>

                                                        {/* Button color picker */}
                                                        <div className="theme-custom-row">
                                                            <label className="theme-color-label">
                                                                <span>Accent / button color</span>
                                                                <div className="theme-color-row">
                                                                    <input
                                                                        type="color"
                                                                        className="theme-color-input"
                                                                        value={themeDraft.btnColor || '#60a5fa'}
                                                                        onChange={(e) => setThemeDraft((prev) => ({ ...prev, btnColor: e.target.value }))}
                                                                    />
                                                                    <input
                                                                        type="text"
                                                                        className="theme-color-text"
                                                                        value={themeDraft.btnColor || '#60a5fa'}
                                                                        maxLength={7}
                                                                        onChange={(e) => {
                                                                            const v = e.target.value;
                                                                            if (/^#[0-9a-fA-F]{0,6}$/.test(v)) {
                                                                                setThemeDraft((prev) => ({ ...prev, btnColor: v }));
                                                                            }
                                                                        }}
                                                                    />
                                                                </div>
                                                            </label>
                                                        </div>

                                                        {/* Background image mode toggle */}
                                                        <div className="theme-bg-mode-row">
                                                            <button
                                                                type="button"
                                                                className={`account-tab-btn${customBgMode === 'universal' ? ' active' : ''}`}
                                                                style={{ fontSize: '12px', padding: '6px 14px' }}
                                                                onClick={() => setCustomBgMode('universal')}
                                                            >
                                                                Single background
                                                            </button>
                                                            <button
                                                                type="button"
                                                                className={`account-tab-btn${customBgMode === 'perScene' ? ' active' : ''}`}
                                                                style={{ fontSize: '12px', padding: '6px 14px' }}
                                                                onClick={() => setCustomBgMode('perScene')}
                                                            >
                                                                Per-weather scenes
                                                            </button>
                                                        </div>

                                                        {customBgMode === 'universal' ? (
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
                                                                            const url = await readFileAsDataUrl(file);
                                                                            setThemeDraft((prev) => ({ ...prev, images: { universal: url } }));
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
                                                                                    const url = await readFileAsDataUrl(file);
                                                                                    setThemeDraft((prev) => ({ ...prev, images: { ...prev.images, [key]: url } }));
                                                                                }}
                                                                            />
                                                                        </label>
                                                                    );
                                                                })}
                                                            </div>
                                                        )}
                                                    </div>
                                                )}

                                                {/* Live preview strip */}
                                                {themeDraft && (
                                                    <div className="account-section-card theme-preview-card">
                                                        <h3>Preview</h3>
                                                        <div className="theme-preview-strip" style={{
                                                            backgroundImage: (() => {
                                                                const imgs = themeDraft.images || {};
                                                                const src = imgs.universal || null;
                                                                return src ? `url(${src})` : themeDraft.preview;
                                                            })(),
                                                            backgroundSize: themeDraft.imageFit === 'contain' ? 'contain' : themeDraft.imageFit === 'center' ? 'auto' : 'cover',
                                                        }}>
                                                            <div className="theme-preview-overlay">
                                                                <button
                                                                    className="theme-preview-btn"
                                                                    style={{
                                                                        '--btn-color': normalizeHexColor(themeDraft.btnColor),
                                                                        '--btn-text-color': getContrastTextColor(themeDraft.btnColor),
                                                                    }}
                                                                    type="button"
                                                                >
                                                                    Sample button
                                                                </button>
                                                                <span className="theme-preview-label">Accent: {themeDraft.btnColor || '#60a5fa'}</span>
                                                            </div>
                                                        </div>
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
                                                const reset = PRESET_THEMES[0];
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
                </>
            ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
            )}
        </>
    );
}

export default App;
