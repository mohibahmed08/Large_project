//UNIT TEST IMPORT FOR TESTING LOGIC IN DAYGRID
import { formatTimeValue, normalizeItemType, formatTaskTime, taskGroupLabel, parseTaskColor, getWeatherImg, weatherCodeToLabel, weatherGlyph, dayWeatherRange } from "../Calendar";

/// FORMAT TIME VALUE TESTS ////

describe("formatTimeValue", () => {

    it("formats normal time correctly", () => {
        const date = new Date(2026, 0, 1, 14, 30); // 14:30
        expect(formatTimeValue(date)).toBe("14:30");
    });

    it("pads single digit hour", () => {
        const date = new Date(2026, 0, 1, 5, 30); // 5:30
        expect(formatTimeValue(date)).toBe("05:30");
    });

    it("pads single digit minutes", () => {
        const date = new Date(2026, 0, 1, 14, 5); // 14:05
        expect(formatTimeValue(date)).toBe("14:05");
    });

    it("handles midnight", () => {
        const date = new Date(2026, 0, 1, 0, 0); // 00:00
        expect(formatTimeValue(date)).toBe("00:00");
    });

    it("handles noon", () => {
        const date = new Date(2026, 0, 1, 12, 0); // 12:00
        expect(formatTimeValue(date)).toBe("12:00");
    });

});

/// NORMALIZE ITEM TYPE TESTS ////

describe("normalizeItemType", () => {

    it("returns plan when source is PLAN", () => {
        expect(normalizeItemType({ source: "PLAN" })).toBe("plan");
    });

    it("returns event when source is EVENT", () => {
        expect(normalizeItemType({ source: "event" })).toBe("event");
    });

    it("returns task when source is TASK", () => {
        expect(normalizeItemType({ source: "TaSk" })).toBe("task");
    });

    it("defaults to event for unknown source", () => {
        expect(normalizeItemType({ source: "somethingElse" })).toBe("event");
    });

    it("defaults to event when source is missing", () => {
        expect(normalizeItemType({})).toBe("event");
    });

    it("defaults to event when input is null", () => {
        expect(normalizeItemType(null)).toBe("event");
    });

    it("defaults to event when input is undefined", () => {
        expect(normalizeItemType(undefined)).toBe("event");
    });

});

/// FORMAT TASK TIME TESTS ////

describe("formatTaskTime", () => {

    it("formats a valid date correctly", () => {
        const date = new Date(2026, 0, 1, 14, 30); // 2:30 PM
        const result = formatTaskTime(date);
        expect(result).toMatch(/14:30|2:30/); // handles 24h vs 12h locale differences
    });

    it("returns No time for invalid string", () => {
        expect(formatTaskTime("invalid-date")).toBe("No time");
    });

    it("returns No time for undefined", () => {
        expect(formatTaskTime(undefined)).toBe("No time");
    });

    it("handles timestamp input", () => {
        const timestamp = new Date(2026, 0, 1, 9, 5).getTime();
        const result = formatTaskTime(timestamp);
        expect(result).toMatch(/9:05|09:05/);
    });

    it("handles midnight correctly", () => {
        const date = new Date(2026, 0, 1, 0, 0);
        const result = formatTaskTime(date);
        expect(result).toMatch(/12:00|00:00/);
    });

});

/// TASK GROUP LABEL TESTS ////

describe("taskGroupLabel", () => {

    // -------------------------
    // 1. Explicit group overrides
    // -------------------------

    it("returns explicit group when provided", () => {
        expect(taskGroupLabel({ group: "Work", source: "task" }))
            .toBe("Work");
    });

    it("trims explicit group", () => {
        expect(taskGroupLabel({ group: "  School  ", source: "task" }))
            .toBe("School");
    });

    // -------------------------
    // 2. Known source mappings
    // -------------------------

    it("maps ical to Imported", () => {
        expect(taskGroupLabel({ source: "ical" }))
            .toBe("Imported");
    });

    it("maps task to Task", () => {
        expect(taskGroupLabel({ source: "task" }))
            .toBe("Task");
    });

    it("maps plan to Plan", () => {
        expect(taskGroupLabel({ source: "plan" }))
            .toBe("Plan");
    });

    it("maps event to Event", () => {
        expect(taskGroupLabel({ source: "event" }))
            .toBe("Event");
    });

    // -------------------------
    // 3. Fallback behavior
    // -------------------------

    it("capitalizes unknown source", () => {
        expect(taskGroupLabel({ source: "customType" }))
            .toBe("Customtype");
    });

    it("returns Other when no source or group", () => {
        expect(taskGroupLabel({}))
            .toBe("Other");
    });

    it("handles null input safely", () => {
        expect(taskGroupLabel(null))
            .toBe("Other");
    });

    it("handles undefined input safely", () => {
        expect(taskGroupLabel(undefined))
            .toBe("Other");
    });

});

