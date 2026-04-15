// @ts-nocheck
import './CalendarMonth.css';

// Day grid cells and weather fetcher for the calendar month view.
import DayGrid from './DayGrid';
import Weather from './Weather';

import { useState, useEffect, useMemo, cloneElement } from 'react';

function CalendarMonth({monthsFromNow, setBackgroundWeather, singleMonth, tasks = [], onSelectDay, onSelectTask, selectedDate}){

    // Cache the fetched weather payload for this month view.
    const [weather, setWeather] = useState(null);
    
    // Base all month math on the current local date.
    const date = new Date();

    // Resolve the month being rendered.
    const targetDate = new Date(date.getFullYear(), date.getMonth() + monthsFromNow, 1);
    const daysInMonth = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0).getDate();
    const firstDay = targetDate.getDay();
    const year = targetDate.getFullYear();

    // Limit weather requests to the range supported by the current UI.
    const earliestAllowed = new Date(date.getFullYear(), date.getMonth() - 4, date.getDate()); // 4 months ago
    
    const latestAllowed = new Date(date); // today
    latestAllowed.setDate(latestAllowed.getDate() + 14); // two weeks ahead

    // Clamp the month range before making a weather request.
    const monthStart = targetDate < earliestAllowed ? earliestAllowed : targetDate;
    const monthEndDate = new Date(targetDate.getFullYear(), targetDate.getMonth(), daysInMonth);
    const monthEnd = monthEndDate > latestAllowed ? latestAllowed : monthEndDate;

    const weatherEnabled = monthEnd >= monthStart;
    const maxPastWeatherDays = weatherEnabled ? Math.max(0, Math.floor((date - monthStart) / (1000 * 60 * 60 * 24))) : 0;
    const maxFutureWeatherDays = weatherEnabled ? Math.max(0, Math.floor((monthEnd - date) / (1000 * 60 * 60 * 24))) : 0;

    // Track the current day's weather so the parent can update the background.
    const [currentWeather, setCurrentWeather] = useState('');

    useEffect(()=>{
        if(!weatherEnabled || !currentWeather) return;
        setBackgroundWeather(currentWeather);
    }, [currentWeather, setBackgroundWeather, weatherEnabled])

    // Build the visible day cells for the target month.
    const realDays =  
        Array.from( {length : daysInMonth}, (_, i) => 
            <DayGrid key = {i} setCurrentWeather = {setCurrentWeather} weather = {weather} dayOfMonth = {i + 1} year = {targetDate.getFullYear()} month = {targetDate.getMonth()}/>
        );

    // Include the trailing days from the previous month for single-month mode.
    const prevMonthDays = singleMonth ? Array.from({ length: firstDay }, (_, i) => {
        const prevMonthDate = new Date(year, date.getMonth() + monthsFromNow, 0);
        const daysInPrevMonth = prevMonthDate.getDate();
        const day = daysInPrevMonth - firstDay + i + 1;
        
        return (<DayGrid key={`prev-${i}`} setCurrentWeather={setCurrentWeather} weather={weather} dayOfMonth={day} year={prevMonthDate.getFullYear()} month={prevMonthDate.getMonth()} isOtherMonth={true}/>);
    
    }) : [];

    const dayArr = [...prevMonthDays, ...realDays];
    const monthTaskMap = useMemo(() => {
        const entries = {};
        tasks.forEach((task) => {
            if (!task?.dueDate) {
                return;
            }

            const dueDate = new Date(task.dueDate);
            const key = `${dueDate.getFullYear()}-${dueDate.getMonth()}-${dueDate.getDate()}`;
            if (!entries[key]) {
                entries[key] = [];
            }
            entries[key].push(task);
        });

        return entries;
    }, [tasks]);

    const dayTasks = (targetYear, targetMonth, targetDay) => {
        const normalizedDate = new Date(targetYear, targetMonth, targetDay);
        const key = `${normalizedDate.getFullYear()}-${normalizedDate.getMonth()}-${normalizedDate.getDate()}`;
        return monthTaskMap[key] || [];
    };

    return (
        <>
            {/* Fetch weather once for the visible month range. */}
            {weatherEnabled && <Weather setWeather = {setWeather} desiredDate = {monthStart} additionalDays = {maxFutureWeatherDays} priorDays = {maxPastWeatherDays}/>}

            <div className="calendar-month-wrapper"> 
                <div className="calendar-month-day-grid-wrapper" style = {{"--first-day" : !singleMonth ? firstDay + 1 : 0}}>  
                    {dayArr.map((dayElement) => {
                        if (!dayElement?.props) {
                            return dayElement;
                        }

                        const targetTasks = dayTasks(
                            dayElement.props.year,
                            dayElement.props.month,
                            dayElement.props.dayOfMonth,
                        );

                        return cloneElement(dayElement, {
                            tasks: targetTasks,
                            onSelectDay,
                            onSelectTask,
                            selectedDate,
                        });
                    })}
                </div>
            </div>
        </>
    );
}

//EXPORTABLE FOR APP (MAIN)
export default CalendarMonth;
