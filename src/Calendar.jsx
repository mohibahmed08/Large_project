import {useState, useRef, useEffect} from 'react';

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

//ICON UI
import UpArrow from './icons/arrow-big-up.svg';
import DownArrow from './icons/arrow-big-down.svg';

//MAIN EXPORTED FUNCTION
function Calendar({singleMonth}){

    //GENERAL DATE OBJECT
    const date = new Date();
    const baseMonth = new Date().getMonth();

    //RENDER MULTIPLE MONTHS WHEN NOT SINGLE MONTH
    const [renderedMonths, setRenderedMonths] = useState(1);

    //BACKGROUND FOR THE GENERAL CALENDAR
    const [background, setBackground] = useState(null);
    const [backgroundWeather, setBackgroundWeather] = useState(-1);

    //HOLDS MONTHS AWAY FROM NOW (CURRENT MONTH)
    const [currentMonthIndex, setCurrentMonthIndex] = useState(0);

    //OBSERVER TO CHANGE MONTH HEADER BASED ON MAJORITY OF MONTH ON SCREEN
    //BASICALLY IF MORE THAN HALF OF APRIL IS ON THE SCREEN AND LESS THAN HALF OF
    //MAY IS ON SCREEN, APRIL WILL BE THE HEADER, ONCE MAY IS ON SCREEN MORE THAN HALF, THEN MAY
    const containerRef = useRef(null);
    const lastMonthRef = useRef();

    //NOT MY CODE, BASICALLY JUST DETERMINES WHICH MONTH IS CURRENTLY
    //ON SCREEN BASED ON IT BEING MORE THAN HALF VISIBLE, THEN SWITCHES
    //TO THAT MONTH BY INCREMENTING THE CURRENT MONTH INDEX
    useEffect(() => {
        // DO NOT USE IF ON SINGLE MONTH USE
        if(singleMonth) return;

        // OTHERWISE USE TO DETERMINE HEADER BASED ON SCROLL POSITION
        const observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    const index = Number(entry.target.dataset.index);

                    // FOR CHANGING THE HEADER BASED ON HOW MUCH OF NEXT MONTH IS SHOWN
                    if (entry.intersectionRatio >= 0.5) { // more than half visible
                        setCurrentMonthIndex(index);
                    }

                    // FOR DYNAMICALLY CREATING MORE MONTHS
                    if (entry.isIntersecting && index === renderedMonths - 1) {
                            setRenderedMonths((prev) => prev + 1);
                    }
                });
            },
            {
                root: containerRef.current,
                threshold: Array.from({ length: 101 }, (_, i) => i / 100), // smooth intersection steps
            }
        );

        // FOR CHANGING THE HEADER BASED ON HOW MUCH OF NEXT MONTH IS SHOWN
        const months = containerRef.current.querySelectorAll(".calendar-month");
        months.forEach((month) => observer.observe(month));

        // FOR DYNAMICALLY CREATING MORE MONTHS
        if (lastMonthRef.current) observer.observe(lastMonthRef.current);

        // DISCONNECT WHEN NOT USING ANYMORE
        return () => observer.disconnect();
    }, [renderedMonths, singleMonth]);

    //COMPUTE THE FIRST DAY OF THE TARGET MONTH
    const targetDate = new Date(date.getFullYear(), baseMonth + currentMonthIndex, 1);
    // THE CURRENT MONTH'S NAME
    const monthName = targetDate.toLocaleString('default', { month: 'long' });
    // CURRENT YEAR (YYYY FORMAT)
    const year = targetDate.getFullYear();    

    //ARRAY OF WEEKDAY NAMES FOR TITLES
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

    //TBD WHEN YOU CLICK THE MONTH/YEAR HEADER
    const [monthDropdown, setMonthDropdown] = useState(false);

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

            {/* THE INTERACTABLE HEADER FOR CALENDAR */}
            <div className="calendar-month-interactable-header">
                {/* LEFT ARROW TO DECREMENT BY A MONTH (ONLY FOR ONE MONTH) */}
                {singleMonth && <img onClick = {()=>setCurrentMonthIndex(currentMonthIndex - 1)} className = "calendar-month-arrow" src = {UpArrow}/>}
                {/* MONTH NAME CORESPONDING TO CURRENT MONTH */}
                <h1 className = "calendar-month-month-name" onClick = {()=>{singleMonth && setMonthDropdown(!monthDropdown)}}>{monthName + " " + year}</h1>
                {/* LEFT ARROW TO INCREMENT BY A MONTH (ONLY FOR ONE MONTH) */}
                {singleMonth && <img onClick = {()=>setCurrentMonthIndex(currentMonthIndex + 1)} className = "calendar-month-arrow" src = {DownArrow}/>}
            </div>

            {/* WEEKDAY HEADER (MONDAY, TUESDAY, ...) */}
            <div className="calendar-weekdays">
                {/* SHOW THE WEEKDAYS ON THE TOP */}
                {weekdays.map((day) => (
                <div key={day} className="weekday">
                    {day}
                </div>
                ))}
            </div>

            {/* CHECK THE TOTAL NUM MONTHS */}
            {singleMonth ? (
                //SINGLE MONTH DOESN'T NEED SCROLLING THEREFORE DON'T USE IT
                <div className="calendar-month" >
                    <CalendarMonth monthsFromNow = {currentMonthIndex} setBackgroundWeather = {setBackgroundWeather} singleMonth = {singleMonth}/>
                </div>
            ) : (
                //SCROLL CONTAINER FOR THE MONTHS TO COMPUTE CURRENT MONTH HEADER
                <div ref={containerRef} style = {{ overflowY: "scroll", maxHeight: "100vh" }}>
                    {/* WRAPPER FOR CALENDAR MONTHS TO BE STACKED PROPERLY */}
                    {/* SHOW THE CALENDARS FOR FIRST 5 MONTHS */}
                    {Array.from({ length: renderedMonths }, (_, i) => (
                        <div key={i} data-index={i} className="calendar-month" >
                            <CalendarMonth monthsFromNow = {i} setBackgroundWeather = {setBackgroundWeather} singleMonth = {singleMonth} ref={i === renderedMonths - 1 ? lastMonthRef : null}/>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );

}

//MAIN EXPORT TO INDEX DOM
export default Calendar;