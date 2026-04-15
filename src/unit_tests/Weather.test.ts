//UNIT TEST IMPORT FOR TESTING LOGIC IN DAYGRID
import { getDateRange } from "../Weather";

/// GET DATE RANGE TESTS ////

describe("getDateRange", () => {

    // -------------------------
    // 1. Default behavior
    // -------------------------

    it("returns same start and end date when totalDays is 0", () => {
        const date = new Date(2026, 0, 1);
        const result = getDateRange(date, 0);

        expect(result.startDate).toBe("2026-01-01");
        expect(result.endDate).toBe("2026-01-01");
    });

    // -------------------------
    // 2. Normal range calculation
    // -------------------------

    it("correctly adds days to calculate endDate", () => {
        const date = new Date(2026, 0, 1);
        const result = getDateRange(date, 5);

        expect(result.startDate).toBe("2026-01-01");
        expect(result.endDate).toBe("2026-01-06");
    });

    it("handles month rollover", () => {
        const date = new Date(2026, 0, 30); // Jan 30
        const result = getDateRange(date, 5);

        expect(result.startDate).toBe("2026-01-30");
        expect(result.endDate).toBe("2026-02-04");
    });

    it("caps year rollover due to max range", () => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date(2026, 11, 1)); // Dec 1

        const date = new Date(2026, 11, 30);
        const result = getDateRange(date, 5);

        expect(result.startDate).toBe("2026-12-30");
        expect(result.endDate).toBe("2026-12-16"); // capped

        jest.useRealTimers();
    });
    // -------------------------
    // 3. Max date cap (15 days)
    // -------------------------

    it("caps endDate to 15 days from today", () => {
        const today = new Date();
        const date = new Date(today);

        const result = getDateRange(date, 100); // large number

        const maxDate = new Date();
        maxDate.setDate(maxDate.getDate() + 15);

        const yyyy = maxDate.getFullYear();
        const mm = String(maxDate.getMonth() + 1).padStart(2, "0");
        const dd = String(maxDate.getDate()).padStart(2, "0");

        expect(result.endDate).toBe(`${yyyy}-${mm}-${dd}`);
    });

    // -------------------------
    // 4. Invalid date input
    // -------------------------

    it("falls back to today when input is not a Date", () => {
        const today = new Date();
        const result = getDateRange("invalid" as any, 3);

        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, "0");
        const dd = String(today.getDate()).padStart(2, "0");

        expect(result.startDate).toBe(`${yyyy}-${mm}-${dd}`);
    });

});

/// WEATHER FETCH TESTS ////

export async function fetchWeatherLogic({ coords, startDate, endDate, setWeather }) {
    try {
        const res = await fetch(
            `https://api.open-meteo.com/v1/forecast?latitude=${coords.latitude}&longitude=${coords.longitude}&start_date=${startDate}&end_date=${endDate}&hourly=temperature_2m,weathercode,windspeed_10m`
        );

        if (!res.ok) throw new Error(`HTTP error ${res.status}`);

        const data = await res.json();
        setWeather(data);

    } catch (err) {
        console.error("Failed to fetch weather:", err);
    }
}

global.fetch = jest.fn();

describe("weather fetch", () => {

    const coords = { latitude: 10, longitude: 20 };
    const startDate = "2026-01-01";
    const endDate = "2026-01-02";

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("calls setWeather with API data on success", async () => {
        const mockData = { hourly: { temperature_2m: [1, 2, 3] } };

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => mockData,
        });

        const setWeather = jest.fn();

        await fetchWeatherLogic({ coords, startDate, endDate, setWeather });

        expect(fetch).toHaveBeenCalled();
        expect(setWeather).toHaveBeenCalledWith(mockData);
    });

});
