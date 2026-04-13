import './App.css';
import { useEffect, useState, useRef } from 'react'; // Added useRef

import Calendar from './Calendar.jsx';
import Login, { ResetPasswordPage } from './login.jsx';
import { requestWeatherLocation } from './weatherLocation.js';

import leftOpenIcon from './icons/panel-left-open.svg';
import leftCloseIcon from './icons/panel-left-close.svg';
import rightOpenIcon from './icons/panel-right-open.svg';
import rightCloseIcon from './icons/panel-right-close.svg';

const RAW_API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';
const API_ROOT = RAW_API_BASE.endsWith('/api') ? RAW_API_BASE : `${RAW_API_BASE}/api`;
const REMINDER_OPTIONS = [
    { value: 0, label: 'At time of event' },
    { value: 5, label: '5 minutes before' },
    { value: 15, label: '15 minutes before' },
    { value: 30, label: '30 minutes before' },
    { value: 60, label: '1 hour before' },
    { value: 1440, label: '1 day before' },
];

function decodeToken(token) {
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

function dateWithSuggestedTime(base, suggestedTime) {
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

function extractJsonArray(text) {
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

function normalizeSuggestions(rawSuggestions) {
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

function displayAssistantStatus(status) {
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
    const [background, setBackground] = useState(null);
    const [aiInput, setAiInput] = useState('');
    const [suggestionPreferences, setSuggestionPreferences] = useState('');
    const [aiLoading, setAiLoading] = useState(false);
    const [suggestions, setSuggestions] = useState([]);
    const [savedSuggestionKeys, setSavedSuggestionKeys] = useState([]);
    const [aiMode, setAiMode] = useState('chat');
    const [location, setLocation] = useState(null);
    const [isLocating, setIsLocating] = useState(false);
    const [locationNotice, setLocationNotice] = useState('Location is blocked, set to UCF');
    const [messages, setMessages] = useState([
        { role: 'assistant', text: 'Ask about your day or grab event suggestions.' },
    ]);
    const [calendarRefreshKey, setCalendarRefreshKey] = useState(0);
    const [calendarModalIntent, setCalendarModalIntent] = useState(null);
    const [selectedDate, setSelectedDate] = useState(initialSelectedDate);
    const [accountModalOpen, setAccountModalOpen] = useState(false);
    const [accountTab, setAccountTab] = useState('account');
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

    // Avatar Feature States
    const fileInputRef = useRef(null);
    const [avatarUrl, setAvatarUrl] = useState(localStorage.getItem('userAvatar') || null);

    const handleAvatarChange = (e) => {
        const file = e.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onloadend = () => {
                setAvatarUrl(reader.result);
                localStorage.setItem('userAvatar', reader.result);
            };
            reader.readAsDataURL(file);
        }
    };

    const currentDate = new Date();
    const verticalDateString = selectedDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const fullDateString = selectedDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
    const todayDate = new Date();
    todayDate.setHours(0, 0, 0, 0);
    const isSelectedToday = selectedDate.getTime() === todayDate.getTime();

    const logout = () => {
        localStorage.removeItem('jwtToken');
        localStorage.removeItem('accessToken');
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
                calendarFeedUrl: '',
                calendarFeedWebcalUrl: '',
                reminderDefaults: {
                    reminderEnabled: false,
                    reminderMinutesBefore: 30,
                },
                avatar: null,
            };
            setAccountSettings(nextSettings);
            setAccountDraft(nextSettings);
            setAvatarPreview(nextSettings.avatar || null);
            setEmailDraft('');
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
        }
    }, [isAuthenticated]);

    const refreshCalendar = () => {
        setCalendarRefreshKey((prev) => prev + 1);
    };

    const openAccountModal = (tab = 'account') => {
        setAccountTab(tab);
        setAccountFeedback('');
        setEmailFeedback('');
        setAccountModalOpen(true);
        if (accountSettings) {
            setAccountDraft(accountSettings);
            setAvatarPreview(accountSettings.avatar || null);
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
            const response = await fetch(`${API_ROOT}/saveaccountsettings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    firstName: accountDraft.firstName,
                    lastName: accountDraft.lastName,
                    avatar: avatarPreview,
                    reminderEnabled: accountDraft.reminderDefaults?.reminderEnabled === true,
                    reminderMinutesBefore: Number(accountDraft.reminderDefaults?.reminderMinutesBefore || 30),
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not save settings.');
            }

            updateToken(data.jwtToken);
            setAccountSettings(data.settings || accountDraft);
            setAccountDraft(data.settings || accountDraft);
            setAccountFeedback('Settings saved.');
        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountSaving(false);
        }
    };

    // Avatar Logic
    const handleFileChange = (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = (event) => {
            if (file.type === 'image/gif') {
                setAvatarPreview(event.target.result);
            } else {
                const img = new Image();
                img.onload = () => {
                    const canvas = document.createElement('canvas');
                    const MAX_WIDTH = 400;
                    const MAX_HEIGHT = 400;
                    let width = img.width;
                    let height = img.height;

                    if (width > height) {
                        if (width > MAX_WIDTH) {
                            height *= MAX_WIDTH / width;
                            width = MAX_WIDTH;
                        }
                    } else {
                        if (height > MAX_HEIGHT) {
                            width *= MAX_HEIGHT / height;
                            height = MAX_HEIGHT;
                        }
                    }

                    canvas.width = width;
                    canvas.height = height;
                    const ctx = canvas.getContext('2d');
                    ctx.drawImage(img, 0, 0, width, height);
                    const dataUrl = canvas.toDataURL('image/jpeg', 0.7); 
                    setAvatarPreview(dataUrl);
                };
                img.src = event.target.result;
            }
        };
        reader.readAsDataURL(file);
    };

    const handleRemoveAvatar = () => {
        setAvatarPreview(null);
        if (fileInputRef.current) fileInputRef.current.value = "";
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
        if (location || isLocating) {
            return location;
        }

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
            setIsLocating(false);
        }
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

            const seed = previous?.role === 'assistant' ? previous : { role: 'assistant', text: '', status: '' };
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
                    messages: nextMessages.map((message) => ({ role: message.role, content: message.text, })),
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
                    }
                }
            }
        } catch (error) {
            updateStreamingAssistantMessage((previous) => ({
                ...previous,
                text: `${previous.text}\n\nError: ${error.message}`,
                status: '',
            }));
        } finally {
            setAiLoading(false);
        }
    };

    const addSuggestionToCalendar = (suggestion) => {
        setCalendarModalIntent({
            kind: 'add',
            title: suggestion.title || '',
            description: suggestion.description || '',
            date: dateWithSuggestedTime(selectedDate, suggestion.suggestedTime || '12:00').toISOString(),
            key: Date.now(),
        });
        setSavedSuggestionKeys((prev) => [...prev, suggestionKey(suggestion)]);
    };

    return (
        <>
            {isAuthenticated ? (
                <>
                    <div className="main-layout" style={{ '--bg-img': `url(${background})` }}>
                        <div className={`sidebar left-sidebar ${leftOpen ? 'open' : 'closed'}`}>
                            <button
                                type="button"
                                className={`toggle-btn ${leftOpen ? 'right-align' : 'left-align'}`}
                                onClick={() => setLeftOpen(!leftOpen)}
                            >
                                <img src={leftOpen ? leftCloseIcon : leftOpenIcon} alt="Toggle Sidebar" />
                            </button>

                            {leftOpen && (
                                <div className="sidebar-content">
                                    <button type="button" className="nav-item" onClick={() => openCalendarModal('add')}>
                                        <span className="nav-icon">＋</span>
                                        <span>New Event</span>
                                    </button>
                                    <button type="button" className="nav-item" onClick={() => openAccountModal('account')}>
                                        <span className="nav-icon">👤</span>
                                        <span>Account</span>
                                    </button>
                                    <button type="button" className="nav-item" onClick={() => openAccountModal('sync')}>
                                        <span className="nav-icon">🔄</span>
                                        <span>Sync</span>
                                    </button>
                                    <button type="button" className="nav-item" style={{ marginTop: 'auto' }} onClick={logout}>
                                        <span className="nav-icon">🚪</span>
                                        <span>Logout</span>
                                    </button>
                                </div>
                            )}
                        </div>

                        <div className="center-content">
                            <div className="calendar-wrapper">
                                <Calendar
                                    refreshKey={calendarRefreshKey}
                                    modalIntent={calendarModalIntent}
                                    onSelectedDateChange={setSelectedDate} 
                                    setBackground={setBackground}
                                    session={getSession()}
                                    apiRoot={API_ROOT}
                                    onSessionRefresh={updateToken}
                                    reminderDefaults={accountSettings?.reminderDefaults}
                                />
                            </div>
                        </div>

                        <div className={`sidebar right-sidebar ${rightOpen ? 'open' : 'closed'}`}>
                            <button
                                type="button"
                                className={`toggle-btn ${rightOpen ? 'left-align' : 'right-align'}`}
                                onClick={() => setRightOpen(!rightOpen)}
                            >
                                <img src={rightOpen ? rightCloseIcon : rightOpenIcon} alt="Toggle AI Panel" />
                            </button>

                            {rightOpen && (
                                <div className="ai-panel">
                                    <div className="ai-panel-header">
                                        <h2>Assistant</h2>
                                    </div>

                                    <div className="ai-hero-card">
                                        <h3>{fullDateString}</h3>
                                        <p className="ai-subtitle">
                                            {isSelectedToday ? "Here's what's happening today." : `Plan ahead for ${fullDateString}.`}
                                        </p>
                                        <div className="ai-location-row">
                                            <LocationIcon />
                                            <span className="ai-location-text">{locationNotice}</span>
                                            <button
                                                type="button"
                                                className="ai-icon-btn"
                                                onClick={loadSuggestions}
                                                disabled={aiLoading}
                                                title="Refresh suggestions"
                                            >
                                                <SparklesIcon />
                                            </button>
                                        </div>
                                    </div>

                                    <div className={`ai-main-shell ${aiMode}-mode`}>
                                        {aiMode === 'suggestions' ? (
                                            <div className="ai-section active">
                                                <div className="ai-section-header">
                                                    <h3>Smart Suggestions</h3>
                                                    <span>Based on location & time</span>
                                                </div>
                                                <div className="ai-suggestion-list">
                                                    {suggestions.length > 0 ? (
                                                        suggestions.map((suggestion, idx) => {
                                                            const key = suggestionKey(suggestion);
                                                            const isSaved = savedSuggestionKeys.includes(key);
                                                            return (
                                                                <div key={idx} className="ai-suggestion-card">
                                                                    <div className="ai-suggestion-copy">
                                                                        <div className="ai-suggestion-time">{suggestion.suggestedTime}</div>
                                                                        <div className="ai-suggestion-title">{suggestion.title}</div>
                                                                        <div className="ai-suggestion-description">{suggestion.description}</div>
                                                                    </div>
                                                                    <button
                                                                        type="button"
                                                                        className={`ai-add-btn ${isSaved ? 'saved' : ''}`}
                                                                        onClick={() => !isSaved && addSuggestionToCalendar(suggestion)}
                                                                        disabled={isSaved}
                                                                    >
                                                                        {isSaved ? '✓' : '+'}
                                                                    </button>
                                                                </div>
                                                            );
                                                        })
                                                    ) : (
                                                        <div className="ai-empty-state">
                                                            No suggestions yet. Try adding preferences or hit the sparkles!
                                                        </div>
                                                    )}
                                                </div>
                                            </div>
                                        ) : (
                                            <div className="ai-section active">
                                                <div className="ai-chat-shell">
                                                    <div className="ai-chat-feed">
                                                        {messages.map((msg, i) => (
                                                            <div key={i} className={`ai-message ${msg.role} ${msg.status ? 'status-loading' : ''}`}>
                                                                {msg.status ? (
                                                                    <div className="ai-status-text">{displayAssistantStatus(msg.status)}</div>
                                                                ) : (
                                                                    renderAssistantMessage(msg.text)
                                                                )}
                                                            </div>
                                                        ))}
                                                    </div>
                                                </div>
                                            </div>
                                        )}
                                    </div>

                                    <div className="ai-input-area">
                                        <div className="ai-input-wrapper">
                                            <textarea
                                                className="ai-input"
                                                placeholder={aiMode === 'suggestions' ? "Add preferences (e.g. 'I like jazz')..." : "Ask anything..."}
                                                value={aiMode === 'suggestions' ? suggestionPreferences : aiInput}
                                                onChange={(e) => aiMode === 'suggestions' ? setSuggestionPreferences(e.target.value) : setAiInput(e.target.value)}
                                                onKeyDown={(e) => {
                                                    if (e.key === 'Enter' && !e.shiftKey) {
                                                        e.preventDefault();
                                                        if (aiMode === 'suggestions') loadSuggestions();
                                                        else sendChat();
                                                    }
                                                }}
                                            />
                                            <button
                                                type="button"
                                                className="ai-send-btn"
                                                onClick={aiMode === 'suggestions' ? loadSuggestions : sendChat}
                                                disabled={aiLoading}
                                            >
                                                {aiLoading ? '...' : <SendIcon />}
                                            </button>
                                        </div>
                                        <div className="ai-mode-toggle">
                                            <button
                                                type="button"
                                                className={`ai-suggest-btn ${aiMode === 'suggestions' ? 'active' : ''}`}
                                                onClick={() => setAiMode('suggestions')}
                                            >
                                                Suggestions
                                            </button>
                                            <button
                                                type="button"
                                                className={`ai-suggest-btn ${aiMode === 'chat' ? 'active' : ''}`}
                                                onClick={() => setAiMode('chat')}
                                            >
                                                Chat
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            )}
                        </div>
                    </div>

                    {accountModalOpen && (
                    <div className="account-modal-overlay">
                        <div className="account-modal">
                            <div className="account-modal-header">
                                <div className="account-modal-tabs">
                                    <button
                                        type="button"
                                        className={`account-tab-btn ${accountTab === 'account' ? 'active' : ''}`}
                                        onClick={() => setAccountTab('account')}
                                    >
                                        Account Settings
                                    </button>
                                    <button
                                        type="button"
                                        className={`account-tab-btn ${accountTab === 'sync' ? 'active' : ''}`}
                                        onClick={() => setAccountTab('sync')}
                                    >
                                        External Sync
                                    </button>
                                </div>
                            </div>

                            <div className="account-modal-body">
                                {accountLoading ? (
                                    <div className="account-loading">Loading settings...</div>
                                ) : (
                                    <>
                                        {accountTab === 'account' && (
                                            <div className="account-settings-form">
                                                <div className="account-avatar-section">
                                                    <div className="account-avatar-container">
                                                        <div 
                                                            className="account-avatar-circle" 
                                                            onClick={() => fileInputRef.current.click()}
                                                            title="Click to upload"
                                                        >
                                                            {avatarPreview ? (
                                                                <img src={avatarPreview} alt="Profile" className="account-avatar-img" />
                                                            ) : (
                                                                <div className="account-avatar-default">👤</div>
                                                            )}
                                                        </div>
                                                        
                                                        <div className="account-avatar-buttons">
                                                            <button 
                                                                type="button" 
                                                                className="account-avatar-upload-btn" 
                                                                onClick={() => fileInputRef.current.click()}
                                                            >
                                                                Upload Picture
                                                            </button>
                                                            {avatarPreview && (
                                                                <button 
                                                                    type="button" 
                                                                    className="account-avatar-remove-btn" 
                                                                    onClick={handleRemoveAvatar}
                                                                >
                                                                    Remove
                                                                </button>
                                                            )}
                                                        </div>

                                                        <input 
                                                            type="file" 
                                                            ref={fileInputRef} 
                                                            onChange={handleFileChange} 
                                                            accept="image/*" 
                                                            style={{ display: 'none' }} 
                                                        />
                                                    </div>
                                                </div>

                                                <div className="account-form-grid">
                                                    <div className="account-field">
                                                        <label>First Name</label>
                                                        <input
                                                            type="text"
                                                            value={accountDraft.firstName}
                                                            onChange={(e) => setAccountDraft({ ...accountDraft, firstName: e.target.value })}
                                                        />
                                                    </div>
                                                    <div className="account-field">
                                                        <label>Last Name</label>
                                                        <input
                                                            type="text"
                                                            value={accountDraft.lastName}
                                                            onChange={(e) => setAccountDraft({ ...accountDraft, lastName: e.target.value })}
                                                        />
                                                    </div>
                                                </div>

                                                <div className="account-field">
                                                    <label>Notification Defaults</label>
                                                    <div className="account-check-row">
                                                        <input
                                                            type="checkbox"
                                                            checked={accountDraft.reminderDefaults?.reminderEnabled}
                                                            onChange={(e) => setAccountDraft({
                                                                ...accountDraft,
                                                                reminderDefaults: {
                                                                    ...accountDraft.reminderDefaults,
                                                                    reminderEnabled: e.target.checked
                                                                }
                                                            })}
                                                        />
                                                        <span>Enable reminders for new events</span>
                                                    </div>
                                                </div>

                                                {accountDraft.reminderDefaults?.reminderEnabled && (
                                                    <div className="account-field">
                                                        <label>Default Reminder Time</label>
                                                        <select
                                                            value={accountDraft.reminderDefaults?.reminderMinutesBefore}
                                                            onChange={(e) => setAccountDraft({
                                                                ...accountDraft,
                                                                reminderDefaults: {
                                                                    ...accountDraft.reminderDefaults,
                                                                    reminderMinutesBefore: Number(e.target.value)
                                                                }
                                                            })}
                                                        >
                                                            {REMINDER_OPTIONS.map((opt) => (
                                                                <option key={opt.value} value={opt.value}>
                                                                    {opt.label}
                                                                </option>
                                                            ))}
                                                        </select>
                                                    </div>
                                                )}

                                                <div className="account-divider" />

                                                <div className="account-field">
                                                    <label>Current Email Address</label>
                                                    <div className="account-email-display">
                                                        {accountSettings?.email}
                                                        {accountSettings?.pendingEmail && (
                                                            <span className="account-email-pending">
                                                                (Pending change to: {accountSettings.pendingEmail})
                                                            </span>
                                                        )}
                                                    </div>
                                                </div>

                                                <div className="account-field">
                                                    <label>Change Email</label>
                                                    <div className="account-input-with-btn">
                                                        <input
                                                            type="email"
                                                            placeholder="New email address"
                                                            value={emailDraft}
                                                            onChange={(e) => setEmailDraft(e.target.value)}
                                                        />
                                                        <button
                                                            type="button"
                                                            className="account-primary-btn"
                                                            onClick={requestEmailChange}
                                                            disabled={accountSaving || !emailDraft.trim()}
                                                        >
                                                            Update
                                                        </button>
                                                    </div>
                                                    {emailFeedback && <div className="account-feedback-small">{emailFeedback}</div>}
                                                </div>
                                            </div>
                                        )}

                                        {accountTab === 'sync' && (
                                            <div className="account-sync-panel">
                                                <div className="account-sync-info">
                                                    <h3>Subscribe to your calendar</h3>
                                                    <p>Use these links to see your events in Google Calendar, Outlook, or Apple Calendar.</p>
                                                </div>

                                                <div className="account-sync-section">
                                                    <label>iCal Subscription Link (Webcal)</label>
                                                    <div className="account-input-with-btn">
                                                        <input type="text" readOnly value={accountSettings?.calendarFeedWebcalUrl || 'Generating...'} />
                                                        <button type="button" className="account-secondary-btn" onClick={() => copyCalendarFeed(true)}>
                                                            Copy
                                                        </button>
                                                    </div>
                                                    <p className="account-help-text">Recommended for most calendar apps.</p>
                                                </div>

                                                <div className="account-sync-section">
                                                    <label>Direct Feed URL (HTTPS)</label>
                                                    <div className="account-input-with-btn">
                                                        <input type="text" readOnly value={accountSettings?.calendarFeedUrl || 'Generating...'} />
                                                        <button type="button" className="account-secondary-btn" onClick={() => copyCalendarFeed(false)}>
                                                            Copy
                                                        </button>
                                                    </div>
                                                </div>

                                                <div className="account-sync-actions">
                                                    <div className="account-sync-row">
                                                        <button type="button" className="account-danger-link" onClick={regenerateCalendarFeed}>
                                                            Regenerate Link
                                                        </button>
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
                                <button type="button" className="account-primary-btn" onClick={saveAccountSettings} disabled={accountSaving || accountLoading}>
                                    {accountSaving ? 'Saving...' : 'Save changes'}
                                </button>
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
