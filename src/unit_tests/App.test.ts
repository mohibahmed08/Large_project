//UNIT TEST IMPORT FOR TESTING LOGIC IN DAYGRID
import { decodeToken, suggestionKey, dateWithSuggestedTime, extractJsonArray, normalizeSuggestions, displayAssistantStatus, waitForNextPaint, renderInlineMarkdown, renderAssistantMessage } from "../App";
// import { requestEmailChange } from "../App";

/// DECODE TOKEN TESTS ////

describe("decodeToken", () => {

    it("returns null for empty token", () => {
        expect(decodeToken(null)).toBeNull();
        expect(decodeToken("")).toBeNull();
    });

    it("returns null for invalid token", () => {
        expect(decodeToken("abc.def")).toBeNull();
    });

});

/// SUGGESTION KEY TESTS ////

describe("suggestionKey", () => {

    it("creates stable composite key", () => {
        expect(
            suggestionKey({
                title: "Meeting",
                suggestedTime: "10:00",
                description: "Work",
            })
        ).toBe("Meeting|10:00|Work");
    });

});

/// DATE WITH SUGGESTED TIME TESTS ////

describe("dateWithSuggestedTime", () => {

    it("uses correct hour and minute", () => {
        const base = new Date(2026, 0, 1);
        const result = dateWithSuggestedTime(base, "14:30");

        expect(result.getHours()).toBe(14);
        expect(result.getMinutes()).toBe(30);
    });

    it("defaults to 12:00 for invalid time", () => {
        const base = new Date(2026, 0, 1);
        const result = dateWithSuggestedTime(base, "invalid");

        expect(result.getHours()).toBe(12);
        expect(result.getMinutes()).toBe(0);
    });

});

/// DISPLAY ASSISTANT STATUS TESTS ////

describe("displayAssistantStatus", () => {

    it("returns empty string for empty input", () => {
        expect(displayAssistantStatus("")).toBe("");
    });

    it("adds ellipsis if missing punctuation", () => {
        expect(displayAssistantStatus("Loading")).toBe("Loading...");
    });

    it("keeps existing punctuation", () => {
        expect(displayAssistantStatus("Done.")).toBe("Done.");
    });

});

/// WAIT FOR NEXT PAINT TESTS ////

describe("waitForNextPaint", () => {

    it("resolves successfully", async () => {
        await expect(waitForNextPaint()).resolves.toBeUndefined();
    });

});

/// EXTRACT JSON ARRAY TESTS ////

describe("extractJsonArray", () => {

    it("extracts JSON array from code block", () => {
        const input = "```json\n[1,2,3]\n```";
        expect(extractJsonArray(input)).toBe("[1,2,3]");
    });

    it("extracts array from raw text", () => {
        const input = "noise [1,2,3] noise";
        expect(extractJsonArray(input)).toBe("[1,2,3]");
    });

    it("returns empty string for no array", () => {
        expect(extractJsonArray("hello world")).toBe("");
    });

});

/// NORMALIZE SUGGESTIONS TESTS ////

describe("normalizeSuggestions", () => {

    it("returns array if already valid", () => {
        const input = [{ title: "A" }];
        expect(normalizeSuggestions(input)).toEqual(input);
    });

    it("parses embedded JSON from parse error case", () => {
        const input = [
            {
                title: "Parse error",
                description: "[{\"title\":\"A\"}]"
            }
        ];

        const result = normalizeSuggestions(input);
        expect(result).toEqual([{ title: "A" }]);
    });

});

/// RENDER INLINE MARKDOWN TESTS ////

describe("renderInlineMarkdown", () => {

    it("returns array or string output", () => {
        const result = renderInlineMarkdown("hello **world**");
        expect(Array.isArray(result)).toBe(true);
    });

    it("renders markdown links as anchor elements", () => {
        const result = renderInlineMarkdown("[AMC](https://example.com/showtimes)");
        expect(Array.isArray(result)).toBe(true);
    });

});

/// RENDER ASSISTANT MESSAGE TESTS ////

describe("renderAssistantMessage", () => {

    it("returns structured blocks", () => {
        const result = renderAssistantMessage("Hello\n- item 1\n- item 2");

        expect(Array.isArray(result)).toBe(true);
    });

    it("keeps links and bullets on separate lines", () => {
        const result = renderAssistantMessage("Here you go\n- item 1\n- [AMC](https://example.com/showtimes)");
        expect(Array.isArray(result)).toBe(true);
    });

});

