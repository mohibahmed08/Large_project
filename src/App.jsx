import './App.css';
import { useState } from 'react';

import Calendar from './Calendar.jsx';
import Login from './login.jsx';

import leftOpenIcon from './icons/panel-left-open.svg';
import leftCloseIcon from './icons/panel-left-close.svg';
import rightOpenIcon from './icons/panel-right-open.svg';
import rightCloseIcon from './icons/panel-right-close.svg';

const RAW_API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';
const API_ROOT = RAW_API_BASE.endsWith('/api') ? RAW_API_BASE : `${RAW_API_BASE}/api`;

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

function App() {
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
    const [locationNotice, setLocationNotice] = useState('Location is off, so the AI will lean on time and calendar context.');
    const [messages, setMessages] = useState([
        { role: 'assistant', text: 'Ask about your day or grab event suggestions.' },
    ]);

    const currentDate = new Date();
    const verticalDateString = currentDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const fullDateString = currentDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });

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
        };
    };

    const updateToken = (nextToken) => {
        if (nextToken) {
            localStorage.setItem('jwtToken', nextToken);
        }
    };

    const ensureLocation = async () => {
        if (location || isLocating || !window.navigator.geolocation) {
            if (!window.navigator.geolocation) {
                setLocationNotice('Location is not available in this browser, so nearby context is turned off.');
            }
            return location;
        }

        setIsLocating(true);
        setLocationNotice('Checking your location for nearby context...');

        try {
            const coords = await new Promise((resolve, reject) => {
                window.navigator.geolocation.getCurrentPosition(
                    ({ coords: nextCoords }) => resolve({
                        latitude: nextCoords.latitude,
                        longitude: nextCoords.longitude,
                    }),
                    reject,
                    {
                        enableHighAccuracy: false,
                        timeout: 10000,
                        maximumAge: 300000,
                    },
                );
            });

            setLocation(coords);
            setLocationNotice('Nearby suggestions are using your current location.');
            return coords;
        } catch {
            setLocationNotice('Could not read your location, so nearby suggestions may be more generic.');
            return null;
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
            setSuggestions(Array.isArray(data.suggestions) ? data.suggestions : []);
        } catch (error) {
            setMessages((prev) => [...prev, { role: 'assistant', text: error.message }]);
        } finally {
            setAiLoading(false);
        }
    };

    const sendChat = async () => {
        const trimmed = aiInput.trim();
        const session = getSession();
        if (!trimmed || !session || aiLoading) return;

        const nextMessages = [...messages, { role: 'user', text: trimmed }];
        setAiMode('chat');
        setMessages([...nextMessages, { role: 'assistant', text: '' }]);
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

                    const payload = JSON.parse(trimmedLine);
                    if (payload.type === 'delta' && payload.delta) {
                        setMessages((prev) => {
                            const updated = [...prev];
                            const lastIndex = updated.length - 1;
                            const previous = updated[lastIndex];
                            updated[lastIndex] = {
                                ...previous,
                                text: `${previous.text}${payload.delta}`,
                            };
                            return updated;
                        });
                    } else if (payload.type === 'done') {
                        updateToken(payload.jwtToken);
                    } else if (payload.type === 'error') {
                        throw new Error(payload.error || 'Streaming failed.');
                    }
                }
            }

            const finalLine = buffer.trim();
            if (finalLine) {
                const payload = JSON.parse(finalLine);
                if (payload.type === 'done') {
                    updateToken(payload.jwtToken);
                } else if (payload.type === 'error') {
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
        } catch (error) {
            setMessages((prev) => [...prev, { role: 'assistant', text: error.message }]);
            setAiMode('chat');
        } finally {
            setAiLoading(false);
        }
    };

    return (
        <>
            {isAuthenticated ? (
                <div className="main-layout" style={{ '--bg-img': `url(${background}` }}>
                    <div className={`sidebar left-sidebar ${leftOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn right-align" onClick={() => setLeftOpen(!leftOpen)}>
                            <img src={leftOpen ? leftCloseIcon : leftOpenIcon} alt="Toggle Left" />
                        </button>

                        {leftOpen ? (
                            <div className="sidebar-content">
                                <div style={{ marginBottom: '20px' }}>
                                    <h2 style={{ margin: '0 0 5px 0' }}>Today</h2>
                                    <p style={{ margin: 0, color: '#60a5fa', fontWeight: 'bold' }}>{fullDateString}</p>
                                </div>

                                <nav style={{ display: 'flex', flexDirection: 'column', gap: '5px' }}>
                                    <button className="nav-item"><span className="nav-icon">Plan</span></button>
                                    <button className="nav-item"><span className="nav-icon">Event</span></button>
                                    <button className="nav-item"><span className="nav-icon">Task</span></button>
                                    <hr style={{ border: '0', borderTop: '1px solid #2c2c3e', margin: '10px 0' }} />
                                    <button className="nav-item"><span className="nav-icon">Settings</span></button>
                                </nav>

                                <div style={{ marginTop: 'auto', paddingTop: '15px', borderTop: '1px solid #2c2c3e', display: 'flex', alignItems: 'center', gap: '12px' }}>
                                    <div style={{ width: '35px', height: '35px', borderRadius: '50%', background: '#3b82f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', flexShrink: 0 }}>
                                        JD
                                    </div>
                                    <span style={{ fontWeight: 'bold' }}>John Doe</span>
                                </div>
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
                            <Calendar singleMonth={false} setBackground={setBackground} />
                        </div>
                    </div>

                    <div className={`sidebar right-sidebar ${rightOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn left-align" onClick={() => setRightOpen(!rightOpen)}>
                            <img src={rightOpen ? rightCloseIcon : rightOpenIcon} alt="Toggle Right" />
                        </button>
                        {rightOpen && (
                            <div className="sidebar-content ai-panel">
                                <div className="ai-hero-card">
                                    <h2>AI Assistant</h2>
                                    <p className="ai-subtitle">
                                        Ask about your schedule or pull suggestions with the same context-aware flow as mobile.
                                    </p>
                                    <div className="ai-location-row">
                                        <span className="ai-location-dot" />
                                        <span>{locationNotice}</span>
                                        <button
                                            className="ai-icon-btn"
                                            type="button"
                                            onClick={ensureLocation}
                                            disabled={isLocating}
                                        >
                                            {isLocating ? '...' : 'Refresh'}
                                        </button>
                                    </div>
                                    <textarea
                                        className="ai-input ai-preferences"
                                        placeholder="Quiet evening, outdoor ideas, study-focused..."
                                        value={suggestionPreferences}
                                        onChange={(event) => setSuggestionPreferences(event.target.value)}
                                    />
                                    <button
                                        className="ai-send-btn"
                                        onClick={loadSuggestions}
                                        disabled={aiLoading}
                                    >
                                        {aiLoading && aiMode === 'suggestions' ? 'Loading...' : 'Suggest Events'}
                                    </button>
                                </div>

                                <div className={`ai-main-shell ${aiMode === 'chat' ? 'chat-priority' : 'suggestions-priority'}`}>
                                    {suggestions.length > 0 && (
                                        <div className={`ai-section ai-suggestions ${aiMode === 'suggestions' ? 'active' : 'compact'}`}>
                                            <div className="ai-section-header">
                                                <h3>Suggestions</h3>
                                                <span>{suggestions.length} ready</span>
                                            </div>
                                            <div className="ai-suggestion-list">
                                                {suggestions.map((suggestion, index) => {
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
                                                                {isSaved ? '✓' : '+'}
                                                            </button>
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                        </div>
                                    )}

                                    <div className={`ai-section ai-chat ${aiMode === 'chat' ? 'active' : 'compact'}`}>
                                        <div className="ai-section-header">
                                            <h3>Chat</h3>
                                            <span>Newer messages take focus</span>
                                        </div>
                                        <div className="ai-chat-feed">
                                            {messages.map((message, index) => (
                                                <div
                                                    key={`${message.role}-${index}`}
                                                    className={`ai-message ${message.role === 'user' ? 'user' : 'assistant'}`}
                                                >
                                                    {message.text}
                                                </div>
                                            ))}
                                        </div>
                                    </div>
                                </div>

                                <textarea
                                    className="ai-input"
                                    placeholder="e.g. What should I move today?"
                                    value={aiInput}
                                    onChange={(event) => setAiInput(event.target.value)}
                                />
                                <button className="ai-send-btn" onClick={sendChat} disabled={aiLoading}>
                                    {aiLoading && aiMode === 'chat' ? 'Sending...' : 'Send to AI'}
                                </button>
                            </div>
                        )}
                    </div>
                </div>
            ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
            )}
        </>
    );
}

export default App;
