//SHOULD BE WHAT SHOWS AS CENTER CONTENT WHEN YOU CLICK ON A DATE
//WILL HOLD ALL INFO FOR THE DATE CLICKED ON INCLUDING HOURLY WEATHER
//TASKS, REMINDERS, SUGGESTIONS, ADD EVENT, EDIT EVENT, REMOVE EVENT

import './EnlargedDate.css';

//FOR TRAVERSAL WHEN WITHIN ENLARGED DATE MODAL
import UpArrow from './icons/arrow-big-up.svg';
import DownArrow from './icons/arrow-big-down.svg';

import {useState, useEffect} from 'react';

//REQUIRES THE DATE PASSED IN & ITS CURRENT WEATHER (IF APPLICABLE) 
function EnlargedDate({setSelectedCalendarDate, selectedCalendarDate, selectedCalendarDateWeather}){

    // HOLDS HOURLY WEATHER FOR THE SELECTED DAY
    const [hourlyWeatherArr, setHourlyWeatherArr] = useState([]);

    //FOR DETERMINING CURRENT WEATHER TIME ON CURRENT DAY
    const date = new Date();

    useEffect(() => {
        if (!selectedCalendarDateWeather || !selectedCalendarDate) {
            setHourlyWeatherArr([]);
            return;
        }

        const { time, temperature_2m, weathercode } = selectedCalendarDateWeather;

        if (time && temperature_2m && weathercode) {
            const selectedDateStr = selectedCalendarDate.toISOString().split('T')[0]; // 'YYYY-MM-DD'

            const hourlyData = time
            .map((t, index) => ({
                fullDate: t,
                time: new Date(t).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }),
                icon: weatherCodeToIcon(weathercode[index]),
                temp: Math.round((temperature_2m[index] * 9) / 5 + 32) // Celsius -> Fahrenheit
            }))
            // FILTER ONLY HOURS OF THE SELECTED DATE
            .filter(hour => hour.fullDate.startsWith(selectedDateStr));

            setHourlyWeatherArr(hourlyData);
        } else {
            setHourlyWeatherArr([]);
        }
    }, [selectedCalendarDateWeather, selectedCalendarDate]);

    // API code -> emoji converter
    function weatherCodeToIcon(code) {
        switch(code) {
            case 0: return '☀️';
            case 1: return '🌤';
            case 2: return '⛅️';
            case 3: return '☁️';
            case 61: return '🌧';
            case 63: return '🌦';
            case 71: return '❄️';
            default: return '❓';
        }
    }

    return(

        //THE OVERALL BUBBLED WRAPPER ENCOMPASSING THE ENLARGED DATE
        <div className = "enlarged-date-wrapper">
            {/* THE DATE TITLE AT THE TOP MIDDLE OF THE WRAPPER */}
            <div className = "enlarged-date-top-title">
                {/* THE TEXT FOR THE ENLARGED DATE TITLE TO KNOW WHICH DATE IT IS USING */}
                <h2 className = 'enlarged-date-top-title-text'>{selectedCalendarDate?.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' , year: 'numeric'}) || 'INVALID DATE'}</h2>
            </div>
            {/* HOLDS THE HOURLY WEATHER FOR THE CURRENT DATE SELECTED IF APPLICABLE */}
            {selectedCalendarDateWeather != null && <div className = "enlarged-date-hourly-weather-wrapper">
                <div className="enlarged-date-hourly-weather-wrapper">
                    {hourlyWeatherArr.map((hour, index) => {
                        const hourTime = new Date(hour.fullDate).getTime();
                        const nextHourTime = hourTime + 60 * 60 * 1000; // add 1 hour in ms
                        const isActive = date.getTime() >= hourTime && date.getTime() < nextHourTime;

                        return (
                            <div key={index} className={`hourly-item ${isActive ? "active" : ""}`}>
                                <div className="hourly-time">{hour.time}</div>
                                <div className="hourly-icon">{hour.icon}</div>
                                <div className="hourly-temp">{hour.temp}°</div>
                            </div>
                        );
                    })}                    
                </div>
            </div>}
            {/* HOLDS THE SUGGESTED CONTENT FOR THE CURRENT DAY */}
            <div className = "enlarged-date-suggested-content-wrapper">
                {/* THE TEXT FOR THE ENLARGED DATE TITLE TO KNOW WHICH DATE IT IS USING */}
                <h2 className='enlarged-date-top-title'>Suggestions</h2>
            </div>
            {/* HOLDS THE TASKS/REMINDERS OF THE CURRENT DAY */}
            <div className = "enlarged-date-tasks-wrapper">
                <h2 className='enlarged-date-top-title'>Tasks</h2>
            </div>
        </div>

    );
}

export default EnlargedDate;