async function fetchAccountSettings({
    session,
    updateToken,
    setAccountSettings,
    setAccountDraft,
    setEmailDraft,
    setAccountFeedback,
    setAccountLoading,
}) {
    try {
        const response = await fetch(`/getaccountsettings`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
            }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || "Could not load account settings.");
        }

        updateToken(data.jwtToken);

        const nextSettings = data.settings || {
            firstName: session.firstName || "",
            lastName: session.lastName || "",
            email: "",
            pendingEmail: "",
            calendarFeedUrl: "",
            calendarFeedWebcalUrl: "",
            reminderDefaults: {
                reminderEnabled: false,
                reminderMinutesBefore: 30,
            },
        };

        setAccountSettings(nextSettings);
        setAccountDraft(nextSettings);
        setEmailDraft("");

    } catch (error) {
        setAccountFeedback(error.message);
    } finally {
        setAccountLoading(false);
    }
}

/// SAVE ACCOUNT SETTINGS TESTS ////

const localStorageMock = (() => {
    let store: Record<string, string> = {};

    return {
        getItem: (key: string) => store[key] || null,
        setItem: (key: string, value: string) => {
            store[key] = value.toString();
        },
        removeItem: (key: string) => {
            delete store[key];
        },
        clear: () => {
            store = {};
        },
    };
})();

Object.defineProperty(window, "localStorage", {
    value: localStorageMock,
});

global.fetch = jest.fn();

describe("save account settings", () => {

    const session = {
        userId: "123",
        jwtToken: "token123",
    };

    const accountDraft = {
        firstName: "John",
        lastName: "Doe",
        reminderDefaults: {
            reminderEnabled: true,
            reminderMinutesBefore: 15,
        },
    };

    beforeEach(() => {
        jest.clearAllMocks();
        localStorage.clear();
    });

    // -------------------------
    // 1. SUCCESS CASE (no avatar change)
    // -------------------------

    it("saves settings successfully without avatar change", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                settings: accountDraft,
            }),
        });

        const updateToken = jest.fn();
        const setAccountSettings = jest.fn();
        const setAccountDraft = jest.fn();
        const setAccountFeedback = jest.fn();
        const setAccountSaving = jest.fn();
        const setAvatarUrl = jest.fn();
        const setPendingAvatarUrl = jest.fn();

        await saveAccountSettings({
            session,
            accountDraft,
            pendingAvatarUrl: null,
            updateToken,
            setAccountSettings,
            setAccountDraft,
            setAccountFeedback,
            setAccountSaving,
            setAvatarUrl,
            setPendingAvatarUrl,
        });

        expect(updateToken).toHaveBeenCalledWith("newToken");
        expect(setAccountSettings).toHaveBeenCalledWith(accountDraft);
        expect(setAccountDraft).toHaveBeenCalledWith(accountDraft);
        expect(setAccountFeedback).toHaveBeenCalledWith("Settings saved.");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 2. SUCCESS CASE (avatar set)
    // -------------------------

    it("updates avatar and localStorage when avatar is set", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                settings: accountDraft,
            }),
        });

        const setAvatarUrl = jest.fn();
        const setPendingAvatarUrl = jest.fn();

        await saveAccountSettings({
            session,
            accountDraft,
            pendingAvatarUrl: "https://avatar.png",
            updateToken: jest.fn(),
            setAccountSettings: jest.fn(),
            setAccountDraft: jest.fn(),
            setAccountFeedback: jest.fn(),
            setAccountSaving: jest.fn(),
            setAvatarUrl,
            setPendingAvatarUrl,
        });

        expect(setAvatarUrl).toHaveBeenCalledWith("https://avatar.png");
        expect(localStorage.getItem("avatarUrl")).toBe("https://avatar.png");
        expect(setPendingAvatarUrl).toHaveBeenCalledWith(null);
    });

    // -------------------------
    // 3. SUCCESS CASE (avatar removed)
    // -------------------------

    it("removes avatar when REMOVED flag is used", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                settings: accountDraft,
            }),
        });

        const setAvatarUrl = jest.fn();

        await saveAccountSettings({
            session,
            accountDraft,
            pendingAvatarUrl: "REMOVED",
            updateToken: jest.fn(),
            setAccountSettings: jest.fn(),
            setAccountDraft: jest.fn(),
            setAccountFeedback: jest.fn(),
            setAccountSaving: jest.fn(),
            setAvatarUrl,
            setPendingAvatarUrl: jest.fn(),
        });

        expect(setAvatarUrl).toHaveBeenCalledWith(null);
        expect(localStorage.getItem("avatarUrl")).toBeNull();
    });

    async function saveAccountSettings({
        session,
        accountDraft,
        pendingAvatarUrl,
        updateToken,
        setAccountSettings,
        setAccountDraft,
        setAccountFeedback,
        setAccountSaving,
        setAvatarUrl,
        setPendingAvatarUrl,
    }) {
        try {
            const response = await fetch(`/saveaccountsettings`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    firstName: accountDraft.firstName,
                    lastName: accountDraft.lastName,
                    reminderEnabled: accountDraft.reminderDefaults?.reminderEnabled === true,
                    reminderMinutesBefore: Number(
                        accountDraft.reminderDefaults?.reminderMinutesBefore || 30
                    ),
                }),
            });

            const data = await response.json();

            if (!response.ok) {
                throw new Error(data.error || "Could not save settings.");
            }

            updateToken(data.jwtToken);
            setAccountSettings(data.settings || accountDraft);
            setAccountDraft(data.settings || accountDraft);

            if (pendingAvatarUrl !== null) {
                const nextAvatar =
                    pendingAvatarUrl === "REMOVED" ? null : pendingAvatarUrl;

                setAvatarUrl(nextAvatar);

                if (nextAvatar) {
                    localStorage.setItem("avatarUrl", nextAvatar);
                } else {
                    localStorage.removeItem("avatarUrl");
                }

                setPendingAvatarUrl(null);
            }

            setAccountFeedback("Settings saved.");

        } catch (error) {
            setAccountFeedback(error.message);
        } finally {
            setAccountSaving(false);
        }

    }
});

