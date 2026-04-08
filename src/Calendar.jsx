import { useState, useRef, useEffect, useMemo } from 'react';
import JSZip from 'jszip';

import './Calendar.css';
import CalendarMonth from './CalendarMonth.jsx';

import ClearSky from './weather_backgrounds/ClearSky.jpg';
import Cloudy from './weather_backgrounds/Cloudy.jpg';
import NightClear from './weather_backgrounds/NightClear.jpg';
import NightCloudy from './weather_backgrounds/NightCloudy.jpg';
import NightPartlyCloudy from './weather_backgrounds/NightPartlyCloudy.jpg';
import PartlyCloudy from './weather_backgrounds/PartlyCloudy.jpg';
import SunsetSunriseClearSky from './weather_backgrounds/SunsetSunriseClearSky.png';
import SunsetSunriseCloudy from './weather_backgrounds/SunsetSunriseCloudy.jpg';
import SunsetSunrisePartlyCloudy from './weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

import UpArrow from './icons/arrow-big-up.svg';
import DownArrow from './icons/arrow-big-down.svg';

const REMINDER_OPTIONS = [
    { value: 0, label: 'At time of event' },
    { value: 5, label: '5 minutes before' },
    { value: 15, label: '15 minutes before' },
    { value: 30, label: '30 minutes before' },
    { value: 60, label: '1 hour before' },
    { value: 1440, label: '1 day before' },
];

const ITEM_TYPE_META = {
    plan: {
        modalTitleCreate: 'New Plan',
        modalTitleEdit: 'Edit Plan',
        saveSource: 'plan',
        titleLabel: 'Plan title',
        descriptionLabel: 'Plan notes',
        descriptionPlaceholder: 'Outline what you want to do...',
        locationLabel: 'Optional place',
        showCompletion: false,
        reminderDefault: false,
        defaultHour: 10,
    },
    event: {
        modalTitleCreate: 'New Event',
        modalTitleEdit: 'Edit Event',
        saveSource: 'event',
        titleLabel: 'Event title',
        descriptionLabel: 'Details',
        descriptionPlaceholder: 'Add details about the event...',
        locationLabel: 'Location',
        showCompletion: false,
        reminderDefault: false,
        defaultHour: 9,
    },
    task: {
        modalTitleCreate: 'New Task',
        modalTitleEdit: 'Edit Task',
        saveSource: 'task',
        titleLabel: 'Task title',
        descriptionLabel: 'Notes',
        descriptionPlaceholder: 'Add task notes...',
        locationLabel: 'Location',
        showCompletion: true,
        reminderDefault: true,
        defaultHour: 9,
    },
};

function normalizeItemType(taskLike) {
    const source = String(taskLike?.source || '').toLowerCase();
    if (source === 'plan' || source === 'event' || source === 'task') {
        return source;
    }
    return 'event';
}

function formatTimeValue(dateValue) {
    return `${dateValue.getHours().toString().padStart(2, '0')}:${dateValue.getMinutes().toString().padStart(2, '0')}`;
}