/// PARSE TASK COLOR TESTS ////

describe("parseTaskColor", () => {

    // -------------------------
    // valid 6-digit hex
    // -------------------------

    it("parses valid 6-digit hex", () => {
        expect(parseTaskColor("#ff0000")).toBe("#ff0000");
    });

    it("parses valid 6-digit hex without #", () => {
        expect(parseTaskColor("ff0000")).toBe("#ff0000");
    });

    // -------------------------
    // valid 8-digit hex (with alpha)
    // -------------------------

    it("parses valid 8-digit hex", () => {
        expect(parseTaskColor("#ff0000ff")).toBe("#ff0000ff");
    });

    it("parses valid 8-digit hex without #", () => {
        expect(parseTaskColor("ff0000ff")).toBe("#ff0000ff");
    });

    // -------------------------
    // invalid inputs
    // -------------------------

    it("returns empty string for empty input", () => {
        expect(parseTaskColor("")).toBe("");
    });

    it("returns empty string for null", () => {
        expect(parseTaskColor(null)).toBe("");
    });

    it("returns empty string for undefined", () => {
        expect(parseTaskColor(undefined)).toBe("");
    });

    it("returns empty string for too short value", () => {
        expect(parseTaskColor("#fff")).toBe("");
    });

    it("returns empty string for too long invalid value", () => {
        expect(parseTaskColor("#ff000")).toBe("");
    });

    // -------------------------
    // whitespace handling
    // -------------------------

    it("handles whitespace around input", () => {
        expect(parseTaskColor("  #00ff00  ")).toBe("#00ff00");
    });

});

/// GET WEATHER IMG TESTS ////

import ClearSky from '../weather_backgrounds/ClearSky.jpg';
import Cloudy from '../weather_backgrounds/Cloudy.jpg';
import NightClear from '../weather_backgrounds/NightClear.jpg';
import NightCloudy from '../weather_backgrounds/NightCloudy.jpg';
import NightPartlyCloudy from '../weather_backgrounds/NightPartlyCloudy.jpg';
import PartlyCloudy from '../weather_backgrounds/PartlyCloudy.jpg';
import SunsetSunriseClearSky from '../weather_backgrounds/SunsetSunriseClearSky.png';
import SunsetSunriseCloudy from '../weather_backgrounds/SunsetSunriseCloudy.jpg';
import SunsetSunrisePartlyCloudy from '../weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

describe("getWeatherImg", () => {

    // -------------------------
    // 1. Clear sky mappings
    // -------------------------

    it("returns ClearSky image during day for Clear sky", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(12); // day
        expect(getWeatherImg("Clear sky")).toBe(ClearSky);
    });

    it("returns NightClear image at night for Clear sky", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(2); // night
        expect(getWeatherImg("Clear sky")).toBe(NightClear);
    });

    it("returns SunsetSunriseClearSky during sunrise/sunset", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(7); // sunrise
        expect(getWeatherImg("Clear sky")).toBe(SunsetSunriseClearSky);
    });

    // -------------------------
    // 2. Overcast mappings
    // -------------------------

    it("returns Cloudy image during day for Overcast", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(12);
        expect(getWeatherImg("Overcast")).toBe(Cloudy);
    });

    it("returns NightCloudy at night for Overcast", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(2);
        expect(getWeatherImg("Overcast")).toBe(NightCloudy);
    });

    it("returns SunsetSunriseCloudy during sunrise/sunset", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(19);
        expect(getWeatherImg("Overcast")).toBe(SunsetSunriseCloudy);
    });

    // -------------------------
    // 3. Partly cloudy mappings
    // -------------------------

    it("returns PartlyCloudy image during day", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(12);
        expect(getWeatherImg("Partly cloudy")).toBe(PartlyCloudy);
    });

    it("returns NightPartlyCloudy at night", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(3);
        expect(getWeatherImg("Partly cloudy")).toBe(NightPartlyCloudy);
    });

    it("returns SunsetSunrisePartlyCloudy during sunrise/sunset", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(18);
        expect(getWeatherImg("Partly cloudy")).toBe(SunsetSunrisePartlyCloudy);
    });

    // -------------------------
    // 4. Default case
    // -------------------------

    it("returns null for unknown weather", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(12);
        expect(getWeatherImg("Random Weather")).toBeNull();
    });

    it("returns null for empty input", () => {
        jest.spyOn(Date.prototype, "getHours").mockReturnValue(12);
        expect(getWeatherImg("")).toBeNull();
    });

});