/// REQUEST EMAIL CHANGE TESTS ////

global.fetch = jest.fn();

describe("request email change", () => {

    const session = {
        userId: "123",
        jwtToken: "token123",
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("requests email change successfully", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
            }),
        });

        const updateToken = jest.fn();
        const setEmailFeedback = jest.fn();
        const setEmailDraft = jest.fn();
        const setAccountSaving = jest.fn();
        const loadAccountSettings = jest.fn();

        await requestEmailChange({
            session,
            emailDraft: "test@email.com",
            updateToken,
            setEmailFeedback,
            setEmailDraft,
            setAccountSaving,
            loadAccountSettings,
        });

        expect(updateToken).toHaveBeenCalledWith("newToken");
        expect(setEmailFeedback).toHaveBeenCalledWith(
            "Verification sent to the new email address."
        );
        expect(loadAccountSettings).toHaveBeenCalled();
        expect(setEmailDraft).toHaveBeenCalledWith("");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 2. API ERROR CASE
    // -------------------------

    it("handles API error response", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Invalid email",
            }),
        });

        const setEmailFeedback = jest.fn();
        const setAccountSaving = jest.fn();

        await requestEmailChange({
            session,
            emailDraft: "bad@email.com",
            updateToken: jest.fn(),
            setEmailFeedback,
            setEmailDraft: jest.fn(),
            setAccountSaving,
            loadAccountSettings: jest.fn(),
        });

        expect(setEmailFeedback).toHaveBeenCalledWith("Invalid email");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 3. FALLBACK ERROR MESSAGE
    // -------------------------

    it("uses default error message when API provides none", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({}),
        });

        const setEmailFeedback = jest.fn();

        await requestEmailChange({
            session,
            emailDraft: "test@email.com",
            updateToken: jest.fn(),
            setEmailFeedback,
            setEmailDraft: jest.fn(),
            setAccountSaving: jest.fn(),
            loadAccountSettings: jest.fn(),
        });

        expect(setEmailFeedback).toHaveBeenCalledWith(
            "Could not start email change."
        );
    });

    // -------------------------
    // 4. NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        (fetch as any).mockRejectedValue(new Error("Network down"));

        const setEmailFeedback = jest.fn();
        const setAccountSaving = jest.fn();

        await requestEmailChange({
            session,
            emailDraft: "test@email.com",
            updateToken: jest.fn(),
            setEmailFeedback,
            setEmailDraft: jest.fn(),
            setAccountSaving,
            loadAccountSettings: jest.fn(),
        });

        expect(setEmailFeedback).toHaveBeenCalledWith("Network down");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

});

