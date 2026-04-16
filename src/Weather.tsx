// @ts-nocheck
import { useState, useEffect } from 'react';
import { DEFAULT_WEATHER_LOCATION, requestWeatherLocation } from './weatherLocation.js';

// Fetch weather data for the visible calendar range.
function Weather({ setWeather, startDate: rangeStart, endDate: rangeEnd }) {

    // Start with the fallback location so the calendar can render immediately.
    const [coords, setCoords] = useState(() => ({
        latitude: DEFAULT_WEATHER_LOCATION.latitude,
        longitude: DEFAULT_WEATHER_LOCATION.longitude,
    }));

    // Convert the requested range to the format expected by Open-Meteo.
    const { startDate, endDate } = getDateRange(rangeStart, rangeEnd);

    // Refresh the coordinates once the browser location request resolves.
    useEffect(() => {
        let ignore = false;

        requestWeatherLocation()
            .then((nextLocation) => {
                if (ignore || nextLocation.isFallback) {
                    return;
                }

                setCoords({
                    latitude: nextLocation.latitude,
                    longitude: nextLocation.longitude,
                });
            })
            .catch((err) => console.error(err.message));

        return () => {
            ignore = true;
        };
    }, []);

    // Refetch weather whenever the range or coordinates change.
    useEffect(() => {
        fetch(
            `https://api.open-meteo.com/v1/forecast?latitude=${coords.latitude}&longitude=${coords.longitude}&start_date=${startDate}&end_date=${endDate}&hourly=temperature_2m,weathercode,windspeed_10m`
        )
        .then((res) => {
            if (!res.ok) throw new Error(`HTTP error ${res.status}`);
            return res.json();
        })
        .then((data) => {
            setWeather(data);
        })
        .catch((err) => console.error('Failed to fetch weather:', err));
    }, [coords.latitude, coords.longitude, startDate, endDate]);

    return null;
}

/**
 * Returns start and end date strings for Open-Meteo API
 * @param {Date} startInput - starting date (optional, defaults to today)
 * @param {Date|number} endInput - ending date or number of days to include
 * @returns {Object} { startDate: 'YYYY-MM-DD', endDate: 'YYYY-MM-DD' }
 */
export function getDateRange(startInput: any, endInput: any = 0) {
    const targetDate = startInput instanceof Date && !Number.isNaN(startInput.getTime())
        ? new Date(startInput)
        : new Date();
    targetDate.setHours(0, 0, 0, 0);

    const formatDate = (date) => {
        const yyyy = date.getFullYear();
        const mm = String(date.getMonth() + 1).padStart(2, '0');
        const dd = String(date.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    };

    const startDate = formatDate(targetDate);

    let endDateObj;
    if (typeof endInput === 'number') {
        endDateObj = new Date(targetDate);
        endDateObj.setDate(endDateObj.getDate() + endInput);
    } else if (endInput instanceof Date && !Number.isNaN(endInput.getTime())) {
        endDateObj = new Date(endInput);
    } else {
        endDateObj = new Date(targetDate);
    }
    endDateObj.setHours(0, 0, 0, 0);

    // Clamp forecasts to at most two weeks ahead of today.
    const maxDate = new Date();
    maxDate.setHours(0, 0, 0, 0);
    maxDate.setDate(maxDate.getDate() + 14);

    if (endDateObj > maxDate) {
        endDateObj.setTime(maxDate.getTime());
    }

    const endDate = formatDate(endDateObj);

    return { startDate, endDate };
}

export default Weather;
