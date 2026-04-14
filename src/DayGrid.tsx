// @ts-nocheck
// Calendar day cell styles.
import { useEffect } from 'react';
import './DayGrid.css';

// Render one day cell inside the monthly calendar grid.
function DayGrid({
    weather,
    setCurrentWeather,
    dayOfMonth,
    year,
    month,
    isOtherMonth,
    tasks = [],
    onSelectDay,
    onSelectTask,
    selectedDate,
}){

    // Normalize the current day once so date comparisons stay stable.
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Flag the tile when it represents the current local date.
    const isToday = dayOfMonth === today.getDate() && year === today.getFullYear() && month === today.getMonth();

    // Normalize the rendered date so selection and weather checks use the same boundary.
    const targetDate = new Date(year, month, dayOfMonth);
    targetDate.setHours(0, 0, 0, 0);
    const normalizedSelectedDate = selectedDate ? new Date(selectedDate) : null;
    if (normalizedSelectedDate) {
        normalizedSelectedDate.setHours(0, 0, 0, 0);
    }
    const isSelected = normalizedSelectedDate ? targetDate.getTime() === normalizedSelectedDate.getTime() : false;

    // Resolve weather directly from the hourly timestamps to avoid off-by-one date bugs.
    const dailyWeatherCode = weather ? getDailyGeneralWeather(weather.hourly, targetDate) : null;
    const generalWeather = dailyWeatherCode === null ? '' : weatherCodeToText(dailyWeatherCode);
    const isWithinWeather = Boolean(generalWeather);
    
    useEffect(() => {
        if (!isToday) {
            return;
        }

        setCurrentWeather?.(generalWeather);
    }, [generalWeather, isToday, setCurrentWeather]);

    const eventPillClass = (task) => {
        const source = String(task?.source || '').toLowerCase();
        if (source === 'plan') return 'plan';
        if (source === 'task') return 'task';
        if (source === 'ical') return 'imported';
        return 'event';
    };

    const parseTaskColor = (colorValue) => {
        const normalized = String(colorValue || '').trim().replace('#', '');
        if (!normalized || (normalized.length !== 6 && normalized.length !== 8)) {
            return '';
        }

        return `#${normalized.slice(0, 8)}`;
    };

    const fallbackTaskColor = (task) => {
        const source = String(task?.source || '').toLowerCase();
        if (source === 'ical') return '#94A3B8';
        if (source === 'task') return '#22C55E';
        if (source === 'plan') return '#A855F7';
        return '#60A5FA';
    };

    const toRgba = (hexColor, alpha) => {
        const normalized = String(hexColor || '').trim().replace('#', '');
        if (normalized.length !== 6) {
            return `rgba(96, 165, 250, ${alpha})`;
        }

        const red = parseInt(normalized.slice(0, 2), 16);
        const green = parseInt(normalized.slice(2, 4), 16);
        const blue = parseInt(normalized.slice(4, 6), 16);
        return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
    };

    const taskDisplayColor = (task) => parseTaskColor(task?.color) || fallbackTaskColor(task);

    return (
        <>
            {/* The tile can be active for today, selected, or dimmed when it belongs to an adjacent month. */}
            <div
                className = {`day-grid-wrapper ${isToday ? "active" : ""} ${isSelected ? "selected" : ""} ${isOtherMonth ? "other-month" : ""}`}
                onClick={() => onSelectDay?.(targetDate)}
            >
                {/* Show the dominant weather label when the fetched dataset includes this date. */}
                {isWithinWeather && <span className = "day-grid-weather-header">{generalWeather}</span>}
                {/* Day number in the upper-right corner. */}
                <span className = "day-grid-day-number">{dayOfMonth}</span>
                {/* Task pills for the current date. */}
                <div className = {`day-grid-tile-wrapper`}>
                    {tasks.length > 0 && <ul className = "day-grid-ul">
                        {tasks.map((task) => (
                            <li
                                className = {`day-grid-event-pill ${eventPillClass(task)}`}
                                key = {task._id || `${task.title}-${task.dueDate}`}
                                style={{
                                    '--pill-accent': taskDisplayColor(task),
                                    '--pill-bg': toRgba(taskDisplayColor(task), 0.18),
                                }}
                                onClick={(event) => {
                                    event.stopPropagation();
                                    onSelectTask?.(task, targetDate);
                                }}
                            >
                                {task.reminderEnabled && <span className="day-grid-event-pill-dot" />}
                                <span className='day-grid-event-pill-title'>{task.title || "Untitled"}</span>
                            </li>
                        ))}
                    </ul>}
                </div>
            </div>
        </>
    );

}

// Map Open-Meteo weather codes to display labels.
function weatherCodeToText(code) {
    switch (code) {
        case 0: return "Clear sky";               
        case 1: return "Mostly clear";                 
        case 2: return "Partly cloudy";
        case 3: return "Overcast";
        case 45: case 48: return "Foggy";
        case 51: case 53: case 55: return "Light drizzle";
        case 56: case 57: return "Freezing drizzle";
        case 61: case 63: case 65: return "Rainy";
        case 66: case 67: return "Freezing rain";
        case 71: case 73: case 75: return "Snowy";
        case 77: return "Snow grains";
        case 80: case 81: case 82: return "Rain showers";
        case 85: case 86: return "Snow showers";
        case 95: return "Thunderstorm";
        case 96: case 99: return "Thunderstorm with hail";
        default: return "Unknown";
    }
}

function buildLocalDateKey(dateValue) {
    return `${dateValue.getFullYear()}-${String(dateValue.getMonth() + 1).padStart(2, '0')}-${String(dateValue.getDate()).padStart(2, '0')}`;
}

// Use the most frequent hourly weather code for the requested local date.
function getDailyGeneralWeather(hourlyData, targetDate) {
    const targetDateKey = buildLocalDateKey(targetDate);
    const hourlyTimes = Array.isArray(hourlyData?.time) ? hourlyData.time : [];
    const hourlyWeather = Array.isArray(hourlyData?.weathercode) ? hourlyData.weathercode : [];
    const dayHours = hourlyWeather.filter((code, index) => String(hourlyTimes[index] || '').startsWith(targetDateKey));

    if (dayHours.length === 0) {
        return null;
    }

    const counts = {};
    dayHours.forEach(code => counts[code] = (counts[code] || 0) + 1);

    let maxCount = 0;
    let generalCode = dayHours[0];
    for (const code in counts) {
        if (counts[code] > maxCount) {
            maxCount = counts[code];
            generalCode = parseInt(code);
        }
    }

    return generalCode;
}

//EXPORT TO OTHER JSX CLASSES FOR USABILITY
export default DayGrid;