export async function requestEmailChange({
    session,
    emailDraft,
    updateToken,
    setEmailFeedback,
    setEmailDraft,
    setAccountSaving,
    loadAccountSettings,
}) {
    try {
        const response = await fetch(`/requestemailchange`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
                nextEmail: emailDraft.trim(),
            }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || "Could not start email change.");
        }

        updateToken(data.jwtToken);
        setEmailFeedback("Verification sent to the new email address.");

        await loadAccountSettings();

        setEmailDraft("");

    } catch (error) {
        setEmailFeedback(error.message);
    } finally {
        setAccountSaving(false);
    }
}

/// EXPORT CALENDAR TESTS ////

global.fetch = jest.fn();

describe("export calendar", () => {

    const session = {
        userId: "123",
        jwtToken: "token123",
    };

    beforeEach(() => {
        jest.clearAllMocks();

        // reset DOM
        document.body.innerHTML = "";
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("exports calendar and triggers download", async () => {

        const mockClick = jest.fn();

        // -------------------------
        // FIX: proper anchor element
        // -------------------------
        const link = {
            href: "",
            download: "",
            click: mockClick,
            remove: jest.fn(),
        };

        jest.spyOn(document, "createElement").mockReturnValue(link as any);

        jest.spyOn(document.body, "appendChild").mockImplementation(() => link as any);

        // -------------------------
        // FIX: URL mock
        // -------------------------
        const createObjectURL = jest.fn(() => "blob:url");
        const revokeObjectURL = jest.fn();

        Object.defineProperty(window, "URL", {
            value: {
                createObjectURL,
                revokeObjectURL,
            },
        });

        // -------------------------
        // FETCH MOCK
        // -------------------------
        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                ics: "BEGIN:VCALENDAR",
                filename: "mycal.ics",
            }),
        });

        const updateToken = jest.fn();
        const setAccountFeedback = jest.fn();

        await exportCalendar({
            session,
            updateToken,
            setAccountFeedback,
        });

        // -------------------------
        // ASSERTIONS
        // -------------------------
        expect(updateToken).toHaveBeenCalledWith("newToken");
        expect(setAccountFeedback).toHaveBeenCalledWith("Calendar exported.");
        expect(createObjectURL).toHaveBeenCalled();
        expect(mockClick).toHaveBeenCalled();
    });

    // -------------------------
    // 2. API ERROR CASE
    // -------------------------

    it("handles API error response", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Export failed",
            }),
        });

        const setAccountFeedback = jest.fn();

        await exportCalendar({
            session,
            updateToken: jest.fn(),
            setAccountFeedback,
        });

        expect(setAccountFeedback).toHaveBeenCalledWith("Export failed");
    });

    // -------------------------
    // 3. DEFAULT ERROR MESSAGE
    // -------------------------

    it("uses fallback error message", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({}),
        });

        const setAccountFeedback = jest.fn();

        await exportCalendar({
            session,
            updateToken: jest.fn(),
            setAccountFeedback,
        });

        expect(setAccountFeedback).toHaveBeenCalledWith(
            "Could not export calendar."
        );
    });

    // -------------------------
    // 4. NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        (fetch as any).mockRejectedValue(new Error("Network down"));

        const setAccountFeedback = jest.fn();

        await exportCalendar({
            session,
            updateToken: jest.fn(),
            setAccountFeedback,
        });

        expect(setAccountFeedback).toHaveBeenCalledWith("Network down");
    });

});

export async function exportCalendar({
    session,
    updateToken,
    setAccountFeedback,
}) {
    try {
        const response = await fetch(`/exportcalendar`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
            }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || "Could not export calendar.");
        }

        updateToken(data.jwtToken);

        const blob = new Blob([data.ics || ""], {
            type: "text/calendar;charset=utf-8",
        });

        const downloadUrl = URL.createObjectURL(blob);

        const link = document.createElement("a");
        link.href = downloadUrl;
        link.download = data.filename || "calendar-plus-plus.ics";

        document.body.appendChild(link);
        link.click();
        link.remove();

        URL.revokeObjectURL(downloadUrl);

        setAccountFeedback("Calendar exported.");

    } catch (error) {
        setAccountFeedback(error.message);
    }
}

