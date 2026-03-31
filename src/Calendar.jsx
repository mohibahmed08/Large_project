import {useState, useEffect} from 'react';

//IMPORT CORRESPONDING CSS SHEET
import './Calendar.css';

//IMPORT FOR CALENDAR UI
import CalendarMonth from './CalendarMonth.jsx';

//PICTURE BACKGROUND IMPORTS
import ClearSky from './weather_backgrounds/ClearSky.jpg';
import Cloudy from './weather_backgrounds/Cloudy.jpg';
import NightClear from './weather_backgrounds/NightClear.jpg';
import NightCloudy from './weather_backgrounds/NightCloudy.jpg';
import NightPartlyCloudy from './weather_backgrounds/NightPartlyCloudy.jpg';
import PartlyCloudy from './weather_backgrounds/PartlyCloudy.jpg';
import SunsetSunriseClearSky from './weather_backgrounds/SunsetSunriseClearSky.png';
import SunsetSunriseCloudy from './weather_backgrounds/SunsetSunriseCloudy.jpg';
import SunsetSunrisePartlyCloudy from './weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

//MAIN EXPORTED FUNCTION
function Calendar({totalNumMonths}){

    //BACKGROUND FOR THE GENERAL CALENDAR
    const [background, setBackground] = useState(null);
    const [backgroundWeather, setBackgroundWeather] = useState(-1);

     //GETS THE CURRENT TIME OF DAY
    function getTimeOfDay() {
        const hour = new Date().getHours();
        if (hour >= 6 && hour < 9) return "sunrise";
        if (hour >= 9 && hour < 18) return "day";
        if (hour >= 18 && hour < 21) return "sunset";
        return "night";
    }

    //TURNS THE CURRENT WEATHER INTO A WEATHER IMAGE
    function getWeatherImg(currentWeather){
        
        //OBTAIN THE CURRENT TIME OF THE DAY
        const timeOfDay = getTimeOfDay();

        //CHANGE BACKGROUND BASED ON WEATHER AND TIME OF DAY
        switch(currentWeather){
            //RETURNS THE WEATHER OF THE CURRENT DAY
            case "Clear sky": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunriseClearSky;
                else if(timeOfDay === "day") return ClearSky;
                else return NightClear;
            case "Overcast": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunriseCloudy;
                else if(timeOfDay === "day") return Cloudy;
                else return NightCloudy;
            case "Partly cloudy": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunrisePartlyCloudy;
                else if(timeOfDay === "day") return PartlyCloudy;
                else return NightPartlyCloudy;
            default: return null;
        }
    }

    //WHEN BACKGROUND WEATHER CHANGES, RECOMPUTE THE BACKGROUND USING WEATHER
    useEffect(() => {
        //SET THE BACKGROUND BASED ON THE CURRENT WEATHER AND TIME
        setBackground(getWeatherImg(backgroundWeather));
    }, [backgroundWeather]);

    //HTML DOM RETURN
    return(
        //BACKGROUND WITH THE CURRENT BACKGROUND IMAGE EMBEDDED IN STYLE
        <div className = "calendar-calendar-background" style={{ '--bg-img': `url(${background}`}}>
            {/* WRAPPER FOR CALENDAR MONTHS TO BE STACKED PROPERLY */}
            {/* SHOW THE CALENDARS FOR FIRST 5 MONTHS */}
            {Array.from({ length: totalNumMonths }, (_, i) => (
                <CalendarMonth key={i} monthsAwayFromNow={i} singleMonth = {totalNumMonths === 1} setBackgroundWeather = {setBackgroundWeather}/>
            ))}
        </div>
    );

}

//MAIN EXPORT TO INDEX DOM
export default Calendar;