function formatTaskTime(dateValue) {
    const date = new Date(dateValue);
    if (Number.isNaN(date.getTime())) {
        return 'No time';
    }

    return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function suggestionKey(suggestion) {
    return `${suggestion?.title || ''}|${suggestion?.suggestedTime || ''}|${suggestion?.description || ''}`;
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

function renderCalendarInlineMarkdown(text) {
    const source = String(text || '');
    const nodes = [];
    const pattern = /(\*\*[^*]+\*\*|\[[^\]]+\]\s*\((https?:\/\/[^\s)]+)\))/g;
    let lastIndex = 0;
    let match;

    while ((match = pattern.exec(source)) !== null) {
        if (match.index > lastIndex) {
            nodes.push(
                <span key={`text-${lastIndex}`}>
                    {source.slice(lastIndex, match.index)}
                </span>
            );
        }

        const token = match[0];
        if (token.startsWith('**') && token.endsWith('**') && token.length > 4) {
            nodes.push(<strong key={`bold-${match.index}`}>{token.slice(2, -2)}</strong>);
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

function renderCalendarMarkdown(text) {
    const lines = String(text || '').split('\n');
    const blocks = [];
    let listItems = [];

    const flushList = () => {
        if (!listItems.length) {
            return;
        }

        blocks.push(
            <ul key={`list-${blocks.length}`} className="calendar-day-copy-list">
                {listItems.map((item, index) => (
                    <li key={`item-${index}`}>{renderCalendarInlineMarkdown(item)}</li>
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
            <div key={`line-${index}`} className="calendar-day-copy-line">
                {renderCalendarInlineMarkdown(trimmed)}
            </div>
        );
    });

    flushList();

    return blocks.length ? blocks : text;
}

function getWeatherImg(currentWeather){
    const hour = new Date().getHours();
    let timeOfDay = 'night';
    if (hour >= 6 && hour < 9) timeOfDay = 'sunrise';
    else if (hour >= 9 && hour < 18) timeOfDay = 'day';
    else if (hour >= 18 && hour < 21) timeOfDay = 'sunset';

    switch(currentWeather){
        case 'Clear sky':
        case 'Mostly clear':
            if(timeOfDay === 'sunrise' || timeOfDay === 'sunset') return SunsetSunriseClearSky;
            if(timeOfDay === 'day') return ClearSky;
            return NightClear;
        case 'Overcast':
            if(timeOfDay === 'sunrise' || timeOfDay === 'sunset') return SunsetSunriseCloudy;
            if(timeOfDay === 'day') return Cloudy;
            return NightCloudy;
        case 'Partly cloudy':
            if(timeOfDay === 'sunrise' || timeOfDay === 'sunset') return SunsetSunrisePartlyCloudy;
            if(timeOfDay === 'day') return PartlyCloudy;
            return NightPartlyCloudy;
        default:
            return null;
    }
}

function normalizeDateKey(dateValue) {
    const date = new Date(dateValue);
    date.setHours(0, 0, 0, 0);
    return date.toISOString();
}

function weatherCodeToEmoji(code) {
    if ([0, 1].includes(code)) return '☀️';
    if ([2, 3].includes(code)) return '⛅';
    if ([45, 48].includes(code)) return '🌫️';
    if ([51, 53, 55, 61, 63, 65, 80, 81, 82].includes(code)) return '🌧️';
    if ([71, 73, 75, 77, 85, 86].includes(code)) return '❄️';
    if ([95, 96, 99].includes(code)) return '⛈️';
    return '•';
}

function weatherCodeToLabel(code) {
    if ([0].includes(code)) return 'Clear';
    if ([1].includes(code)) return 'Mostly clear';
    if ([2].includes(code)) return 'Partly cloudy';
    if ([3].includes(code)) return 'Overcast';
    if ([45, 48].includes(code)) return 'Fog';
    if ([51, 53, 55, 61, 63, 65, 80, 81, 82].includes(code)) return 'Rain';
    if ([71, 73, 75, 77, 85, 86].includes(code)) return 'Snow';
    if ([95, 96, 99].includes(code)) return 'Storm';
    return 'Weather';
}

function weatherGlyph(code) {
    if ([0, 1].includes(code)) return '\u2600\uFE0F';
    if ([2, 3].includes(code)) return '\u26C5';
    if ([45, 48].includes(code)) return '\uD83C\uDF2B\uFE0F';
    if ([51, 53, 55, 61, 63, 65, 80, 81, 82].includes(code)) return '\uD83C\uDF27\uFE0F';
    if ([71, 73, 75, 77, 85, 86].includes(code)) return '\u2744\uFE0F';
    if ([95, 96, 99].includes(code)) return '\u26C8\uFE0F';
    return '\u2022';
}

function dayWeatherRange() {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - 7);
    const end = new Date(start);
    end.setDate(end.getDate() + 22);
    return {
        startDate: start.toISOString().slice(0, 10),
        endDate: end.toISOString().slice(0, 10),
    };
}

function currentTimeContext() {
    const now = new Date();
    return {
        timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        utcOffsetMinutes: -now.getTimezoneOffset(),
    };
}

function Calendar({
    singleMonth,
    setBackground,
    session,
    apiRoot,
    onSessionRefresh,
    refreshKey,
    modalIntent,
    reminderDefaults,
    onSelectedDateChange,
}) {
    const [date] = useState(() => new Date());
    const baseMonth = date.getMonth();
    const [renderedMonths, setRenderedMonths] = useState(1);
    const [backgroundWeather, setBackgroundWeather] = useState(-1);
    const [currentMonthIndex, setCurrentMonthIndex] = useState(0);
    const containerRef = useRef(null);
    const lastMonthRef = useRef();
    const weatherStripRef = useRef(null);
    const weatherCacheRef = useRef(new Map());
    const weatherCoordsRef = useRef(null);

    const [calendarTasks, setCalendarTasks] = useState([]);
    const [calendarReloadTick, setCalendarReloadTick] = useState(0);
    const [isSavingItem, setIsSavingItem] = useState(false);
    const [lastModalType, setLastModalType] = useState('event');
    const [editorState, setEditorState] = useState(null);
    const [selectedDate, setSelectedDate] = useState(() => {
        const now = new Date();
        now.setHours(0, 0, 0, 0);
        return now;
    });
    const [dayModalState, setDayModalState] = useState({
        open: false,
        suggestions: [],
        savedSuggestionKeys: [],
        suggestionsLoading: false,
        weather: [],
        weatherLoading: false,
        feedback: '',
    });
    const [importState, setImportState] = useState({
        open: false,
        icsUrl: '',
        icsContent: '',
        subscriptions: [],
        isLoadingSubscriptions: false,
        isImporting: false,
        isSyncingSubscriptionId: '',
        isDeletingSubscriptionId: '',
        feedback: '',
    });

    useEffect(() => {
        if (singleMonth) return;

        const observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    const index = Number(entry.target.dataset.index);
                    if (entry.intersectionRatio >= 0.5) {
                        setCurrentMonthIndex(index);
                    }
                    if (entry.isIntersecting && index === renderedMonths - 1) {
                        setRenderedMonths((prev) => prev + 1);
                    }
                });
            },
            {
                root: containerRef.current,
                threshold: Array.from({ length: 101 }, (_, i) => i / 100),
            },
        );

        const months = containerRef.current?.querySelectorAll('.calendar-month') || [];
        months.forEach((month) => observer.observe(month));
        if (lastMonthRef.current) observer.observe(lastMonthRef.current);
        return () => observer.disconnect();
    }, [renderedMonths, singleMonth]);

    const targetDate = new Date(date.getFullYear(), baseMonth + currentMonthIndex, 1);
    const monthName = targetDate.toLocaleString('default', { month: 'long' });
    const year = targetDate.getFullYear();
    const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    const visibleRange = useMemo(() => {
        if (singleMonth) {
            const start = new Date(date.getFullYear(), baseMonth + currentMonthIndex, 1);
            const end = new Date(date.getFullYear(), baseMonth + currentMonthIndex + 1, 0, 23, 59, 59, 999);
            return { start, end };
        }

        const start = new Date(date.getFullYear(), baseMonth, 1);
        const end = new Date(date.getFullYear(), baseMonth + renderedMonths, 0, 23, 59, 59, 999);
        return { start, end };
    }, [singleMonth, currentMonthIndex, renderedMonths, baseMonth, date]);

    useEffect(() => {
        setBackground(getWeatherImg(backgroundWeather));
    }, [backgroundWeather, setBackground]);

    const refreshCalendar = () => {
        setCalendarReloadTick((prev) => prev + 1);
    };

    const selectedDayTasks = useMemo(() => {
        const selectedKey = normalizeDateKey(selectedDate);
        return calendarTasks.filter((task) => task?.dueDate && normalizeDateKey(task.dueDate) === selectedKey);
    }, [calendarTasks, selectedDate]);

    useEffect(() => {
        onSelectedDateChange?.(selectedDate);
    }, [selectedDate, onSelectedDateChange]);

    useEffect(() => {
        if (!session?.userId || !session?.jwtToken || !apiRoot) {
            setCalendarTasks([]);
            return;
        }

        let ignore = false;

        const loadCalendar = async () => {
            try {
                const response = await fetch(`${apiRoot}/loadcalendar`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        userId: session.userId,
                        jwtToken: session.jwtToken,
                        startDate: visibleRange.start.toISOString(),
                        endDate: visibleRange.end.toISOString(),
                        ...currentTimeContext(),
                    }),
                });

                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.error || 'Could not load calendar.');
                }

                if (!ignore) {
                    onSessionRefresh?.(data.jwtToken);
                    setCalendarTasks(Array.isArray(data.tasks) ? data.tasks : []);
                }
            } catch (error) {
                if (!ignore) {
                    console.error(error);
                }
            }
        };

        loadCalendar();
        return () => {
            ignore = true;
        };
    }, [apiRoot, session?.userId, session?.jwtToken, visibleRange, onSessionRefresh, refreshKey, calendarReloadTick]);

    const buildDraft = (type, targetDay, task = null) => {
        const normalizedType = type || normalizeItemType(task);
        const meta = ITEM_TYPE_META[normalizedType] || ITEM_TYPE_META.event;
        const defaultReminderEnabled = reminderDefaults?.reminderEnabled === true
            ? true
            : meta.reminderDefault;
        const defaultReminderMinutes = Number.isFinite(Number(reminderDefaults?.reminderMinutesBefore))
            ? Number(reminderDefaults.reminderMinutesBefore)
            : 30;
        const dueDate = task?.dueDate
            ? new Date(task.dueDate)
            : new Date(targetDay.getFullYear(), targetDay.getMonth(), targetDay.getDate(), meta.defaultHour, 0, 0, 0);
        const endDate = task?.endDate
            ? new Date(task.endDate)
            : new Date(dueDate.getTime() + 60 * 60 * 1000);

        return {
            mode: task ? 'edit' : 'create',
            itemType: normalizedType,
            taskId: task?._id || '',
            selectedDate: new Date(targetDay.getFullYear(), targetDay.getMonth(), targetDay.getDate()),
            title: task?.title || '',
            description: task?.description || '',
            location: task?.location || '',
            startTime: formatTimeValue(dueDate),
            endTime: formatTimeValue(endDate),
            reminderEnabled: task?.reminderEnabled === true || (!task && defaultReminderEnabled),
            reminderMinutesBefore: Number.isFinite(Number(task?.reminderMinutesBefore))
                ? Number(task.reminderMinutesBefore)
                : defaultReminderMinutes,
            isCompleted: task?.isCompleted === true,
            source: task?.source || meta.saveSource,
        };
    };

    const openCreateModal = (type, targetDay = new Date()) => {
        const normalizedType = type || lastModalType || 'event';
        setLastModalType(normalizedType);
        setEditorState(buildDraft(normalizedType, targetDay));
    };

    const openEditModal = (task, targetDay) => {
        const normalizedType = normalizeItemType(task);
        setLastModalType(normalizedType);
        setEditorState(buildDraft(normalizedType, targetDay, task));
    };

    const openDayModal = (targetDay) => {
        const normalizedDate = new Date(targetDay);
        normalizedDate.setHours(0, 0, 0, 0);
        setSelectedDate(normalizedDate);
        setDayModalState((prev) => ({
            ...prev,
            open: true,
            feedback: '',
            savedSuggestionKeys: [],
        }));
    };

    useEffect(() => {
        if (!modalIntent?.kind) {
            return;
        }

        if (modalIntent.kind === 'import') {
            setImportState((prev) => ({ ...prev, open: true, feedback: '' }));
            return;
        }

        if (modalIntent.kind === 'plan' || modalIntent.kind === 'event' || modalIntent.kind === 'task') {
            openCreateModal(modalIntent.kind, modalIntent.date ? new Date(modalIntent.date) : new Date());
        }
    }, [modalIntent]);

    useEffect(() => {
        if (!dayModalState.open) {
            return;
        }

        let ignore = false;
        const { startDate, endDate } = dayWeatherRange();

        const loadWeather = async () => {
            if (!navigator.geolocation) {
                setDayModalState((prev) => ({
                    ...prev,
                    weather: [],
                    weatherLoading: false,
                }));
                return;
            }

            setDayModalState((prev) => ({ ...prev, weatherLoading: true }));

            try {
                const coords = weatherCoordsRef.current || await new Promise((resolve, reject) => {
                    navigator.geolocation.getCurrentPosition(
                        ({ coords: nextCoords }) => resolve(nextCoords),
                        reject,
                        { enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 },
                    );
                });
                weatherCoordsRef.current = coords;

                const cacheKey = [
                    Number(coords.latitude).toFixed(2),
                    Number(coords.longitude).toFixed(2),
                    startDate,
                    endDate,
                ].join('|');

                if (weatherCacheRef.current.has(cacheKey)) {
                    const cachedDays = weatherCacheRef.current.get(cacheKey);
                    if (!ignore) {
                        setDayModalState((prev) => ({
                            ...prev,
                            weather: cachedDays,
                            weatherLoading: false,
                        }));
                    }
                    return;
                }

                const response = await fetch(
                    `https://api.open-meteo.com/v1/forecast?latitude=${coords.latitude}&longitude=${coords.longitude}&daily=weathercode,temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&start_date=${startDate}&end_date=${endDate}`
                );
                const data = await response.json();
                if (!response.ok) {
                    throw new Error('Could not load weather.');
                }

                if (!ignore) {
                    const days = (data.daily?.time || []).map((day, index) => ({
                        date: day,
                        code: data.daily.weathercode?.[index],
                        max: data.daily.temperature_2m_max?.[index],
                        min: data.daily.temperature_2m_min?.[index],
                    }));
                    weatherCacheRef.current.set(cacheKey, days);
                    setDayModalState((prev) => ({
                        ...prev,
                        weather: days,
                        weatherLoading: false,
                    }));
                }
            } catch {
                if (!ignore) {
                    setDayModalState((prev) => ({
                        ...prev,
                        weather: [],
                        weatherLoading: false,
                    }));
                }
            }
        };

        const loadSuggestions = async () => {
            if (!session?.userId || !session?.jwtToken || !apiRoot) {
                return;
            }

            setDayModalState((prev) => ({ ...prev, suggestionsLoading: true }));

            try {
                const response = await fetch(`${apiRoot}/suggestevents`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        userId: session.userId,
                        jwtToken: session.jwtToken,
                        date: selectedDate.toISOString(),
                        localNow: new Date().toISOString(),
                        preferences: '',
                        ...currentTimeContext(),
                    }),
                });

                const data = await response.json();
                if (!response.ok) {
                    throw new Error(data.error || 'Could not load suggestions.');
                }

                if (!ignore) {
                    onSessionRefresh?.(data.jwtToken);
                    setDayModalState((prev) => ({
                        ...prev,
                        suggestions: normalizeSuggestions(data.suggestions),
                        suggestionsLoading: false,
                    }));
                }
            } catch (error) {
                if (!ignore) {
                    setDayModalState((prev) => ({
                        ...prev,
                        suggestions: [],
                        suggestionsLoading: false,
                        feedback: error.message,
                    }));
                }
            }
        };

        loadWeather();
        loadSuggestions();

        return () => {
            ignore = true;
        };
    }, [dayModalState.open, selectedDate, apiRoot, session?.userId, session?.jwtToken, onSessionRefresh]);

    useEffect(() => {
        if (!dayModalState.open || !weatherStripRef.current || dayModalState.weather.length === 0) {
            return;
        }

        const strip = weatherStripRef.current;
        const selectedIsoDate = selectedDate.toISOString().slice(0, 10);
        const selectedIndex = dayModalState.weather.findIndex((entry) => entry.date === selectedIsoDate);
        let targetIndex = selectedIndex > 0 ? selectedIndex - 1 : selectedIndex;

        if (targetIndex < 0) {
            const firstDate = dayModalState.weather[0]?.date || '';
            const lastDate = dayModalState.weather[dayModalState.weather.length - 1]?.date || '';
            if (selectedIsoDate > lastDate) {
                targetIndex = Math.max(0, dayModalState.weather.length - 2);
            } else {
                targetIndex = 0;
            }
            if (selectedIsoDate < firstDate) {
                targetIndex = 0;
            }
        }

        const targetCard = strip.children[targetIndex];

        if (!targetCard) {
            return;
        }

        const nextLeft = Math.max(0, targetCard.offsetLeft - 8);
        strip.scrollTo({ left: nextLeft, behavior: 'smooth' });
    }, [dayModalState.open, dayModalState.weather, selectedDate]);

    const updateDraft = (key, value) => {
        setEditorState((prev) => ({ ...prev, [key]: value }));
    };

    const closeEditor = () => {
        setEditorState(null);
    };

    const saveItem = async () => {
        if (!editorState?.title.trim() || !session?.userId || !session?.jwtToken) {
            return;
        }

        setIsSavingItem(true);

        try {
            const [startHour, startMinute] = editorState.startTime.split(':').map(Number);
            const [endHour, endMinute] = editorState.endTime.split(':').map(Number);
            const dueDate = new Date(
                editorState.selectedDate.getFullYear(),
                editorState.selectedDate.getMonth(),
                editorState.selectedDate.getDate(),
                Number.isFinite(startHour) ? startHour : 9,
                Number.isFinite(startMinute) ? startMinute : 0,
                0,
                0,
            );
            const endDate = new Date(
                editorState.selectedDate.getFullYear(),
                editorState.selectedDate.getMonth(),
                editorState.selectedDate.getDate(),
                Number.isFinite(endHour) ? endHour : dueDate.getHours() + 1,
                Number.isFinite(endMinute) ? endMinute : dueDate.getMinutes(),
                0,
                0,
            );

            const response = await fetch(`${apiRoot}/savecalendar`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    taskId: editorState.taskId || undefined,
                    title: editorState.title.trim(),
                    description: editorState.description.trim(),
                    location: editorState.location.trim(),
                    dueDate: dueDate.toISOString(),
                    endDate: endDate.toISOString(),
                    source: editorState.source,
                    isCompleted: editorState.itemType === 'task' ? editorState.isCompleted : false,
                    reminderEnabled: editorState.reminderEnabled,
                    reminderMinutesBefore: Number(editorState.reminderMinutesBefore),
                    ...currentTimeContext(),
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not save item.');
            }

            onSessionRefresh?.(data.jwtToken);
            refreshCalendar();
            closeEditor();
        } catch (error) {
            console.error(error);
        } finally {
            setIsSavingItem(false);
        }
    };

    const deleteItem = async () => {
        if (!editorState?.taskId || !session?.userId || !session?.jwtToken) {
            return;
        }

        setIsSavingItem(true);
        try {
            const response = await fetch(`${apiRoot}/deletecalendar`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    taskId: editorState.taskId,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not delete item.');
            }

            onSessionRefresh?.(data.jwtToken);
            refreshCalendar();
            closeEditor();
        } catch (error) {
            console.error(error);
        } finally {
            setIsSavingItem(false);
        }
    };

    const loadSubscriptions = async () => {
        if (!session?.userId || !session?.jwtToken || !apiRoot) {
            return;
        }

        setImportState((prev) => ({ ...prev, isLoadingSubscriptions: true }));
        try {
            const response = await fetch(`${apiRoot}/listcalendarsubscriptions`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not load subscriptions.');
            }

            onSessionRefresh?.(data.jwtToken);
            setImportState((prev) => ({
                ...prev,
                subscriptions: Array.isArray(data.subscriptions) ? data.subscriptions : [],
                isLoadingSubscriptions: false,
            }));
        } catch (error) {
            setImportState((prev) => ({
                ...prev,
                isLoadingSubscriptions: false,
                feedback: error.message,
            }));
        }
    };

    useEffect(() => {
        if (importState.open) {
            loadSubscriptions();
        }
    }, [importState.open]);

    const importCalendarPayload = async ({ icsUrl = '', icsContent = '' }) => {
        const timeContext = currentTimeContext();
        const response = await fetch(`${apiRoot}/readcalendar`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
                ...timeContext,
                ...(icsUrl ? { icsUrl } : {}),
                ...(icsContent ? { icsContent } : {}),
            }),
        });

        const data = await response.json();
        if (!response.ok) {
            throw new Error(data.error || 'Import failed.');
        }

        onSessionRefresh?.(data.jwtToken);
        return data;
    };

    const importFiles = async (fileList) => {
        const files = Array.from(fileList || []);
        if (!files.length) return;

        setImportState((prev) => ({ ...prev, isImporting: true, feedback: '' }));
        try {
            let totalImported = 0;

            for (const file of files) {
                const lowerName = file.name.toLowerCase();
                if (lowerName.endsWith('.ics')) {
                    const content = await file.text();
                    const data = await importCalendarPayload({ icsContent: content });
                    totalImported += Number(data.count || 0);
                    continue;
                }

                if (lowerName.endsWith('.zip')) {
                    const zip = await JSZip.loadAsync(await file.arrayBuffer());
                    const entries = [];
                    zip.forEach((name, entry) => {
                        if (!entry.dir && name.toLowerCase().endsWith('.ics')) {
                            entries.push(entry);
                        }
                    });

                    for (const entry of entries) {
                        const content = await entry.async('string');
                        const data = await importCalendarPayload({ icsContent: content });
                        totalImported += Number(data.count || 0);
                    }
                }
            }

            refreshCalendar();
            await loadSubscriptions();
            setImportState((prev) => ({
                ...prev,
                isImporting: false,
                feedback: `Imported ${totalImported} calendar events.`,
            }));
        } catch (error) {
            setImportState((prev) => ({
                ...prev,
                isImporting: false,
                feedback: error.message,
            }));
        }
    };

    const submitImport = async () => {
        if (!importState.icsUrl.trim() && !importState.icsContent.trim()) {
            setImportState((prev) => ({
                ...prev,
                feedback: 'Paste ICS content or enter an HTTPS ICS URL.',
            }));
            return;
        }

        setImportState((prev) => ({ ...prev, isImporting: true, feedback: '' }));
        try {
            const data = await importCalendarPayload({
                icsUrl: importState.icsUrl.trim(),
                icsContent: importState.icsContent.trim(),
            });
            refreshCalendar();
            await loadSubscriptions();
            setImportState((prev) => ({
                ...prev,
                isImporting: false,
                feedback: `Imported ${Number(data.count || 0)} calendar events.`,
            }));
        } catch (error) {
            setImportState((prev) => ({
                ...prev,
                isImporting: false,
                feedback: error.message,
            }));
        }
    };

    const syncSubscription = async (subscriptionId) => {
        const timeContext = currentTimeContext();
        setImportState((prev) => ({ ...prev, isSyncingSubscriptionId: subscriptionId, feedback: '' }));
        try {
            const response = await fetch(`${apiRoot}/synccalendarsubscription`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    subscriptionId,
                    ...timeContext,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not sync subscription.');
            }

            onSessionRefresh?.(data.jwtToken);
            refreshCalendar();
            await loadSubscriptions();
            setImportState((prev) => ({
                ...prev,
                isSyncingSubscriptionId: '',
                feedback: 'Calendar synced.',
            }));
        } catch (error) {
            setImportState((prev) => ({
                ...prev,
                isSyncingSubscriptionId: '',
                feedback: error.message,
            }));
        }
    };

    const deleteSubscription = async (subscriptionId) => {
        setImportState((prev) => ({ ...prev, isDeletingSubscriptionId: subscriptionId, feedback: '' }));
        try {
            const response = await fetch(`${apiRoot}/deletecalendarsubscription`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    subscriptionId,
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not remove subscription.');
            }

            onSessionRefresh?.(data.jwtToken);
            refreshCalendar();
            await loadSubscriptions();
            setImportState((prev) => ({
                ...prev,
                isDeletingSubscriptionId: '',
                feedback: 'Subscription removed.',
            }));
        } catch (error) {
            setImportState((prev) => ({
                ...prev,
                isDeletingSubscriptionId: '',
                feedback: error.message,
            }));
        }
    };

    const saveDaySuggestion = async (suggestion) => {
        if (!session?.userId || !session?.jwtToken) {
            return;
        }

        const key = suggestionKey(suggestion);
        if (dayModalState.savedSuggestionKeys.includes(key)) {
            return;
        }

        setIsSavingItem(true);
        try {
            const suggestedTime = String(suggestion?.suggestedTime || '12:00');
            const timeParts = suggestedTime.split(':').map(Number);
            const hour = timeParts[0];
            const minute = timeParts[1];
            const startDate = new Date(
                selectedDate.getFullYear(),
                selectedDate.getMonth(),
                selectedDate.getDate(),
                Number.isFinite(hour) ? hour : 12,
                Number.isFinite(minute) ? minute : 0,
                0,
                0,
            );
            const endDate = new Date(startDate.getTime() + 60 * 60 * 1000);

            const response = await fetch(`${apiRoot}/savecalendar`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    title: suggestion?.title || 'Suggested event',
                    description: suggestion?.description || '',
                    dueDate: startDate.toISOString(),
                    endDate: endDate.toISOString(),
                    source: 'event',
                    ...currentTimeContext(),
                }),
            });

            const data = await response.json();
            if (!response.ok) {
                throw new Error(data.error || 'Could not save suggestion.');
            }

            onSessionRefresh?.(data.jwtToken);
            setDayModalState((prev) => ({
                ...prev,
                savedSuggestionKeys: [...prev.savedSuggestionKeys, key],
            }));
            refreshCalendar();
        } catch (error) {
            setDayModalState((prev) => ({ ...prev, feedback: error.message }));
        } finally {
            setIsSavingItem(false);
        }
    };

    const shiftSelectedDay = (dayDelta) => {
        setSelectedDate((prev) => {
            const next = new Date(prev);
            next.setDate(next.getDate() + dayDelta);
            next.setHours(0, 0, 0, 0);
            return next;
        });
        setDayModalState((prev) => ({
            ...prev,
            feedback: '',
            savedSuggestionKeys: [],
        }));
    };

    const editorMeta = editorState ? ITEM_TYPE_META[editorState.itemType] || ITEM_TYPE_META.event : null;

    return (
        <div className="calendar-calendar-background">
            <div className="calendar-month-interactable-header">
                {singleMonth && <img onClick={() => setCurrentMonthIndex(currentMonthIndex - 1)} className="calendar-month-arrow" src={UpArrow} alt="Previous month" />}
                <h1 className="calendar-month-month-name">{monthName} {year}</h1>
                {singleMonth && <img onClick={() => setCurrentMonthIndex(currentMonthIndex + 1)} className="calendar-month-arrow" src={DownArrow} alt="Next month" />}
            </div>

            <div className="calendar-weekdays">
                {weekdays.map((day) => (
                    <div key={day} className="weekday">{day}</div>
                ))}
            </div>

            {singleMonth ? (
                <div className="calendar-month">
                    <CalendarMonth
                        monthsFromNow={currentMonthIndex}
                        setBackgroundWeather={setBackgroundWeather}
                        singleMonth={singleMonth}
                        tasks={calendarTasks}
                        onSelectDay={openDayModal}
                        onSelectTask={openEditModal}
                        selectedDate={selectedDate}
                    />
                </div>
            ) : (
                <div ref={containerRef} className="calendar-scroll-shell">
                    {Array.from({ length: renderedMonths }, (_, i) => (
                        <div key={i} data-index={i} className="calendar-month">
                            <CalendarMonth
                                monthsFromNow={i}
                                setBackgroundWeather={setBackgroundWeather}
                                singleMonth={singleMonth}
                                tasks={calendarTasks}
                                onSelectDay={openDayModal}
                                onSelectTask={openEditModal}
                                selectedDate={selectedDate}
                                ref={i === renderedMonths - 1 ? lastMonthRef : null}
                            />
                        </div>
                    ))}
                </div>
            )}

            {dayModalState.open && (
                <div className="calendar-task-modal-overlay" onClick={() => setDayModalState((prev) => ({ ...prev, open: false }))}>
                    <div className="calendar-task-modal calendar-day-modal" onClick={(event) => event.stopPropagation()}>
                        <div className="calendar-task-modal-header">
                            <div>
                                <div className="calendar-item-type-chip">day</div>
                                <h2>{selectedDate.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</h2>
                            </div>
                            <div className="calendar-day-modal-header-actions">
                                <button type="button" className="calendar-task-close-btn" onClick={() => openCreateModal(lastModalType || 'event', selectedDate)}>
                                    Add item
                                </button>
                                <button type="button" className="calendar-task-close-btn" onClick={() => setDayModalState((prev) => ({ ...prev, open: false }))}>
                                    Close
                                </button>
                            </div>
                        </div>
                        <div className="calendar-day-weather-strip-shell">
                            <button type="button" className="calendar-day-weather-nav" onClick={() => shiftSelectedDay(-1)}>
                                <span className="calendar-day-weather-nav-glyph" aria-hidden="true">&#8249;</span>
                            </button>
                            <div ref={weatherStripRef} className="calendar-day-weather-strip">
                            {dayModalState.weatherLoading ? (
                                <div className="calendar-day-weather-empty">Loading weather...</div>
                            ) : dayModalState.weather.length > 0 ? (
                                dayModalState.weather.map((entry) => (
                                    <div
                                        key={entry.date}
                                        className={`calendar-day-weather-card ${entry.date === selectedDate.toISOString().slice(0, 10) ? 'active' : ''}`}
                                        onClick={() => {
                                            const nextDate = new Date(`${entry.date}T00:00:00`);
                                            nextDate.setHours(0, 0, 0, 0);
                                            setSelectedDate(nextDate);
                                            setDayModalState((prev) => ({
                                                ...prev,
                                                feedback: '',
                                                savedSuggestionKeys: [],
                                            }));
                                        }}
                                    >
                                        <div className="calendar-day-weather-weekday">
                                            {new Date(`${entry.date}T00:00:00`).toLocaleDateString([], { weekday: 'short' })}
                                        </div>
                                        <div className="calendar-day-weather-icon">{weatherGlyph(entry.code)}</div>
                                        <div className="calendar-day-weather-range">
                                            <span>{Math.round(Number(entry.max || 0))}{'\u00B0'}</span>
                                            <span>{Math.round(Number(entry.min || 0))}{'\u00B0'}</span>
                                        </div>
                                        <div className="calendar-day-weather-label">{weatherCodeToLabel(entry.code)}</div>
                                    </div>
                                ))
                            ) : (
                                <div className="calendar-day-weather-empty">Weather unavailable for this date.</div>
                            )}
                            </div>
                            <button type="button" className="calendar-day-weather-nav" onClick={() => shiftSelectedDay(1)}>
                                <span className="calendar-day-weather-nav-glyph" aria-hidden="true">&#8250;</span>
                            </button>
                        </div>
                        <div className="calendar-day-modal-body">
                            <div className="calendar-day-column">
                                <div className="calendar-day-column-header">
                                    <h3>Tasks for the day</h3>
                                    <span>{selectedDayTasks.length} scheduled</span>
                                </div>
                                <div className="calendar-day-list">
                                    {selectedDayTasks.length > 0 ? selectedDayTasks.map((task) => (
                                        <button
                                            key={task._id || `${task.title}-${task.dueDate}`}
                                            type="button"
                                            className={`calendar-day-card ${normalizeItemType(task)}`}
                                            onClick={() => openEditModal(task, selectedDate)}
                                        >
                                            <div className="calendar-day-card-time">{formatTaskTime(task.dueDate)}</div>
                                            <div className="calendar-day-card-title">{task.title || 'Untitled'}</div>
                                            {task.description && (
                                                <div className="calendar-day-card-copy">
                                                    {renderCalendarMarkdown(task.description)}
                                                </div>
                                            )}
                                        </button>
                                    )) : (
                                        <div className="calendar-day-empty">Nothing scheduled yet. Add an item or pull suggestions.</div>
                                    )}
                                    <button
                                        type="button"
                                        className="calendar-day-add-schedule-card"
                                        onClick={() => openCreateModal(lastModalType || 'event', selectedDate)}
                                    >
                                        <span className="calendar-day-add-schedule-kicker">Quick add</span>
                                        <span className="calendar-day-add-schedule-title">Add to Schedule</span>
                                        <span className="calendar-day-add-schedule-copy">Create a plan, event, or task for this day.</span>
                                    </button>
                                </div>
                            </div>
                            <div className="calendar-day-column">
                                <div className="calendar-day-column-header">
                                    <h3>Suggestions</h3>
                                    <span>{dayModalState.suggestions.length} ready</span>
                                </div>
                                <div className="calendar-day-list">
                                    {dayModalState.suggestionsLoading ? (
                                        <div className="calendar-day-empty">Finding ideas...</div>
                                    ) : dayModalState.suggestions.length > 0 ? dayModalState.suggestions.map((suggestion, index) => {
                                        const key = suggestionKey(suggestion);
                                        const isSaved = dayModalState.savedSuggestionKeys.includes(key);

                                        return (
                                        <div key={`${suggestion.title}-${index}`} className="calendar-day-card suggestion">
                                            <div className="calendar-day-card-time">{suggestion.suggestedTime || 'Flexible'}</div>
                                            <div className="calendar-day-card-title">{suggestion.title}</div>
                                            <div className="calendar-day-card-copy">
                                                {renderCalendarMarkdown(suggestion.description)}
                                            </div>
                                            <button
                                                type="button"
                                                className={`calendar-day-add-icon ${isSaved ? 'saved' : ''}`}
                                                onClick={() => saveDaySuggestion(suggestion)}
                                                disabled={isSaved || isSavingItem}
                                                aria-label={isSaved ? 'Already added' : 'Add to calendar'}
                                            >
                                                {isSaved ? '\u2713' : '+'}
                                            </button>
                                        </div>
                                    ); }) : (
                                        <div className="calendar-day-empty">No suggestions yet for this day.</div>
                                    )}
                                </div>
                            </div>
                        </div>
                        {dayModalState.feedback && <div className="calendar-import-feedback calendar-day-feedback">{dayModalState.feedback}</div>}
                    </div>
                </div>
            )}

            {editorState && editorMeta && (
                <div className="calendar-task-modal-overlay" onClick={closeEditor}>
                    <div className={`calendar-task-modal calendar-item-modal ${editorState.itemType}`} onClick={(event) => event.stopPropagation()}>
                        <div className="calendar-task-modal-header">
                            <div>
                                <div className="calendar-item-type-chip">{editorState.itemType}</div>
                                <h2>{editorState.mode === 'edit' ? editorMeta.modalTitleEdit : editorMeta.modalTitleCreate}</h2>
                            </div>
                            <button type="button" className="calendar-task-close-btn" onClick={closeEditor}>Close</button>
                        </div>
                        <div className="calendar-task-modal-body">
                            <label className="calendar-task-field">
                                <span>{editorMeta.titleLabel}</span>
                                <input value={editorState.title} onChange={(event) => updateDraft('title', event.target.value)} placeholder="Add a title" />
                            </label>
                            <label className="calendar-task-field">
                                <span>{editorMeta.descriptionLabel}</span>
                                <textarea value={editorState.description} onChange={(event) => updateDraft('description', event.target.value)} placeholder={editorMeta.descriptionPlaceholder} />
                            </label>
                            <div className="calendar-task-field-row">
                                <label className="calendar-task-field">
                                    <span>Start</span>
                                    <input type="time" value={editorState.startTime} onChange={(event) => updateDraft('startTime', event.target.value)} />
                                </label>
                                <label className="calendar-task-field">
                                    <span>End</span>
                                    <input type="time" value={editorState.endTime} onChange={(event) => updateDraft('endTime', event.target.value)} />
                                </label>
                            </div>
                            <label className="calendar-task-field">
                                <span>{editorMeta.locationLabel}</span>
                                <input value={editorState.location} onChange={(event) => updateDraft('location', event.target.value)} placeholder="Add a location" />
                            </label>
                            <div className="calendar-task-reminder-row">
                                <label className="calendar-task-checkbox">
                                    <input type="checkbox" checked={editorState.reminderEnabled} onChange={(event) => updateDraft('reminderEnabled', event.target.checked)} />
                                    <span>Email reminder</span>
                                </label>
                                <select value={editorState.reminderMinutesBefore} onChange={(event) => updateDraft('reminderMinutesBefore', Number(event.target.value))} disabled={!editorState.reminderEnabled}>
                                    {REMINDER_OPTIONS.map((option) => (
                                        <option key={option.value} value={option.value}>{option.label}</option>
                                    ))}
                                </select>
                            </div>
                            {editorMeta.showCompletion && (
                                <label className="calendar-task-checkbox calendar-task-checkbox-standalone">
                                    <input type="checkbox" checked={editorState.isCompleted} onChange={(event) => updateDraft('isCompleted', event.target.checked)} />
                                    <span>Mark task complete</span>
                                </label>
                            )}
                        </div>
                        <div className="calendar-task-modal-actions">
                            {editorState.taskId && (
                                <button type="button" className="calendar-task-delete-btn" onClick={deleteItem} disabled={isSavingItem}>Delete</button>
                            )}
                            <button type="button" className="calendar-task-save-btn" onClick={saveItem} disabled={isSavingItem}>
                                {isSavingItem ? 'Saving...' : 'Save'}
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {importState.open && (
                <div className="calendar-task-modal-overlay" onClick={() => setImportState((prev) => ({ ...prev, open: false }))}>
                    <div className="calendar-task-modal calendar-import-modal" onClick={(event) => event.stopPropagation()}>
                        <div className="calendar-task-modal-header">
                            <div>
                                <div className="calendar-item-type-chip">import</div>
                                <h2>Import Calendar</h2>
                            </div>
                            <button type="button" className="calendar-task-close-btn" onClick={() => setImportState((prev) => ({ ...prev, open: false }))}>Close</button>
                        </div>
                        <div className="calendar-task-modal-body">
                            <div className="calendar-import-upload-row">
                                <label className="calendar-task-save-btn calendar-import-file-btn">
                                    Upload .ics or .zip
                                    <input type="file" accept=".ics,.zip" multiple onChange={(event) => importFiles(event.target.files)} hidden />
                                </label>
                            </div>
                            <label className="calendar-task-field">
                                <span>ICS URL</span>
                                <input value={importState.icsUrl} onChange={(event) => setImportState((prev) => ({ ...prev, icsUrl: event.target.value }))} placeholder="https://..." />
                            </label>
                            <label className="calendar-task-field">
                                <span>Paste ICS content</span>
                                <textarea value={importState.icsContent} onChange={(event) => setImportState((prev) => ({ ...prev, icsContent: event.target.value }))} placeholder="BEGIN:VCALENDAR..." />
                            </label>
                            <div className="calendar-import-subscriptions">
                                <div className="calendar-import-subscriptions-header">
                                    <h3>Connected calendars</h3>
                                    <button type="button" className="calendar-task-close-btn" onClick={loadSubscriptions}>Refresh</button>
                                </div>
                                {importState.isLoadingSubscriptions ? (
                                    <div className="calendar-import-empty">Loading calendars...</div>
                                ) : importState.subscriptions.length === 0 ? (
                                    <div className="calendar-import-empty">No connected calendars yet.</div>
                                ) : (
                                    <div className="calendar-import-subscription-list">
                                        {importState.subscriptions.map((subscription) => (
                                            <div key={subscription._id} className="calendar-import-subscription-row">
                                                <div className="calendar-import-subscription-copy">
                                                    <div className="calendar-import-subscription-name">{subscription.name || 'Imported calendar'}</div>
                                                    <div className="calendar-import-subscription-url">{subscription.url}</div>
                                                    {subscription.lastSyncedAt && <div className="calendar-import-subscription-meta">Synced {new Date(subscription.lastSyncedAt).toLocaleString()}</div>}
                                                    {subscription.lastSyncError && <div className="calendar-import-subscription-error">{subscription.lastSyncError}</div>}
                                                </div>
                                                <div className="calendar-import-subscription-actions">
                                                    <button type="button" className="calendar-task-close-btn" onClick={() => syncSubscription(subscription._id)} disabled={importState.isSyncingSubscriptionId === subscription._id}>
                                                        {importState.isSyncingSubscriptionId === subscription._id ? 'Syncing...' : 'Sync'}
                                                    </button>
                                                    <button type="button" className="calendar-task-delete-btn" onClick={() => deleteSubscription(subscription._id)} disabled={importState.isDeletingSubscriptionId === subscription._id}>
                                                        {importState.isDeletingSubscriptionId === subscription._id ? 'Removing...' : 'Remove'}
                                                    </button>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                )}
                            </div>
                            {importState.feedback && <div className="calendar-import-feedback">{importState.feedback}</div>}
                        </div>
                        <div className="calendar-task-modal-actions">
                            <button type="button" className="calendar-task-save-btn" onClick={submitImport} disabled={importState.isImporting}>
                                {importState.isImporting ? 'Importing...' : 'Import'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

export default Calendar;