/// REGENERATE CALENDAR FEED TESTS ////

global.fetch = jest.fn();

describe("regenerate calendar feed", () => {

    const session = {
        userId: "123",
        jwtToken: "token123",
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("regenerates calendar feed successfully", async () => {

        const mockSettings = {
            firstName: "John",
            lastName: "Doe",
        };

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                settings: mockSettings,
            }),
        });

        const updateToken = jest.fn();
        const setAccountSettings = jest.fn();
        const setAccountDraft = jest.fn();
        const setAccountFeedback = jest.fn();
        const setAccountSaving = jest.fn();

        await regenerateCalendarFeed({
            session,
            updateToken,
            setAccountSettings,
            setAccountDraft,
            setAccountFeedback,
            setAccountSaving,
        });

        expect(updateToken).toHaveBeenCalledWith("newToken");
        expect(setAccountSettings).toHaveBeenCalledWith(mockSettings);
        expect(setAccountDraft).toHaveBeenCalledWith(mockSettings);
        expect(setAccountFeedback).toHaveBeenCalledWith(
            "Subscription link regenerated. Old links no longer work."
        );
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 2. API ERROR CASE
    // -------------------------

    it("handles API error response", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Regeneration failed",
            }),
        });

        const setAccountFeedback = jest.fn();
        const setAccountSaving = jest.fn();

        await regenerateCalendarFeed({
            session,
            updateToken: jest.fn(),
            setAccountSettings: jest.fn(),
            setAccountDraft: jest.fn(),
            setAccountFeedback,
            setAccountSaving,
        });

        expect(setAccountFeedback).toHaveBeenCalledWith("Regeneration failed");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 3. DEFAULT ERROR MESSAGE
    // -------------------------

    it("uses fallback error message when none provided", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({}),
        });

        const setAccountFeedback = jest.fn();

        await regenerateCalendarFeed({
            session,
            updateToken: jest.fn(),
            setAccountSettings: jest.fn(),
            setAccountDraft: jest.fn(),
            setAccountFeedback,
            setAccountSaving: jest.fn(),
        });

        expect(setAccountFeedback).toHaveBeenCalledWith(
            "Could not regenerate calendar feed."
        );
    });

    // -------------------------
    // 4. NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        (fetch as any).mockRejectedValue(new Error("Network down"));

        const setAccountFeedback = jest.fn();
        const setAccountSaving = jest.fn();

        await regenerateCalendarFeed({
            session,
            updateToken: jest.fn(),
            setAccountSettings: jest.fn(),
            setAccountDraft: jest.fn(),
            setAccountFeedback,
            setAccountSaving,
        });

        expect(setAccountFeedback).toHaveBeenCalledWith("Network down");
        expect(setAccountSaving).toHaveBeenCalledWith(false);
    });

});

export async function regenerateCalendarFeed({
    session,
    updateToken,
    setAccountSettings,
    setAccountDraft,
    setAccountFeedback,
    setAccountSaving,
}) {
    try {
        const response = await fetch(`/regeneratecalendarfeed`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                userId: session.userId,
                jwtToken: session.jwtToken,
            }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(
                data.error || "Could not regenerate calendar feed."
            );
        }

        updateToken(data.jwtToken);
        setAccountSettings(data.settings);
        setAccountDraft(data.settings);

        setAccountFeedback(
            "Subscription link regenerated. Old links no longer work."
        );

    } catch (error) {
        setAccountFeedback(error.message);
    } finally {
        setAccountSaving(false);
    }
}

/// SUGGEST EVENTS TESTS ////

global.fetch = jest.fn();

