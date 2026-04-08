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

function App() {
    const [isAuthenticated, setIsAuthenticated] = useState(Boolean(localStorage.getItem('jwtToken')));
    const [leftOpen, setLeftOpen] = useState(true);
    const [rightOpen, setRightOpen] = useState(true);
    const [background, setBackground] = useState(null);
    const [aiInput, setAiInput] = useState('');
    const [aiLoading, setAiLoading] = useState(false);
    const [suggestions, setSuggestions] = useState([]);
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

    const loadSuggestions = async () => {
        const session = getSession();
        if (!session) return;

        setAiLoading(true);
        try {
            const localNow = new Date();
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
        setMessages(nextMessages);
        setAiInput('');
        setAiLoading(true);

        try {
            const localNow = new Date();
            const response = await fetch(`${API_ROOT}/chat`, {
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
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Chat failed.');
            }

            updateToken(data.jwtToken);
            setMessages([...nextMessages, { role: 'assistant', text: data.reply || 'No reply from AI.' }]);
        } catch (error) {
            setMessages([...nextMessages, { role: 'assistant', text: error.message }]);
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
                            <div className="sidebar-content" style={{ height: 'calc(100vh - 80px)' }}>
                                <h2>AI Assistant</h2>
                                <p style={{ fontSize: '0.85rem', color: '#9ca3af', marginTop: 0 }}>
                                    Ask about your schedule or pull suggestions for today.
                                </p>
                                <button
                                    className="ai-send-btn"
                                    onClick={loadSuggestions}
                                    disabled={aiLoading}
                                    style={{ marginBottom: '10px' }}
                                >
                                    {aiLoading ? 'Loading...' : 'Suggest Events'}
                                </button>

                                {suggestions.length > 0 && (
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginBottom: '10px', maxHeight: '180px', overflowY: 'auto' }}>
                                        {suggestions.map((suggestion, index) => (
                                            <div
                                                key={`${suggestion.title}-${suggestion.suggestedTime}-${index}`}
                                                style={{
                                                    background: 'rgba(18, 18, 31, 0.55)',
                                                    border: '1px solid rgba(255,255,255,0.08)',
                                                    borderRadius: '8px',
                                                    padding: '10px',
                                                }}
                                            >
                                                <div style={{ color: '#60a5fa', fontWeight: 'bold', fontSize: '0.8rem' }}>
                                                    {suggestion.suggestedTime || 'No time'}
                                                </div>
                                                <div style={{ fontWeight: 'bold', marginTop: '4px' }}>{suggestion.title}</div>
                                                <div style={{ fontSize: '0.85rem', color: '#cbd5e1', marginTop: '4px' }}>
                                                    {suggestion.description}
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                )}

                                <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '8px', marginBottom: '10px' }}>
                                    {messages.map((message, index) => (
                                        <div
                                            key={`${message.role}-${index}`}
                                            style={{
                                                alignSelf: message.role === 'user' ? 'flex-end' : 'flex-start',
                                                background: message.role === 'user' ? 'rgba(96, 165, 250, 0.18)' : 'rgba(18, 18, 31, 0.65)',
                                                borderRadius: '8px',
                                                padding: '10px 12px',
                                                maxWidth: '92%',
                                                whiteSpace: 'pre-wrap',
                                                lineHeight: 1.4,
                                            }}
                                        >
                                            {message.text}
                                        </div>
                                    ))}
                                </div>

                                <textarea
                                    className="ai-input"
                                    placeholder="e.g. What should I move today?"
                                    value={aiInput}
                                    onChange={(event) => setAiInput(event.target.value)}
                                />
                                <button className="ai-send-btn" onClick={sendChat} disabled={aiLoading}>
                                    {aiLoading ? 'Sending...' : 'Send to AI'}
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
