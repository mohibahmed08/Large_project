import React, { useState, useEffect } from "react";
import { DEFAULT_WEATHER_LOCATION, requestWeatherLocation } from './weatherLocation.js';

//RETURNS THE WEATHER FOR A SPECIFIC DATE
function Weather({ setWeather, desiredDate, additionalDays, priorDays }) {

    //HOLDS CURRENT LONGITUDE AND LATITUDE THAT THE USER IS AT (ONCE ENABLED)
    const [coords, setCoords] = useState(() => ({
        latitude: DEFAULT_WEATHER_LOCATION.latitude,
        longitude: DEFAULT_WEATHER_LOCATION.longitude,
    }));

    //FIRST DAY TO GO BACK TO IN THE PAST FROM TODAY
    const firstDay = desiredDate ? new Date(desiredDate) : new Date();
    firstDay.setDate(firstDay.getDate() - priorDays);

    //GET START AND END DATE STRINGS FOR OPEN-METEO API
    const { startDate, endDate } = getDateRange(firstDay, priorDays + additionalDays);

    //REQUESTS THE USER'S LOCATION WHEN COMPONENT MOUNTS
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

    //USE EFFECT FOR WEATHER INITIALIZATION WHEN LOCATION CHANGES OR DATE CHANGES
    useEffect(() => {
        fetch(
            `https://api.open-meteo.com/v1/forecast?latitude=${coords.latitude}&longitude=${coords.longitude}&start_date=${startDate}&end_date=${endDate}&hourly=temperature_2m,weathercode,windspeed_10m`
        )
        .then((res) => {
            if (!res.ok) throw new Error(`HTTP error ${res.status}`);
            return res.json();
        })
        .then((data) => {
            console.log("Weather fetched:", data); // debug
            setWeather(data); // STORE FULL DATA (hourly/daily)
        })
        .catch((err) => console.error("Failed to fetch weather:", err));
    //USE EFFECT FOR WEATHER INITIALIZATION WHEN LOCATION CHANGES OR DATE CHANGES
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
    const mm = String(targetDate.getMonth() + 1).padStart(2, "0");
    const dd = String(targetDate.getDate()).padStart(2, "0");
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
    const endM = String(endDateObj.getMonth() + 1).padStart(2, "0");
    const endD = String(endDateObj.getDate()).padStart(2, "0");
    const endDate = `${endY}-${endM}-${endD}`;

    return { startDate, endDate };
}

export default Weather;