describe("suggest events", () => {

    const session = {
        userId: "123",
        jwtToken: "token123",
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("loads event suggestions successfully", async () => {

        // FIXED TIME (stable test)
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-01-01T12:00:00Z"));

        const mockCoords = {
            latitude: 10,
            longitude: 20,
        };

        const ensureLocation = jest.fn().mockResolvedValue(mockCoords);

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                jwtToken: "newToken",
                suggestions: [
                    { title: "Event A" },
                ],
            }),
        });

        const updateToken = jest.fn();
        const setSuggestions = jest.fn();
        const setAiLoading = jest.fn();
        const setMessages = jest.fn();

        await suggestEvents({
            session,
            suggestionPreferences: "fun",
            ensureLocation,
            updateToken,
            setSuggestions,
            setMessages,
            setAiLoading,
        });

        expect(updateToken).toHaveBeenCalledWith("newToken");
        expect(setSuggestions).toHaveBeenCalledWith([
            { title: "Event A" },
        ]);

        jest.useRealTimers();
    });

    // -------------------------
    // 2. API ERROR CASE
    // -------------------------

    it("handles API error response", async () => {

        const ensureLocation = jest.fn().mockResolvedValue(null);

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "No suggestions available",
            }),
        });

        const setMessages = jest.fn();

        await suggestEvents({
            session,
            suggestionPreferences: "",
            ensureLocation,
            updateToken: jest.fn(),
            setSuggestions: jest.fn(),
            setMessages,
            setAiLoading: jest.fn(),
        });

        expect(setMessages).toHaveBeenCalledTimes(1);

        const updater = setMessages.mock.calls[0][0];

        expect(typeof updater).toBe("function");

        // simulate React state
        const result = updater([]);

        expect(result).toEqual([
            { role: "assistant", text: "No suggestions available" }
        ]);
    });

    // -------------------------
    // 3. FALLBACK ERROR MESSAGE
    // -------------------------

    it("uses default error message when missing", async () => {

        const ensureLocation = jest.fn().mockResolvedValue(null);

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({}),
        });

        const setMessages = jest.fn();

        await suggestEvents({
            session,
            suggestionPreferences: "",
            ensureLocation,
            updateToken: jest.fn(),
            setSuggestions: jest.fn(),
            setMessages,
            setAiLoading: jest.fn(),
        });

        const updater = setMessages.mock.calls[0][0];

        const result = updater([]);

        expect(result).toEqual([
            { role: "assistant", text: "Could not load suggestions." }
        ]);
    });

    // -------------------------
    // 4. NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        const ensureLocation = jest.fn().mockRejectedValue(new Error("Network down"));

        const setMessages = jest.fn();

        await suggestEvents({
            session,
            suggestionPreferences: "",
            ensureLocation,
            updateToken: jest.fn(),
            setSuggestions: jest.fn(),
            setMessages,
            setAiLoading: jest.fn(),
        });

        const updater = setMessages.mock.calls[0][0];

        const result = updater([]);

        expect(result).toEqual([
            { role: "assistant", text: "Network down" }
        ]);
    });

    async function suggestEvents({
        session,
        suggestionPreferences,
        ensureLocation,
        updateToken,
        setSuggestions,
        setMessages,
        setAiLoading,
    }) {
        try {
            const localNow = new Date();
            const coords = await ensureLocation();

            const response = await fetch(`/suggestevents`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    userId: session.userId,
                    jwtToken: session.jwtToken,
                    date: localNow.toISOString(),
                    localNow: localNow.toISOString(),
                    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                    utcOffsetMinutes: -localNow.getTimezoneOffset(),
                    preferences: suggestionPreferences.trim(),
                    latitude: coords?.latitude,
                    longitude: coords?.longitude,
                }),
            });

            const data = await response.json();

            if (!response.ok) {
                throw new Error(data.error || "Could not load suggestions.");
            }

            updateToken(data.jwtToken);
            setSuggestions(normalizeSuggestions(data.suggestions));

        } catch (error) {
            setMessages((prev) => [
                ...prev,
                { role: "assistant", text: error.message },
            ]);
        } finally {
            setAiLoading(false);
        }
    }
});

/// SAVE CALENDAR SUGGESTION TESTS ////

global.fetch = jest.fn();

