//UNIT TEST IMPORT FOR TESTING LOGIC IN DAYGRID
import { describe, it, expect } from "vitest";
import { getDailyGeneralWeather, weatherCodeToText } from "../DayGrid";

/// WEATHER CODE RETURN TEST ////

const weatherCodeTestCases = [
  // CLEAR dominates
  {
    input: Array(24).fill(0),
    dayIndex: 0,
    expected: 0,
  },

  // PARTLY CLOUDY dominates
  {
    input: [
      ...Array(10).fill(1),
      ...Array(14).fill(2),
    ],
    dayIndex: 0,
    expected: 2, // 2 appears more often
  },

  // CLOUDY dominates
  {
    input: [
      ...Array(5).fill(1),
      ...Array(5).fill(2),
      ...Array(14).fill(3),
    ],
    dayIndex: 0,
    expected: 3,
  },

  // RAIN dominates
  {
    input: [
      ...Array(15).fill(61),
      ...Array(9).fill(0),
    ],
    dayIndex: 0,
    expected: 61,
  },

  // TEST dayIndex slicing (day 1 vs day 0)
  {
    input: [
      ...Array(24).fill(0),
      ...Array(24).fill(3),
    ],
    dayIndex: 1,
    expected: 3,
  },

  // TIE case (important edge case!)
  {
    input: [
      ...Array(12).fill(1),
      ...Array(12).fill(2),
    ],
    dayIndex: 0,
    expected: 1,
  },
];

describe("getDailyGeneralWeather", () => {
  weatherCodeTestCases.forEach(({ input, dayIndex, expected }) => {
    it(`returns ${expected}`, () => {
      expect(getDailyGeneralWeather(input, dayIndex)).toBe(expected);
    });
  });
});

/// WEATHER CODE TO TEXT RETURN TEST ////

const weatherCodeToTextTestCases = [
  { code: 0, expected: "Clear sky" },
  { code: 1, expected: "Mostly clear" },
  { code: 2, expected: "Partly cloudy" },
  { code: 3, expected: "Overcast" },
  { code: 45, expected: "Foggy" },
  { code: 48, expected: "Foggy" },
  { code: 51, expected: "Light drizzle" },
  { code: 53, expected: "Light drizzle" },
  { code: 55, expected: "Light drizzle" },
  { code: 56, expected: "Freezing drizzle" },
  { code: 57, expected: "Freezing drizzle" },
  { code: 61, expected: "Rainy" },
  { code: 63, expected: "Rainy" },
  { code: 65, expected: "Rainy" },
  { code: 66, expected: "Freezing rain" },
  { code: 67, expected: "Freezing rain" },
  { code: 71, expected: "Snowy" },
  { code: 73, expected: "Snowy" },
  { code: 75, expected: "Snowy" },
  { code: 77, expected: "Snow grains" },
  { code: 80, expected: "Rain showers" },
  { code: 81, expected: "Rain showers" },
  { code: 82, expected: "Rain showers" },
  { code: 85, expected: "Snow showers" },
  { code: 86, expected: "Snow showers" },
  { code: 95, expected: "Thunderstorm" },
  { code: 96, expected: "Thunderstorm with hail" },
  { code: 99, expected: "Thunderstorm with hail" },
  { code: 999, expected: "Unknown" },
];

describe("weatherCodeToText", () => {
  weatherCodeToTextTestCases.forEach(({ code, expected }) => {
    it(`returns "${expected}" for code ${code}`, () => {
      expect(weatherCodeToText(code)).toBe(expected);
    });
  });
});