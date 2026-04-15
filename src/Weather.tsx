// @ts-nocheck
import { useState, useEffect } from 'react';
import { DEFAULT_WEATHER_LOCATION, requestWeatherLocation } from './weatherLocation.js';

// Fetch weather data for the visible calendar range.
function Weather({ setWeather, desiredDate, additionalDays, priorDays }) {

    // Start with the fallback location so the calendar can render immediately.
    const [coords, setCoords] = useState(() => ({
        latitude: DEFAULT_WEATHER_LOCATION.latitude,
        longitude: DEFAULT_WEATHER_LOCATION.longitude,
    }));

    // Build the first requested day from the month range and any earlier days we want to include.
    const firstDay = desiredDate ? new Date(desiredDate) : new Date();
    firstDay.setDate(firstDay.getDate() - priorDays);

    // Convert the range to the format expected by Open-Meteo.
    const { startDate, endDate } = getDateRange(firstDay, priorDays + additionalDays);

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
 * @param {Date} date - starting date (optional, defaults to today)
 * @param {number} totalDays - number of days to include (optional, defaults to 0)
 * @returns {Object} { startDate: 'YYYY-MM-DD', endDate: 'YYYY-MM-DD' }
 */
function getDateRange(date, totalDays = 0) {
    // Use today if no date is provided
    const targetDate = date instanceof Date ? date : new Date();

    // Format start date
    const yyyy = targetDate.getFullYear();
    const mm = String(targetDate.getMonth() + 1).padStart(2, '0');
    const dd = String(targetDate.getDate()).padStart(2, '0');
    const startDate = `${yyyy}-${mm}-${dd}`;

    // Calculate end date
    const endDateObj = new Date(targetDate); // copy date
    endDateObj.setDate(endDateObj.getDate() + totalDays); // automatically handles month/year rollover

    // Can go a max of two weeks out
    const maxDate = new Date();
    maxDate.setDate(maxDate.getDate() + 15);

    // Max endDate to maxDate
    if (endDateObj > maxDate) {
        endDateObj.setTime(maxDate.getTime());
    }

    const endY = endDateObj.getFullYear();
    const endM = String(endDateObj.getMonth() + 1).padStart(2, '0');
    const endD = String(endDateObj.getDate()).padStart(2, '0');
    const endDate = `${endY}-${endM}-${endD}`;

    return { startDate, endDate };
}

export default Weather;