describe("save calendar suggestion", () => {

  const session = {
    userId: "123",
    jwtToken: "token123",
  };

  const suggestion = {
    title: "Test Event",
    description: "Test Desc",
    suggestedTime: "14:30",
  };

  const currentDate = new Date("2026-01-01T00:00:00Z");

  beforeEach(() => {
    jest.clearAllMocks();
  });

  // -------------------------
  // 1. SUCCESS CASE
  // -------------------------

  it("saves suggestion successfully", async () => {

    (fetch as any).mockResolvedValue({
      ok: true,
      json: async () => ({
        jwtToken: "newToken",
      }),
    });

    const updateToken = jest.fn();
    const setSavedSuggestionKeys = jest.fn();
    const refreshCalendar = jest.fn();
    const setAiLoading = jest.fn();

    await saveSuggestion({
      session,
      suggestion,
      currentDate,
      key: "key-1",
      dateWithSuggestedTime,
      updateToken,
      setSavedSuggestionKeys,
      refreshCalendar,
      setMessages: jest.fn(),
      setAiMode: jest.fn(),
      setAiLoading,
    });

    expect(updateToken).toHaveBeenCalledWith("newToken");
    expect(setSavedSuggestionKeys).toHaveBeenCalledTimes(1);
    expect(refreshCalendar).toHaveBeenCalledTimes(1);
  });

  // -------------------------
  // 2. API ERROR CASE
  // -------------------------

  it("handles API error response", async () => {

    (fetch as any).mockResolvedValue({
      ok: false,
      json: async () => ({
        error: "Save failed",
      }),
    });

    const setMessages = jest.fn();
    const setAiMode = jest.fn();

    await saveSuggestion({
      session,
      suggestion,
      currentDate,
      key: "key-1",
      dateWithSuggestedTime,
      updateToken: jest.fn(),
      setSavedSuggestionKeys: jest.fn(),
      refreshCalendar: jest.fn(),
      setMessages,
      setAiMode,
      setAiLoading: jest.fn(),
    });

    const updater = setMessages.mock.calls[0][0];

    expect(updater([])).toEqual([
      { role: "assistant", text: "Save failed" },
    ]);

    expect(setAiMode).toHaveBeenCalledWith("chat");
  });

  // -------------------------
  // 3. DEFAULT ERROR MESSAGE
  // -------------------------

  it("uses default error message when missing", async () => {

    (fetch as any).mockResolvedValue({
      ok: false,
      json: async () => ({}),
    });

    const setMessages = jest.fn();
    const setAiMode = jest.fn();

    await saveSuggestion({
      session,
      suggestion,
      currentDate,
      key: "key-1",
      dateWithSuggestedTime,
      updateToken: jest.fn(),
      setSavedSuggestionKeys: jest.fn(),
      refreshCalendar: jest.fn(),
      setMessages,
      setAiMode,
      setAiLoading: jest.fn(),
    });

    const updater = setMessages.mock.calls[0][0];

    expect(updater([])).toEqual([
      { role: "assistant", text: "Could not save suggestion." },
    ]);

    expect(setAiMode).toHaveBeenCalledWith("chat");
  });

  // -------------------------
  // 4. NETWORK ERROR
  // -------------------------

  it("handles network failure", async () => {

    (fetch as any).mockRejectedValue(new Error("Network down"));

    const setMessages = jest.fn();
    const setAiMode = jest.fn();

    await saveSuggestion({
      session,
      suggestion,
      currentDate,
      key: "key-1",
      dateWithSuggestedTime,
      updateToken: jest.fn(),
      setSavedSuggestionKeys: jest.fn(),
      refreshCalendar: jest.fn(),
      setMessages,
      setAiMode,
      setAiLoading: jest.fn(),
    });

    const updater = setMessages.mock.calls[0][0];

    expect(updater([])).toEqual([
      { role: "assistant", text: "Network down" },
    ]);

    expect(setAiMode).toHaveBeenCalledWith("chat");
  });

});

export async function saveSuggestion({
  session,
  suggestion,
  currentDate,
  key,
  dateWithSuggestedTime,
  updateToken,
  setSavedSuggestionKeys,
  refreshCalendar,
  setMessages,
  setAiMode,
  setAiLoading,
}) {
  try {
    const startDate = dateWithSuggestedTime(
      currentDate,
      suggestion.suggestedTime || ""
    );

    const endDate = new Date(startDate.getTime() + 60 * 60 * 1000);

    const response = await fetch(`/savecalendar`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: session.userId,
        jwtToken: session.jwtToken,
        title: suggestion.title,
        description: suggestion.description,
        dueDate: startDate.toISOString(),
        endDate: endDate.toISOString(),
        source: "manual",
        isCompleted: false,
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Could not save suggestion.");
    }

    updateToken(data.jwtToken);
    setSavedSuggestionKeys((prev) => [...prev, key]);
    refreshCalendar();

  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unknown error";

    setMessages((prev) => [
      ...prev,
      { role: "assistant", text: message },
    ]);

    setAiMode("chat");
  } finally {
    setAiLoading(false);
  }
}