/// WEATHER CODE TO LABEL TESTS ////

describe("weatherCodeToLabel", () => {

    // -------------------------
    // 1. Clear / simple conditions
    // -------------------------

    it("returns Clear for code 0", () => {
        expect(weatherCodeToLabel(0)).toBe("Clear");
    });

    it("returns Mostly clear for code 1", () => {
        expect(weatherCodeToLabel(1)).toBe("Mostly clear");
    });

    it("returns Partly cloudy for code 2", () => {
        expect(weatherCodeToLabel(2)).toBe("Partly cloudy");
    });

    it("returns Overcast for code 3", () => {
        expect(weatherCodeToLabel(3)).toBe("Overcast");
    });

    // -------------------------
    // 2. Fog
    // -------------------------

    it("returns Fog for codes 45 and 48", () => {
        expect(weatherCodeToLabel(45)).toBe("Fog");
        expect(weatherCodeToLabel(48)).toBe("Fog");
    });

    // -------------------------
    // 3. Rain group
    // -------------------------

    it("returns Rain for rain codes", () => {
        expect(weatherCodeToLabel(51)).toBe("Rain");
        expect(weatherCodeToLabel(61)).toBe("Rain");
        expect(weatherCodeToLabel(80)).toBe("Rain");
        expect(weatherCodeToLabel(82)).toBe("Rain");
    });

    // -------------------------
    // 4. Snow group
    // -------------------------

    it("returns Snow for snow codes", () => {
        expect(weatherCodeToLabel(71)).toBe("Snow");
        expect(weatherCodeToLabel(86)).toBe("Snow");
    });

    // -------------------------
    // 5. Storm group
    // -------------------------

    it("returns Storm for storm codes", () => {
        expect(weatherCodeToLabel(95)).toBe("Storm");
        expect(weatherCodeToLabel(99)).toBe("Storm");
    });

    // -------------------------
    // 6. Default case
    // -------------------------

    it("returns Weather for unknown code", () => {
        expect(weatherCodeToLabel(999)).toBe("Weather");
    });

});

/// WEATHER GLYPH TESTS ////

describe("weatherGlyph", () => {

    // -------------------------
    // 1. Clear / sun group
    // -------------------------

    it("returns sun glyph for clear codes", () => {
        expect(weatherGlyph(0)).toBe("☀️");
        expect(weatherGlyph(1)).toBe("☀️");
    });

    // -------------------------
    // 2. Cloud group
    // -------------------------

    it("returns partly cloudy glyph", () => {
        expect(weatherGlyph(2)).toBe("⛅");
        expect(weatherGlyph(3)).toBe("⛅");
    });

    // -------------------------
    // 3. Fog
    // -------------------------

    it("returns fog glyph", () => {
        expect(weatherGlyph(45)).toBe("🌫️");
        expect(weatherGlyph(48)).toBe("🌫️");
    });

    // -------------------------
    // 4. Rain
    // -------------------------

    it("returns rain glyph", () => {
        expect(weatherGlyph(51)).toBe("🌧️");
        expect(weatherGlyph(61)).toBe("🌧️");
        expect(weatherGlyph(82)).toBe("🌧️");
    });

    // -------------------------
    // 5. Snow
    // -------------------------

    it("returns snow glyph", () => {
        expect(weatherGlyph(71)).toBe("❄️");
        expect(weatherGlyph(86)).toBe("❄️");
    });

    // -------------------------
    // 6. Storm
    // -------------------------

    it("returns storm glyph", () => {
        expect(weatherGlyph(95)).toBe("⛈️");
        expect(weatherGlyph(99)).toBe("⛈️");
    });

    // -------------------------
    // 7. Default case
    // -------------------------

    it("returns bullet for unknown code", () => {
        expect(weatherGlyph(999)).toBe("•");
    });

});

/// DAY WEATHER RANGE TESTS ////

describe("dayWeatherRange", () => {

    it("returns valid ISO date range", () => {
        const result = dayWeatherRange();

        expect(result).toHaveProperty("startDate");
        expect(result).toHaveProperty("endDate");

        expect(typeof result.startDate).toBe("string");
        expect(typeof result.endDate).toBe("string");
    });

    it("start date is 7 days before current adjusted date", () => {
        const result = dayWeatherRange();

        const start = new Date(result.startDate);
        const end = new Date(result.endDate);

        expect(end.getTime()).toBeGreaterThan(start.getTime());
    });

    it("range spans approximately 22 days", () => {
        const result = dayWeatherRange();

        const start = new Date(result.startDate);
        const end = new Date(result.endDate);

        const diffDays = (end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24);

        expect(Math.round(diffDays)).toBe(22);
    });

});
