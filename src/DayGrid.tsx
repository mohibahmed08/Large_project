// @ts-nocheck
//IMMPORT THE STYLE SHEET
import './DayGrid.css';

//THIS CLASS WILL BE ONE DAY INSIDE THE CALENDAR GRID
//I.E. THE BOX THAT IS INTERACTABLE AND SHOWS STUFF
//WITHIN THE CALENDAR U.I.

//SHOULD BE USED AS AN ARRAY OF DAYS WITHIN THE CALENDAR U.I.
function DayGrid({
    weather,
    setCurrentWeather,
    maxFutureWeatherDays,
    maxPastWeatherDays,
    dayOfMonth,
    year,
    month,
    isOtherMonth,
    tasks = [],
    onSelectDay,
    onSelectTask,
    selectedDate,
}){

    //DATE OBJECT FOR DETERMINING THINGS
    const date = new Date();

    //CHECK IF THIS DAY GRID IS ACTIVE (TODAY == DAY OF MONTH)
    const isToday = dayOfMonth == date.getDate() && year == date.getFullYear() && month == date.getMonth();

    //TARGET DATE FOR DAY INDEX AND WITHIN WEEK
    const targetDate = new Date(year, month, dayOfMonth);
    //NORMALIZE THE HOURS
    targetDate.setHours(0,0,0,0);
    const normalizedSelectedDate = selectedDate ? new Date(selectedDate) : null;
    if (normalizedSelectedDate) {
        normalizedSelectedDate.setHours(0, 0, 0, 0);
    }
    const isSelected = normalizedSelectedDate ? targetDate.getTime() === normalizedSelectedDate.getTime() : false;
    //COMPUTE THE DIFFERENCE IN TIME
    const diffMs = targetDate - date; 
    //CONVERT THAT TO DAYS AND DETERMINE DIFFERENCE IN DAYS
    const diffDays = diffMs / (1000 * 60 * 60 * 24);
    //TRUE IF TARGET DAY IS 7 DAYS AWAY FROM CURRENT
    const isWithinWeather = diffDays >= -maxPastWeatherDays - 1 && diffDays <= maxFutureWeatherDays;
    
    //COMPUTES THE DAY INDEX
    const dayIndex = Math.floor(diffDays + 1);
    //COMPUTES THE START HOUR FOR EACH DAY
    // const hourIndex = dayIndex * 24; // start of the day in hourly array

    //GENERAL WEATHER FOR THE CURRENT DAY
    const generalWeather = weather ? weatherCodeToText(getDailyGeneralWeather(weather.hourly.weathercode, dayIndex)) : "";
    
    //PASS IN THE CURRENT WEATHER FOR TODAY
    if(isToday) setCurrentWeather(generalWeather);

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

    //RETURN DOM
    return (
        <>
            {/* THE DATE BOX ITSELF CONTAINING SUBINFO AND IF ACTIVE (CURRRENT DAY), OTHER MONTH IF SPACER FROM PRIOR/NEXT MONTH BLEEDING OVER TO THIS ONE */}
            <div
                className = {`day-grid-wrapper ${isToday ? "active" : ""} ${isSelected ? "selected" : ""} ${isOtherMonth ? "other-month" : ""}`}
                onClick={() => onSelectDay?.(targetDate)}
            >
                {/* TOP LEFT WEATHER OF THE CURRENT DAY */}
                {isWithinWeather && <span className = "day-grid-weather-header">{generalWeather}</span>}
                {/* TOP RIGHT DAY NUMBER IN THE BOX */}
                <span className = "day-grid-day-number">{dayOfMonth}</span>
                {/* SECTION TO HOLD TILED REMINDERS / SUGGESTIONS */}
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

//TURNS THE WEATHER CODE TO MEANINGFUL TEXT 
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

//GETS THE MOST GENERAL WEATHER FOR THE DAY BASED ON CHOOSING 
//THE WEATHERCODE THAT IS MOST OCCURING
function getDailyGeneralWeather(hourlyWeather, dayIndex) {
    const start = dayIndex * 24;
    const dayHours = hourlyWeather.slice(start, start + 24);

    // Count frequency
    const counts = {};
    dayHours.forEach(code => counts[code] = (counts[code] || 0) + 1);

    // Find most frequent
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
